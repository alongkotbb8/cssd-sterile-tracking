import { BadRequestException, ConflictException, Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { createHash } from 'crypto';
import { IdempotencyStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

// เก็บ response ของ request ที่จบแล้วไว้ replay ได้ระยะหนึ่ง แล้วให้ cron เก็บกวาด
// กันตารางโตไม่จำกัด (audit ข้อ 2.7)
const DONE_RETENTION_MS = 24 * 60 * 60_000;
// เผื่อ scan batch ใหญ่ที่ทำหลายห่อในทรานแซกชันเดียว — interactive tx ของ Prisma
// default timeout แค่ 5 วิ ซึ่งอาจไม่พอ จึงตั้งให้กว้างขึ้น (single-hospital scale)
const TX_TIMEOUT_MS = 20_000;
const TX_MAX_WAIT_MS = 8_000;

export type IdempotentFn<T> = (tx: Prisma.TransactionClient) => Promise<T>;

/**
 * กันคำขอซ้ำจาก retry/offline-sync แบบ **atomic จริง + crash-safe** (FIX-02
 * ของ M1_M2_REAUDIT_FIX_DIRECTIVE, แนวทาง A)
 *
 * reservation (แถว idempotent_requests) + domain mutation + AuditLog + การเก็บ
 * response ทั้งหมดอยู่ใน **transaction เดียวกัน** — ถ้า process ตายกลางคัน
 * transaction จะ rollback ทั้งก้อน จึงเป็นไปไม่ได้ที่จะมีแถว PENDING ที่ commit
 * แล้วคู่กับ mutation ที่สำเร็จไปครึ่งทาง (ไม่มี stale PENDING ให้ต้อง reconcile
 * และไม่มีการ rerun mutation โดยเดาจากเวลา ซึ่งกฎห้ามละเมิดสั่งห้ามไว้ชัดเจน)
 *
 * unique constraint บน `key` ทำหน้าที่เป็น compare-and-swap: request ซ้ำที่ยิง
 * พร้อมกันจะถูก Postgres บล็อกที่ INSERT จนกว่าตัวแรกจะ commit/rollback แล้วจึง
 * เห็นผลจริง (commit → P2002 → replay response, rollback → รันเองได้)
 */
@Injectable()
export class IdempotencyService {
  private readonly logger = new Logger(IdempotencyService.name);

  constructor(private prisma: PrismaService) {}

  private hash(payload: unknown): string {
    return createHash('sha256').update(JSON.stringify(payload ?? null)).digest('hex');
  }

  /**
   * รัน `fn(tx)` แบบกันซ้ำ + atomic
   *
   * - `opts.required=true` แล้วไม่ส่ง key มา → 400 (endpoint นี้บังคับต้องมี key)
   * - ไม่ required และไม่มี key → รันใน transaction เดี่ยว (ไม่กันซ้ำ แต่ยัง atomic)
   * - key เดิม + payload เดิม + เคยรันจบแล้ว → คืน response เดิม ไม่รันซ้ำ
   * - key เดิม + payload ต่างกัน → 409
   * - key เดิม + user ต่างกัน → 409 (กันเห็น response ข้ามผู้ใช้)
   * - key เดิมยังค้าง PENDING (ผิดปกติ/แถวเก่าจากโค้ดก่อน FIX-02) → 409 ไม่ rerun
   */
  async run<T>(
    key: string | undefined,
    userId: string,
    endpoint: string,
    method: string,
    payload: unknown,
    fn: IdempotentFn<T>,
    opts: { required?: boolean } = {},
  ): Promise<T> {
    if (!key) {
      if (opts.required) {
        throw new BadRequestException(`endpoint นี้ต้องส่ง header Idempotency-Key`);
      }
      // ไม่มี key แต่ยังต้องรันใน transaction เพื่อความ atomic ของ mutation เอง
      return this.prisma.$transaction((tx) => fn(tx), {
        timeout: TX_TIMEOUT_MS,
        maxWait: TX_MAX_WAIT_MS,
      });
    }

    const requestHash = this.hash(payload);
    const now = new Date();

    try {
      return await this.prisma.$transaction(
        async (tx) => {
          // reservation ในทรานแซกชันเดียวกับ mutation — ถ้า INSERT ชนกับ key ที่
          // commit แล้ว (request ก่อน/ที่ยิงพร้อมกัน) จะ throw P2002 → rollback ทั้งก้อน
          await tx.idempotentRequest.create({
            data: {
              key,
              userId,
              endpoint,
              method,
              requestHash,
              status: IdempotencyStatus.PENDING,
              expiresAt: new Date(now.getTime() + DONE_RETENTION_MS),
            },
          });
          const result = await fn(tx);
          await tx.idempotentRequest.update({
            where: { key },
            data: {
              status: IdempotencyStatus.DONE,
              response: result as Prisma.InputJsonValue,
              expiresAt: new Date(Date.now() + DONE_RETENTION_MS),
            },
          });
          return result;
        },
        { timeout: TX_TIMEOUT_MS, maxWait: TX_MAX_WAIT_MS },
      );
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        // P2002 อาจมาจาก (ก) reservation key ชน หรือ (ข) unique constraint ของ
        // domain เอง (เช่น เลขรัน/รอบซ้ำ) — แยกด้วยการอ่านแถว idempotent_requests
        // ของ key นี้: ถ้ามี = กรณี (ก) reconcile, ถ้าไม่มี = กรณี (ข) โยนต่อ
        const existing = await this.prisma.idempotentRequest.findUnique({ where: { key } });
        if (existing) return this.replay<T>(existing, userId, requestHash, endpoint, method);
      }
      throw e;
    }
  }

  private replay<T>(
    existing: {
      userId: string;
      endpoint: string;
      method: string;
      requestHash: string;
      status: IdempotencyStatus;
      response: unknown;
    },
    userId: string,
    requestHash: string,
    endpoint: string,
    method: string,
  ): T {
    if (existing.userId !== userId) {
      throw new ConflictException({ message: 'Idempotency-Key นี้ถูกใช้โดยผู้ใช้อื่นแล้ว', code: 'IDEMPOTENCY_CONFLICT' });
    }
    // key เดิมต้องมาจาก endpoint+method เดิมเท่านั้น — กัน client เผลอ reuse key
    // ข้าม endpoint (เช่น key เดียวยิงทั้ง scan/out และ print-jobs/create)
    if (existing.endpoint !== endpoint || existing.method !== method) {
      throw new ConflictException(
        `Idempotency-Key นี้เคยใช้กับ endpoint อื่น (${existing.method} ${existing.endpoint}) — ต้องสร้าง key ใหม่`,
      );
    }
    if (existing.requestHash !== requestHash) {
      throw new ConflictException(
        'Idempotency-Key นี้เคยใช้กับคำขอที่มีข้อมูลต่างกัน — ต้องสร้าง key ใหม่',
      );
    }
    if (existing.status === IdempotencyStatus.DONE) {
      return existing.response as T;
    }
    // ยังเป็น PENDING: ในแนวทาง A แถว PENDING จะไม่มีทาง commit เดี่ยวๆ (commit
    // พร้อม DONE เสมอ) การเจอ PENDING ที่ commit แล้วจึงผิดปกติ (เช่นแถวค้างจาก
    // โค้ดก่อน FIX-02) — ตอบ 409 ห้าม rerun เด็ดขาด ให้ client สร้าง key ใหม่หรือ
    // ตรวจผลลัพธ์จริงเอง (ห้ามใช้เวลาอย่างเดียวตัดสินว่า mutation ไม่สำเร็จ)
    throw new ConflictException(
      'คำขอที่ใช้ Idempotency-Key นี้ยังค้างอยู่หรือผลลัพธ์ไม่แน่นอน — กรุณาตรวจสอบผลก่อน แล้วใช้ key ใหม่หากต้องลองซ้ำ',
    );
  }

  /**
   * เก็บกวาดเฉพาะแถว **DONE** ที่เกิน retention เท่านั้น
   *
   * ⚠️ ห้ามลบแถว PENDING ในนี้เด็ดขาด (กฎห้ามละเมิด: "ห้ามลบ PENDING โดยไม่ตรวจ
   * domain result") — ในแนวทาง A แถว PENDING จะไม่มีทาง commit เดี่ยวๆ อยู่แล้ว
   * ถ้าเจอ PENDING ค้าง (แถวเก่าจากก่อน FIX-02 หรือความผิดปกติ) ให้คงไว้เป็น
   * หลักฐานให้คนตรวจ/ reconcile เอง ไม่ลบทิ้งโดยดูแค่เวลา
   */
  @Cron('0 * * * *')
  async cleanupExpired() {
    const { count } = await this.prisma.idempotentRequest.deleteMany({
      where: { status: IdempotencyStatus.DONE, expiresAt: { lt: new Date() } },
    });
    if (count > 0) this.logger.log(`Cleaned up ${count} expired DONE idempotency record(s)`);
  }
}
