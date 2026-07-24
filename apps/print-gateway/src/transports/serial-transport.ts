import { SerialPort } from 'serialport';
import { PrinterTransport, TransportSendError } from './transport';

/**
 * ส่ง TSPL ตรงผ่าน virtual COM/serial — ใช้เมื่อ driver ของเครื่องพิมพ์สร้าง COM
 * port ให้ OS เท่านั้น ⚠️ **ทางหลักของ Xprinter XP-420B คือ `usb_spool`** (USB
 * printer-class → OS printer queue ดู usb-spool-transport.ts) SerialTransport
 * เป็นทางเลือกสำรองกรณีเครื่อง/driver ปรากฏเป็น virtual COM — ต้องตั้ง baud rate
 * ให้ตรงกับเครื่อง (ดู DIP switch/คู่มือ ค่าเริ่มต้นทั่วไป 9600)
 *
 * FIX-04 — จัดประเภท error ตามช่วงที่เกิด:
 * - เปิด port ไม่ได้ (ก่อน write) → NOT_SENT (ยังไม่มี byte ออกไป retry ปลอดภัย)
 * - write() callback error → MAYBE_SENT (เริ่มเขียนแล้ว อาจออกไปบางส่วน ห้าม retry)
 * - drain() error หลัง write สำเร็จ → MAYBE_SENT (ข้อมูลน่าจะออกไปแล้ว ห้าม retry)
 */
export class SerialTransport implements PrinterTransport {
  readonly isSimulated = false;
  private port: SerialPort;
  private opening: Promise<void> | null = null;

  constructor(path: string, baudRate: number) {
    this.port = new SerialPort({ path, baudRate, autoOpen: false });
  }

  private ensureOpen(): Promise<void> {
    if (this.port.isOpen) return Promise.resolve();
    if (!this.opening) {
      this.opening = new Promise<void>((resolve, reject) => {
        this.port.open((err) => {
          this.opening = null;
          if (err) reject(err);
          else resolve();
        });
      });
    }
    return this.opening;
  }

  async send(tspl: Buffer): Promise<void> {
    // เปิด port ล้มเหลว = ยังไม่ได้เขียนอะไรเลย → NOT_SENT
    try {
      await this.ensureOpen();
    } catch (e) {
      throw new TransportSendError(
        'NOT_SENT',
        `เปิดพอร์ตเครื่องพิมพ์ไม่ได้: ${e instanceof Error ? e.message : String(e)}`,
      );
    }

    // ถึงจุดนี้เริ่มเขียนแล้ว — error ใดๆ ต่อจากนี้ถือว่า MAYBE_SENT เสมอ
    await new Promise<void>((resolve, reject) => {
      this.port.write(tspl, (writeErr) => {
        if (writeErr) {
          return reject(
            new TransportSendError('MAYBE_SENT', `write ล้มเหลว (อาจส่งไปบางส่วน): ${writeErr.message}`),
          );
        }
        this.port.drain((drainErr) => {
          if (drainErr) {
            return reject(
              new TransportSendError(
                'MAYBE_SENT',
                `drain ล้มเหลวหลัง write (ข้อมูลน่าจะออกไปแล้ว): ${drainErr.message}`,
              ),
            );
          }
          resolve();
        });
      });
    });
  }
}
