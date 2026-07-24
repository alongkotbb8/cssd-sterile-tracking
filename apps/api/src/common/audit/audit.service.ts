import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private prisma: PrismaService) {}

  /**
   * เขียน audit log **ภายใน transaction เดียวกับ mutation หลัก** — ถ้า audit
   * เขียนไม่ได้ทั้ง transaction จะ rollback (ข้อมูลหลักกับ audit ตรงกันเสมอ)
   * ใช้ตัวนี้กับทุก mutation ที่อยู่ใน $transaction อยู่แล้ว
   */
  logTx(
    tx: Prisma.TransactionClient,
    userId: string,
    action: string,
    targetId?: string,
    metadata?: Record<string, unknown>,
  ) {
    return tx.auditLog.create({
      data: {
        userId,
        action,
        targetId,
        metadata: metadata as Prisma.InputJsonValue | undefined,
      },
    });
  }

  /** เขียน audit นอก transaction (best-effort) — ใช้เฉพาะจุดที่ไม่มี transaction ครอบ */
  async log(userId: string, action: string, targetId?: string, metadata?: Record<string, unknown>) {
    try {
      return await this.prisma.auditLog.create({
        data: {
          userId,
          action,
          targetId,
          metadata: metadata as Prisma.InputJsonValue | undefined,
        },
      });
    } catch (e) {
      // An audit failure must never roll back / mask the business operation,
      // but it must be visible in server logs.
      this.logger.error(
        `Failed to write audit log (${action} ${targetId ?? ''})`,
        e instanceof Error ? e.stack : String(e),
      );
      return null;
    }
  }
}
