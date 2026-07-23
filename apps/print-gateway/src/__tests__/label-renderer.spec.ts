import jsQR from 'jsqr';
import { createCanvas } from 'canvas';
import { buildTsplLabel, PayloadValidationError, verifyPayloadHash } from '../label-renderer';
import { PrintJobPayload } from '../types';

const WIDTH_DOTS = 480;
const HEIGHT_DOTS = 320;

/** แกะ header/BITMAP data ออกจากผล buildTsplLabel แล้ว render กลับเป็นภาพ RGBA เพื่อตรวจเนื้อหาจริง */
function decodeBitmap(tspl: Buffer): { header: string; rgba: Uint8ClampedArray } {
  const marker = Buffer.from('BITMAP 0,0,60,320,0,', 'ascii');
  const start = tspl.indexOf(marker) + marker.length;
  const header = tspl.subarray(0, start).toString('ascii');
  const widthBytes = WIDTH_DOTS / 8;
  const mono = tspl.subarray(start, start + widthBytes * HEIGHT_DOTS);

  const canvas = createCanvas(WIDTH_DOTS, HEIGHT_DOTS);
  const ctx = canvas.getContext('2d');
  const imageData = ctx.createImageData(WIDTH_DOTS, HEIGHT_DOTS);
  for (let y = 0; y < HEIGHT_DOTS; y++) {
    for (let x = 0; x < WIDTH_DOTS; x++) {
      const byteIndex = y * widthBytes + (x >> 3);
      const bit = 7 - (x & 7);
      const isWhite = (mono[byteIndex] >> bit) & 1;
      const o = (y * WIDTH_DOTS + x) * 4;
      const v = isWhite ? 255 : 0;
      imageData.data[o] = v;
      imageData.data[o + 1] = v;
      imageData.data[o + 2] = v;
      imageData.data[o + 3] = 255;
    }
  }
  return { header, rgba: imageData.data };
}

describe('buildTsplLabel (bitmap rendering)', () => {
  const base: PrintJobPayload = {
    packageId: 'clx4qr7z10000abcd12345678',
    setName: 'ชุดทำแผล',
    wrapType: 'SEAL',
    sterilizeDate: null,
    expiryDate: null,
  };

  it('starts with the correct 60x40mm size header and a BITMAP command', async () => {
    const tspl = await buildTsplLabel(base);
    const text = tspl.toString('ascii');
    expect(text.startsWith('SIZE 60 mm, 40 mm')).toBe(true);
    expect(text).toContain('BITMAP 0,0,60,320,0,');
    expect(text).toContain('PRINT 1,1');
  });

  it('encodes only packageId in the QR (domain rule: no extra data in QR) — decodes back correctly', async () => {
    const tspl = await buildTsplLabel(base);
    const { rgba } = decodeBitmap(tspl);
    const result = jsQR(rgba, WIDTH_DOTS, HEIGHT_DOTS);
    expect(result?.data).toBe(base.packageId);
  });

  it('renders Thai glyphs without throwing (bitmap has black pixels — not blank/tofu)', async () => {
    const tspl = await buildTsplLabel(base);
    const { rgba } = decodeBitmap(tspl);
    let blackCount = 0;
    for (let i = 0; i < rgba.length; i += 4) {
      if (rgba[i] === 0) blackCount++;
    }
    expect(blackCount).toBeGreaterThan(100);
  });

  it('draws the "not sterilized" banner (extra black pixels in the date area) when dates are unset', async () => {
    const notSterilized = await buildTsplLabel(base);
    const sterilized = await buildTsplLabel({
      ...base,
      sterilizeDate: '2026-06-30T00:00:00.000Z',
      expiryDate: '2026-12-27T00:00:00.000Z',
    });
    // แถบดำเต็มพื้นที่ (ไม่ใช่ fabricate วันที่) ต้องมีจุดดำในโซนวันที่มากกว่าเคสมีวันที่จริงมาก
    const countBlackInBand = (buf: Buffer) => {
      const { rgba } = decodeBitmap(buf);
      let count = 0;
      for (let y = 254; y < 314; y++) {
        for (let x = 12; x < WIDTH_DOTS - 12; x++) {
          const o = (y * WIDTH_DOTS + x) * 4;
          if (rgba[o] === 0) count++;
        }
      }
      return count;
    };
    expect(countBlackInBand(notSterilized)).toBeGreaterThan(countBlackInBand(sterilized) * 5);
  });

  it('rejects a packageId with an unsafe format (defense-in-depth against tampered payloads)', async () => {
    await expect(
      buildTsplLabel({ ...base, packageId: '../../etc/passwd\r\nEVIL' }),
    ).rejects.toThrow(PayloadValidationError);
  });
});

describe('verifyPayloadHash', () => {
  const payload: PrintJobPayload = {
    packageId: 'clx4qr7z10000abcd12345678',
    setName: 'ชุดทำแผล',
    wrapType: 'SEAL',
    sterilizeDate: null,
    expiryDate: null,
  };

  it('matches regardless of key order (Postgres jsonb does not guarantee order)', () => {
    const hash = require('crypto')
      .createHash('sha256')
      .update(JSON.stringify(payload, Object.keys(payload).sort()))
      .digest('hex');
    const reordered = {
      wrapType: payload.wrapType,
      packageId: payload.packageId,
      expiryDate: payload.expiryDate,
      setName: payload.setName,
      sterilizeDate: payload.sterilizeDate,
    };
    expect(verifyPayloadHash(reordered as PrintJobPayload, hash)).toBe(true);
  });

  it('rejects a mismatched hash (tampered/stale payload)', () => {
    expect(verifyPayloadHash(payload, 'deadbeef')).toBe(false);
  });
});
