import { spawn } from 'child_process';
import { PrinterTransport, TransportSendError } from './transport';

/**
 * ส่ง raw TSPL เข้า OS printer queue (USB printer-class) — สำหรับ Xprinter XP-420B
 * ที่ต่อ USB แล้วปรากฏเป็น printer queue ไม่ใช่ virtual COM/serial
 *
 * ข้ามแพลตฟอร์ม (เลือกตอน runtime ตาม `process.platform`):
 * - posix (linux/darwin): `lp -d <queue> -o raw` อ่าน TSPL จาก stdin (CUPS)
 * - win32: `lpr -S 127.0.0.1 -P <queue> -o l <stdin?>` ... Windows lpr อ่านจากไฟล์
 *   เท่านั้น ไม่รับ stdin → ใช้ temp file (ยังไม่ทดสอบบน Windows จริง — ดู README/
 *   HARDWARE_VERIFICATION) *ต้องยืนยัน mechanism กับ host Windows จริงก่อน pilot*
 *
 * ความปลอดภัย: **ไม่ใช้ shell** (spawn + arg array) และ validate ชื่อ queue ให้เป็น
 * ตัวอักษร/ตัวเลข/`._-` เท่านั้น กัน command/arg injection (บรีฟ section 4.2)
 *
 * การจำแนกผล (FIX-04 semantics):
 * - เปิด process/หา command ไม่ได้ (ก่อนเขียน byte ใด) → NOT_SENT (retry ปลอดภัย)
 * - เขียน stdin แล้ว process จบด้วย exit code != 0 / timeout / error หลังเริ่มเขียน
 *   → MAYBE_SENT (ข้อมูลอาจถึง spooler/เครื่องแล้ว ห้าม auto-retry)
 * - exit 0 → SENT (ส่งเข้า queue สำเร็จ — *ไม่ยืนยันว่ากระดาษออกจริง* ดู SOP)
 */
const QUEUE_NAME_RE = /^[A-Za-z0-9._-]+$/;

export class UsbSpoolTransport implements PrinterTransport {
  readonly isSimulated = false;

  constructor(
    private readonly queueName: string,
    private readonly timeoutMs: number = 15_000,
  ) {
    if (!QUEUE_NAME_RE.test(queueName)) {
      // ผิดตั้งแต่ config — โยนตอนสร้าง (fail fast ก่อนสตาร์ท) กัน injection
      throw new Error(
        `PRINTER_QUEUE_NAME ไม่ถูกต้อง: "${queueName}" (ใช้ได้เฉพาะ A-Z a-z 0-9 . _ -)`,
      );
    }
  }

  send(tspl: Buffer): Promise<void> {
    const isWin = process.platform === 'win32';
    // posix: lp อ่าน stdin ได้; win32: lpr ต้องอ่านจากไฟล์ (จัดการแยกด้านล่าง)
    return isWin ? this.sendWindows(tspl) : this.sendPosix(tspl);
  }

  /** CUPS: `lp -d <queue> -o raw` (อ่าน TSPL จาก stdin) */
  private sendPosix(tspl: Buffer): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const child = spawn('lp', ['-d', this.queueName, '-o', 'raw'], { stdio: ['pipe', 'ignore', 'pipe'] });
      let settled = false;
      let stderr = '';

      const done = (fn: () => void) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        fn();
      };

      const timer = setTimeout(() => {
        child.kill('SIGKILL');
        done(() => reject(new TransportSendError('MAYBE_SENT', `lp timeout ${this.timeoutMs}ms`)));
      }, this.timeoutMs);

      child.stderr?.on('data', (d) => (stderr += d.toString()));

      // child 'error' = spawn ล้มเหลว (ไม่มี lp/CUPS, EACCES) — process ไม่ได้รัน
      // จึงยังไม่มี byte ใดออก → NOT_SENT (retry ปลอดภัย)
      child.on('error', (err) =>
        done(() => reject(new TransportSendError('NOT_SENT', `เรียก lp ไม่สำเร็จ: ${err.message}`))),
      );

      // process รันแล้วแต่จบ != 0 (queue ไม่มี/เครื่องมีปัญหา) — แยกไม่ได้ชัดว่าถึง
      // เครื่องหรือยัง → MAYBE_SENT (ห้าม auto-retry, ให้คนตรวจ)
      child.on('close', (code) =>
        code === 0
          ? done(() => resolve())
          : done(() => reject(new TransportSendError('MAYBE_SENT', `lp exit ${code}: ${stderr.trim()}`))),
      );

      const stdin = child.stdin;
      if (!stdin) {
        done(() => reject(new TransportSendError('NOT_SENT', 'lp ไม่มี stdin')));
        return;
      }
      // stdin error หลังเริ่มเขียน (เช่น EPIPE เพราะ process ตายกลางคัน) — อาจส่งไป
      // บางส่วนแล้ว → MAYBE_SENT
      stdin.on('error', (err) =>
        done(() => reject(new TransportSendError('MAYBE_SENT', `เขียน stdin ล้มเหลว: ${err.message}`))),
      );
      stdin.end(tspl);
    });
  }

  /**
   * Windows: lpr อ่านจากไฟล์ (ไม่รับ stdin) — เขียน temp file แล้ว `lpr -S 127.0.0.1
   * -P <queue> -o l <file>` (ต้องเปิด LPD/LPR Port Monitor feature) *ยังไม่ทดสอบบน
   * Windows จริง* — ต้องยืนยันตอน hardware verification (อาจต้องเปลี่ยนเป็นวิธีอื่น
   * เช่น RawPrint/native ตาม setup ของโรงพยาบาล)
   */
  private async sendWindows(tspl: Buffer): Promise<void> {
    const os = await import('os');
    const path = await import('path');
    const fs = await import('fs/promises');
    const tmp = path.join(os.tmpdir(), `cssd-print-${process.pid}-${Date.now()}.bin`);
    try {
      await fs.writeFile(tmp, tspl);
    } catch (e) {
      // เขียน temp file ไม่ได้ = ยังไม่ได้ส่งอะไร → NOT_SENT
      throw new TransportSendError('NOT_SENT', `เขียน temp file ไม่ได้: ${(e as Error).message}`);
    }
    try {
      await new Promise<void>((resolve, reject) => {
        const child = spawn('lpr', ['-S', '127.0.0.1', '-P', this.queueName, '-o', 'l', tmp]);
        let settled = false;
        let stderr = '';
        const done = (fn: () => void) => { if (!settled) { settled = true; clearTimeout(timer); fn(); } };
        const timer = setTimeout(() => {
          child.kill();
          done(() => reject(new TransportSendError('MAYBE_SENT', `lpr timeout ${this.timeoutMs}ms`)));
        }, this.timeoutMs);
        child.stderr?.on('data', (d) => (stderr += d.toString()));
        // lpr เริ่มรับงานเมื่อ spawn สำเร็จ — ถ้า spawn error ถือ NOT_SENT (ยังไม่ส่ง)
        child.on('error', (err) =>
          done(() => reject(new TransportSendError('NOT_SENT', `เรียก lpr ไม่สำเร็จ: ${err.message}`))),
        );
        child.on('close', (code) =>
          code === 0
            ? done(() => resolve())
            : done(() => reject(new TransportSendError('MAYBE_SENT', `lpr exit ${code}: ${stderr.trim()}`))),
        );
      });
    } finally {
      await fs.unlink(tmp).catch(() => {});
    }
  }
}
