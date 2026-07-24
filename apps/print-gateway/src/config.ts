import 'dotenv/config';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const apiBaseUrl = (process.env.API_BASE_URL ?? 'http://localhost:3000/api/v1').replace(/\/+$/, '');
const printerTransport = process.env.PRINTER_TRANSPORT ?? 'console';
const nodeEnv = process.env.NODE_ENV ?? 'development';

// FIX-06 — กฎเข้มขึ้น (Private IP ไม่ใช่เหตุผลให้ยอม HTTP ใน production):
//   production               → https:// เท่านั้น (แม้ localhost/LAN ก็ไม่ยอม http)
//   development/test         → http:// ได้เฉพาะ localhost/127.0.0.1/::1 เท่านั้น
// เหตุผล: X-Gateway-Key เดินทางแบบ plaintext ถ้าใช้ http บนเครือข่ายจริง
function assertSafeApiBaseUrl(url: string, env: string): void {
  const u = new URL(url);
  if (u.protocol === 'https:') return;
  if (u.protocol !== 'http:') {
    throw new Error(`API_BASE_URL ต้องเป็น http:// หรือ https:// เท่านั้น (ได้ "${url}")`);
  }
  // ถึงตรงนี้ = http://
  if (env === 'production') {
    throw new Error(
      `API_BASE_URL ต้องเป็น https:// เมื่อ NODE_ENV=production (ได้ "${url}") — ` +
        'Private IP ก็ไม่ยอม เพราะ X-Gateway-Key จะรั่วแบบ plaintext บนสาย',
    );
  }
  const isLocalhost =
    u.hostname === 'localhost' || u.hostname === '127.0.0.1' || u.hostname === '::1';
  if (!isLocalhost) {
    throw new Error(
      `http:// ใช้ได้เฉพาะ localhost/127.0.0.1 ใน development/test (ได้ "${url}") — ` +
        'ปลายทางอื่นต้องใช้ https://',
    );
  }
}
assertSafeApiBaseUrl(apiBaseUrl, nodeEnv);

// ConsoleTransport (mock) ต้องไม่ถูกใช้ใน production เด็ดขาด — จะ ACK เป็น
// SIMULATED เสมอ (ดู transports/console-transport.ts) ถ้าลืมสลับ transport
// จริงจะดูเหมือนพิมพ์ "สำเร็จ" ทั้งที่ไม่มีอะไรออกจากเครื่องจริงสักใบ (audit ข้อ 1.2)
if (nodeEnv === 'production' && printerTransport === 'console') {
  throw new Error(
    'ห้ามใช้ PRINTER_TRANSPORT=console บน production — ตั้งค่าเป็น "serial" ' +
      'พร้อม PRINTER_SERIAL_PATH หรือ transport จริงอื่น',
  );
}

// usb_spool: ต้องมีชื่อ printer queue (RAW) — fail fast ถ้าไม่ตั้ง
const printerQueueName = process.env.PRINTER_QUEUE_NAME ?? '';
if (printerTransport === 'usb_spool' && printerQueueName.trim() === '') {
  throw new Error('PRINTER_TRANSPORT=usb_spool ต้องตั้ง PRINTER_QUEUE_NAME (ชื่อ printer queue แบบ RAW)');
}

// renderer ปัจจุบัน layout ตายตัวที่ 60×40mm @203DPI (bitmap 480×320) — ถ้า config
// ระบุขนาด/DPI ต่างจากนี้ ให้ fail fast กันพิมพ์เพี้ยนเงียบ ๆ (ต้องแก้ layout ก่อน)
const printerDpi = Number(process.env.PRINTER_DPI ?? 203);
const labelWidthMm = Number(process.env.LABEL_WIDTH_MM ?? 60);
const labelHeightMm = Number(process.env.LABEL_HEIGHT_MM ?? 40);
if (printerDpi !== 203 || labelWidthMm !== 60 || labelHeightMm !== 40) {
  throw new Error(
    `ตอนนี้ renderer รองรับเฉพาะ 60×40mm @203DPI (ได้ ${labelWidthMm}×${labelHeightMm}mm @${printerDpi}DPI) — ` +
      'ต้องปรับ layout ใน label-renderer.ts ก่อนเปลี่ยนขนาด/ความละเอียด',
  );
}

export const config = {
  apiBaseUrl,
  gatewayApiKey: requireEnv('GATEWAY_API_KEY'),
  pollIntervalMs: Number(process.env.POLL_INTERVAL_MS ?? 3000),
  heartbeatIntervalMs: Number(process.env.HEARTBEAT_INTERVAL_MS ?? 30_000),
  printerTransport,
  printerModel: process.env.PRINTER_MODEL ?? 'XP-420B',
  serialPath: process.env.PRINTER_SERIAL_PATH ?? '',
  serialBaudRate: Number(process.env.PRINTER_SERIAL_BAUD_RATE ?? 9600),
  printerQueueName,
  spoolTimeoutMs: Number(process.env.PRINTER_SPOOL_TIMEOUT_MS ?? 15_000),
  // usb_spool บน Windows (lpr) = UNSUPPORTED จนกว่าจะผ่าน hardware verification —
  // ต้อง opt-in ชัดเจน (Pilot ใช้ Raspberry Pi/Linux + CUPS เป็นหลัก)
  allowUnverifiedWindowsSpool:
    process.env.PRINTER_ALLOW_UNVERIFIED_WINDOWS_SPOOL === 'true',
  printerDpi,
  labelWidthMm,
  labelHeightMm,
};
