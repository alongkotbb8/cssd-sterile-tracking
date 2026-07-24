import { PrismaClient, PrintJobStatus } from '@prisma/client';
import { makeClient, services, seedBase, truncateTx, makePackage, makeJob, SeedIds } from './harness';

/**
 * FIX-07 — Print Job concurrency กับ PostgreSQL จริง: claim (FOR UPDATE SKIP
 * LOCKED), ACK race, cancel-vs-claim, resolve ACK_UNKNOWN, REQUEUE ซ้ำ
 */
describe('[integration] Print Job concurrency กับ Postgres จริง', () => {
  let prisma: PrismaClient;
  let svc: ReturnType<typeof services>;
  let seed: SeedIds;

  beforeAll(async () => {
    prisma = makeClient();
    await prisma.$connect();
    svc = services(prisma);
    seed = await seedBase(prisma);
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await truncateTx(prisma);
  });

  it('gateway สองตัว claim พร้อมกัน 1 งาน → ได้แค่ตัวเดียว (FOR UPDATE SKIP LOCKED)', async () => {
    await makePackage(prisma, seed, { id: 'PKG-CLAIM' });
    await makeJob(prisma, seed, 'PKG-CLAIM', { status: PrintJobStatus.QUEUED });

    const gw2 = await prisma.printerDevice.create({
      data: { name: 'gw2', keyId: 'intkey02', apiKeyHash: 'x' },
    });

    const [a, b] = await Promise.all([
      svc.printJobs.claim(seed.gatewayRealId),
      svc.printJobs.claim(gw2.id),
    ]);
    const claimed = [a, b].filter(Boolean);
    expect(claimed).toHaveLength(1); // มีแค่ตัวเดียวที่ claim ได้
    const job = await prisma.printJob.findFirst();
    expect(job?.status).toBe(PrintJobStatus.CLAIMED);
    expect(job?.attemptCount).toBe(1); // increment ครั้งเดียว
  });

  it('ACK สองครั้งพร้อมกันบนงาน SENT → reprintCount เพิ่มครั้งเดียว, สำเร็จตัวเดียว', async () => {
    await makePackage(prisma, seed, { id: 'PKG-ACK', printedAt: new Date('2026-01-01'), reprintCount: 1 });
    await makeJob(prisma, seed, 'PKG-ACK', {
      status: PrintJobStatus.SENT, printerId: seed.gatewayRealId, isReprint: true,
    });
    const jobId = (await prisma.printJob.findFirstOrThrow()).id;

    const results = await Promise.all([
      svc.printJobs.ack(jobId, seed.gatewayRealId).catch((e) => e),
      svc.printJobs.ack(jobId, seed.gatewayRealId).catch((e) => e),
    ]);
    expect(results.filter((r) => !(r instanceof Error))).toHaveLength(1);
    const pkg = await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-ACK' } });
    expect(pkg.reprintCount).toBe(2); // ไม่ใช่ 3
    expect((await prisma.printJob.findUniqueOrThrow({ where: { id: jobId } })).status).toBe(
      PrintJobStatus.PRINTED,
    );
  });

  it('cancel ชนกับ claim → อย่างใดอย่างหนึ่งชนะ ไม่ใช่ทั้งคู่', async () => {
    await makePackage(prisma, seed, { id: 'PKG-CC' });
    const jobId = await makeJob(prisma, seed, 'PKG-CC', { status: PrintJobStatus.QUEUED });

    const [cancelRes, claimRes] = await Promise.all([
      svc.printJobs.cancel(jobId, seed.userId, 'ADMIN' as any).catch((e) => e),
      svc.printJobs.claim(seed.gatewayRealId).catch((e) => e),
    ]);

    const cancelled = !(cancelRes instanceof Error);
    const claimed = claimRes && !(claimRes instanceof Error);
    // ต้องไม่เกิดทั้ง cancel สำเร็จ และ claim ได้งานเดียวกันพร้อมกัน
    expect(cancelled && claimed).toBe(false);

    const job = await prisma.printJob.findUniqueOrThrow({ where: { id: jobId } });
    expect([PrintJobStatus.CANCELLED, PrintJobStatus.CLAIMED]).toContain(job.status);
  });

  it('resolve ACK_UNKNOWN (CONFIRM_PRINTED) พร้อมกัน → สำเร็จครั้งเดียว, reprintCount เพิ่มครั้งเดียว', async () => {
    await makePackage(prisma, seed, { id: 'PKG-RES', printedAt: new Date('2026-01-01'), reprintCount: 1 });
    const jobId = await makeJob(prisma, seed, 'PKG-RES', {
      status: PrintJobStatus.ACK_UNKNOWN, printerId: seed.gatewayRealId, isReprint: true,
    });

    const results = await Promise.all([
      svc.printJobs.resolveAckUnknown(jobId, seed.userId, 'CONFIRM_PRINTED', 'a').catch((e) => e),
      svc.printJobs.resolveAckUnknown(jobId, seed.userId, 'CONFIRM_PRINTED', 'b').catch((e) => e),
    ]);
    expect(results.filter((r) => !(r instanceof Error))).toHaveLength(1);
    const pkg = await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-RES' } });
    expect(pkg.reprintCount).toBe(2);
    expect((await prisma.printJob.findUniqueOrThrow({ where: { id: jobId } })).status).toBe(
      PrintJobStatus.RESOLVED_PRINTED,
    );
  });

  it('REQUEUE พร้อมกันสองครั้ง → สร้างงานใหม่แค่งานเดียว (CAS + requeuedFromJobId @unique)', async () => {
    await makePackage(prisma, seed, { id: 'PKG-RQ' });
    const jobId = await makeJob(prisma, seed, 'PKG-RQ', {
      status: PrintJobStatus.ACK_UNKNOWN, printerId: seed.gatewayRealId,
    });

    const results = await Promise.all([
      svc.printJobs.resolveAckUnknown(jobId, seed.userId, 'REQUEUE', 'a').catch((e) => e),
      svc.printJobs.resolveAckUnknown(jobId, seed.userId, 'REQUEUE', 'b').catch((e) => e),
    ]);
    expect(results.filter((r) => !(r instanceof Error))).toHaveLength(1);
    // มีงานใหม่ที่ลิงก์กลับ job เดิมแค่ 1 งาน
    const requeued = await prisma.printJob.findMany({ where: { requeuedFromJobId: jobId } });
    expect(requeued).toHaveLength(1);
    expect((await prisma.printJob.findUniqueOrThrow({ where: { id: jobId } })).status).toBe(
      PrintJobStatus.RESOLVED_REQUEUED,
    );
  });

  it('REQUEUE ซ้ำแบบเรียงลำดับ → ครั้งที่สองถูกปฏิเสธ ไม่มีงานใหม่เพิ่ม', async () => {
    await makePackage(prisma, seed, { id: 'PKG-RQ2' });
    const jobId = await makeJob(prisma, seed, 'PKG-RQ2', {
      status: PrintJobStatus.ACK_UNKNOWN, printerId: seed.gatewayRealId,
    });
    await svc.printJobs.resolveAckUnknown(jobId, seed.userId, 'REQUEUE', 'first');
    await expect(
      svc.printJobs.resolveAckUnknown(jobId, seed.userId, 'REQUEUE', 'second'),
    ).rejects.toBeTruthy();
    expect(await prisma.printJob.count({ where: { requeuedFromJobId: jobId } })).toBe(1);
  });

  it('CONSOLE gateway (แม้ persist canConfirmRealPrint=true) → ACK ได้แค่ SIMULATED ไม่แตะ Package (FIX-05 re-check)', async () => {
    // สร้าง gateway ที่ค่าไม่สอดคล้องโดยตรง (bypass validation) เพื่อพิสูจน์ว่า ACK re-check กันได้
    const consoleGw = await prisma.printerDevice.create({
      data: {
        name: 'console-bad', keyId: 'intkeycon', apiKeyHash: 'x',
        environment: 'DEVELOPMENT', transportMode: 'CONSOLE', canConfirmRealPrint: true,
      },
    });
    await makePackage(prisma, seed, { id: 'PKG-CON', printedAt: null, reprintCount: 0 });
    const jobId = await makeJob(prisma, seed, 'PKG-CON', { status: PrintJobStatus.SENT, printerId: consoleGw.id });

    const res = await svc.printJobs.ack(jobId, consoleGw.id);
    expect(res.status).toBe(PrintJobStatus.SIMULATED);
    const pkg = await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-CON' } });
    expect(pkg.printedAt).toBeNull();
    expect(pkg.reprintCount).toBe(0);
  });

  it('lease recovery แปลง PRINTING ที่ค้าง → ACK_UNKNOWN (ไม่ auto-retry)', async () => {
    await makePackage(prisma, seed, { id: 'PKG-LEASE' });
    const jobId = await makeJob(prisma, seed, 'PKG-LEASE', {
      status: PrintJobStatus.PRINTING, printerId: seed.gatewayRealId,
    });
    // ทำให้ printingAt เก่าเกิน lease timeout (10 นาที)
    await prisma.printJob.update({
      where: { id: jobId },
      data: { printingAt: new Date(Date.now() - 11 * 60_000) },
    });
    await svc.printJobs.recoverStaleLeases();
    expect((await prisma.printJob.findUniqueOrThrow({ where: { id: jobId } })).status).toBe(
      PrintJobStatus.ACK_UNKNOWN,
    );
  });
});
