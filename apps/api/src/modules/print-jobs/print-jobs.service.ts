import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import {
  GatewayEnvironment,
  GatewayTransportMode,
  Prisma,
  PrintJobStatus,
  UserRole,
} from '@prisma/client';
import { createHash, randomBytes } from 'crypto';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';

const MAX_ATTEMPTS = 3;
// งานที่ CLAIMED ค้างเกินเวลานี้ (gateway อาจ crash ก่อนเริ่มพิมพ์) → คืนเข้าคิวได้ปลอดภัย
const LEASE_TIMEOUT_MS = 10 * 60_000;

export interface PrintJobPayload {
  packageId: string;
  setName: string;
  wrapType: string; // 'SEAL' | 'CLOTH'
  // null = ห่อยังไม่ผ่านการนึ่ง — gateway/label renderer ต้องพิมพ์แถบ
  // "ยังไม่ผ่านการฆ่าเชื้อ" แทนวันที่ ห้าม fabricate วันที่เด็ดขาด (ข้อ 2.3)
  sterilizeDate: string | null;
  expiryDate: string | null;
}

@Injectable()
export class PrintJobsService {
  private readonly logger = new Logger(PrintJobsService.name);

  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  // ── Gateway registration (ADMIN เท่านั้น — เรียกจาก controller) ──

  /**
   * FIX-05 invariant: `canConfirmRealPrint=true` อนุญาตเฉพาะเมื่อเป็น gateway
   * production ที่ใช้ transport จริงเท่านั้น — Console/Test/Development ต้องเป็น
   * SIMULATED เสมอ (directive: "Console/Test Gateway → SIMULATED เท่านั้น")
   * ตรวจทั้งตอนตั้งค่า (register/update) และตอน ACK (canReallyConfirm ด้านล่าง)
   */
  private canReallyConfirm(g: {
    environment: GatewayEnvironment;
    transportMode: GatewayTransportMode;
    canConfirmRealPrint: boolean;
  }): boolean {
    return (
      g.canConfirmRealPrint &&
      g.environment === GatewayEnvironment.PRODUCTION &&
      g.transportMode !== GatewayTransportMode.CONSOLE
    );
  }

  private assertCapabilityConsistent(
    environment: GatewayEnvironment,
    transportMode: GatewayTransportMode,
    canConfirmRealPrint: boolean,
  ) {
    if (canConfirmRealPrint && !this.canReallyConfirm({ environment, transportMode, canConfirmRealPrint })) {
      throw new BadRequestException({
        message:
          'canConfirmRealPrint=true ได้เฉพาะ gateway ที่ environment=PRODUCTION และ transportMode ไม่ใช่ CONSOLE ' +
          `(ได้ environment=${environment}, transportMode=${transportMode}) — Console/Test/Dev ต้องเป็น SIMULATED เท่านั้น`,
        code: 'GATEWAY_CONFIG',
      });
    }
  }

  async registerGateway(
    name: string,
    userId: string,
    capability: {
      environment?: GatewayEnvironment;
      transportMode?: GatewayTransportMode;
      canConfirmRealPrint?: boolean;
    } = {},
  ) {
    const keyId = randomBytes(9).toString('hex'); // 18 hex chars
    const secret = randomBytes(24).toString('hex');
    const apiKeyHash = await bcrypt.hash(secret, 10);

    // FIX-05: capability default ปลอดภัยสุด — ต้อง ADMIN ตั้ง canConfirmRealPrint=true
    // อย่างจงใจเท่านั้นถึงจะพิมพ์จริงได้ (console/dev ตั้งไม่ได้โดยบังเอิญ)
    const environment = capability.environment ?? GatewayEnvironment.DEVELOPMENT;
    const transportMode = capability.transportMode ?? GatewayTransportMode.CONSOLE;
    const canConfirmRealPrint = capability.canConfirmRealPrint ?? false;
    this.assertCapabilityConsistent(environment, transportMode, canConfirmRealPrint);

    const printer = await this.prisma.$transaction(async (tx) => {
      const p = await tx.printerDevice.create({
        data: { name, keyId, apiKeyHash, environment, transportMode, canConfirmRealPrint },
      });
      await this.audit.logTx(tx, userId, 'GATEWAY_REGISTER', p.id, {
        name, environment, transportMode, canConfirmRealPrint,
      });
      return p;
    });

    // apiKey เต็มแสดงครั้งเดียวตอนสร้าง — เก็บได้แค่ hash เท่านั้นหลังจากนี้
    return {
      id: printer.id,
      name: printer.name,
      environment: printer.environment,
      transportMode: printer.transportMode,
      canConfirmRealPrint: printer.canConfirmRealPrint,
      apiKey: `${keyId}.${secret}`,
    };
  }

  /** FIX-05: เปลี่ยน capability ของ gateway (ADMIN เท่านั้น) + AuditLog บันทึกการเปลี่ยน */
  async updateGatewayCapability(
    id: string,
    userId: string,
    capability: {
      environment?: GatewayEnvironment;
      transportMode?: GatewayTransportMode;
      canConfirmRealPrint?: boolean;
    },
  ) {
    const printer = await this.prisma.printerDevice.findUnique({ where: { id } });
    if (!printer) throw new NotFoundException({ message: 'ไม่พบ gateway', code: 'GATEWAY_NOT_FOUND' });

    // ตรวจ invariant กับค่า "หลัง merge" (ค่าเดิม + สิ่งที่ patch มา) — กันตั้ง
    // canConfirmRealPrint=true คู่กับ CONSOLE/Dev ผ่านการ update ทีละฟิลด์
    const nextEnv = capability.environment ?? printer.environment;
    const nextTransport = capability.transportMode ?? printer.transportMode;
    const nextCanConfirm = capability.canConfirmRealPrint ?? printer.canConfirmRealPrint;
    this.assertCapabilityConsistent(nextEnv, nextTransport, nextCanConfirm);

    const updated = await this.prisma.$transaction(async (tx) => {
      const p = await tx.printerDevice.update({
        where: { id },
        data: {
          ...(capability.environment !== undefined ? { environment: capability.environment } : {}),
          ...(capability.transportMode !== undefined ? { transportMode: capability.transportMode } : {}),
          ...(capability.canConfirmRealPrint !== undefined
            ? { canConfirmRealPrint: capability.canConfirmRealPrint }
            : {}),
        },
      });
      await this.audit.logTx(tx, userId, 'GATEWAY_CAPABILITY_CHANGE', id, {
        before: {
          environment: printer.environment,
          transportMode: printer.transportMode,
          canConfirmRealPrint: printer.canConfirmRealPrint,
        },
        after: {
          environment: p.environment,
          transportMode: p.transportMode,
          canConfirmRealPrint: p.canConfirmRealPrint,
        },
      });
      return p;
    });
    return {
      id: updated.id,
      name: updated.name,
      environment: updated.environment,
      transportMode: updated.transportMode,
      canConfirmRealPrint: updated.canConfirmRealPrint,
    };
  }

  /**
   * หมุน key ของ gateway (ADMIN) — ออก keyId+secret ใหม่ key เดิมใช้ไม่ได้ทันที
   * (สำหรับกรณีสงสัยว่า key รั่ว/หมุนตามรอบ) — **ไม่เปลี่ยน PrinterDevice.id** ที่
   * งานพิมพ์อ้างอิงอยู่ จึงไม่กระทบงานเดิม; gateway process ต้องอัปเดต GATEWAY_API_KEY
   * เป็นค่าใหม่ที่คืนกลับ (แสดงครั้งเดียว)
   */
  async rotateGatewayKey(id: string, userId: string) {
    const printer = await this.prisma.printerDevice.findUnique({ where: { id } });
    if (!printer) throw new NotFoundException({ message: 'ไม่พบ gateway', code: 'GATEWAY_NOT_FOUND' });
    if (printer.revokedAt) {
      throw new BadRequestException({ message: 'gateway นี้ถูกเพิกถอนแล้ว หมุน key ไม่ได้ (ลงทะเบียนใหม่แทน)', code: 'GATEWAY_REVOKED' });
    }

    const keyId = randomBytes(9).toString('hex');
    const secret = randomBytes(24).toString('hex');
    const apiKeyHash = await bcrypt.hash(secret, 10);

    await this.prisma.$transaction(async (tx) => {
      await tx.printerDevice.update({ where: { id }, data: { keyId, apiKeyHash } });
      await this.audit.logTx(tx, userId, 'GATEWAY_KEY_ROTATE', id, { name: printer.name });
    });
    return { id, name: printer.name, apiKey: `${keyId}.${secret}` };
  }

  async revokeGateway(id: string, userId: string) {
    const printer = await this.prisma.printerDevice.findUnique({ where: { id } });
    if (!printer) throw new NotFoundException({ message: 'ไม่พบ gateway', code: 'GATEWAY_NOT_FOUND' });

    await this.prisma.$transaction(async (tx) => {
      await tx.printerDevice.update({
        where: { id },
        data: { isActive: false, revokedAt: new Date() },
      });
      await this.audit.logTx(tx, userId, 'GATEWAY_REVOKE', id, { name: printer.name });
    });
    return { revoked: true };
  }

  listGateways() {
    return this.prisma.printerDevice.findMany({
      select: {
        id: true,
        name: true,
        keyId: true,
        isActive: true,
        environment: true,
        transportMode: true,
        canConfirmRealPrint: true,
        lastHeartbeatAt: true,
        revokedAt: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async heartbeat(printerId: string) {
    await this.prisma.printerDevice.update({
      where: { id: printerId },
      data: { lastHeartbeatAt: new Date() },
    });
    return { ok: true };
  }

  // ── Print job lifecycle (เรียกจาก PWA ผ่าน JWT) ──

  /**
   * ต้องให้ผล **เดิมเป๊ะ** ไม่ว่าคีย์จะเรียงลำดับมาแบบไหน — Postgres jsonb
   * ไม่รับประกัน preserve key order ตอนอ่านกลับ (เพื่อความปลอดภัย ไม่พึ่ง
   * behavior ที่ไม่ได้ documented) จึงบังคับ sort key ก่อน stringify เสมอ
   * ต้องตรงกับ hashPayload ฝั่ง apps/print-gateway/src/label-renderer.ts
   * (payloadHash verification ก่อนพิมพ์จริง — audit ข้อ 2.4)
   */
  private hashPayload(payload: PrintJobPayload): string {
    const orderedKeys = Object.keys(payload).sort();
    return createHash('sha256').update(JSON.stringify(payload, orderedKeys)).digest('hex');
  }

  private async buildPayload(
    db: Prisma.TransactionClient | PrismaService,
    packageId: string,
  ): Promise<{ pkg: Prisma.PackageGetPayload<{ include: { setTemplate: true } }>; payload: PrintJobPayload; payloadHash: string }> {
    const pkg = await db.package.findUnique({
      where: { id: packageId },
      include: { setTemplate: true },
    });
    if (!pkg) throw new NotFoundException({ message: `ไม่พบห่อ ${packageId}`, code: 'PKG_NOT_FOUND' });

    const payload: PrintJobPayload = {
      packageId: pkg.id,
      setName: pkg.setTemplate.name,
      wrapType: pkg.wrapType,
      sterilizeDate: pkg.sterilizeDate?.toISOString() ?? null,
      expiryDate: pkg.expiryDate?.toISOString() ?? null,
    };
    return { pkg, payload, payloadHash: this.hashPayload(payload) };
  }

  /**
   * สร้าง print job — รันในทรานแซกชันที่ idempotency ส่งเข้ามา (FIX-02 แนวทาง A)
   * การอ่าน payload + สร้าง job + AuditLog + เก็บ response ของ idempotency อยู่ใน
   * ทรานแซกชันเดียวกัน crash = rollback ไม่เกิดงานพิมพ์ซ้ำ
   */
  async createJob(
    packageId: string,
    userId: string,
    opts: { requestedPrinterId?: string; reprintReason?: string },
    tx: Prisma.TransactionClient,
  ) {
    // payload มาจากข้อมูล backend ล้วนๆ — ตรงกับ domain rule ข้อ 2.3 ทั้ง
    // AGENTS.md และ guardrails ห้าม client กำหนดวันที่เอง และห้ามคาดเดาวันที่
    // ก่อนนึ่งจริง (sterilizeDate/expiryDate เป็น null จนกว่าจะผ่านรอบนึ่ง)
    const { pkg, payload, payloadHash } = await this.buildPayload(tx, packageId);

    if (opts.requestedPrinterId) {
      const printer = await tx.printerDevice.findUnique({ where: { id: opts.requestedPrinterId } });
      if (!printer || !printer.isActive) throw new BadRequestException({ message: 'ไม่พบเครื่องพิมพ์ที่ระบุ', code: 'PRINTER_NOT_FOUND' });
    }

    // isReprint คำนวณที่ backend เสมอ (ห้ามให้ client ส่งมาเอง) กันหลบการกรอก
    // เหตุผล reprint (AI_DEVELOPMENT_GUARDRAILS.md ข้อ 2.2)
    const isReprint = pkg.printedAt !== null;
    if (isReprint && !opts.reprintReason?.trim()) {
      throw new BadRequestException({ message: 'ห่อนี้เคยพิมพ์แล้ว ต้องระบุเหตุผลการพิมพ์ซ้ำ (reprintReason)', code: 'REPRINT_REASON_REQUIRED' });
    }

    const created = await tx.printJob.create({
      data: {
        packageId: pkg.id,
        requestedPrinterId: opts.requestedPrinterId ?? null,
        requestedById: userId,
        isReprint,
        reprintReason: isReprint ? opts.reprintReason : null,
        payload: payload as unknown as Prisma.InputJsonValue,
        payloadHash,
      },
    });
    await this.audit.logTx(tx, userId, 'PRINT_REQUEST', created.id, {
      packageId: pkg.id,
      isReprint,
      reprintReason: created.reprintReason,
    });
    return created;
  }

  /** เจ้าของงานหรือ SUPERVISOR/ADMIN เท่านั้นที่ดูรายละเอียดงานพิมพ์ได้ (กัน IDOR) */
  async findOne(id: string, userId: string, role: UserRole) {
    const job = await this.prisma.printJob.findUnique({ where: { id } });
    if (!job) throw new NotFoundException({ message: 'ไม่พบ print job', code: 'PRINT_JOB_NOT_FOUND' });

    const canSeeAll = role === UserRole.SUPERVISOR || role === UserRole.ADMIN;
    if (!canSeeAll && job.requestedById !== userId) {
      throw new ForbiddenException({ message: 'ไม่มีสิทธิ์ดูงานพิมพ์นี้', code: 'PRINT_JOB_FORBIDDEN' });
    }
    return job;
  }

  async listJobs(userId: string, role: UserRole, filters: { status?: PrintJobStatus; packageId?: string }) {
    const canSeeAll = role === UserRole.SUPERVISOR || role === UserRole.ADMIN;
    return this.prisma.printJob.findMany({
      where: {
        ...(canSeeAll ? {} : { requestedById: userId }),
        ...(filters.status ? { status: filters.status } : {}),
        ...(filters.packageId ? { packageId: filters.packageId } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  /** ยกเลิกได้เฉพาะงานที่ยังไม่ถูก gateway claim (QUEUED) — claim แล้วอาจพิมพ์ไปแล้ว ยกเลิกไม่ปลอดภัย */
  async cancel(id: string, userId: string, role: UserRole) {
    const job = await this.prisma.printJob.findUnique({ where: { id } });
    if (!job) throw new NotFoundException({ message: 'ไม่พบ print job', code: 'PRINT_JOB_NOT_FOUND' });

    const isOwner = job.requestedById === userId;
    const isPrivileged = role === UserRole.SUPERVISOR || role === UserRole.ADMIN;
    if (!isOwner && !isPrivileged) throw new ForbiddenException({ message: 'ยกเลิกงานนี้ไม่ได้', code: 'PRINT_JOB_FORBIDDEN' });

    if (job.status !== PrintJobStatus.QUEUED) {
      throw new BadRequestException({
        message: `ยกเลิกได้เฉพาะงานที่ยังไม่ถูก claim (ปัจจุบัน: ${job.status})`,
        code: 'PRINT_JOB_STATE',
      });
    }

    await this.prisma.$transaction(async (tx) => {
      const { count } = await tx.printJob.updateMany({
        where: { id, status: PrintJobStatus.QUEUED }, // CAS กันชนกับ gateway claim พอดี
        data: { status: PrintJobStatus.CANCELLED },
      });
      if (count === 0) throw new BadRequestException({ message: 'สถานะงานเปลี่ยนไปแล้ว ลองโหลดใหม่', code: 'PRINT_JOB_STATE' });
      await this.audit.logTx(tx, userId, 'PRINT_CANCEL', id, { previousStatus: job.status });
    });
    return { cancelled: true };
  }

  /** SUPERVISOR/ADMIN ตัดสินใจงานที่ค้าง ACK_UNKNOWN (ส่งสำเร็จแต่ไม่รู้ว่าพิมพ์จริงหรือยัง) */
  async resolveAckUnknown(
    jobId: string,
    userId: string,
    decision: 'CONFIRM_PRINTED' | 'REQUEUE',
    note: string,
  ) {
    if (!note?.trim()) throw new BadRequestException({ message: 'ต้องระบุหมายเหตุการตัดสินใจ', code: 'PRINT_JOB_NOTE_REQUIRED' });

    const job = await this.prisma.printJob.findUnique({ where: { id: jobId } });
    if (!job) throw new NotFoundException({ message: 'ไม่พบ print job', code: 'PRINT_JOB_NOT_FOUND' });
    if (job.status !== PrintJobStatus.ACK_UNKNOWN) {
      throw new BadRequestException({ message: `แก้ไขได้เฉพาะงานที่เป็น ACK_UNKNOWN (ปัจจุบัน: ${job.status})`, code: 'PRINT_JOB_STATE' });
    }

    if (decision === 'CONFIRM_PRINTED') {
      return this.prisma.$transaction(async (tx) => {
        // CAS: ต้องยังเป็น ACK_UNKNOWN และ **ยังไม่เคย resolve** (resolvedAt IS NULL)
        // — resolve พร้อมกัน 2 request จะมีแค่ตัวเดียวได้ count=1, อีกตัว count=0
        // → 409 (FIX-03: กัน resolve ซ้ำ / เพิ่ม reprintCount ซ้ำ)
        const { count } = await tx.printJob.updateMany({
          where: { id: jobId, status: PrintJobStatus.ACK_UNKNOWN, resolvedAt: null },
          data: {
            status: PrintJobStatus.RESOLVED_PRINTED,
            printedAt: new Date(),
            resolvedById: userId,
            resolvedAt: new Date(),
            resolutionNote: note,
          },
        });
        if (count === 0) throw new ConflictException({ message: 'งานนี้ถูกตัดสินใจไปแล้ว หรือสถานะเปลี่ยนไป', code: 'PRINT_JOB_STATE' });

        const pkg = await tx.package.findUniqueOrThrow({ where: { id: job.packageId } });
        await tx.package.update({
          where: { id: job.packageId },
          data: {
            printedAt: new Date(),
            ...(job.isReprint || pkg.printedAt ? { reprintCount: { increment: 1 } } : {}),
          },
        });
        await this.audit.logTx(tx, userId, 'PRINT_ACK_UNKNOWN_RESOLVED', jobId, {
          decision, note, packageId: job.packageId,
        });
        return tx.printJob.findUniqueOrThrow({ where: { id: jobId } });
      });
    }

    // REQUEUE: ไม่ยืนยันว่าพิมพ์จริง → ปิดงานเดิมเป็น RESOLVED_REQUEUED (terminal —
    // ไม่ใช่ ACK_UNKNOWN แล้ว จึง resolve ซ้ำไม่ได้) แล้วเปิดงานใหม่ลิงก์กลับผ่าน
    // requeuedFromJobId (@unique = กันสร้างงานใหม่ซ้ำแม้แข่งกัน) การ resolve +
    // สร้างงานใหม่อยู่ในทรานแซกชันเดียวกัน (FIX-03)
    return this.prisma.$transaction(async (tx) => {
      const { count } = await tx.printJob.updateMany({
        where: { id: jobId, status: PrintJobStatus.ACK_UNKNOWN, resolvedAt: null },
        data: {
          status: PrintJobStatus.RESOLVED_REQUEUED,
          resolvedById: userId,
          resolvedAt: new Date(),
          resolutionNote: note,
        },
      });
      if (count === 0) throw new ConflictException({ message: 'งานนี้ถูกตัดสินใจไปแล้ว หรือสถานะเปลี่ยนไป', code: 'PRINT_JOB_STATE' });

      const { pkg, payload, payloadHash } = await this.buildPayload(tx, job.packageId);
      const requeued = await tx.printJob.create({
        data: {
          packageId: pkg.id,
          requestedPrinterId: job.requestedPrinterId,
          requestedById: userId,
          isReprint: true,
          reprintReason: `แก้ไขงานพิมพ์ ${jobId} (ไม่ยืนยันว่าพิมพ์จริง): ${note}`,
          payload: payload as unknown as Prisma.InputJsonValue,
          payloadHash,
          requeuedFromJobId: jobId,
        },
      });
      await this.audit.logTx(tx, userId, 'PRINT_ACK_UNKNOWN_RESOLVED', jobId, {
        decision, note, requeuedJobId: requeued.id, packageId: job.packageId,
      });
      return requeued;
    });
  }

  // ── Gateway-only operations (auth ผ่าน GatewayAuthGuard, ไม่ใช่ JWT) ──

  /**
   * Claim แบบ atomic ด้วย `SELECT ... FOR UPDATE SKIP LOCKED` — กัน 2 gateway
   * claim งานเดียวกันพร้อมกัน (row lock ระดับ DB, ไม่ใช่แค่ตรวจ status ที่แอป)
   * จับคู่ด้วย requestedPrinterId (สิ่งที่ผู้ใช้ระบุตอนสร้าง, immutable) — ไม่ใช่
   * printerId (เครื่องที่ claim ไปแล้ว) เพื่อไม่ให้งาน pool ปนกับงานที่ระบุเครื่อง
   */
  async claim(printerId: string) {
    return this.prisma.$transaction(async (tx) => {
      const rows = await tx.$queryRaw<{ id: string }[]>`
        SELECT id FROM print_jobs
        WHERE status = 'QUEUED' AND ("requestedPrinterId" IS NULL OR "requestedPrinterId" = ${printerId})
        ORDER BY "createdAt" ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED
      `;
      if (rows.length === 0) return null;

      const jobId = rows[0].id;
      const { count } = await tx.printJob.updateMany({
        where: { id: jobId, status: PrintJobStatus.QUEUED },
        data: {
          status: PrintJobStatus.CLAIMED,
          printerId,
          claimedAt: new Date(),
          attemptCount: { increment: 1 },
        },
      });
      if (count === 0) return null; // กันไว้เผื่อชนกันพอดี (ไม่ควรเกิดเพราะ row lock แล้ว)

      const claimed = await tx.printJob.findUniqueOrThrow({ where: { id: jobId } });
      await this.audit.logTx(tx, claimed.requestedById, 'PRINT_CLAIM', jobId, { printerId });
      return claimed;
    });
  }

  private async assertOwnedByGateway(jobId: string, printerId: string) {
    const job = await this.prisma.printJob.findUnique({ where: { id: jobId } });
    if (!job) throw new NotFoundException({ message: 'ไม่พบ print job', code: 'PRINT_JOB_NOT_FOUND' });
    if (job.printerId !== printerId) {
      throw new ForbiddenException({ message: 'งานนี้ไม่ได้ผูกกับ gateway นี้', code: 'PRINT_JOB_FORBIDDEN' });
    }
    return job;
  }

  /** CLAIMED → PRINTING (ก่อนเรียก transport.send()) */
  async markPrinting(jobId: string, printerId: string) {
    const job = await this.assertOwnedByGateway(jobId, printerId);
    const { count } = await this.prisma.printJob.updateMany({
      where: { id: jobId, printerId, status: PrintJobStatus.CLAIMED },
      data: { status: PrintJobStatus.PRINTING, printingAt: new Date() },
    });
    if (count === 0) {
      throw new BadRequestException({ message: `เปลี่ยนเป็น PRINTING ไม่ได้จากสถานะ ${job.status}`, code: 'PRINT_JOB_STATE' });
    }
    return this.prisma.printJob.findUniqueOrThrow({ where: { id: jobId } });
  }

  /**
   * เรียกทันทีหลัง transport.send() คืนผลสำเร็จ (ก่อนเรียก ack) — บันทึกว่า
   * "ข้อมูลถึงเครื่องพิมพ์แน่นอนแล้ว" ถ้า network หลุดตอนเรียกเมธอดนี้ job จะค้าง
   * ที่ PRINTING — lease recovery จะไม่ auto-retry (กันพิมพ์ซ้ำ) แต่จะกลายเป็น
   * ACK_UNKNOWN ให้ SUPERVISOR/ADMIN ตัดสินใจแทน (ตรงตาม audit ข้อ 1.1)
   */
  async markSent(jobId: string, printerId: string) {
    const job = await this.assertOwnedByGateway(jobId, printerId);
    if (job.status === PrintJobStatus.SENT) return job; // gateway retry การเรียกซ้ำ — idempotent
    const { count } = await this.prisma.printJob.updateMany({
      where: { id: jobId, printerId, status: PrintJobStatus.PRINTING },
      data: { status: PrintJobStatus.SENT, sentAt: new Date() },
    });
    if (count === 0) {
      throw new BadRequestException({ message: `เปลี่ยนเป็น SENT ไม่ได้จากสถานะ ${job.status}`, code: 'PRINT_JOB_STATE' });
    }
    return this.prisma.printJob.findUniqueOrThrow({ where: { id: jobId } });
  }

  /**
   * MAYBE_SENT (FIX-04): gateway เรียก write() แล้วเกิด callback/drain error ซึ่ง
   * **อาจมี byte ออกไปหาเครื่องพิมพ์แล้วบางส่วน/ทั้งหมด** — ห้ามถือว่าไม่ได้ส่ง
   * และห้าม auto-retry เด็ดขาด (จะพิมพ์ซ้ำ) จึงย้ายเข้า ACK_UNKNOWN ทันทีให้
   * SUPERVISOR/ADMIN ตรวจสอบเอง (แทนที่จะรอ lease timeout)
   */
  async reportIndeterminate(jobId: string, printerId: string, errorCode: string, message?: string) {
    const job = await this.assertOwnedByGateway(jobId, printerId);
    if (job.status === PrintJobStatus.ACK_UNKNOWN) return job; // gateway retry — idempotent
    const { count } = await this.prisma.$transaction(async (tx) => {
      const res = await tx.printJob.updateMany({
        where: {
          id: jobId,
          printerId,
          status: { in: [PrintJobStatus.CLAIMED, PrintJobStatus.PRINTING] },
        },
        data: { status: PrintJobStatus.ACK_UNKNOWN, errorCode, failedAt: new Date() },
      });
      if (res.count > 0) {
        await this.audit.logTx(tx, job.requestedById, 'PRINT_MAYBE_SENT', jobId, {
          errorCode,
          message,
          previousStatus: job.status,
        });
      }
      return res;
    });
    if (count === 0) {
      throw new BadRequestException({
        message: `รายงาน MAYBE_SENT ไม่ได้จากสถานะ ${job.status} (ต้องเป็น CLAIMED/PRINTING)`,
        code: 'PRINT_JOB_STATE',
      });
    }
    return this.prisma.printJob.findUniqueOrThrow({ where: { id: jobId } });
  }

  /**
   * ACK สำเร็จ — ทางเดียวที่ printedAt/reprintCount ของ Package จะถูกอัปเดต
   * (AI_DEVELOPMENT_GUARDRAILS.md ข้อ 2.7: ห้าม PWA ตั้งสถานะ PRINTED เอง)
   * ต้องมาจากสถานะ SENT เท่านั้น (ยืนยันแล้วว่า transport.send() สำเร็จจริง)
   * ACK ซ้ำ (retry ของ gateway เอง) เป็น idempotent — ถ้า PRINTED/SIMULATED
   * อยู่แล้วคืนผลเดิมเฉยๆ ไม่ทำซ้ำ
   *
   * FIX-05: **backend** เป็นผู้ตัดสินว่าจะเป็น PRINTED หรือ SIMULATED จาก
   * capability ของ gateway (`canConfirmRealPrint`) เท่านั้น — ไม่รับ flag จาก
   * request เด็ดขาด (gateway ที่ผิดพลาด/ถูกยึดจะแกล้งเป็น real ไม่ได้) console/
   * test gateway (canConfirmRealPrint=false) → SIMULATED เสมอ ไม่แตะ Package
   */
  async ack(jobId: string, printerId: string) {
    const job = await this.assertOwnedByGateway(jobId, printerId);
    const gateway = await this.prisma.printerDevice.findUniqueOrThrow({ where: { id: printerId } });
    // ตรวจซ้ำครบทั้ง 3 ค่าตอน ACK (ไม่เชื่อแค่ canConfirmRealPrint ตัวเดียว) — ต่อให้
    // มีแถวที่ค่าไม่สอดคล้องหลุดเข้ามา (เช่น CONSOLE + canConfirmRealPrint=true) ก็จะ
    // ยังเป็น SIMULATED เสมอ (FIX-05 defense-in-depth)
    const simulated = !this.canReallyConfirm(gateway);
    const targetStatus = simulated ? PrintJobStatus.SIMULATED : PrintJobStatus.PRINTED;
    if (job.status === targetStatus) return job;

    return this.prisma.$transaction(async (tx) => {
      const { count } = await tx.printJob.updateMany({
        where: { id: jobId, printerId, status: PrintJobStatus.SENT },
        data: { status: targetStatus, printedAt: new Date() },
      });
      if (count === 0) {
        throw new BadRequestException({ message: `ACK ไม่ได้จากสถานะ ${job.status} (ต้องเป็น SENT ก่อน)`, code: 'PRINT_JOB_STATE' });
      }

      if (!simulated) {
        const pkg = await tx.package.findUniqueOrThrow({ where: { id: job.packageId } });
        await tx.package.update({
          where: { id: job.packageId },
          data: {
            printedAt: new Date(),
            ...(job.isReprint || pkg.printedAt ? { reprintCount: { increment: 1 } } : {}),
          },
        });
      }
      await this.audit.logTx(
        tx,
        job.requestedById,
        simulated ? 'PRINT_SIMULATED' : 'PRINT_SUCCESS',
        jobId,
        { packageId: job.packageId, isReprint: job.isReprint },
      );
      return tx.printJob.findUniqueOrThrow({ where: { id: jobId } });
    });
  }

  /**
   * รายงาน transport.send() ล้มเหลว — อนุญาตเฉพาะตอนยังไม่ยืนยันว่าส่งสำเร็จ
   * (CLAIMED/PRINTING เท่านั้น) หลังเข้าสถานะ SENT แล้วห้าม fail() เด็ดขาด
   * (รู้แน่ว่าส่งไปเครื่องพิมพ์แล้ว retry จะพิมพ์ซ้ำ — ต้องใช้ resolveAckUnknown แทน)
   */
  async fail(jobId: string, printerId: string, errorCode: string, message?: string) {
    const job = await this.assertOwnedByGateway(jobId, printerId);
    if (job.status !== PrintJobStatus.CLAIMED && job.status !== PrintJobStatus.PRINTING) {
      throw new BadRequestException({
        message: `รายงาน fail ไม่ได้จากสถานะ ${job.status} — หลังส่งข้อมูลสำเร็จ (SENT ขึ้นไป) ห้าม retry อัตโนมัติ`,
        code: 'PRINT_JOB_STATE',
      });
    }

    const nextStatus =
      job.attemptCount >= MAX_ATTEMPTS ? PrintJobStatus.DEAD_LETTER : PrintJobStatus.RETRYING;

    return this.prisma.$transaction(async (tx) => {
      const { count } = await tx.printJob.updateMany({
        where: { id: jobId, printerId, status: job.status },
        data: { status: nextStatus, errorCode, failedAt: new Date() },
      });
      if (count === 0) throw new BadRequestException({ message: 'สถานะงานเปลี่ยนไปแล้ว ลองโหลดใหม่', code: 'PRINT_JOB_STATE' });

      await this.audit.logTx(tx, job.requestedById, 'PRINT_FAILURE', jobId, {
        errorCode,
        message,
        attemptCount: job.attemptCount,
        nextStatus,
      });

      if (nextStatus === PrintJobStatus.RETRYING) {
        // เข้าคิวใหม่ให้ gateway ใดๆ ที่ตรง requestedPrinterId claim ได้อีกครั้ง
        await tx.printJob.updateMany({
          where: { id: jobId, status: PrintJobStatus.RETRYING },
          data: { status: PrintJobStatus.QUEUED, printerId: null, claimedAt: null, printingAt: null },
        });
      }
      return tx.printJob.findUniqueOrThrow({ where: { id: jobId } });
    });
  }

  // ── Lease timeout recovery ──

  @Cron('*/2 * * * *')
  async recoverStaleLeases() {
    const staleBefore = new Date(Date.now() - LEASE_TIMEOUT_MS);

    // CLAIMED ค้าง = gateway ยังไม่ทันเริ่มพิมพ์ (ยังไม่เรียก transport.send())
    // ปลอดภัยที่จะคืนเข้าคิวให้ตัวอื่น claim ใหม่ได้เลย
    const staleClaimed = await this.prisma.printJob.findMany({
      where: { status: PrintJobStatus.CLAIMED, claimedAt: { lt: staleBefore } },
      select: { id: true, requestedById: true, printerId: true },
    });
    for (const job of staleClaimed) {
      await this.prisma.$transaction(async (tx) => {
        const { count } = await tx.printJob.updateMany({
          where: { id: job.id, status: PrintJobStatus.CLAIMED },
          data: { status: PrintJobStatus.QUEUED, printerId: null, claimedAt: null },
        });
        if (count > 0) {
          await this.audit.logTx(tx, job.requestedById, 'PRINT_LEASE_TIMEOUT', job.id, {
            printerId: job.printerId,
            recovered: 'QUEUED',
          });
        }
      });
    }

    // PRINTING/SENT ค้าง = ไม่รู้ว่าข้อมูลถึงเครื่องพิมพ์จริงหรือยัง (อาจ crash
    // กลางคัน) ห้าม auto-retry เด็ดขาด (เสี่ยงพิมพ์ซ้ำ) ต้องให้ SUPERVISOR/ADMIN
    // ตรวจสอบมือผ่าน resolveAckUnknown เท่านั้น (audit ข้อ 1.1)
    const stalePrinting = await this.prisma.printJob.findMany({
      where: { status: PrintJobStatus.PRINTING, printingAt: { lt: staleBefore } },
      select: { id: true, requestedById: true, printerId: true, status: true },
    });
    const staleSent = await this.prisma.printJob.findMany({
      where: { status: PrintJobStatus.SENT, sentAt: { lt: staleBefore } },
      select: { id: true, requestedById: true, printerId: true, status: true },
    });
    const staleUnknown = [...stalePrinting, ...staleSent];
    for (const job of staleUnknown) {
      await this.prisma.$transaction(async (tx) => {
        const { count } = await tx.printJob.updateMany({
          where: { id: job.id, status: job.status },
          data: { status: PrintJobStatus.ACK_UNKNOWN },
        });
        if (count > 0) {
          await this.audit.logTx(tx, job.requestedById, 'PRINT_LEASE_TIMEOUT', job.id, {
            printerId: job.printerId,
            recovered: 'ACK_UNKNOWN',
            previousStatus: job.status,
          });
        }
      });
    }

    const total = staleClaimed.length + staleUnknown.length;
    if (total > 0) {
      this.logger.warn(
        `Recovered ${staleClaimed.length} stale CLAIMED -> QUEUED, ${staleUnknown.length} stale PRINTING/SENT -> ACK_UNKNOWN`,
      );
    }
  }
}
