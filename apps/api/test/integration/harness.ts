import { PrismaClient, PrintJobStatus } from '@prisma/client';
import { TEST_DATABASE_URL } from './config';
import { AuditService } from '../../src/common/audit/audit.service';
import { IdempotencyService } from '../../src/common/idempotency/idempotency.service';
import { PackagesService } from '../../src/modules/packages/packages.service';
import { RunningNumberService } from '../../src/modules/packages/running-number.service';
import { PrintJobsService } from '../../src/modules/print-jobs/print-jobs.service';

export function makeClient(): PrismaClient {
  return new PrismaClient({ datasources: { db: { url: TEST_DATABASE_URL } } });
}

export function services(prisma: PrismaClient) {
  const audit = new AuditService(prisma as any);
  const running = new RunningNumberService(prisma as any);
  const packages = new PackagesService(prisma as any, running, audit);
  const idem = new IdempotencyService(prisma as any);
  const printJobs = new PrintJobsService(prisma as any, audit);
  return { audit, running, packages, idem, printJobs };
}

export interface SeedIds {
  userId: string;
  setTemplateId: string;
  gatewayRealId: string; // canConfirmRealPrint = true
}

/** รีเซ็ตทุกตาราง (รวม base) แล้วสร้างข้อมูลตั้งต้นใหม่ — เรียกใน beforeAll ของแต่ละ
 *  spec file ได้อย่างปลอดภัย (ไฟล์รันเรียงกันบน DB เดียว ต้องไม่ชน unique) */
export async function seedBase(prisma: PrismaClient): Promise<SeedIds> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE "print_jobs","idempotent_requests","movements","audit_logs","packages","running_number_sequences","printer_devices","set_templates","users" RESTART IDENTITY CASCADE',
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
  return { userId: user.id, setTemplateId: template.id, gatewayRealId: gateway.id };
}

/** ล้างข้อมูล transactional ระหว่างเทส (คง user/template/gateway ไว้) */
export async function truncateTx(prisma: PrismaClient): Promise<void> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE "print_jobs","idempotent_requests","movements","audit_logs","packages","running_number_sequences" RESTART IDENTITY CASCADE',
  );
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
