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

  async create(dto: CreateBatchDto, userId: string, tx: Prisma.TransactionClient) {
    const sterilizer = await tx.sterilizer.findUnique({ where: { id: dto.sterilizerId } });
    if (!sterilizer) throw new NotFoundException('ไม่พบเครื่องนึ่งที่ระบุ');

    let batch;
    try {
      batch = await tx.sterilizationBatch.create({
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

    await this.audit.logTx(tx, userId, 'BATCH_CREATE', batch.id, {
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

  /**
   * Record CI/BI results and auto-set batch status.
   *
   * ลำดับที่ถูกหลัก traceability: ห่อถูกผูกเข้ารอบ (PENDING) ก่อนนึ่ง แล้วผล
   * ตรวจเป็นตัวตัดสิน —
   * - PASSED: ห่อ PACKED ทุกใบในรอบ → STERILE + คำนวณวันหมดอายุ + Movement IN
   *   (ทั้งหมดใน transaction เดียว — ห้ามมีห่อครึ่งๆ กลางๆ)
   * - FAILED: ห่อคง PACKED และถูกปลดออกจากรอบ (ต้องเข้ารอบนึ่งใหม่)
   */
  async recordResult(
    id: string,
    ciResult: boolean,
    biResult: boolean | null,
    userId: string,
    tx: Prisma.TransactionClient,
  ) {
    const batch = await tx.sterilizationBatch.findUnique({ where: { id } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');
    if (batch.status !== BatchStatus.PENDING) throw new BadRequestException('รอบนึ่งนี้บันทึกผลแล้ว');

    const status: BatchStatus =
      ciResult && (biResult === null || biResult) ? BatchStatus.PASSED : BatchStatus.FAILED;
    const finishedAt = new Date();

    const b = await tx.sterilizationBatch.update({
      where: { id },
      data: { ciResult, biResult, status, finishedAt },
    });

    const bound = await tx.package.findMany({
      where: { batchId: id, status: PackageStatus.PACKED },
      select: { id: true, wrapType: true },
    });

    if (status === BatchStatus.PASSED) {
      // Domain rule: SEAL = +180 days, CLOTH = +7 days — computed server-side only.
      for (const pkg of bound) {
        const expiryDate = new Date(finishedAt);
        expiryDate.setUTCDate(expiryDate.getUTCDate() + (pkg.wrapType === 'SEAL' ? 180 : 7));
        await tx.package.update({
          where: { id: pkg.id },
          data: { status: PackageStatus.STERILE, sterilizeDate: finishedAt, expiryDate },
        });
        await tx.movement.create({
          data: { packageId: pkg.id, type: 'IN', performedById: userId },
        });
      }
    } else {
      // ไม่ผ่าน: ห่อยังไม่เคยปลอดเชื้อ → คง PACKED, ปลดจากรอบเพื่อเข้ารอบใหม่
      await tx.package.updateMany({
        where: { batchId: id, status: PackageStatus.PACKED },
        data: { batchId: null },
      });
    }

    await this.audit.logTx(tx, userId, 'BATCH_RESULT', id, {
      ciResult,
      biResult,
      status,
      promotedPackages: status === BatchStatus.PASSED ? bound.map(p => p.id) : [],
      unboundPackages: status === BatchStatus.FAILED ? bound.map(p => p.id) : [],
    });

    if (status === BatchStatus.FAILED) {
      // recall ห่อจากรอบเดิม (flow เก่า) ที่เป็น STERILE/ISSUED อยู่แล้ว — รันใน
      // ทรานแซกชันเดียวกัน (FIX-02 แนวทาง A) ห้ามแยกทรานแซกชันเพื่อไม่ให้ recall
      // สำเร็จแต่ผลตรวจ rollback (หรือกลับกัน)
      await this.recallTx(tx, id, userId);
    }

    return b;
  }

  /**
   * FR-5: Recall — pull back every package in a failed batch.
   * Covers packages still in the sterile store (STERILE) AND packages already
   * issued to departments (ISSUED) — both become RETURNED (awaiting reprocess).
   * Returns each affected package with its last movement = current location.
   */
  async recall(batchId: string, userId: string) {
    const packages = await this.prisma.$transaction((tx) => this.recallTx(tx, batchId, userId));
    return { recalled: packages.length, packages };
  }

  /** แกนกลางของ recall — รับ tx เพื่อให้ recordResult เรียกในทรานแซกชันเดียวกันได้ */
  private async recallTx(tx: Prisma.TransactionClient, batchId: string, userId: string) {
    const batch = await tx.sterilizationBatch.findUnique({ where: { id: batchId } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');

    const recallable: PackageStatus[] = [PackageStatus.STERILE, PackageStatus.ISSUED];

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

    await this.audit.logTx(tx, userId, 'RECALL_BATCH', batchId, {
      affectedPackages: affected.map(p => ({ id: p.id, previousStatus: p.status })),
    });

    return affected;
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
