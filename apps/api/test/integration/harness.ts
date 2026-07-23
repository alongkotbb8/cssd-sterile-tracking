import { PrismaClient, PrintJobStatus } from '@prisma/client';
import { TEST_DATABASE_URL } from './config';
import { AuditService } from '../../src/common/audit/audit.service';
import { IdempotencyService } from '../../src/common/idempotency/idempotency.service';
import { PackagesService } from '../../src/modules/packages/packages.service';
import { RunningNumberService } from '../../src/modules/packages/running-number.service';
import { PrintJobsService } from '../../src/modules/print-jobs/print-jobs.service';
import { BatchesService } from '../../src/modules/batches/batches.service';
import { ScanService } from '../../src/modules/scan/scan.service';

export function makeClient(): PrismaClient {
  return new PrismaClient({ datasources: { db: { url: TEST_DATABASE_URL } } });
}

export function services(prisma: PrismaClient) {
  const audit = new AuditService(prisma as any);
  const running = new RunningNumberService(prisma as any);
  const packages = new PackagesService(prisma as any, running, audit);
  const idem = new IdempotencyService(prisma as any);
  const printJobs = new PrintJobsService(prisma as any, audit);
  const batches = new BatchesService(prisma as any, audit);
  const scan = new ScanService(prisma as any, audit);
  return { audit, running, packages, idem, printJobs, batches, scan };
}

export interface SeedIds {
  userId: string;
  setTemplateId: string;
  gatewayRealId: string; // canConfirmRealPrint = true
  sterilizerId: string;
}

/** รีเซ็ตทุกตาราง (รวม base) แล้วสร้างข้อมูลตั้งต้นใหม่ — เรียกใน beforeAll ของแต่ละ
 *  spec file ได้อย่างปลอดภัย (ไฟล์รันเรียงกันบน DB เดียว ต้องไม่ชน unique) */
export async function seedBase(prisma: PrismaClient): Promise<SeedIds> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE "package_batch_attempts","sterilization_batches","sterilizers","print_jobs","idempotent_requests","movements","audit_logs","packages","running_number_sequences","printer_devices","set_templates","users" RESTART IDENTITY CASCADE',
  );
  const user = await prisma.user.create({
    data: { employeeCode: 'INT001', name: 'Integration Tester', passwordHash: 'x', role: 'ADMIN' },
  });
  const template = await prisma.setTemplate.create({
    data: { code: 'INT', name: 'ชุดทดสอบ', itemList: ['a', 'b'] as any, defaultWrapType: 'SEAL' },
  });
  const gateway = await prisma.printerDevice.create({
    data: {
      name: 'int-gateway', keyId: 'intkey01', apiKeyHash: 'x',
      // ต้องสอดคล้อง invariant FIX-05: canConfirmRealPrint=true ได้เฉพาะ PRODUCTION + ไม่ใช่ CONSOLE
      environment: 'PRODUCTION', transportMode: 'SERIAL', canConfirmRealPrint: true,
    },
  });
  const sterilizer = await prisma.sterilizer.create({
    data: { code: 'AUTO-1', name: 'เครื่องนึ่งทดสอบ' },
  });
  return {
    userId: user.id,
    setTemplateId: template.id,
    gatewayRealId: gateway.id,
    sterilizerId: sterilizer.id,
  };
}

/** ล้างข้อมูล transactional ระหว่างเทส (คง user/template/gateway/sterilizer ไว้) */
export async function truncateTx(prisma: PrismaClient): Promise<void> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE "package_batch_attempts","sterilization_batches","print_jobs","idempotent_requests","movements","audit_logs","packages","running_number_sequences" RESTART IDENTITY CASCADE',
  );
}

/** สร้างรอบนึ่ง PENDING (ตรงเข้า DB) */
export async function makeBatch(
  prisma: PrismaClient,
  seed: SeedIds,
  roundNo: number,
): Promise<string> {
  const now = new Date('2026-07-23T02:00:00.000Z');
  const b = await prisma.sterilizationBatch.create({
    data: {
      sterilizerId: seed.sterilizerId,
      roundNo,
      runDate: now,
      startedAt: now,
      status: 'PENDING',
    },
  });
  return b.id;
}

export async function makePackage(
  prisma: PrismaClient,
  seed: SeedIds,
  opts: { id: string; printedAt?: Date | null; reprintCount?: number },
): Promise<string> {
  await prisma.package.create({
    data: {
      id: opts.id,
      setTemplateId: seed.setTemplateId,
      wrapType: 'SEAL',
      status: 'PACKED',
      createdById: seed.userId,
      printedAt: opts.printedAt ?? null,
      reprintCount: opts.reprintCount ?? 0,
    },
  });
  return opts.id;
}

export async function makeJob(
  prisma: PrismaClient,
  seed: SeedIds,
  packageId: string,
  opts: {
    status: PrintJobStatus;
    printerId?: string | null;
    requestedPrinterId?: string | null;
    isReprint?: boolean;
    attemptCount?: number;
  },
): Promise<string> {
  const payload = { packageId, setName: 'ชุดทดสอบ', wrapType: 'SEAL', sterilizeDate: null, expiryDate: null };
  const job = await prisma.printJob.create({
    data: {
      packageId,
      requestedById: seed.userId,
      status: opts.status,
      printerId: opts.printerId ?? null,
      requestedPrinterId: opts.requestedPrinterId ?? null,
      isReprint: opts.isReprint ?? false,
      attemptCount: opts.attemptCount ?? 0,
      payload: payload as any,
      payloadHash: 'inthash',
    },
  });
  return job.id;
}
