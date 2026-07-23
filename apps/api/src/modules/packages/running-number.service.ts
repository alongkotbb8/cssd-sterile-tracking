import { ConflictException, Injectable } from '@nestjs/common';
import { Prisma, RunningNumberSequence } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';

// Running number format: {SET_CODE}-{YYYYMMDD}-{SEQ4}
// e.g. DELIV-20260630-0007
// MUST be generated server-side to prevent duplicates across concurrent users.

const MAX_RETRIES = 3;

@Injectable()
export class RunningNumberService {
  constructor(private prisma: PrismaService) {}

  /**
   * Atomically increment the per-template/per-day sequence and return the row.
   *
   * `upsert` here compiles to a single `INSERT ... ON CONFLICT DO UPDATE`
   * (no nested writes, unique where) so the increment is atomic. If Prisma
   * ever falls back to select-then-insert, two concurrent first-of-the-day
   * calls can race on the create — that surfaces as P2002, which we retry
   * (the retry takes the `update: increment` path and succeeds).
   */
  private async incrementSeq(
    db: Prisma.TransactionClient | PrismaService,
    setTemplateId: string,
    dateStr: string,
    by: number,
  ): Promise<RunningNumberSequence> {
    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      try {
        // upsert = INSERT ... ON CONFLICT DO UPDATE (statement เดียว atomic) จึง
        // ปลอดภัยเมื่อรันในทรานแซกชันร่วมกับ package.create (FIX-02 แนวทาง A) —
        // เลขรันจะ rollback ไปพร้อมกันถ้าทรานแซกชันล้ม (ไม่เกิดเลขกระโดด)
        return await db.runningNumberSequence.upsert({
          where: { setTemplateId_date: { setTemplateId, date: dateStr } },
          update: { lastSeq: { increment: by } },
          create: { setTemplateId, date: dateStr, lastSeq: by },
        });
      } catch (e) {
        const isUniqueConflict =
          e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002';
        if (!isUniqueConflict) throw e;
      }
    }
    throw new ConflictException('ออกเลขรันไม่สำเร็จ กรุณาลองใหม่');
  }

  async nextId(
    setTemplateCode: string,
    setTemplateId: string,
    date: Date,
    db: Prisma.TransactionClient | PrismaService = this.prisma,
  ): Promise<string> {
    const dateStr = this.toDateStr(date);
    const row = await this.incrementSeq(db, setTemplateId, dateStr, 1);
    return this.format(setTemplateCode, dateStr, row.lastSeq);
  }

  /** Reserve a pool of IDs for offline use */
  async reservePool(
    setTemplateId: string,
    setTemplateCode: string,
    date: Date,
    count: number,
    deviceId: string,
    userId: string,
  ): Promise<string[]> {
    const dateStr = this.toDateStr(date);
    const row = await this.incrementSeq(this.prisma, setTemplateId, dateStr, count);

    const from = row.lastSeq - count + 1;
    const to = row.lastSeq;

    await this.prisma.numberPoolReservation.create({
      data: { setTemplateId, date: dateStr, fromSeq: from, toSeq: to, deviceId, userId },
    });

    const ids: string[] = [];
    for (let i = from; i <= to; i++) {
      ids.push(this.format(setTemplateCode, dateStr, i));
    }
    return ids;
  }

  private format(code: string, dateStr: string, seq: number): string {
    return `${code}-${dateStr}-${String(seq).padStart(4, '0')}`;
  }

  private toDateStr(date: Date): string {
    return date.toISOString().slice(0, 10).replace(/-/g, '');
  }
}
