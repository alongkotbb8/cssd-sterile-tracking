import { PrismaClient } from '@prisma/client';
import { makeClient, services, seedBase, truncateTx, makePackage, SeedIds } from './harness';

/**
 * [integration] Packages bulk-delete + search บน PostgreSQL จริง — พิสูจน์สิ่งที่
 * fake-prisma พิสูจน์ไม่ได้: การลบจริงหายจาก DB, ห่อที่มีประวัติ (movement) ถูก
 * ปฏิเสธและแถวยังอยู่ครบ, และ search (id/ชื่อชุด/อุปกรณ์/คลัง) คืน match จริงผ่าน
 * where OR + relation filter + `mode: insensitive` ของ Postgres
 */
describe('[integration] Packages bulk-delete + search กับ Postgres จริง', () => {
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

  const runBulkDelete = (packageIds: string[], key: string) =>
    svc.idem.run(
      key,
      seed.userId,
      'packages/bulk-delete',
      'POST',
      { packageIds },
      (tx) => svc.packages.bulkDelete(packageIds, seed.userId, tx),
      { required: true },
    );

  it('PACKED ไม่มีประวัติ → ลบสำเร็จ + หายจาก DB + audit PACKAGE_DELETE', async () => {
    await makePackage(prisma, seed, { id: 'DEL-20260724-0001' });

    const res = await runBulkDelete(['DEL-20260724-0001'], 'bd-key-1');
    expect(res).toEqual([{ packageId: 'DEL-20260724-0001', success: true }]);

    expect(await prisma.package.findUnique({ where: { id: 'DEL-20260724-0001' } })).toBeNull();
    const audit = await prisma.auditLog.findFirst({
      where: { action: 'PACKAGE_DELETE', targetId: 'DEL-20260724-0001' },
    });
    expect(audit).not.toBeNull();
    expect(audit!.metadata).toMatchObject({ setTemplateId: seed.setTemplateId, wrapType: 'SEAL' });
  });

  it('ห่อที่มี movement → ถูกปฏิเสธ PKG_HAS_HISTORY และแถวยังอยู่ครบ', async () => {
    await makePackage(prisma, seed, { id: 'HIS-20260724-0001' });
    await prisma.movement.create({
      data: { packageId: 'HIS-20260724-0001', type: 'IN', performedById: seed.userId },
    });

    const res = await runBulkDelete(['HIS-20260724-0001'], 'bd-key-2');
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_HAS_HISTORY' });
    // ห่อยังอยู่ + movement ยังอยู่ (traceability คงเดิม)
    expect(await prisma.package.findUnique({ where: { id: 'HIS-20260724-0001' } })).not.toBeNull();
    expect(await prisma.movement.count({ where: { packageId: 'HIS-20260724-0001' } })).toBe(1);
    // ไม่มี audit PACKAGE_DELETE ของห่อนี้
    expect(
      await prisma.auditLog.count({ where: { action: 'PACKAGE_DELETE', targetId: 'HIS-20260724-0001' } }),
    ).toBe(0);
  });

  it('non-PACKED (STERILE) → ปฏิเสธ PKG_WRONG_STATUS, ห่อยังอยู่', async () => {
    await makePackage(prisma, seed, { id: 'STE-20260724-0001' });
    await prisma.package.update({ where: { id: 'STE-20260724-0001' }, data: { status: 'STERILE' } });

    const res = await runBulkDelete(['STE-20260724-0001'], 'bd-key-3');
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_WRONG_STATUS' });
    expect(await prisma.package.findUnique({ where: { id: 'STE-20260724-0001' } })).not.toBeNull();
  });

  it('mixed batch: clean ลบได้, มีประวัติถูกกัน — ผลลัพธ์แยกทีละรายการ', async () => {
    await makePackage(prisma, seed, { id: 'MIX-20260724-0001' }); // clean
    await makePackage(prisma, seed, { id: 'MIX-20260724-0002' }); // has movement
    await prisma.movement.create({
      data: { packageId: 'MIX-20260724-0002', type: 'IN', performedById: seed.userId },
    });

    const res = await runBulkDelete(['MIX-20260724-0001', 'MIX-20260724-0002'], 'bd-key-4');
    expect(res).toEqual([
      { packageId: 'MIX-20260724-0001', success: true },
      { packageId: 'MIX-20260724-0002', success: false, error: expect.any(String), errorCode: 'PKG_HAS_HISTORY' },
    ]);
    expect(await prisma.package.findUnique({ where: { id: 'MIX-20260724-0001' } })).toBeNull();
    expect(await prisma.package.findUnique({ where: { id: 'MIX-20260724-0002' } })).not.toBeNull();
  });

  describe('search', () => {
    let deptId: string;

    beforeEach(async () => {
      // seedBase/truncateTx ไม่แตะ departments → สร้าง/หาแบบ upsert กัน unique ชน
      const dept = await prisma.department.upsert({
        where: { code: 'LR' },
        update: {},
        create: { code: 'LR', name: 'ห้องคลอด', type: 'internal' },
      });
      deptId = dept.id;
      // template seedBase = { code:'INT', name:'ชุดทดสอบ', itemList:['a','b'] }
      await makePackage(prisma, seed, { id: 'SRCH-20260724-0001' });
      await makePackage(prisma, seed, { id: 'OTHER-20260724-0002' });
      // ห่อ SRCH เคยถูกเบิกไปห้องคลอด → match ตามคลัง
      await prisma.movement.create({
        data: { packageId: 'SRCH-20260724-0001', type: 'OUT', departmentId: deptId, performedById: seed.userId },
      });
    });

    const ids = async (q: string) =>
      (await svc.packages.findAll(undefined, undefined, undefined, q)).map((p: any) => p.id).sort();

    it('match id ห่อ (บางส่วน, case-insensitive)', async () => {
      expect(await ids('srch-2026')).toEqual(['SRCH-20260724-0001']);
    });

    it('match ชื่อชุด (setTemplate.name)', async () => {
      expect((await ids('ทดสอบ')).sort()).toEqual(['OTHER-20260724-0002', 'SRCH-20260724-0001']);
    });

    it('match อุปกรณ์ในชุด (itemList element)', async () => {
      // itemList ของ template = ['a','b'] → ค้น 'a' ต้องเจอทั้งสองห่อ
      expect((await ids('a')).length).toBeGreaterThanOrEqual(2);
    });

    it('match คลังปัจจุบัน (ชื่อแผนกของ movement) → เฉพาะห่อที่เคยไปห้องคลอด', async () => {
      expect(await ids('คลอด')).toEqual(['SRCH-20260724-0001']);
    });

    it('search ที่ไม่ match อะไรเลย → []', async () => {
      expect(await ids('ไม่มีทางเจอ-zzz')).toEqual([]);
    });

    it('search ว่าง → คืนทุกห่อ (พฤติกรรมเดิม)', async () => {
      expect((await ids('')).length).toBe(2);
    });
  });
});
