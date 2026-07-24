import { ApiClient } from './api-client';
import { buildTsplLabel, PayloadValidationError, verifyPayloadHash } from './label-renderer';
import { PrinterTransport, TransportSendError } from './transports/transport';

/**
 * Claim → ตรวจ payloadHash → PRINTING → ส่งจริง → SENT → ACK/fail หนึ่งงาน —
 * คืน `false` เมื่อไม่มีงานรอ
 *
 * FIX-04 (duplicate-print ambiguity หลัง write) — จัดประเภทผล transport.send():
 * - SENT (resolve)         → markSent + ack (พิมพ์สำเร็จ)
 * - NOT_SENT               → fail() ได้ (retry ปลอดภัย เพราะยังไม่มี byte ออกไป)
 * - MAYBE_SENT             → reportMaybeSent() → ACK_UNKNOWN ห้าม auto-retry
 * - error ที่ไม่ระบุชนิด    → ถือเป็น MAYBE_SENT เสมอ (กฎห้ามละเมิด: "ห้ามถือว่า
 *                            write() error แปลว่าไม่มี byte ใดถูกส่ง")
 *
 * หลัง transport.send() สำเร็จแล้ว ถ้า markSent()/ack() ยิงไป backend ไม่ได้
 * (network หลุด) ให้ log เฉยๆ ปล่อยให้ backend lease-recovery แปลง job ที่ค้าง
 * เป็น ACK_UNKNOWN แทนการเดา — ไม่ retry เอง
 */
export async function processOneJob(
  api: ApiClient,
  transport: PrinterTransport,
): Promise<boolean> {
  const job = await api.claim();
  if (!job) return false;

  if (!verifyPayloadHash(job.payload, job.payloadHash)) {
    // payload ไม่ตรง hash — อาจถูกแก้ระหว่างทาง/บั๊ก ห้ามพิมพ์ (audit ข้อ 2.4)
    // ยังไม่เคยเรียก transport.send() จึง fail() ได้ปลอดภัย
    await api
      .fail(job.id, 'PAYLOAD_HASH_MISMATCH', 'payload ไม่ตรงกับ payloadHash — ปฏิเสธการพิมพ์')
      .catch(() => {});
    return true;
  }

  let tspl: Buffer;
  try {
    await api.markPrinting(job.id);
    tspl = await buildTsplLabel(job.payload);
  } catch (e) {
    // ล้มก่อนเรียก transport.send() (validation/render/markPrinting) — ยังไม่เคย
    // ส่งอะไรไปเครื่องพิมพ์ → NOT_SENT → fail() ได้ปลอดภัย
    const errorCode = e instanceof PayloadValidationError ? 'INVALID_PAYLOAD' : 'RENDER_ERROR';
    const message = e instanceof Error ? e.message : String(e);
    await api.fail(job.id, errorCode, message).catch(() => {});
    return true;
  }

  try {
    await transport.send(tspl);
  } catch (e) {
    if (e instanceof TransportSendError && e.outcome === 'NOT_SENT') {
      // ยังไม่มี byte ออกไปเลย (เช่นเปิดพอร์ตไม่ได้) → retry ปลอดภัย
      await api.fail(job.id, 'TRANSPORT_NOT_SENT', e.message).catch(() => {});
    } else {
      // MAYBE_SENT หรือ error ที่ไม่ระบุชนิด → ถือว่าอาจส่งไปแล้วบางส่วน ห้าม retry
      const message = e instanceof Error ? e.message : String(e);
      await api.reportMaybeSent(job.id, 'TRANSPORT_MAYBE_SENT', message).catch(() => {
        // แจ้ง backend ไม่ได้ (network) — ปล่อยให้ lease-recovery แปลง PRINTING →
        // ACK_UNKNOWN แทน (ไม่ retry เอง)
      });
    }
    return true;
  }

  // transport.send() confirm สำเร็จแล้ว (SENT) — ห้าม fail()/retry อีกต่อไป
  // backend ตัดสินเองว่าจะเป็น PRINTED หรือ SIMULATED จาก capability ของ gateway (FIX-05)
  try {
    await api.markSent(job.id);
    await api.ack(job.id);
  } catch (e) {
    console.error(
      `[poll-loop] ส่งพิมพ์สำเร็จแล้วแต่แจ้ง backend ไม่สำเร็จ (job ${job.id}):`,
      e instanceof Error ? e.message : e,
      '— ปล่อยให้ backend lease-recovery แปลงเป็น ACK_UNKNOWN แทน (ไม่ retry เอง)',
    );
  }
  return true;
}
