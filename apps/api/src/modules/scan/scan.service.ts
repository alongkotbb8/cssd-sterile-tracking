import {
  Injectable,
  BadRequestException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { PackageStatus, MovementType, Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { isExpired, daysLeft } from '../../common/expiry';

export interface ScanResult {
  packageId: string;
  success: boolean;
  error?: string;
  package?: Record<string, unknown>;
}

@Injectable()
export class ScanService {
  private readonly logger = new Logger(ScanService.name);

  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  /**
   * ⚠️ FIX-02 แนวทาง A: ทั้ง request รันในทรานแซกชันเดียว (idempotency ส่ง tx เข้ามา)
   *
   * ผลลัพธ์รายห่อ (สำเร็จ/ไม่ผ่าน) ยังรายงานแยกได้เหมือนเดิม เพราะ "ไม่ผ่าน" ที่
   * เป็นเหตุการณ์ปกติ (ไม่พบห่อ/สถานะผิด/หมดอายุ/CAS ชน) จะ **ไม่ throw** แค่ push
   * ลง results แล้วไปห่อถัดไป ทรานแซกชันยังใช้ได้ต่อ
   *
   * แต่ถ้าเกิด DB error จริง (constraint/connection) จะ throw ออกไปให้ทรานแซกชัน
   * rollback ทั้ง request (all-or-nothing) — ปลอดภัยกว่าเดิมเพราะไม่มีทางที่บาง
   * ห่อ commit แล้วบางห่อค้าง และ retry ด้วย idempotency-key เดิมจะเริ่มใหม่สะอาด
   * (ต่างจากพฤติกรรมเดิมที่ commit ทีละห่อแยกกัน — ดู PROGRESS.md/known limitations)
   */

  /**
   * Scan in: ผูกห่อ PACKED เข้ารอบนึ่งที่ยัง PENDING (ก่อนเริ่มนึ่ง)
   *
   * ลำดับที่ถูกหลัก traceability: ห่อต้องอยู่ในรอบ *ก่อน* มีผลตรวจ — ห่อจะ
   * กลายเป็น STERILE ก็ต่อเมื่อ SUPERVISOR/ADMIN บันทึกผล CI/BI ผ่าน
   */
  async scanIn(
    packageIds: string[],
    batchId: string,
    userId: string,
    manualEntry: boolean,
    tx: Prisma.TransactionClient,
  ): Promise<ScanResult[]> {
    const batch = await tx.sterilizationBatch.findUnique({ where: { id: batchId } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');
    if (batch.status !== 'PENDING') {
      throw new BadRequestException(
        'รอบนึ่งนี้บันทึกผลไปแล้ว — เพิ่มห่อย้อนหลังไม่ได้ กรุณาเปิดรอบใหม่',
      );
    }

    const results: ScanResult[] = [];
    for (const id of packageIds) {
      const pkg = await tx.package.findUnique({ where: { id } });
      if (!pkg) { results.push({ packageId: id, success: false, error: 'ไม่พบห่อ' }); continue; }
      if (pkg.status !== PackageStatus.PACKED) {
        results.push({ packageId: id, success: false, error: `สถานะปัจจุบัน: ${pkg.status}` }); continue;
      }
      if (pkg.batchId === batchId) {
        results.push({ packageId: id, success: false, error: 'ห่อนี้อยู่ในรอบนี้แล้ว' }); continue;
      }
      if (pkg.batchId) {
        results.push({ packageId: id, success: false, error: 'ห่อนี้อยู่ในรอบนึ่งอื่นอยู่แล้ว' }); continue;
      }

      // CAS: batchId ต้องยังว่างและสถานะยัง PACKED กันสแกนซ้ำพร้อมกันจาก 2 เครื่อง
      const { count } = await tx.package.updateMany({
        where: { id, status: PackageStatus.PACKED, batchId: null },
        data: { batchId },
      });
      if (count === 0) {
        results.push({ packageId: id, success: false, error: 'ห่อนี้ถูกสแกนไปพร้อมกันจากที่อื่นแล้ว' });
        continue;
      }
      await this.audit.logTx(tx, userId, 'SCAN_IN_BATCH', id, {
        batchId,
        ...(manualEntry ? { manualEntry: true } : {}),
      });
      const updated = await tx.package.findUniqueOrThrow({ where: { id } });
      results.push({ packageId: id, success: true, package: updated as unknown as Record<string, unknown> });
    }
    return results;
  }

  /**
   * Scan out — two paths, chosen by the package's current status:
   *   STERILE → ISSUED     (ปกติ — บล็อกของหมดอายุ)
   *   PACKED  → PACKED_OUT (ส่งออกโดยยังไม่ฆ่าเชื้อ เช่น ส่งไป รพ. อื่น — ไม่มี expiry ให้เช็ค)
   */
  async scanOut(
    packageIds: string[],
    departmentId: string,
    receiverName: string | undefined,
    userId: string,
    manualEntry: boolean,
    tx: Prisma.TransactionClient,
  ): Promise<ScanResult[]> {
    const dept = await tx.department.findUnique({ where: { id: departmentId } });
    if (!dept) throw new NotFoundException('ไม่พบแผนกปลายทาง');

    const now = new Date();
    const results: ScanResult[] = [];

    for (const id of packageIds) {
      const pkg = await tx.package.findUnique({ where: { id } });
      if (!pkg) { results.push({ packageId: id, success: false, error: 'ไม่พบห่อ' }); continue; }

      // FR-4: block expired — บันทึกเหตุการณ์ถูกบล็อกไว้ทำรายงานเหตุการณ์ผิดปกติ
      // (ใช้ได้ตลอดวันหมดอายุ บล็อกตั้งแต่วันถัดไป — ดู common/expiry.ts)
      if (pkg.expiryDate && isExpired(pkg.expiryDate, now)) {
        await this.audit.logTx(tx, userId, 'SCAN_BLOCKED', id, {
          reason: 'EXPIRED',
          departmentId,
          expiryDate: pkg.expiryDate,
        });
        results.push({ packageId: id, success: false, error: '⛔ ห้ามใช้ — ห่อหมดอายุแล้ว' }); continue;
      }
      if (pkg.status !== PackageStatus.STERILE && pkg.status !== PackageStatus.PACKED) {
        results.push({ packageId: id, success: false, error: `สถานะปัจจุบัน: ${pkg.status}` }); continue;
      }

      const fromStatus = pkg.status;
      const toStatus =
        fromStatus === PackageStatus.STERILE ? PackageStatus.ISSUED : PackageStatus.PACKED_OUT;

      // status ใน where เป็น compare-and-swap อะตอมมิก กันสแกนซ้ำพร้อมกันจาก 2 เครื่อง
      const { count } = await tx.package.updateMany({
        where: { id, status: fromStatus },
        data: { status: toStatus },
      });
      if (count === 0) {
        results.push({ packageId: id, success: false, error: 'ห่อนี้ถูกสแกนไปพร้อมกันจากที่อื่นแล้ว' });
        continue;
      }
      await tx.movement.create({
        data: {
          packageId: id,
          type: MovementType.OUT,
          departmentId,
          receiverName: receiverName ?? null,
          performedById: userId,
        },
      });
      await this.audit.logTx(tx, userId, 'SCAN_OUT', id, {
        departmentId,
        receiverName,
        ...(toStatus === PackageStatus.PACKED_OUT ? { unsterile: true } : {}),
        ...(manualEntry ? { manualEntry: true } : {}),
      });
      results.push({ packageId: id, success: true });
    }
    return results;
  }

  /**
   * Return — two paths, chosen by the package's current status:
   *   ISSUED     → RETURNED (ปกติ — รอ reprocess)
   *   PACKED_OUT → PACKED   (ของไม่เคยฆ่าเชื้อ คืนแล้วพร้อมเข้ารอบนึ่งได้ทันที)
   */
  async scanReturn(
    packageIds: string[],
    departmentId: string,
    userId: string,
    manualEntry: boolean,
    tx: Prisma.TransactionClient,
  ): Promise<ScanResult[]> {
    const dept = await tx.department.findUnique({ where: { id: departmentId } });
    if (!dept) throw new NotFoundException('ไม่พบแผนก');

    const results: ScanResult[] = [];
    for (const id of packageIds) {
      const pkg = await tx.package.findUnique({ where: { id } });
      if (!pkg) { results.push({ packageId: id, success: false, error: 'ไม่พบห่อ' }); continue; }
      if (pkg.status !== PackageStatus.ISSUED && pkg.status !== PackageStatus.PACKED_OUT) {
        results.push({ packageId: id, success: false, error: `สถานะปัจจุบัน: ${pkg.status}` }); continue;
      }

      const fromStatus = pkg.status;
      const toStatus =
        fromStatus === PackageStatus.ISSUED ? PackageStatus.RETURNED : PackageStatus.PACKED;

      // status ใน where เป็น compare-and-swap อะตอมมิก กันสแกนซ้ำพร้อมกันจาก 2 เครื่อง
      const { count } = await tx.package.updateMany({
        where: { id, status: fromStatus },
        data: { status: toStatus },
      });
      if (count === 0) {
        results.push({ packageId: id, success: false, error: 'ห่อนี้ถูกสแกนไปพร้อมกันจากที่อื่นแล้ว' });
        continue;
      }
      await tx.movement.create({
        data: { packageId: id, type: MovementType.RETURN, departmentId, performedById: userId },
      });
      await this.audit.logTx(tx, userId, 'SCAN_RETURN', id, {
        departmentId,
        ...(fromStatus === PackageStatus.PACKED_OUT ? { unsterile: true } : {}),
        ...(manualEntry ? { manualEntry: true } : {}),
      });
      results.push({ packageId: id, success: true });
    }
    return results;
  }

  /** Lookup: scan QR → get package info + expiry warning */
  async lookup(packageId: string) {
    const pkg = await this.prisma.package.findUnique({
      where: { id: packageId },
      include: { setTemplate: true, batch: true },
    });
    if (!pkg) throw new NotFoundException(`ไม่พบห่อ ${packageId}`);

    const now = new Date();
    return {
      ...pkg,
      isExpired: pkg.expiryDate ? isExpired(pkg.expiryDate, now) : false,
      daysLeft: pkg.expiryDate ? daysLeft(pkg.expiryDate, now) : null,
    };
  }
}
