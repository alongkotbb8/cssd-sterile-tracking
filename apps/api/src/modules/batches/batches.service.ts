import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { BatchAttemptResult, BatchStatus, PackageStatus, Prisma } from '@prisma/client';
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
   * บันทึกผล CI (± BI) — โมเดล **early release** (ยืนยันแล้ว):
   * - CI ไม่ผ่าน → FAILED + recall (ห่อไม่ถูกปล่อย)
   * - CI ผ่าน + BI ผ่าน → PASSED (สมบูรณ์) → ห่อ PACKED ในรอบ → STERILE
   * - CI ผ่าน + BI ไม่ผ่าน → FAILED + recall
   * - CI ผ่าน + ยังไม่มีผล BI (null) → **PENDING_BI**: ปล่อยห่อเป็น STERILE ทันที
   *   (early release) รอบันทึกผล BI ทีหลังผ่าน recordBiResult()
   *
   * การผูกห่อ–รอบเก็บถาวรใน PackageBatchAttempt (Package.batchId เป็นแค่รอบปัจจุบัน)
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
    if (batch.status !== BatchStatus.PENDING) {
      throw new BadRequestException('รอบนึ่งนี้บันทึกผลไปแล้ว (บันทึกผล CI ได้ครั้งเดียว)');
    }

    // release = ห่อพร้อมใช้ (STERILE) — เมื่อ CI ผ่าน และ BI ไม่ได้ระบุว่า "ไม่ผ่าน"
    const release = ciResult && biResult !== false;
    const status: BatchStatus = !release
      ? BatchStatus.FAILED
      : biResult === true
        ? BatchStatus.PASSED
        : BatchStatus.PENDING_BI;
    const finishedAt = new Date();

    const b = await tx.sterilizationBatch.update({
      where: { id },
      data: { ciResult, biResult, status, finishedAt },
    });

    const bound = await tx.package.findMany({
      where: { batchId: id, status: PackageStatus.PACKED },
      select: { id: true, wrapType: true },
    });

    if (release) {
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
      // PASSED → attempt PASSED, PENDING_BI → คง PENDING (รอ BI)
      await this.setAttemptResult(
        tx, id,
        status === BatchStatus.PASSED ? BatchAttemptResult.PASSED : BatchAttemptResult.PENDING,
      );
    } else {
      // ไม่ผ่าน: ห่อยังไม่เคยปลอดเชื้อ → คง PACKED, ปลด batchId ปัจจุบัน (เข้ารอบใหม่ได้)
      // ประวัติยังอยู่ใน PackageBatchAttempt (ไม่หาย)
      await tx.package.updateMany({
        where: { batchId: id, status: PackageStatus.PACKED },
        data: { batchId: null },
      });
      await this.setAttemptResult(tx, id, BatchAttemptResult.FAILED);
    }

    await this.audit.logTx(tx, userId, 'BATCH_RESULT', id, {
      ciResult,
      biResult,
      status,
      releasedPackages: release ? bound.map(p => p.id) : [],
      unboundPackages: release ? [] : bound.map(p => p.id),
    });

    if (status === BatchStatus.FAILED) {
      // recall ห่อรอบเดิมที่เป็น STERILE/ISSUED อยู่แล้ว — ในทรานแซกชันเดียวกัน
      await this.recallTx(tx, id, userId);
    }

    return b;
  }

  /**
   * บันทึกผล BI ที่มาทีหลัง (สำหรับรอบที่ early-release อยู่ที่ PENDING_BI):
   * - BI ผ่าน → PASSED (ห่อเป็น STERILE อยู่แล้ว ไม่ต้องแก้)
   * - BI ไม่ผ่าน → FAILED + **recall** ห่อทุกใบในรอบ (อาจ STERILE/ISSUED ไปแล้ว)
   */
  async recordBiResult(
    id: string,
    biResult: boolean,
    userId: string,
    tx: Prisma.TransactionClient,
  ) {
    const batch = await tx.sterilizationBatch.findUnique({ where: { id } });
    if (!batch) throw new NotFoundException('ไม่พบรอบนึ่ง');
    if (batch.status !== BatchStatus.PENDING_BI) {
      throw new BadRequestException(
        `บันทึกผล BI ได้เฉพาะรอบที่ยังรอผล BI (PENDING_BI) — ปัจจุบัน: ${batch.status}`,
      );
    }

    const status = biResult ? BatchStatus.PASSED : BatchStatus.FAILED;
    const b = await tx.sterilizationBatch.update({
      where: { id },
      data: { biResult, status },
    });

    if (biResult) {
      await this.setAttemptResult(tx, id, BatchAttemptResult.PASSED, BatchAttemptResult.PENDING);
      await this.audit.logTx(tx, userId, 'BATCH_BI_RESULT', id, { biResult, status });
    } else {
      // BI ไม่ผ่านหลัง early release → ต้อง recall ห่อที่ปล่อยไปแล้วทันที
      await this.audit.logTx(tx, userId, 'BATCH_BI_RESULT', id, { biResult, status });
      await this.recallTx(tx, id, userId);
      await this.setAttemptResult(tx, id, BatchAttemptResult.RECALLED, BatchAttemptResult.PENDING);
    }
    return b;
  }

  /** ตั้งผลของ attempt ของรอบนี้ (option: เฉพาะที่ยังเป็น [onlyFrom]) */
  private async setAttemptResult(
    tx: Prisma.TransactionClient,
    batchId: string,
    result: BatchAttemptResult,
    onlyFrom?: BatchAttemptResult,
  ) {
    await tx.packageBatchAttempt.updateMany({
      where: { batchId, ...(onlyFrom ? { result: onlyFrom } : {}) },
      data: { result, resolvedAt: new Date() },
    });
  }

  async recall(batchId: string, userId: string) {
    const packages = await this.prisma.$transaction((tx) => this.recallTx(tx, batchId, userId));
    return { recalled: packages.length, packages };
  }

  /** แกนกลางของ recall — รับ tx เพื่อให้ recordResult/recordBiResult เรียกในทรานแซกชันเดียวกันได้ */
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
