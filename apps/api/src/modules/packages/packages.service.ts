import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { WrapType, PackageStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RunningNumberService } from './running-number.service';
import { AuditService } from '../../common/audit/audit.service';
import { CreatePackageDto } from './dto/create-package.dto';

const SHELF_LIFE: Record<WrapType, number> = {
  SEAL: 180,
  CLOTH: 7,
};

function addDays(date: Date, days: number): Date {
  // UTC-based so expiry does not depend on server timezone.
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

@Injectable()
export class PackagesService {
  constructor(
    private prisma: PrismaService,
    private runningNum: RunningNumberService,
    private audit: AuditService,
  ) {}

  async create(dto: CreatePackageDto, userId: string) {
    const template = await this.prisma.setTemplate.findUnique({
      where: { id: dto.setTemplateId },
    });
    if (!template) throw new NotFoundException('ไม่พบ SetTemplate ที่ระบุ');

    const wrapType: WrapType = dto.wrapType ?? template.defaultWrapType;
    const id = await this.runningNum.nextId(template.code, template.id, new Date());

    const pkg = await this.prisma.package.create({
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

    await this.audit.log(userId, 'PACKAGE_CREATE', id, { wrapType });
    return pkg;
  }

  async findOne(id: string) {
    const pkg = await this.prisma.package.findUnique({
      where: { id },
      include: {
        setTemplate: true,
        batch: true,
        movements: {
          include: {
            department: true,
            performedBy: { select: { id: true, name: true, employeeCode: true } },
          },
        },
      },
    });
    if (!pkg) throw new NotFoundException(`ไม่พบห่อ ${id}`);

    const isExpired = pkg.expiryDate && pkg.expiryDate < new Date() && pkg.status === PackageStatus.STERILE;
    return { ...pkg, isExpired: isExpired ?? false };
  }

  async findAll(status?: PackageStatus, templateId?: string) {
    const now = new Date();
    return this.prisma.package.findMany({
      where: {
        ...(status ? { status } : {}),
        ...(templateId ? { setTemplateId: templateId } : {}),
      },
      include: { setTemplate: true, batch: { select: { id: true, status: true } } },
      orderBy: { expiryDate: 'asc' }, // FEFO order
    }).then(pkgs =>
      pkgs.map(p => ({
        ...p,
        isExpired: p.expiryDate ? p.expiryDate < now && p.status === PackageStatus.STERILE : false,
      })),
    );
  }

  /** Mark sterilised — called when batch is confirmed PASSED */
  async markSterile(id: string, batchId: string, sterilizeDate: Date, userId: string) {
    const pkg = await this.prisma.package.findUniqueOrThrow({ where: { id } });
    if (pkg.status !== PackageStatus.PACKED) {
      throw new BadRequestException(`ห่อ ${id} ไม่ได้อยู่ในสถานะ PACKED`);
    }

    const expiryDate = addDays(sterilizeDate, SHELF_LIFE[pkg.wrapType]);
    const updated = await this.prisma.package.update({
      where: { id },
      data: { status: PackageStatus.STERILE, batchId, sterilizeDate, expiryDate },
    });

    await this.audit.log(userId, 'PACKAGE_STERILE', id, { batchId, expiryDate });
    return updated;
  }

  /** Any status → DISCARDED (except already discarded) */
  async discard(id: string, userId: string, notes?: string) {
    const pkg = await this.prisma.package.findUnique({ where: { id } });
    if (!pkg) throw new NotFoundException(`ไม่พบห่อ ${id}`);
    if (pkg.status === PackageStatus.DISCARDED) {
      throw new BadRequestException(`ห่อ ${id} ถูกทิ้งไปแล้ว`);
    }

    await this.prisma.package.update({
      where: { id },
      data: { status: PackageStatus.DISCARDED, notes },
    });
    await this.audit.log(userId, 'PACKAGE_DISCARD', id, { previousStatus: pkg.status });
  }

  /** Reserve an offline ID pool */
  async reservePool(setTemplateId: string, count: number, deviceId: string, userId: string) {
    const template = await this.prisma.setTemplate.findUnique({ where: { id: setTemplateId } });
    if (!template) throw new NotFoundException('ไม่พบ SetTemplate ที่ระบุ');

    const ids = await this.runningNum.reservePool(
      template.id,
      template.code,
      new Date(),
      count,
      deviceId,
      userId,
    );
    await this.audit.log(userId, 'POOL_RESERVE', template.id, { count, deviceId });
    return ids;
  }
}
