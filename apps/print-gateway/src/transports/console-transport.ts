import { PrinterTransport } from './transport';

/**
 * Transport เริ่มต้น — พิมพ์คำสั่ง TSPL ลง console แทนฮาร์ดแวร์จริง
 * (เทียบเท่า MockPrinterAdapter ฝั่ง Flutter) ใช้พัฒนา/ทดสอบ pipeline
 * คิวงานได้โดยไม่ต้องมีเครื่องพิมพ์จริง — `isSimulated=true` กันไม่ให้ ACK
 * กลายเป็น PRINTED จริง (ดู transport.ts) — ต้องไม่ใช้ตัวนี้ใน production
 * (config.ts ปฏิเสธการสตาร์ทถ้า NODE_ENV=production ใช้ transport นี้)
 */
export class ConsoleTransport implements PrinterTransport {
  readonly isSimulated = true;

  async send(tspl: Buffer): Promise<void> {
    console.log('[ConsoleTransport] would send %d bytes of TSPL:', tspl.length);
    console.log(tspl.toString('latin1'));
  }
}
