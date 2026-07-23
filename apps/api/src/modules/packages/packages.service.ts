import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { WrapType, PackageStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RunningNumberService } from './running-number.service';
import { AuditService } from '../../common/audit/audit.service';
import { isExpired } from '../../common/expiry';
import { CreatePackageDto } from './dto/create-package.dto';

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
    if (!template) throw new NotFoundException('ไม่พบ SetTemplate ที่ระบุ');

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
    if (!pkg) throw new NotFoundException(`ไม่พบห่อ ${id}`);

    const expired =
      !!pkg.expiryDate && isExpired(pkg.expiryDate) && pkg.status === PackageStatus.STERILE;
    return { ...pkg, isExpired: expired };
  }

  async findAll(status?: PackageStatus, templateId?: string, tagId?: string) {
    const now = new Date();
    return this.prisma.package.findMany({
      where: {
        ...(status ? { status } : {}),
        ...(templateId ? { setTemplateId: templateId } : {}),
        ...(tagId ? { tags: { some: { tagId } } } : {}), // กรองตาม tag
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

  // หมายเหตุ: markSterile() เดิมถูกตัดออก — การเปลี่ยนห่อเป็น STERILE ทำใน
  // BatchesService.recordResult (promote ทั้งรอบใน transaction เดียว) แทน

  /** Any status → DISCARDED (except already discarded) — mutation + AuditLog ใน tx เดียว */
  async discard(id: string, userId: string, notes?: string) {
    const pkg = await this.prisma.package.findUnique({ where: { id } });
    if (!pkg) throw new NotFoundException(`ไม่พบห่อ ${id}`);
    if (pkg.status === PackageStatus.DISCARDED) {
      throw new BadRequestException(`ห่อ ${id} ถูกทิ้งไปแล้ว`);
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
    if (!pkg) throw new NotFoundException(`ไม่พบห่อ ${id}`);

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
