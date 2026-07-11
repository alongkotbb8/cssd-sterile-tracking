import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { BatchStatus, PackageStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { CreateBatchDto } from './dto/create-batch.dto';

@Injectable()
export class BatchesService {
  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  async create(dto: CreateBatchDto, userId: string) {
    const sterilizer = await this.prisma.sterilizer.findUnique({ where: { id: dto.sterilizerId } });
    if (!sterilizer) throw new NotFoundException('ไม่พบเครื่องนึ่งที่ระบุ');

    let batch;
    try {
      batch = await this.prisma.sterilizationBatch.create({
        data: {
          sterilizerId: dto.sterilizerId,
          roundNo: dto.roundNo,
          runDate: new Date(dto.startedAt),
          startedAt: new Date(dto.startedAt),
          status: BatchStatus.PENDING,
        },
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        throw new ConflictException('มีรอบนึ่งนี้อยู่แล้ว (เครื่อง/วัน/รอบซ้ำ)');
      }
      throw e;
    }

    await this.audit.log(userId, 'BATCH_CREATE', batch.id, {
      sterilizerId: dto.sterilizerId,
      roundNo: dto.roundNo,
    });
    return batch;
  }

  findAll(status?: BatchStatus) {
    return this.prisma.sterilizationBatch.findMany({
      where: status ? { status } : {},
      include: { sterilizer: true, _count: { select: { packages: true } } },
      orderBy: { startedAt: 'desc' },
      take: 50,
    });
  }

  /** Record CI/BI results and auto-set batch status */
  async recordResult(id: string, ciResult: boolean, biResult: boolean | null, userId: string) {
    const batch = await this.prisma.sterilizationBatch.findUnique({ where: { id } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');
    if (batch.status !== BatchStatus.PENDING) throw new BadRequestException('รอบนึ่งนี้บันทึกผลแล้ว');

    const status: BatchStatus =
      ciResult && (biResult === null || biResult) ? BatchStatus.PASSED : BatchStatus.FAILED;

    const updated = await this.prisma.sterilizationBatch.update({
      where: { id },
      data: { ciResult, biResult, status, finishedAt: new Date() },
    });

    await this.audit.log(userId, 'BATCH_RESULT', id, { ciResult, biResult, status });

    if (status === BatchStatus.FAILED) {
      await this.recall(id, userId);
    }

    return updated;
  }

  /**
   * FR-5: Recall — pull back every package in a failed batch.
   * Covers packages still in the sterile store (STERILE) AND packages already
   * issued to departments (ISSUED) — both become RETURNED (awaiting reprocess).
   * Returns each affected package with its last movement = current location.
   */
  async recall(batchId: string, userId: string) {
    const batch = await this.prisma.sterilizationBatch.findUnique({ where: { id: batchId } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');

    const recallable: PackageStatus[] = [PackageStatus.STERILE, PackageStatus.ISSUED];

    const packages = await this.prisma.$transaction(async (tx) => {
      const affected = await tx.package.findMany({
        where: { batchId, status: { in: recallable } },
        include: {
          setTemplate: true,
          movements: {
            orderBy: { createdAt: 'desc' },
            take: 1,
            include: { department: true },
          },
        },
      });

      await tx.package.updateMany({
        where: { id: { in: affected.map(p => p.id) } },
        data: { status: PackageStatus.RETURNED },
      });

      return affected;
    });

    await this.audit.log(userId, 'RECALL_BATCH', batchId, {
      affectedPackages: packages.map(p => ({ id: p.id, previousStatus: p.status })),
    });

    return { recalled: packages.length, packages };
  }

  /** Get all packages in a batch with their current locations */
  async getPackages(batchId: string) {
    return this.prisma.package.findMany({
      where: { batchId },
      include: {
        setTemplate: true,
        movements: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { department: true },
        },
      },
    });
  }

  async findOne(id: string) {
    const batch = await this.prisma.sterilizationBatch.findUnique({
      where: { id },
      include: { sterilizer: true, _count: { select: { packages: true } } },
    });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');
    return batch;
  }
}
