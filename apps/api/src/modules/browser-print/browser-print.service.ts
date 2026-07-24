import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  BrowserPrintMode,
  BrowserPrintOrigin,
  BrowserPrintStatus,
  PackageStatus,
  Prisma,
  UserRole,
} from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { assertValidPackageId } from '../scan/package-id.util';
import {
  BROWSER_PRINT_TEMPLATE_VERSION,
  resolveBrowserPrintEnabled,
} from './browser-print-config';
import { CreateBrowserPrintRequestDto } from './dto/create-browser-print-request.dto';
import {
  BROWSER_PRINT_LIST_DEFAULT_PAGE_SIZE,
  BROWSER_PRINT_LIST_MAX_PAGE_SIZE,
  ListBrowserPrintRequestsQuery,
} from './dto/list-browser-print-requests.query';

const USER_AGENT_MAX_LEN = 300;

/** สรุปประวัติการสั่งพิมพ์ก่อนหน้า (รวมทั้ง browser และ gateway) — คำนวณฝั่ง backend เท่านั้น */
export interface PriorPrints {
  count: number;
  lastAt: Date | null;
  lastByName: string | null;
  lastStatus: string | null;
  lastSource: 'BROWSER' | 'GATEWAY' | null;
}

type RequestRow = Prisma.BrowserPrintRequestGetPayload<Record<string, never>> & {
  requestedBy?: { name: string } | null;
};

/**
 * โหมดพิมพ์ `BROWSER_DIALOG` (MACOS_BROWSER_PRINT_DIRECTIVE.md) — เก็บประวัติคำขอ
 * พิมพ์ผ่าน macOS system print dialog แยกจาก Print Gateway โดยสิ้นเชิง
 *
 * กฎเหล็ก (directive §3/§19):
 * - ห้ามแตะ Package.printedAt/reprintCount และห้ามแตะตาราง PrintJob ใดๆ
 * - ห้ามใช้สถานะ PRINTED/SENT/ACK_UNKNOWN — browser พิสูจน์ผล hardware ไม่ได้
 * - USER_CONFIRMED = ผู้ใช้ยืนยันเองเท่านั้น (ไม่ใช่ hardware-confirmed)
 * - state machine จำกัด: CREATED→DIALOG_OPENED, CREATED→CANCELLED,
 *   DIALOG_OPENED→USER_CONFIRMED, DIALOG_OPENED→CANCELLED (CAS ผ่าน updateMany)
 */
@Injectable()
export class BrowserPrintService {
  // อ่าน flag ตอน construct (= ตอนบูตแอป) — ค่า env ผิดรูปแบบโยน error ทันที (fail fast)
  private readonly enabled = resolveBrowserPrintEnabled(process.env);

  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  /** directive §4: backend ต้องตรวจ feature flag เองทุก endpoint ห้ามพึ่งการซ่อน UI */
  assertEnabled(): void {
    if (!this.enabled) {
      throw new ForbiddenException({
        message: 'โหมดพิมพ์ผ่านเบราว์เซอร์ถูกปิดใช้งานอยู่',
        code: 'BROWSER_PRINT_DISABLED',
      });
    }
  }

  /** serialize แถวแบบ allowlist — ไม่คืน userAgent/idempotencyKey (ไม่คืนข้อมูลเกินจำเป็น) */
  private toRow(row: RequestRow) {
    return {
      id: row.id,
      packageId: row.packageId,
      requestedByUserId: row.requestedByUserId,
      requestedByName: row.requestedBy?.name ?? null,
      requestedAt: row.requestedAt,
      mode: row.mode,
      templateVersion: row.templateVersion,
      copies: row.copies,
      isReprint: row.isReprint,
      reprintReason: row.reprintReason,
      status: row.status,
      dialogOpenedAt: row.dialogOpenedAt,
      userConfirmedAt: row.userConfirmedAt,
      cancelledAt: row.cancelledAt,
      createdFrom: row.createdFrom,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  /**
   * ประวัติสั่งพิมพ์ก่อนหน้า: browser priors (DIALOG_OPENED/USER_CONFIRMED) +
   * gateway ที่ ACK จริงแล้ว (package.printedAt / reprintCount — อ่านอย่างเดียว)
   */
  private buildPriorPrints(
    pkg: { printedAt: Date | null; reprintCount?: number | null },
    priors: RequestRow[],
  ): PriorPrints {
    const gatewayCount = pkg.printedAt ? 1 + (pkg.reprintCount ?? 0) : 0;
    const count = priors.length + gatewayCount;
    if (count === 0) {
      return { count: 0, lastAt: null, lastByName: null, lastStatus: null, lastSource: null };
    }

    const latest = priors[0] ?? null;
    const browserAt = latest
      ? (latest.userConfirmedAt ?? latest.dialogOpenedAt ?? latest.requestedAt)
      : null;
    if (
      latest &&
      browserAt &&
      (!pkg.printedAt || browserAt.getTime() >= pkg.printedAt.getTime())
    ) {
      return {
        count,
        lastAt: browserAt,
        lastByName: latest.requestedBy?.name ?? null,
        lastStatus: latest.status,
        lastSource: 'BROWSER',
      };
    }
    return {
      count,
      lastAt: pkg.printedAt,
      lastByName: null, // gateway ACK ไม่ผูกชื่อผู้สั่งใน Package — ไม่เดา
      lastStatus: 'PRINTED',
      lastSource: 'GATEWAY',
    };
  }

  private auditMeta(
    row: RequestRow,
    previousStatus: BrowserPrintStatus | null,
    newStatus: BrowserPrintStatus,
  ): Record<string, unknown> {
    // directive §8: ห้ามใส่ secret/token — เก็บเฉพาะข้อมูล traceability ที่จำเป็น
    return {
      requestId: row.id,
      packageId: row.packageId,
      mode: row.mode,
      copies: row.copies,
      templateVersion: row.templateVersion,
      previousStatus,
      newStatus,
      isReprint: row.isReprint,
      ...(row.reprintReason ? { reprintReason: row.reprintReason } : {}),
    };
  }

  /**
   * สร้างคำขอพิมพ์ผ่านเบราว์เซอร์ — รันในทรานแซกชันของ idempotency (แนวทางเดียวกับ
   * print-jobs createJob): อ่าน package + คำนวณ isReprint/priorPrints + สร้างแถว +
   * AuditLog อยู่ใน tx เดียวกันทั้งหมด
   *
   * label ที่คืนเป็น authoritative จาก DB — วันที่มาจาก backend เท่านั้น (null เมื่อ
   * ยังไม่ผ่านการฆ่าเชื้อ) client ห้ามคำนวณวันหมดอายุเอง (directive §11)
   */
  async create(
    dto: CreateBrowserPrintRequestDto,
    userId: string,
    userAgent: string | undefined,
    idempotencyKey: string,
    tx: Prisma.TransactionClient,
  ) {
    this.assertEnabled();
    assertValidPackageId(dto.packageId); // 400 PKG_ID_INVALID

    const pkg = await tx.package.findUnique({
      where: { id: dto.packageId },
      include: { setTemplate: true },
    });
    if (!pkg) {
      throw new NotFoundException({ message: `ไม่พบห่อ ${dto.packageId}`, code: 'PKG_NOT_FOUND' });
    }
    // นโยบายเดียวกับฝั่ง packages: ห่อที่ทิ้งแล้วห้ามสั่งพิมพ์ label ใหม่
    if (pkg.status === PackageStatus.DISCARDED) {
      throw new BadRequestException({
        message: `ห่อ ${pkg.id} ถูกทิ้งไปแล้ว สั่งพิมพ์ label ไม่ได้`,
        code: 'PKG_DISCARDED',
      });
    }

    // isReprint คำนวณที่ backend เสมอ (directive §9): เคยมี browser request ที่
    // DIALOG_OPENED/USER_CONFIRMED หรือ gateway เคย ACK พิมพ์จริง (printedAt)
    const priors = (await tx.browserPrintRequest.findMany({
      where: {
        packageId: pkg.id,
        status: { in: [BrowserPrintStatus.DIALOG_OPENED, BrowserPrintStatus.USER_CONFIRMED] },
      },
      orderBy: { updatedAt: 'desc' },
      include: { requestedBy: { select: { name: true } } },
    })) as RequestRow[];
    const priorPrints = this.buildPriorPrints(pkg, priors);
    const isReprint = priors.length > 0 || pkg.printedAt !== null;

    if (isReprint && !dto.reprintReason?.trim()) {
      throw new BadRequestException({
        message: 'ห่อนี้เคยสั่งพิมพ์แล้ว ต้องระบุเหตุผลการพิมพ์ซ้ำ (reprintReason)',
        code: 'BROWSER_PRINT_REPRINT_REASON_REQUIRED',
        prior: priorPrints,
      });
    }

    const created = (await tx.browserPrintRequest.create({
      data: {
        packageId: pkg.id,
        requestedByUserId: userId,
        mode: BrowserPrintMode.BROWSER_DIALOG,
        templateVersion: BROWSER_PRINT_TEMPLATE_VERSION,
        copies: dto.copies,
        isReprint,
        reprintReason: isReprint ? dto.reprintReason!.trim() : null,
        createdFrom: dto.createdFrom as BrowserPrintOrigin,
        userAgent: userAgent ? userAgent.slice(0, USER_AGENT_MAX_LEN) : null,
        idempotencyKey,
      },
      include: { requestedBy: { select: { name: true } } },
    })) as RequestRow;

    await this.audit.logTx(
      tx,
      userId,
      'BROWSER_PRINT_REQUEST_CREATED',
      created.id,
      this.auditMeta(created, null, BrowserPrintStatus.CREATED),
    );
    if (isReprint) {
      await this.audit.logTx(
        tx,
        userId,
        'BROWSER_PRINT_REPRINT_REQUESTED',
        created.id,
        this.auditMeta(created, null, BrowserPrintStatus.CREATED),
      );
    }

    return {
      ...this.toRow(created),
      // label authoritative จาก DB — ห่อยังไม่ sterile → วันที่เป็น null ทั้งคู่
      label: {
        packageId: pkg.id,
        templateName: pkg.setTemplate.name,
        wrapType: pkg.wrapType,
        status: pkg.status,
        sterilizeDate: pkg.sterilizeDate,
        expiryDate: pkg.expiryDate,
        isSterilized: pkg.sterilizeDate !== null,
      },
      priorPrints,
    };
  }

  /**
   * เปลี่ยนสถานะแบบ CAS (updateMany บนสถานะที่คาดหวัง) — เจ้าของคำขอเท่านั้น
   * (แม้ ADMIN ก็เปลี่ยนแทนไม่ได้ — การยืนยันผลเป็นคำให้การของคนที่อยู่หน้าเครื่อง)
   * timestamp ของ transition มาจากนาฬิกา backend เสมอ
   */
  private async transition(
    tx: Prisma.TransactionClient,
    id: string,
    userId: string,
    allowedFrom: BrowserPrintStatus[],
    to: BrowserPrintStatus,
    timestampField: 'dialogOpenedAt' | 'userConfirmedAt' | 'cancelledAt',
    auditAction: string,
  ) {
    this.assertEnabled();
    const row = (await tx.browserPrintRequest.findUnique({ where: { id } })) as RequestRow | null;
    if (!row) {
      throw new NotFoundException({
        message: 'ไม่พบคำขอพิมพ์ผ่านเบราว์เซอร์',
        code: 'BROWSER_PRINT_NOT_FOUND',
      });
    }
    if (row.requestedByUserId !== userId) {
      throw new ForbiddenException({
        message: 'เปลี่ยนสถานะได้เฉพาะเจ้าของคำขอเท่านั้น',
        code: 'BROWSER_PRINT_FORBIDDEN',
      });
    }
    if (!allowedFrom.includes(row.status)) {
      throw new BadRequestException({
        message: `เปลี่ยนสถานะจาก ${row.status} เป็น ${to} ไม่ได้`,
        code: 'BROWSER_PRINT_STATE',
      });
    }

    // CAS ต้อง pin "สถานะที่อ่านได้จริง" (row.status) ไม่ใช่ทั้งชุด allowedFrom —
    // ไม่งั้น cancel (allowedFrom 2 ค่า) ที่แข่งกับ dialog-opened อาจสำเร็จทั้งที่สถานะ
    // เพิ่งเปลี่ยนไปแล้ว ทำให้ audit บันทึก previousStatus ผิดจากความจริง (ผิด §8)
    const { count } = await tx.browserPrintRequest.updateMany({
      where: { id, status: row.status }, // CAS — กันยิงซ้ำ/แข่งกัน + ผูก previousStatus ให้ตรงจริง
      data: { status: to, [timestampField]: new Date() },
    });
    if (count === 0) {
      throw new ConflictException({
        message: 'สถานะคำขอเปลี่ยนไปแล้ว กรุณาโหลดใหม่',
        code: 'BROWSER_PRINT_STATE',
      });
    }

    await this.audit.logTx(tx, userId, auditAction, id, this.auditMeta(row, row.status, to));

    const updated = (await tx.browserPrintRequest.findUnique({
      where: { id },
      include: { requestedBy: { select: { name: true } } },
    })) as RequestRow;
    return this.toRow(updated);
  }

  /** CREATED → DIALOG_OPENED — PWA บันทึกก่อนเรียกเปิด system print dialog */
  dialogOpened(id: string, userId: string, tx: Prisma.TransactionClient) {
    return this.transition(
      tx,
      id,
      userId,
      [BrowserPrintStatus.CREATED],
      BrowserPrintStatus.DIALOG_OPENED,
      'dialogOpenedAt',
      'BROWSER_PRINT_DIALOG_OPENED',
    );
  }

  /** DIALOG_OPENED → USER_CONFIRMED — ผู้ใช้ยืนยันเองว่ากระดาษออก (ไม่ใช่ hardware-confirmed) */
  confirm(id: string, userId: string, tx: Prisma.TransactionClient) {
    return this.transition(
      tx,
      id,
      userId,
      [BrowserPrintStatus.DIALOG_OPENED],
      BrowserPrintStatus.USER_CONFIRMED,
      'userConfirmedAt',
      'BROWSER_PRINT_USER_CONFIRMED',
    );
  }

  /** CREATED|DIALOG_OPENED → CANCELLED — ผู้ใช้แจ้งว่าไม่ได้พิมพ์/ยกเลิก */
  cancel(id: string, userId: string, tx: Prisma.TransactionClient) {
    return this.transition(
      tx,
      id,
      userId,
      [BrowserPrintStatus.CREATED, BrowserPrintStatus.DIALOG_OPENED],
      BrowserPrintStatus.CANCELLED,
      'cancelledAt',
      'BROWSER_PRINT_CANCELLED',
    );
  }

  /** เจ้าของคำขอ หรือ SUPERVISOR/ADMIN เท่านั้น (กัน IDOR — นโยบายเดียวกับ print-jobs) */
  async findOne(id: string, userId: string, role: UserRole) {
    this.assertEnabled();
    const row = (await this.prisma.browserPrintRequest.findUnique({
      where: { id },
      include: { requestedBy: { select: { name: true } } },
    })) as RequestRow | null;
    if (!row) {
      throw new NotFoundException({
        message: 'ไม่พบคำขอพิมพ์ผ่านเบราว์เซอร์',
        code: 'BROWSER_PRINT_NOT_FOUND',
      });
    }
    const canSeeAll = role === UserRole.SUPERVISOR || role === UserRole.ADMIN;
    if (!canSeeAll && row.requestedByUserId !== userId) {
      throw new ForbiddenException({
        message: 'ไม่มีสิทธิ์ดูคำขอพิมพ์นี้',
        code: 'BROWSER_PRINT_FORBIDDEN',
      });
    }
    return this.toRow(row);
  }

  /**
   * รายการประวัติ (directive §7) — non-privileged ถูกบังคับให้เห็นเฉพาะของตัวเอง
   * และการระบุ userId ที่ไม่ใช่ตัวเอง → 403 (ไม่เงียบๆ ทับค่า — บอกชัดว่าไม่มีสิทธิ์)
   */
  async list(userId: string, role: UserRole, q: ListBrowserPrintRequestsQuery) {
    this.assertEnabled();
    const canSeeAll = role === UserRole.SUPERVISOR || role === UserRole.ADMIN;
    if (!canSeeAll && q.userId && q.userId !== userId) {
      throw new ForbiddenException({
        message: 'ไม่มีสิทธิ์ดูคำขอพิมพ์ของผู้ใช้อื่น',
        code: 'BROWSER_PRINT_FORBIDDEN',
      });
    }

    const page = q.page ?? 1;
    const pageSize = Math.min(
      q.pageSize ?? BROWSER_PRINT_LIST_DEFAULT_PAGE_SIZE,
      BROWSER_PRINT_LIST_MAX_PAGE_SIZE,
    );
    const where: Prisma.BrowserPrintRequestWhereInput = {
      // non-privileged ถูกบังคับ filter เป็นของตัวเองเสมอ
      ...(canSeeAll ? (q.userId ? { requestedByUserId: q.userId } : {}) : { requestedByUserId: userId }),
      ...(q.packageId ? { packageId: q.packageId } : {}),
      ...(q.status ? { status: q.status } : {}),
      ...(q.from || q.to
        ? {
            createdAt: {
              ...(q.from ? { gte: new Date(q.from) } : {}),
              ...(q.to ? { lte: new Date(q.to) } : {}),
            },
          }
        : {}),
    };

    const [rows, total] = await Promise.all([
      this.prisma.browserPrintRequest.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
        include: { requestedBy: { select: { name: true } } },
      }) as Promise<RequestRow[]>,
      this.prisma.browserPrintRequest.count({ where }),
    ]);
    return { items: rows.map((r) => this.toRow(r)), total, page, pageSize };
  }
}
