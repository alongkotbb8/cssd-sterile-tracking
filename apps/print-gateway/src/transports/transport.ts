/**
 * Adapter pattern เดียวกับ `PrinterAdapter` ฝั่ง Flutter
 * (apps/mobile/lib/core/printer/printer_adapter.dart) — สลับ implementation
 * ได้โดยไม่แตะ logic คิวงาน สลับผ่าน `PRINTER_TRANSPORT` env var
 */
export interface PrinterTransport {
  /**
   * true = mock/console (ไม่ใช่การพิมพ์จริง) — poll-loop ใช้ค่านี้ตัดสินว่าต้อง
   * ACK เป็น SIMULATED เท่านั้น ห้ามตั้งเป็น PRINTED เด็ดขาด (audit ข้อ 1.2)
   */
  readonly isSimulated: boolean;
  /**
   * ส่ง bytes (คำสั่ง TSPL) ไปเครื่องพิมพ์
   * - resolve = SENT (ยืนยันว่าข้อมูลออกไปครบแล้ว)
   * - throw TransportSendError('NOT_SENT') = ยังไม่มี byte ใดออกไปเลย (retry ได้)
   * - throw TransportSendError('MAYBE_SENT') = อาจมี byte ออกไปแล้วบางส่วน (ห้าม retry)
   */
  send(tspl: Buffer): Promise<void>;
}

/**
 * FIX-04: แยกผลของการส่งเป็น 3 ระดับ เพื่อไม่ให้ write() error กลายเป็นการ
 * พิมพ์ซ้ำ — "ห้ามถือว่า write() error แปลว่าไม่มี byte ใดถูกส่ง"
 */
export type SendOutcome = 'NOT_SENT' | 'MAYBE_SENT';

export class TransportSendError extends Error {
  constructor(
    public readonly outcome: SendOutcome,
    message: string,
  ) {
    super(message);
    this.name = 'TransportSendError';
  }
}
