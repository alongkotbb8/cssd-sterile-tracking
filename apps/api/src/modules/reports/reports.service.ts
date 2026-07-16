import { BadRequestException, Injectable } from '@nestjs/common';
import { PackageStatus } from '@prisma/client';
import { AuditService } from '../../common/audit/audit.service';
import { PrismaService } from '../../common/prisma/prisma.service';

function parseDateOrThrow(value: string | undefined, name: string): Date {
  const d = value ? new Date(value) : new Date(NaN);
  if (isNaN(d.getTime())) {
    throw new BadRequestException(`พารามิเตอร์ ${name} ต้องเป็นวันที่ (เช่น 2026-06-30)`);
  }
  return d;
}

@Injectable()
export class ReportsService {
  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  /** FR-6: Dashboard data */
  async dashboard() {
    const now = new Date();
    const [sterileByTemplate, issuedByDept, expiringSoon, expired, awaitingReprocess, packedOut] =
      await Promise.all([
        // Stock by set template
        this.prisma.package.groupBy({
          by: ['setTemplateId'],
          where: { status: PackageStatus.STERILE },
          _count: { id: true },
        }),
        // Issued by department (last 30 days)
        this.prisma.movement.groupBy({
          by: ['departmentId'],
          where: {
            type: 'OUT',
            createdAt: { gte: new Date(Date.now() - 30 * 86_400_000) },
          },
          _count: { id: true },
        }),
        // Expiring within 7 days (SEAL) / 2 days (CLOTH)
        this.prisma.package.count({
          where: {
            status: PackageStatus.STERILE,
            expiryDate: { gt: now, lte: new Date(Date.now() + 7 * 86_400_000) },
          },
        }),
        // Already expired and still in STERILE (should be 0 ideally)
        this.prisma.package.count({
          where: { status: PackageStatus.STERILE, expiryDate: { lt: now } },
        }),
        // Awaiting reprocess
        this.prisma.package.count({ where: { status: PackageStatus.RETURNED } }),
        // ส่งออกโดยยังไม่ฆ่าเชื้อ ที่ยังไม่คืน
        this.prisma.package.count({ where: { status: PackageStatus.PACKED_OUT } }),
      ]);

    // Enrich template names
    const templateIds = sterileByTemplate.map(r => r.setTemplateId);
    const templates = await this.prisma.setTemplate.findMany({ where: { id: { in: templateIds } } });
    const templateMap = Object.fromEntries(templates.map(t => [t.id, t.name]));

    // Enrich dept names
    const deptIds = issuedByDept.map(r => r.departmentId).filter(Boolean) as string[];
    const depts = await this.prisma.department.findMany({ where: { id: { in: deptIds } } });
    const deptMap = Object.fromEntries(depts.map(d => [d.id, d.name]));

    return {
      sterileStock: sterileByTemplate.map(r => ({
        templateId: r.setTemplateId,
        templateName: templateMap[r.setTemplateId] ?? r.setTemplateId,
        count: r._count.id,
      })),
      issuedByDept: issuedByDept.map(r => ({
        departmentId: r.departmentId,
        departmentName: r.departmentId ? deptMap[r.departmentId] ?? r.departmentId : 'ไม่ระบุ',
        count: r._count.id,
      })),
      summary: { expiringSoon, expired, awaitingReprocess, packedOut },
    };
  }

  /** FR-7: Weekly movement report */
  async weekly(from: string, to: string, departmentId?: string) {
    const fromDate = parseDateOrThrow(from, 'from');
    const toDate = parseDateOrThrow(to, 'to');
    // Make `to` inclusive of the whole day when a bare date is given.
    if (/^\d{4}-\d{2}-\d{2}$/.test(to)) toDate.setUTCHours(23, 59, 59, 999);

    const movements = await this.prisma.movement.findMany({
      where: {
        createdAt: { gte: fromDate, lte: toDate },
        ...(departmentId ? { departmentId } : {}),
      },
      include: {
        package: { include: { setTemplate: true } },
        department: true,
        performedBy: { select: { name: true, employeeCode: true } },
      },
      orderBy: { createdAt: 'asc' },
    });

    const summary = { IN: 0, OUT: 0, RETURN: 0 };
    for (const m of movements) summary[m.type]++;

    return { movements, summary, from, to };
  }

  /** Packages issued but not yet returned */
  async unreturned(departmentId?: string) {
    return this.prisma.package.findMany({
      where: {
        status: PackageStatus.ISSUED,
        ...(departmentId
          ? {
              movements: {
                some: { type: 'OUT', departmentId },
              },
            }
          : {}),
      },
      include: {
        setTemplate: true,
        movements: {
          where: { type: 'OUT' },
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { department: true },
        },
      },
    });
  }

  /**
   * ล้างข้อมูลประวัติเก่าหลังพิมพ์รายงานเก็บเข้าแฟ้มแล้ว (ADMIN เท่านั้น)
   *
   * ลบ:  movement เก่ากว่า `before`, ห่อสถานะ DISCARDED ที่จบชีวิตก่อน `before`
   *      (พร้อม movement ที่เหลือของห่อเหล่านั้น), audit log เก่ากว่า `before`
   * ไม่แตะ: ห่อทุกสถานะที่ยังอยู่ในวงจร (PACKED/STERILE/ISSUED/RETURNED)
   *         — สต๊อกคลังปัจจุบันคงอยู่ครบ
   */
  async cleanup(beforeStr: string, userId: string) {
    const before = parseDateOrThrow(beforeStr, 'before');
    if (before >= new Date()) {
      throw new BadRequestException('วันที่ตัดข้อมูลต้องเป็นอดีตเท่านั้น');
    }

    const result = await this.prisma.$transaction(async (tx) => {
      const discarded = await tx.package.findMany({
        where: { status: PackageStatus.DISCARDED, updatedAt: { lt: before } },
        select: { id: true },
      });
      const discardedIds = discarded.map((p) => p.id);

      const movements = await tx.movement.deleteMany({
        where: {
          OR: [
            { createdAt: { lt: before } },
            ...(discardedIds.length
              ? [{ packageId: { in: discardedIds } }]
              : []),
          ],
        },
      });

      const packages = discardedIds.length
        ? await tx.package.deleteMany({ where: { id: { in: discardedIds } } })
        : { count: 0 };

      const audits = await tx.auditLog.deleteMany({
        where: { createdAt: { lt: before } },
      });

      return {
        deletedMovements: movements.count,
        deletedPackages: packages.count,
        deletedAuditLogs: audits.count,
      };
    });

    // บันทึกการล้างข้อมูลไว้เป็นหลักฐาน (audit ใหม่ เกิดหลัง cutoff เสมอ)
    await this.audit.log(userId, 'DATA_CLEANUP', undefined, {
      before: before.toISOString(),
      ...result,
    });

    return { before: before.toISOString(), ...result };
  }
}
