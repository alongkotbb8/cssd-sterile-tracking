import { PrismaClient } from '@prisma/client';
import { ReportsService } from '../../src/modules/reports/reports.service';
import { AuditService } from '../../src/common/audit/audit.service';
import { makeClient, services, seedBase, truncateTx, makePackage, makeBatch, SeedIds } from './harness';

/**
 * S1 — Batch workflow (early-release + late-BI), Reprocess, Cleanup กับ Postgres จริง
 * ครอบตามที่บรีฟเน้น: Batch, Recall, Reprocess, Cleanup + PackageBatchAttempt history
 */
describe('[integration] Batch workflow / recall / reprocess / cleanup', () => {
  let prisma: PrismaClient;
  let svc: ReturnType<typeof services>;
  let seed: SeedIds;
  let reports: ReportsService;

  beforeAll(async () => {
    prisma = makeClient();
    await prisma.$connect();
    svc = services(prisma);
    reports = new ReportsService(prisma as any, new AuditService(prisma as any));
    seed = await seedBase(prisma);
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await truncateTx(prisma);
  });

  const tx = <T>(fn: (t: any) => Promise<T>) => prisma.$transaction(fn);

  // ผูกห่อ n ใบเข้ารอบใหม่ แล้วคืน [batchId, packageIds]
  async function bindPackages(round: number, ids: string[]): Promise<string> {
    const batchId = await makeBatch(prisma, seed, round);
    for (const id of ids) await makePackage(prisma, seed, { id });
    await tx((t) => svc.scan.scanIn(ids, batchId, seed.userId, false, t));
    return batchId;
  }

  it('scanIn → บันทึก PackageBatchAttempt (PENDING) เก็บประวัติ', async () => {
    const batchId = await bindPackages(1, ['PKG-A1']);
    const attempts = await prisma.packageBatchAttempt.findMany({ where: { batchId } });
    expect(attempts).toHaveLength(1);
    expect(attempts[0].result).toBe('PENDING');
    expect(attempts[0].packageId).toBe('PKG-A1');
  });

  it('CI ผ่าน ไม่มี BI → PENDING_BI + ห่อ STERILE (early release) + Movement IN', async () => {
    const batchId = await bindPackages(1, ['PKG-B1', 'PKG-B2']);
    await tx((t) => svc.batches.recordResult(batchId, true, null, seed.userId, t));

    const batch = await prisma.sterilizationBatch.findUniqueOrThrow({ where: { id: batchId } });
    expect(batch.status).toBe('PENDING_BI');
    const pkgs = await prisma.package.findMany({ where: { batchId } });
    expect(pkgs.every((p) => p.status === 'STERILE')).toBe(true);
    expect(pkgs.every((p) => p.expiryDate != null)).toBe(true);
    expect(await prisma.movement.count({ where: { type: 'IN' } })).toBe(2);
    // attempts ยัง PENDING (รอ BI)
    const attempts = await prisma.packageBatchAttempt.findMany({ where: { batchId } });
    expect(attempts.every((a) => a.result === 'PENDING')).toBe(true);
  });

  it('BI ตามมาผ่าน → PASSED (ห่อยัง STERILE) + attempts PASSED', async () => {
    const batchId = await bindPackages(1, ['PKG-C1']);
    await tx((t) => svc.batches.recordResult(batchId, true, null, seed.userId, t));
    await tx((t) => svc.batches.recordBiResult(batchId, true, seed.userId, t));

    expect((await prisma.sterilizationBatch.findUniqueOrThrow({ where: { id: batchId } })).status).toBe('PASSED');
    expect((await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-C1' } })).status).toBe('STERILE');
    const att = await prisma.packageBatchAttempt.findFirstOrThrow({ where: { batchId } });
    expect(att.result).toBe('PASSED');
  });

  it('BI ตามมาไม่ผ่าน → FAILED + recall ห่อที่ปล่อยไปแล้ว (STERILE→RETURNED) + attempts RECALLED', async () => {
    const batchId = await bindPackages(1, ['PKG-D1']);
    await tx((t) => svc.batches.recordResult(batchId, true, null, seed.userId, t)); // early release → STERILE
    await tx((t) => svc.batches.recordBiResult(batchId, false, seed.userId, t)); // BI fail → recall

    expect((await prisma.sterilizationBatch.findUniqueOrThrow({ where: { id: batchId } })).status).toBe('FAILED');
    expect((await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-D1' } })).status).toBe('RETURNED');
    const att = await prisma.packageBatchAttempt.findFirstOrThrow({ where: { batchId } });
    expect(att.result).toBe('RECALLED');
  });

  it('CI ไม่ผ่าน → FAILED, ห่อคง PACKED + batchId ถูกปลด (แต่ประวัติ attempt=FAILED ยังอยู่)', async () => {
    const batchId = await bindPackages(1, ['PKG-E1']);
    await tx((t) => svc.batches.recordResult(batchId, false, null, seed.userId, t));

    expect((await prisma.sterilizationBatch.findUniqueOrThrow({ where: { id: batchId } })).status).toBe('FAILED');
    const pkg = await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-E1' } });
    expect(pkg.status).toBe('PACKED');
    expect(pkg.batchId).toBeNull(); // ปลดรอบปัจจุบัน (เข้ารอบใหม่ได้)
    const att = await prisma.packageBatchAttempt.findFirstOrThrow({ where: { batchId } });
    expect(att.result).toBe('FAILED'); // ประวัติเก็บถาวร
  });

  it('บันทึกผล CI ซ้ำ → reject (บันทึกได้ครั้งเดียว)', async () => {
    const batchId = await bindPackages(1, ['PKG-F1']);
    await tx((t) => svc.batches.recordResult(batchId, true, null, seed.userId, t));
    await expect(
      tx((t) => svc.batches.recordResult(batchId, true, null, seed.userId, t)),
    ).rejects.toBeTruthy();
  });

  it('Reprocess: RETURNED → PACKED + ปลด batchId → เข้ารอบใหม่ได้ (ประวัติเดิมคงอยู่)', async () => {
    // รอบ 1 fail (BI) → PKG-G1 กลายเป็น RETURNED, มี attempt RECALLED
    const batch1 = await bindPackages(1, ['PKG-G1']);
    await tx((t) => svc.batches.recordResult(batch1, true, null, seed.userId, t));
    await tx((t) => svc.batches.recordBiResult(batch1, false, seed.userId, t));
    expect((await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-G1' } })).status).toBe('RETURNED');

    // reprocess → PACKED + batchId null
    await tx((t) => svc.scan.scanReprocess(['PKG-G1'], seed.userId, false, t));
    const reproc = await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-G1' } });
    expect(reproc.status).toBe('PACKED');
    expect(reproc.batchId).toBeNull();

    // เข้ารอบใหม่ได้ (batch 2) — ประวัติ attempt มี 2 แถว (รอบเก่า + รอบใหม่)
    const batch2 = await makeBatch(prisma, seed, 2);
    const res = await tx((t) => svc.scan.scanIn(['PKG-G1'], batch2, seed.userId, false, t));
    expect(res[0].success).toBe(true);
    expect(await prisma.packageBatchAttempt.count({ where: { packageId: 'PKG-G1' } })).toBe(2);
  });

  it('Reprocess ปฏิเสธห่อที่ไม่ใช่ RETURNED', async () => {
    await makePackage(prisma, seed, { id: 'PKG-H1' }); // PACKED
    const res = await tx((t) => svc.scan.scanReprocess(['PKG-H1'], seed.userId, false, t));
    expect(res[0].success).toBe(false);
  });

  it('PACKED_OUT: ส่งห่อ PACKED (ยังไม่ฆ่าเชื้อ) ออกได้เฉพาะปลายทาง external (2.1)', async () => {
    const internal = await prisma.department.create({ data: { code: 'WARD1', name: 'วอร์ด 1', type: 'internal' } });
    const external = await prisma.department.create({ data: { code: 'EXT1', name: 'รพ.อื่น', type: 'external' } });
    await makePackage(prisma, seed, { id: 'PKG-PO1' }); // PACKED
    await makePackage(prisma, seed, { id: 'PKG-PO2' }); // PACKED

    // internal → บล็อก
    const blocked = await tx((t) => svc.scan.scanOut(['PKG-PO1'], internal.id, undefined, seed.userId, false, t));
    expect(blocked[0].success).toBe(false);
    expect((await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-PO1' } })).status).toBe('PACKED');

    // external → PACKED_OUT ได้
    const ok = await tx((t) => svc.scan.scanOut(['PKG-PO2'], external.id, undefined, seed.userId, false, t));
    expect(ok[0].success).toBe(true);
    expect((await prisma.package.findUniqueOrThrow({ where: { id: 'PKG-PO2' } })).status).toBe('PACKED_OUT');
  });

  it('Cleanup ไม่ลบ Movement history (traceability คงอยู่)', async () => {
    await makePackage(prisma, seed, { id: 'PKG-CL1' });
    await prisma.movement.create({
      data: {
        packageId: 'PKG-CL1',
        type: 'IN',
        performedById: seed.userId,
        createdAt: new Date('2020-01-01T00:00:00.000Z'), // เก่ามาก
      },
    });
    const before = await prisma.movement.count();
    const result = await reports.cleanup('2021-01-01', seed.userId);
    expect(result.deletedMovements).toBe(0);
    expect(result.eligibleMovements).toBeGreaterThanOrEqual(1);
    expect(await prisma.movement.count()).toBe(before); // ไม่ถูกลบ
  });
});
