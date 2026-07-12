import {
  Injectable,
  BadRequestException,
  HttpException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { PackageStatus, MovementType } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';

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

  /** Log full error server-side, return only a safe message to the client. */
  private safeError(e: unknown, packageId: string): string {
    if (e instanceof HttpException) return e.message;
    this.logger.error(`Scan failed for package ${packageId}`, e instanceof Error ? e.stack : String(e));
    return 'เกิดข้อผิดพลาดภายในระบบ';
  }

  /** Scan in: PACKED → STERILE (batch must be PASSED) */
  async scanIn(packageIds: string[], batchId: string, userId: string): Promise<ScanResult[]> {
    const batch = await this.prisma.sterilizationBatch.findUnique({ where: { id: batchId } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');
    if (batch.status !== 'PASSED') throw new BadRequestException('รอบนึ่งยังไม่ผ่านการตรวจสอบ');

    const results: ScanResult[] = [];
    for (const id of packageIds) {
      try {
        const pkg = await this.prisma.package.findUnique({ where: { id } });
        if (!pkg) { results.push({ packageId: id, success: false, error: 'ไม่พบห่อ' }); continue; }
        if (pkg.status !== PackageStatus.PACKED) {
          results.push({ packageId: id, success: false, error: `สถานะปัจจุบัน: ${pkg.status}` }); continue;
        }

        // Domain rule: SEAL = +180 days, CLOTH = +7 days — always computed server-side.
        const sterilizeDate = batch.finishedAt ?? new Date();
        const shelfLife = pkg.wrapType === 'SEAL' ? 180 : 7;
        const expiryDate = new Date(sterilizeDate);
        expiryDate.setUTCDate(expiryDate.getUTCDate() + shelfLife);

        const updated = await this.prisma.$transaction(async (tx) => {
          // status ใน where เป็น compare-and-swap อะตอมมิก กันสแกนซ้ำพร้อมกันจาก 2 เครื่อง
          const { count } = await tx.package.updateMany({
            where: { id, status: PackageStatus.PACKED },
            data: { status: PackageStatus.STERILE, batchId, sterilizeDate, expiryDate },
          });
          if (count === 0) return null;
          await tx.movement.create({
            data: { packageId: id, type: MovementType.IN, performedById: userId },
          });
          return tx.package.findUniqueOrThrow({ where: { id } });
        });

        if (!updated) {
          results.push({ packageId: id, success: false, error: 'ห่อนี้ถูกสแกนไปพร้อมกันจากที่อื่นแล้ว' });
          continue;
        }

        await this.audit.log(userId, 'SCAN_IN', id, { batchId, expiryDate });
        results.push({ packageId: id, success: true, package: updated as unknown as Record<string, unknown> });
      } catch (e) {
        results.push({ packageId: id, success: false, error: this.safeError(e, id) });
      }
    }
    return results;
  }

  /** Scan out: STERILE → ISSUED. Blocks if expired. */
  async scanOut(
    packageIds: string[],
    departmentId: string,
    receiverName: string | undefined,
    userId: string,
  ): Promise<ScanResult[]> {
    const dept = await this.prisma.department.findUnique({ where: { id: departmentId } });
    if (!dept) throw new NotFoundException('ไม่พบแผนกปลายทาง');

    const now = new Date();
    const results: ScanResult[] = [];

    for (const id of packageIds) {
      try {
        const pkg = await this.prisma.package.findUnique({ where: { id } });
        if (!pkg) { results.push({ packageId: id, success: false, error: 'ไม่พบห่อ' }); continue; }

        // FR-4: block expired
        if (pkg.expiryDate && pkg.expiryDate < now) {
          results.push({ packageId: id, success: false, error: '⛔ ห้ามใช้ — ห่อหมดอายุแล้ว' }); continue;
        }
        if (pkg.status !== PackageStatus.STERILE) {
          results.push({ packageId: id, success: false, error: `สถานะปัจจุบัน: ${pkg.status}` }); continue;
        }

        const done = await this.prisma.$transaction(async (tx) => {
          // status ใน where เป็น compare-and-swap อะตอมมิก กันสแกนซ้ำพร้อมกันจาก 2 เครื่อง
          const { count } = await tx.package.updateMany({
            where: { id, status: PackageStatus.STERILE },
            data: { status: PackageStatus.ISSUED },
          });
          if (count === 0) return false;
          await tx.movement.create({
            data: {
              packageId: id,
              type: MovementType.OUT,
              departmentId,
              receiverName: receiverName ?? null,
              performedById: userId,
            },
          });
          return true;
        });

        if (!done) {
          results.push({ packageId: id, success: false, error: 'ห่อนี้ถูกสแกนไปพร้อมกันจากที่อื่นแล้ว' });
          continue;
        }

        await this.audit.log(userId, 'SCAN_OUT', id, { departmentId, receiverName });
        results.push({ packageId: id, success: true });
      } catch (e) {
        results.push({ packageId: id, success: false, error: this.safeError(e, id) });
      }
    }
    return results;
  }

  /** Return: ISSUED → RETURNED (awaiting reprocess) */
  async scanReturn(packageIds: string[], departmentId: string, userId: string): Promise<ScanResult[]> {
    const dept = await this.prisma.department.findUnique({ where: { id: departmentId } });
    if (!dept) throw new NotFoundException('ไม่พบแผนก');

    const results: ScanResult[] = [];
    for (const id of packageIds) {
      try {
        const pkg = await this.prisma.package.findUnique({ where: { id } });
        if (!pkg) { results.push({ packageId: id, success: false, error: 'ไม่พบห่อ' }); continue; }
        if (pkg.status !== PackageStatus.ISSUED) {
          results.push({ packageId: id, success: false, error: `สถานะปัจจุบัน: ${pkg.status}` }); continue;
        }

        const done = await this.prisma.$transaction(async (tx) => {
          // status ใน where เป็น compare-and-swap อะตอมมิก กันสแกนซ้ำพร้อมกันจาก 2 เครื่อง
          const { count } = await tx.package.updateMany({
            where: { id, status: PackageStatus.ISSUED },
            data: { status: PackageStatus.RETURNED },
          });
          if (count === 0) return false;
          await tx.movement.create({
            data: { packageId: id, type: MovementType.RETURN, departmentId, performedById: userId },
          });
          return true;
        });

        if (!done) {
          results.push({ packageId: id, success: false, error: 'ห่อนี้ถูกสแกนไปพร้อมกันจากที่อื่นแล้ว' });
          continue;
        }

        await this.audit.log(userId, 'SCAN_RETURN', id, { departmentId });
        results.push({ packageId: id, success: true });
      } catch (e) {
        results.push({ packageId: id, success: false, error: this.safeError(e, id) });
      }
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
    const isExpired = pkg.expiryDate ? pkg.expiryDate < now : false;
    const daysLeft = pkg.expiryDate
      ? Math.ceil((pkg.expiryDate.getTime() - now.getTime()) / 86_400_000)
      : null;

    return { ...pkg, isExpired, daysLeft };
  }
}
