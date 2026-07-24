import { BadRequestException, Injectable } from '@nestjs/common';
import { PackageStatus } from '@prisma/client';
import { AuditService } from '../../common/audit/audit.service';
import { startOfTodayUtc } from '../../common/expiry';
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
    const [
      sterileByTemplate,
      issuedByDept,
      expiringSoon,
      expired,
      awaitingReprocess,
      packedOut,
      recentMovementRows,
    ] =
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
        // Expiring within 7 days — นับตั้งแต่ "วันนี้เป็นวันสุดท้าย" (daysLeft 0-7)
        // นิยาม expiry: ใช้ได้ตลอดวันหมดอายุ (ดู common/expiry.ts)
        this.prisma.package.count({
          where: {
            status: PackageStatus.STERILE,
            expiryDate: { gte: startOfTodayUtc(now), lte: new Date(now.getTime() + 7 * 86_400_000) },
          },
        }),
        // Already expired and still in STERILE (should be 0 ideally)
        // = วันหมดอายุพ้นไปแล้ว (ก่อนเที่ยงคืนวันนี้ UTC)
        this.prisma.package.count({
          where: { status: PackageStatus.STERILE, expiryDate: { lt: startOfTodayUtc(now) } },
        }),
        // Awaiting reprocess
        this.prisma.package.count({ where: { status: PackageStatus.RETURNED } }),
        // ส่งออกโดยยังไม่ฆ่าเชื้อ ที่ยังไม่คืน
        this.prisma.package.count({ where: { status: PackageStatus.PACKED_OUT } }),
        // การเคลื่อนไหวล่าสุด 8 รายการ (ทุกชนิด) — "ชุดอะไรไปอยู่ที่ไหน"
        this.prisma.movement.findMany({
          orderBy: { createdAt: 'desc' },
          take: 8,
          include: {
            package: { include: { setTemplate: true } },
            department: true,
          },
        }),
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
      recentMovements: recentMovementRows.map((m) => ({
        packageId: m.packageId,
        setName: m.package?.setTemplate?.name ?? m.packageId,
        type: m.type,
        departmentName: m.department?.name ?? null,
        receiverName: m.receiverName ?? null,
        at: m.createdAt.toISOString(),
        packageStatus: m.package?.status ?? null,
      })),
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

  /**
   * FR: Excel export ของรายงาน movement ช่วงวันที่ (สร้างไฟล์ .xlsx จริง)
   * แถวข้อมูล + แผ่นสรุป (IN/OUT/RETURN + อัตราการส่งคืนต่อแผนก)
   */
  async weeklyXlsx(from: string, to: string, departmentId?: string): Promise<Buffer> {
    // import แบบ dynamic — exceljs ตัวใหญ่ ไม่ควรโหลดตอน boot ถ้าไม่ได้ใช้
    const ExcelJS = await import('exceljs');
    const data = await this.weekly(from, to, departmentId);
    const returnRates = await this.returnRateByDepartment(from, to);

    const wb = new ExcelJS.Workbook();
    wb.creator = 'CSSD Sterile Tracking';

    const typeLabel: Record<string, string> = {
      IN: 'เข้ารอบนึ่ง/เข้าคลัง',
      OUT: 'เบิกออก',
      RETURN: 'ส่งคืน',
    };

    // ── แผ่นที่ 1: รายการ movement ──
    const ws = wb.addWorksheet('รายการเคลื่อนไหว');
    ws.columns = [
      { header: 'วันเวลา', key: 'at', width: 20 },
      { header: 'ประเภท', key: 'type', width: 14 },
      { header: 'เลขห่อ', key: 'pkg', width: 24 },
      { header: 'ชุดอุปกรณ์', key: 'set', width: 26 },
      { header: 'แผนก', key: 'dept', width: 22 },
      { header: 'ผู้รับ', key: 'receiver', width: 18 },
      { header: 'ผู้ทำรายการ', key: 'by', width: 20 },
    ];
    ws.getRow(1).font = { bold: true };
    for (const m of data.movements) {
      ws.addRow({
        at: m.createdAt,
        type: typeLabel[m.type] ?? m.type,
        pkg: m.packageId,
        set: m.package?.setTemplate?.name ?? '',
        dept: m.department?.name ?? '',
        receiver: m.receiverName ?? '',
        by: m.performedBy?.name ?? '',
      });
    }

    // ── แผ่นที่ 2: สรุป ──
    const sum = wb.addWorksheet('สรุป');
    sum.columns = [
      { header: 'รายการ', key: 'k', width: 32 },
      { header: 'จำนวน', key: 'v', width: 14 },
    ];
    sum.getRow(1).font = { bold: true };
    sum.addRow({ k: 'ช่วงวันที่', v: `${from} ถึง ${to}` });
    sum.addRow({ k: 'เข้ารอบนึ่ง/เข้าคลัง (IN)', v: data.summary.IN });
    sum.addRow({ k: 'เบิกออก (OUT)', v: data.summary.OUT });
    sum.addRow({ k: 'ส่งคืน (RETURN)', v: data.summary.RETURN });
    sum.addRow({});
    sum.addRow({ k: 'อัตราการส่งคืนต่อแผนก', v: '' }).font = { bold: true };
    for (const r of returnRates) {
      sum.addRow({
        k: r.departmentName,
        v: `คืน ${r.returned}/${r.issued} (${r.ratePercent}%)`,
      });
    }

    return Buffer.from(await wb.xlsx.writeBuffer());
  }

  /** อัตราการส่งคืนต่อแผนก (OUT เทียบ RETURN ในช่วงวันที่) — ตามขอบเขตระบบข้อ 2.7 */
  async returnRateByDepartment(from: string, to: string) {
    const fromDate = parseDateOrThrow(from, 'from');
    const toDate = parseDateOrThrow(to, 'to');
    if (/^\d{4}-\d{2}-\d{2}$/.test(to)) toDate.setUTCHours(23, 59, 59, 999);

    const grouped = await this.prisma.movement.groupBy({
      by: ['departmentId', 'type'],
      where: {
        createdAt: { gte: fromDate, lte: toDate },
        type: { in: ['OUT', 'RETURN'] },
        departmentId: { not: null },
      },
      _count: { id: true },
    });

    const byDept = new Map<string, { issued: number; returned: number }>();
    for (const g of grouped) {
      const d = byDept.get(g.departmentId!) ?? { issued: 0, returned: 0 };
      if (g.type === 'OUT') d.issued += g._count.id;
      else d.returned += g._count.id;
      byDept.set(g.departmentId!, d);
    }

    const depts = await this.prisma.department.findMany({
      where: { id: { in: [...byDept.keys()] } },
    });
    const nameMap = Object.fromEntries(depts.map(d => [d.id, d.name]));

    return [...byDept.entries()].map(([id, v]) => ({
      departmentId: id,
      departmentName: nameMap[id] ?? id,
      issued: v.issued,
      returned: v.returned,
      ratePercent: v.issued === 0 ? 0 : Math.round((v.returned / v.issued) * 100),
    }));
  }

  /** รายงาน recall: รอบที่ผลไม่ผ่านทั้งหมด + ห่อที่ถูก recall + ตำแหน่งล่าสุด
   *
   *  ห่อของแต่ละรอบดึงจาก **ประวัติถาวร (PackageBatchAttempt)** ไม่ใช่ relation
   *  `batch.packages` (= batchId ปัจจุบัน) — ไม่งั้นห่อที่ถูกปลด batchId ตอนรอบไม่ผ่าน/
   *  ถูก reprocess จะหายจากรายงาน recall ทั้งที่เคยอยู่ในรอบที่ปนเปื้อน */
  async recalls() {
    const failed = await this.prisma.sterilizationBatch.findMany({
      where: { status: 'FAILED' },
      include: { sterilizer: true },
      orderBy: { finishedAt: 'desc' },
    });

    return Promise.all(
      failed.map(async (b) => {
        const attempts = await this.prisma.packageBatchAttempt.findMany({
          where: { batchId: b.id },
          orderBy: { boundAt: 'asc' },
          include: {
            package: {
              include: {
                setTemplate: true,
                movements: {
                  orderBy: { createdAt: 'desc' },
                  take: 1,
                  include: { department: true },
                },
              },
            },
          },
        });
        return {
          ...b,
          packages: attempts.map((a) => ({
            ...a.package,
            attemptResult: a.result,
            stillBound: a.package.batchId === b.id,
          })),
        };
      }),
    );
  }

  /**
   * รายงานประวัติการพิมพ์ label ที่ **สำเร็จจริง** — ใช้ action ที่ระบบเขียนจริงตอนนี้:
   * `PRINT_SUCCESS` (Gateway ACK พิมพ์จริง) เท่านั้น
   * (ไม่รวม PRINT_SIMULATED = โหมดทดสอบ, ไม่ใช่ 'PRINT_LABEL' เดิมที่เลิกใช้แล้ว)
   */
  async printHistory(from: string, to: string) {
    const fromDate = parseDateOrThrow(from, 'from');
    const toDate = parseDateOrThrow(to, 'to');
    if (/^\d{4}-\d{2}-\d{2}$/.test(to)) toDate.setUTCHours(23, 59, 59, 999);

    return this.prisma.auditLog.findMany({
      where: { action: 'PRINT_SUCCESS', createdAt: { gte: fromDate, lte: toDate } },
      include: { user: { select: { name: true, employeeCode: true } } },
      orderBy: { createdAt: 'desc' },
      take: 500,
    });
  }

  /** รายงานเหตุการณ์ถูกบล็อก (สแกนของหมดอายุ ฯลฯ — action SCAN_BLOCKED) */
  async blockedEvents(from: string, to: string) {
    const fromDate = parseDateOrThrow(from, 'from');
    const toDate = parseDateOrThrow(to, 'to');
    if (/^\d{4}-\d{2}-\d{2}$/.test(to)) toDate.setUTCHours(23, 59, 59, 999);

    return this.prisma.auditLog.findMany({
      where: { action: 'SCAN_BLOCKED', createdAt: { gte: fromDate, lte: toDate } },
      include: { user: { select: { name: true, employeeCode: true } } },
      orderBy: { createdAt: 'desc' },
      take: 500,
    });
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
   *      (พร้อม movement ที่เหลือของห่อเหล่านั้น)
   * ไม่แตะ: ห่อทุกสถานะที่ยังอยู่ในวงจร (PACKED/STERILE/ISSUED/RETURNED)
   *         — สต๊อกคลังปัจจุบันคงอยู่ครบ
   * **ไม่ลบ AuditLog เด็ดขาด** (ผล security audit): audit trail ต้อง append-only
   * เพื่อการตรวจสอบย้อนหลัง — การลบ audit log ทำลาย traceability ถาวร
   */
  async cleanup(beforeStr: string, userId: string) {
    const before = parseDateOrThrow(beforeStr, 'before');
    if (before >= new Date()) {
      throw new BadRequestException({ message: 'วันที่ตัดข้อมูลต้องเป็นอดีตเท่านั้น', code: 'CLEANUP_DATE_INVALID' });
    }

    // ⚠️ **ปิดการลบแบบทำลายข้อมูลแล้ว** — Movement คือ traceability history รายห่อ
    // (หัวใจความปลอดภัยผู้ป่วย) การลบทำลายการตามรอยถาวร; Package ที่ถูกทิ้งก็ต้องคง
    // ประวัติ movement ไว้ ต้องมี archive/retention policy อย่างเป็นทางการก่อนจึงจะ
    // ลบ/ย้ายออกได้ (AI_DEVELOPMENT_GUARDRAILS.md §9 Data) — ตอนนี้ endpoint นี้แค่
    // "รายงานจำนวนที่เข้าเกณฑ์" ไม่ลบอะไรจริง
    const eligibleMovements = await this.prisma.movement.count({
      where: { createdAt: { lt: before } },
    });
    const eligibleDiscarded = await this.prisma.package.count({
      where: { status: PackageStatus.DISCARDED, updatedAt: { lt: before } },
    });

    await this.audit.log(userId, 'DATA_CLEANUP_SKIPPED', undefined, {
      before: before.toISOString(),
      eligibleMovements,
      eligibleDiscarded,
      deleted: 0,
    });

    return {
      before: before.toISOString(),
      deletedMovements: 0,
      deletedPackages: 0,
      eligibleMovements,
      eligibleDiscarded,
      note: 'ปิดการลบข้อมูลแบบทำลายแล้ว — Movement/Package เก็บถาวรเพื่อ traceability (ต้องมี archive/retention policy ก่อนจึงจะลบได้)',
    };
  }
}
