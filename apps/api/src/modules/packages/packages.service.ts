import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { WrapType, PackageStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RunningNumberService } from './running-number.service';
import { AuditService } from '../../common/audit/audit.service';
import { isExpired } from '../../common/expiry';
import { assertValidPackageId } from '../scan/package-id.util';
import { CreatePackageDto } from './dto/create-package.dto';

/** ผลลัพธ์รายห่อของ bulk-delete (mirror ScanResult idiom) — success/fail แยกทีละรายการ */
export interface BulkDeleteResult {
  packageId: string;
  success: boolean;
  error?: string;
  /** stable code สำหรับ client map เป็นข้อความตาม locale (i18n) */
  errorCode?: string;
}

@Injectable()
export class PackagesService {
  constructor(
    private prisma: PrismaService,
    private runningNum: RunningNumberService,
    private audit: AuditService,
  ) {}

  /**
   * สร้างห่อใหม่ + ออกเลขรัน — รันในทรานแซกชันที่ idempotency ส่งเข้ามา (FIX-02
   * แนวทาง A): การออกเลขรัน + package.create + AuditLog + การเก็บ response ของ
   * idempotency อยู่ในทรานแซกชันเดียวกัน crash กลางคัน = rollback ทั้งหมด ไม่มี
   * ห่อซ้ำและเลขรันไม่กระโดด
   */
  async create(dto: CreatePackageDto, userId: string, tx: Prisma.TransactionClient) {
    const template = await tx.setTemplate.findUnique({
      where: { id: dto.setTemplateId },
    });
    if (!template) throw new NotFoundException({ message: 'ไม่พบ SetTemplate ที่ระบุ', code: 'TEMPLATE_NOT_FOUND' });

    const wrapType: WrapType = dto.wrapType ?? template.defaultWrapType;
    const id = await this.runningNum.nextId(template.code, template.id, new Date(), tx);

    const created = await tx.package.create({
      data: {
        id,
        setTemplateId: dto.setTemplateId,
        wrapType,
        status: PackageStatus.PACKED,
        createdById: userId,
        notes: dto.notes,
      },
      include: { setTemplate: true },
    });
    await this.audit.logTx(tx, userId, 'PACKAGE_CREATE', id, { wrapType });
    return created;
  }

  async findOne(id: string) {
    const pkg = await this.prisma.package.findUnique({
      where: { id },
      include: {
        setTemplate: true,
        batch: true,
        tags: { include: { tag: true } },
        movements: {
          include: {
            department: true,
            performedBy: { select: { id: true, name: true, employeeCode: true } },
          },
        },
      },
    });
    if (!pkg) throw new NotFoundException({ message: `ไม่พบห่อ ${id}`, code: 'PKG_NOT_FOUND' });

    const expired =
      !!pkg.expiryDate && isExpired(pkg.expiryDate) && pkg.status === PackageStatus.STERILE;
    return { ...pkg, isExpired: expired };
  }

  async findAll(status?: PackageStatus, templateId?: string, tagId?: string, search?: string) {
    const now = new Date();
    const q = search?.trim();
    // ค้นหาแบบ contains (case-insensitive) บน id / ชื่อชุด / อุปกรณ์ในชุด / คลังปัจจุบัน
    const searchWhere = q ? await this.buildSearchWhere(q) : undefined;
    return this.prisma.package.findMany({
      where: {
        ...(status ? { status } : {}),
        ...(templateId ? { setTemplateId: templateId } : {}),
        ...(tagId ? { tags: { some: { tagId } } } : {}), // กรองตาม tag
        ...(searchWhere ? { OR: searchWhere } : {}),
      },
      include: {
        setTemplate: true,
        batch: { select: { id: true, status: true } },
        tags: { include: { tag: true } },
        // movement ล่าสุด → บอกตำแหน่งปัจจุบันของห่อ (การ์ดแสดง "อยู่ที่ ...")
        movements: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { department: true },
        },
      },
      orderBy: { expiryDate: 'asc' }, // FEFO order
    }).then(pkgs =>
      pkgs.map(p => ({
        ...p,
        isExpired: p.expiryDate
          ? isExpired(p.expiryDate, now) && p.status === PackageStatus.STERILE
          : false,
      })),
    );
  }

  /**
   * แปลงคำค้น q เป็นเงื่อนไข OR ของ Prisma — match แบบ contains (case-insensitive) บน
   * id ห่อ / ชื่อ template / อุปกรณ์ในชุด (itemList) / ชื่อหรือรหัสคลังของ movement ล่าสุด
   *
   * template set เล็ก → ดึงมา filter itemList (String[] JSON) ใน memory ได้; ชื่อ/รหัส
   * dept ก็ prefetch id ที่ match แล้วค่อยเทียบผ่าน relation movements
   */
  private async buildSearchWhere(q: string): Promise<Prisma.PackageWhereInput[]> {
    const [nameMatched, allTemplates, matchedDepts] = await Promise.all([
      this.prisma.setTemplate.findMany({
        where: { name: { contains: q, mode: 'insensitive' } },
        select: { id: true },
      }),
      this.prisma.setTemplate.findMany({ select: { id: true, itemList: true } }),
      this.prisma.department.findMany({
        where: {
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { code: { contains: q, mode: 'insensitive' } },
          ],
        },
        select: { id: true },
      }),
    ]);

    const lower = q.toLowerCase();
    const itemMatchedIds = allTemplates
      .filter((t) =>
        Array.isArray(t.itemList) &&
        (t.itemList as unknown[]).some(
          (it) => typeof it === 'string' && it.toLowerCase().includes(lower),
        ),
      )
      .map((t) => t.id);

    const matchedTemplateIds = [...new Set([...nameMatched.map((t) => t.id), ...itemMatchedIds])];
    const matchedDeptIds = matchedDepts.map((d) => d.id);

    return [
      { id: { contains: q, mode: 'insensitive' } },
      { setTemplateId: { in: matchedTemplateIds } },
      { movements: { some: { departmentId: { in: matchedDeptIds } } } },
    ];
  }

  /**
   * ลบห่อถาวรหลายรายการ — **เฉพาะห่อ PACKED ที่ยังไม่มีประวัติการใช้งานเลย** (patient-safety:
   * ห้ามลบสิ่งที่มี traceability history) รันในทรานแซกชันที่ idempotency ส่งเข้ามา
   *
   * ผลลัพธ์รายห่อ (mirror ScanResult) — "ลบไม่ได้" เป็นเหตุการณ์ปกติ **ไม่ throw** แค่
   * push ลง results แล้วไปห่อถัดไป (ทรานแซกชันยังใช้ได้) DB error จริงจึงจะ throw ให้ rollback
   */
  async bulkDelete(
    packageIds: string[],
    userId: string,
    tx: Prisma.TransactionClient,
  ): Promise<BulkDeleteResult[]> {
    const results: BulkDeleteResult[] = [];
    for (const id of packageIds) {
      // รูปแบบ id ผิด → 400 ทั้ง request (กัน API-direct bypass) เหมือน lookup/DTO อื่น
      assertValidPackageId(id);

      const pkg = await tx.package.findUnique({ where: { id } });
      if (!pkg) {
        results.push({ packageId: id, success: false, error: 'ไม่พบห่อ', errorCode: 'PKG_NOT_FOUND' });
        continue;
      }
      if (pkg.status !== PackageStatus.PACKED) {
        results.push({
          packageId: id,
          success: false,
          error: `สถานะปัจจุบัน: ${pkg.status} (ลบได้เฉพาะห่อที่แพ็กแล้ว)`,
          errorCode: 'PKG_WRONG_STATUS',
        });
        continue;
      }

      // ต้องไม่มีประวัติการใช้งานใด ๆ เลย — ไม่งั้นการลบทำลาย traceability ถาวร (ให้ใช้ DISCARD แทน)
      const [movementCount, printJobCount, browserPrintCount, batchAttemptCount] = await Promise.all([
        tx.movement.count({ where: { packageId: id } }),
        tx.printJob.count({ where: { packageId: id } }),
        tx.browserPrintRequest.count({ where: { packageId: id } }),
        tx.packageBatchAttempt.count({ where: { packageId: id } }),
      ]);
      const hasHistory =
        pkg.batchId != null ||
        pkg.printedAt != null ||
        pkg.reprintCount !== 0 ||
        movementCount > 0 ||
        printJobCount > 0 ||
        browserPrintCount > 0 ||
        batchAttemptCount > 0;
      if (hasHistory) {
        results.push({
          packageId: id,
          success: false,
          error: 'ลบไม่ได้ ห่อนี้มีประวัติการใช้งานแล้ว (ใช้การทิ้ง/DISCARD แทน)',
          errorCode: 'PKG_HAS_HISTORY',
        });
        continue;
      }

      // สะอาด → audit ก่อนลบ (เก็บ metadata พอสำหรับ reconstruct) แล้วจึงลบจริง
      await this.audit.logTx(tx, userId, 'PACKAGE_DELETE', id, {
        setTemplateId: pkg.setTemplateId,
        wrapType: pkg.wrapType,
        createdById: pkg.createdById,
      });
      // package_tags มี onDelete Cascade — แต่ลบให้ชัดก่อนกันปัญหา FK ในบาง engine
      await tx.packageTag.deleteMany({ where: { packageId: id } });
      await tx.package.delete({ where: { id } });
      results.push({ packageId: id, success: true });
    }
    return results;
  }

  // หมายเหตุ: markSterile() เดิมถูกตัดออก — การเปลี่ยนห่อเป็น STERILE ทำใน
  // BatchesService.recordResult (promote ทั้งรอบใน transaction เดียว) แทน

  /** Any status → DISCARDED (except already discarded) — mutation + AuditLog ใน tx เดียว */
  async discard(id: string, userId: string, notes?: string) {
    const pkg = await this.prisma.package.findUnique({ where: { id } });
    if (!pkg) throw new NotFoundException({ message: `ไม่พบห่อ ${id}`, code: 'PKG_NOT_FOUND' });
    if (pkg.status === PackageStatus.DISCARDED) {
      throw new BadRequestException({ message: `ห่อ ${id} ถูกทิ้งไปแล้ว`, code: 'PKG_DISCARDED' });
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.package.update({
        where: { id },
        data: { status: PackageStatus.DISCARDED, notes },
      });
      await this.audit.logTx(tx, userId, 'PACKAGE_DISCARD', id, { previousStatus: pkg.status });
    });
  }

  /** ตั้ง tag ของห่อ (แทนที่ทั้งชุด) — ใช้ติด/ถอด tag จากหน้ารายละเอียด */
  async setTags(id: string, tagIds: string[], userId: string) {
    const pkg = await this.prisma.package.findUnique({ where: { id } });
    if (!pkg) throw new NotFoundException({ message: `ไม่พบห่อ ${id}`, code: 'PKG_NOT_FOUND' });

    await this.prisma.$transaction(async (tx) => {
      await tx.packageTag.deleteMany({ where: { packageId: id } });
      if (tagIds.length) {
        await tx.packageTag.createMany({
          data: tagIds.map((tagId) => ({ packageId: id, tagId })),
          skipDuplicates: true,
        });
      }
      await this.audit.logTx(tx, userId, 'PACKAGE_TAGS_SET', id, { tagIds });
    });

    return this.prisma.packageTag.findMany({
      where: { packageId: id },
      include: { tag: true },
    });
  }
}
