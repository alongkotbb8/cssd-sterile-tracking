import { createCanvas, registerFont, CanvasRenderingContext2D } from 'canvas';
import * as QRCode from 'qrcode';
import { createHash } from 'crypto';
import * as path from 'path';
import { PrintJobPayload } from './types';

/** 203 DPI ≈ 8 dots/mm — เดียวกับ apps/mobile/lib/core/printer/label_renderer.dart */
const DOTS_PER_MM = 8;
const WIDTH_MM = 60;
const HEIGHT_MM = 40;
const WIDTH_DOTS = WIDTH_MM * DOTS_PER_MM; // 480 — หารด้วย 8 ลงตัวพอดี ไม่ต้อง pad
const HEIGHT_DOTS = HEIGHT_MM * DOTS_PER_MM; // 320

export class PayloadValidationError extends Error {}

// packageId เป็น cuid จาก backend เสมอ (Package.id) — ยอมรับเฉพาะ charset ปลอดภัย
// กันข้อมูลแปลกปลอมหลุดเข้ามา render/ฝัง QR (defense-in-depth แม้ backend สร้างเองก็ตาม)
const SAFE_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

function assertSafeId(id: string, field: string): void {
  if (!SAFE_ID_RE.test(id)) {
    throw new PayloadValidationError(`${field} มีรูปแบบไม่ถูกต้อง: ${JSON.stringify(id)}`);
  }
}

// ตัด control character (CR/LF/NUL/ESC ฯลฯ) ทิ้งเสมอก่อน render — กัน layout
// เพี้ยน/บรรทัดแตกจากข้อความที่ไม่คาดคิด (defense-in-depth; เส้นทางหลักตอนนี้
// วาดเป็น bitmap ทั้งใบแล้วจึงไม่มีช่องโหว่ TSPL string injection เหมือนเดิมที่ใช้ TEXT/QRCODE ตรงๆ)
function sanitizeText(s: string, maxLen: number): string {
  // eslint-disable-next-line no-control-regex
  const cleaned = s.replace(/[\x00-\x1F\x7F]/g, '').trim();
  return cleaned.length > maxLen ? cleaned.slice(0, maxLen) : cleaned;
}

/**
 * ต้องตรงเป๊ะกับ hashPayload ฝั่ง apps/api/src/modules/print-jobs/print-jobs.service.ts
 * (sort key ก่อนเสมอ กัน Postgres jsonb ไม่ preserve key order ตอนอ่านกลับ)
 */
function hashPayload(payload: PrintJobPayload): string {
  const orderedKeys = Object.keys(payload).sort();
  return createHash('sha256').update(JSON.stringify(payload, orderedKeys)).digest('hex');
}

/**
 * ยืนยันว่า payload ที่ backend ส่งมาไม่ถูกแก้ระหว่างทาง/ไม่ตรงกับตอนสร้าง job
 * จริง ก่อนจะพิมพ์จริงเสมอ (audit ข้อ 2.4) — ไม่ตรง = ห้ามพิมพ์เด็ดขาด
 */
export function verifyPayloadHash(payload: PrintJobPayload, expectedHash: string): boolean {
  return hashPayload(payload) === expectedHash;
}

let fontRegistered = false;
function ensureFontRegistered(): void {
  if (fontRegistered) return;
  const dir = path.join(__dirname, '..', 'assets', 'fonts');
  registerFont(path.join(dir, 'Sarabun-Regular.ttf'), { family: 'Sarabun', weight: 'normal' });
  registerFont(path.join(dir, 'Sarabun-Bold.ttf'), { family: 'Sarabun', weight: 'bold' });
  fontRegistered = true;
}

function drawEllipsized(
  ctx: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  maxWidth: number,
): void {
  let s = text;
  if (ctx.measureText(s).width > maxWidth) {
    while (s.length > 0 && ctx.measureText(`${s}…`).width > maxWidth) {
      s = s.slice(0, -1);
    }
    s = `${s}…`;
  }
  ctx.fillText(s, x, y);
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
}

/**
 * แปลง RGBA → 1 บิตต่อพิกเซลตามรูปแบบ TSPL BITMAP (bit 0 = ดำ/พิมพ์, bit 1 =
 * ขาว/ไม่พิมพ์, MSB ก่อน) — ตรรกะเดียวกับ label_renderer.dart `_toMonochrome`
 */
function toMonochromeBitmap(
  ctx: CanvasRenderingContext2D,
  widthDots: number,
  heightDots: number,
): Buffer {
  const { data } = ctx.getImageData(0, 0, widthDots, heightDots);
  const widthBytes = widthDots / 8;
  const mono = Buffer.alloc(widthBytes * heightDots, 0xff);

  for (let y = 0; y < heightDots; y++) {
    for (let x = 0; x < widthDots; x++) {
      const o = (y * widthDots + x) * 4;
      const r = data[o];
      const g = data[o + 1];
      const b = data[o + 2];
      const a = data[o + 3];
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;
      if (a > 128 && lum < 128) {
        const byteIndex = y * widthBytes + (x >> 3);
        const bit = 7 - (x & 7);
        mono[byteIndex] &= ~(1 << bit);
      }
    }
  }
  return mono;
}

/**
 * Render label ทั้งใบเป็นภาพ (canvas + ฟอนต์ Sarabun ที่แนบมากับ service เอง)
 * แล้วแปลงเป็น bitmap — วิธีเดียวกับ apps/mobile/lib/core/printer/label_renderer.dart
 * ใช้ได้กับเครื่องพิมพ์ label TSPL 203 DPI ทั่วไป (เช่น Xprinter รุ่น label) เพราะคำสั่ง
 * TSPL `TEXT` ใช้ฟอนต์ในตัวเครื่องซึ่งไม่มีอักษรไทย ส่วน `QRCODE` แบบ native ก็
 * ถูกแทนที่ด้วยการวาด QR ลงในภาพเดียวกันนี้ไปเลย (ตัด TSPL string injection
 * surface ทั้งหมดออกไปพร้อมกัน — ไม่มี TEXT/QRCODE ที่รับ user-controlled string ตรงๆ อีกแล้ว)
 */
async function renderLabelImage(payload: PrintJobPayload): Promise<Buffer> {
  ensureFontRegistered();
  assertSafeId(payload.packageId, 'packageId');

  const setName = sanitizeText(payload.setName, 60);
  const wrapType = sanitizeText(payload.wrapType, 30);

  const canvas = createCanvas(WIDTH_DOTS, HEIGHT_DOTS);
  const ctx = canvas.getContext('2d');

  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, WIDTH_DOTS, HEIGHT_DOTS);
  ctx.fillStyle = '#000000';
  ctx.textBaseline = 'top';

  ctx.font = 'bold 30px Sarabun';
  drawEllipsized(ctx, setName, 12, 8, WIDTH_DOTS - 12);

  ctx.font = '22px Sarabun';
  drawEllipsized(ctx, wrapType, 12, 46, WIDTH_DOTS - 12);

  // QR — เนื้อหา = packageId เท่านั้น (กฎโดเมน: ห้ามยัดข้อมูลอื่นลง QR)
  const qrSize = 150;
  const qrCanvas = createCanvas(qrSize, qrSize);
  await QRCode.toCanvas(qrCanvas, payload.packageId, {
    errorCorrectionLevel: 'M',
    margin: 0,
    width: qrSize,
    color: { dark: '#000000', light: '#ffffff' },
  });
  ctx.drawImage(qrCanvas, 12, 92);

  ctx.font = 'bold 22px Sarabun';
  drawEllipsized(ctx, payload.packageId, 175, 150, WIDTH_DOTS - 175 - 8);

  if (payload.sterilizeDate && payload.expiryDate) {
    ctx.font = '20px Sarabun';
    ctx.fillText(`นึ่ง: ${formatDate(payload.sterilizeDate)}`, 12, 258);
    ctx.fillText(`หมดอายุ: ${formatDate(payload.expiryDate)}`, 12, 286);
  } else {
    // ห่อยังไม่ผ่านการนึ่ง — ห้ามคาดเดาวันที่เด็ดขาด แสดงแถบเตือนแทน (ข้อ 2.3/9 ของ AGENTS.md)
    ctx.fillStyle = '#000000';
    ctx.fillRect(12, 254, WIDTH_DOTS - 24, 60);
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 26px Sarabun';
    const text = 'ยังไม่ผ่านการฆ่าเชื้อ';
    const textWidth = ctx.measureText(text).width;
    const textX = Math.max(12, 12 + (WIDTH_DOTS - 24 - textWidth) / 2);
    ctx.fillText(text, textX, 254 + (60 - 26) / 2);
  }

  return toMonochromeBitmap(ctx, WIDTH_DOTS, HEIGHT_DOTS);
}

/** คืนคำสั่ง TSPL ทั้งชุด (header ASCII + BITMAP data + PRINT) พร้อมส่งเครื่องพิมพ์จริง */
export async function buildTsplLabel(payload: PrintJobPayload): Promise<Buffer> {
  const mono = await renderLabelImage(payload);
  const widthBytes = WIDTH_DOTS / 8;

  const header = Buffer.from(
    `SIZE ${WIDTH_MM} mm, ${HEIGHT_MM} mm\r\n` +
      `GAP 3 mm, 0\r\n` +
      `DIRECTION 1\r\n` +
      `REFERENCE 0,0\r\n` +
      `CLS\r\n` +
      `BITMAP 0,0,${widthBytes},${HEIGHT_DOTS},0,`,
    'ascii',
  );
  const footer = Buffer.from('\r\nPRINT 1,1\r\n', 'ascii');
  return Buffer.concat([header, mono, footer]);
}
