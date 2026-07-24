import { PrismaClient } from '@prisma/client';
import { makeClient, services, seedBase, truncateTx, makePackage, SeedIds } from './harness';

/**
 * [integration] Browser Print บน PostgreSQL จริง — พิสูจน์สิ่งที่ fake-prisma unit test
 * พิสูจน์ไม่ได้: (P1) การตัดสิน reprint ต้อง atomic ต่อ 1 ห่อ เมื่อสองคำขอ (idempotency
 * key คนละค่า) ยิงพร้อมกันจริง; (P0) reprocess (RETURNED→PACKED) ล้างวันที่รอบเก่าจริง
 * และ label ที่ backend สร้างต้องไม่มีวันที่หลัง reprocess
 */
describe('[integration] Browser Print — atomic reprint (P1) + reprocess date clearing (P0)', () => {
  let prisma: PrismaClient;
  let seed: SeedIds;
  let svc: ReturnType<typeof services>;
  const prevFlag = process.env.CSSD_BROWSER_PRINT_ENABLED;

  beforeAll(async () => {
    process.env.CSSD_BROWSER_PRINT_ENABLED = 'true';
    prisma = makeClient();
    await prisma.$connect();
    seed = await seedBase(prisma);
    svc = services(prisma);
  });

  afterAll(async () => {
    await prisma.$disconnect();
    if (prevFlag === undefined) delete process.env.CSSD_BROWSER_PRINT_ENABLED;
    else process.env.CSSD_BROWSER_PRINT_ENABLED = prevFlag;
  });

  beforeEach(async () => {
    await truncateTx(prisma);
  });

  const createDto = (packageId: string) => ({
    packageId,
    copies: 1,
    createdFrom: 'PACKAGE_DETAIL' as const,
  });

  const runCreate = (packageId: string, key: string, reprintReason?: string) =>
    svc.idem.run(
      key,
      seed.userId,
      'browser-print/create',
      'POST',
      { ...createDto(packageId), reprintReason },
      (tx) =>
        svc.browserPrint.create(
          { ...createDto(packageId), reprintReason } as any,
          seed.userId,
          'UA',
          key,
          tx,
        ),
      { required: true },
    );

  it('P1: สองคำขอ (key คนละค่า) ยิงพร้อมกัน → 1 เป็น isReprint=false, อีกอันถูกบังคับ reprint (atomic)', async () => {
    const pkgId = 'INT-20260724-0001';
    await makePackage(prisma, seed, { id: pkgId }); // PACKED, ยังไม่เคยพิมพ์

    // ยิงพร้อมกันจริงด้วย key คนละค่า — advisory lock ต้อง serialize การตัดสิน
    const results = await Promise.allSettled([
      runCreate(pkgId, 'key-A'),
      runCreate(pkgId, 'key-B'),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled') as PromiseFulfilledResult<any>[];
    const rejected = results.filter((r) => r.status === 'rejected') as PromiseRejectedResult[];

    // ต้องมีคำขอแรกสำเร็จ (isReprint=false) และคำขอที่สองถูกบังคับให้เป็น reprint
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect(fulfilled[0].value.isReprint).toBe(false);
    expect(rejected[0].reason?.response?.code).toBe('BROWSER_PRINT_REPRINT_REASON_REQUIRED');

    // มีแถวเดียวใน DB (ไม่เกิด isReprint=false ซ้อนสองแถวจาก TOCTOU)
    const rows = await prisma.browserPrintRequest.findMany({ where: { packageId: pkgId } });
    expect(rows).toHaveLength(1);
    expect(rows[0].isReprint).toBe(false);
  });

  it('P1: คำขอที่สอง (ตามลำดับ) ระบุเหตุผล → isReprint=true; ทั้งคู่ commit', async () => {
    const pkgId = 'INT-20260724-0002';
    await makePackage(prisma, seed, { id: pkgId });

    const first = await runCreate(pkgId, 'seq-A');
    expect(first.isReprint).toBe(false);

    const second = await runCreate(pkgId, 'seq-B', 'พิมพ์ซ้ำเพราะ label เดิมชำรุด');
    expect(second.isReprint).toBe(true);
    expect(second.reprintReason).toContain('label เดิมชำรุด');

    const rows = await prisma.browserPrintRequest.findMany({ where: { packageId: pkgId } });
    expect(rows).toHaveLength(2);
    expect(rows.filter((r) => r.isReprint).length).toBe(1);
  });

  it('P0: reprocess (RETURNED→PACKED) ล้าง sterilizeDate/expiryDate + label หลัง reprocess ไม่มีวันที่', async () => {
    const pkgId = 'INT-20260724-0003';
    // ห่อสถานะ RETURNED ที่ยังมีวันที่รอบเก่าค้างอยู่ (สถานการณ์จริงหลังหมุนเวียน)
    await prisma.package.create({
      data: {
        id: pkgId,
        setTemplateId: seed.setTemplateId,
        wrapType: 'SEAL',
        status: 'RETURNED',
        createdById: seed.userId,
        sterilizeDate: new Date('2026-01-01T00:00:00Z'),
        expiryDate: new Date('2026-06-30T00:00:00Z'),
      },
    });

    // reprocess → PACKED + ล้างวันที่จริงใน DB
    const res = await prisma.$transaction((tx) =>
      svc.scan.scanReprocess([pkgId], seed.userId, false, tx),
    );
    expect(res[0].success).toBe(true);

    const after = await prisma.package.findUnique({ where: { id: pkgId } });
    expect(after!.status).toBe('PACKED');
    expect(after!.sterilizeDate).toBeNull();
    expect(after!.expiryDate).toBeNull();

    // label หลัง reprocess ก็ไม่มีวันที่
    const bp = await prisma.$transaction((tx) =>
      svc.browserPrint.create(createDto(pkgId) as any, seed.userId, 'UA', 'p0-after', tx),
    );
    expect(bp.label.isSterilized).toBe(false);
    expect(bp.label.sterilizeDate).toBeNull();
    expect(bp.label.expiryDate).toBeNull();
  });

  it('P0: ห่อ STERILE ที่มีวันที่ครบ → label แสดงวันที่ (ยืนยันว่า gate ไม่ over-block)', async () => {
    const pkgId = 'INT-20260724-0004';
    const sterilizeDate = new Date('2026-07-01T00:00:00Z');
    const expiryDate = new Date('2026-12-28T00:00:00Z');
    await prisma.package.create({
      data: {
        id: pkgId,
        setTemplateId: seed.setTemplateId,
        wrapType: 'SEAL',
        status: 'STERILE',
        createdById: seed.userId,
        sterilizeDate,
        expiryDate,
      },
    });
    const bp = await prisma.$transaction((tx) =>
      svc.browserPrint.create(createDto(pkgId) as any, seed.userId, 'UA', 'p0-sterile', tx),
    );
    expect(bp.label.isSterilized).toBe(true);
    expect(bp.label.sterilizeDate).toEqual(sterilizeDate);
    expect(bp.label.expiryDate).toEqual(expiryDate);
  });
});
