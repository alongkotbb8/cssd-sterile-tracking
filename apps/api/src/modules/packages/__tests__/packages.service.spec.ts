import { BadRequestException } from '@nestjs/common';
import { PackageStatus } from '@prisma/client';
import { AuditService } from '../../../common/audit/audit.service';
import { PackagesService } from '../packages.service';

/**
 * Fake Prisma แบบ stateful (idiom เดียวกับ print-jobs/browser-print spec) — bulkDelete
 * ทำงานบน in-memory map จริง (count/delete/deleteMany) + findAll(search) เก็บ where
 * ที่ส่งเข้า package.findMany มาตรวจโครงสร้าง OR ที่ buildSearchWhere คำนวณ
 */
function makeDb(opts: {
  packages?: any[];
  templates?: any[];
  departments?: any[];
  movements?: any[];
  printJobs?: any[];
  browserPrints?: any[];
  batchAttempts?: any[];
} = {}) {
  const packages = new Map((opts.packages ?? []).map((p) => [p.id, { ...p }]));
  const templates = (opts.templates ?? []).map((t) => ({ ...t }));
  const departments = (opts.departments ?? []).map((d) => ({ ...d }));
  const movements = (opts.movements ?? []).map((m) => ({ ...m }));
  const printJobs = (opts.printJobs ?? []).map((j) => ({ ...j }));
  const browserPrints = (opts.browserPrints ?? []).map((b) => ({ ...b }));
  const batchAttempts = (opts.batchAttempts ?? []).map((a) => ({ ...a }));
  const audit: any[] = [];
  const findAllCalls: any[] = [];
  const containsCI = (hay: string, sub: any) =>
    typeof sub?.contains === 'string' && hay.toLowerCase().includes(sub.contains.toLowerCase());

  const pkg = {
    findUnique: async ({ where: { id } }: any) => (packages.has(id) ? { ...packages.get(id) } : null),
    findMany: async (args: any) => {
      findAllCalls.push(args);
      // พอสำหรับ assertion ของ findAll — คืนทุกห่อ (จริง ๆ WHERE ทดสอบผ่านโครงสร้าง args)
      return [...packages.values()].map((p) => ({ ...p, movements: [], setTemplate: {}, tags: [], batch: null }));
    },
    delete: async ({ where: { id } }: any) => {
      const row = packages.get(id);
      packages.delete(id);
      return row;
    },
  };

  const tx = {
    package: pkg,
    packageTag: { deleteMany: async () => ({ count: 0 }) },
    movement: { count: async ({ where: { packageId } }: any) => movements.filter((m) => m.packageId === packageId).length },
    printJob: { count: async ({ where: { packageId } }: any) => printJobs.filter((j) => j.packageId === packageId).length },
    browserPrintRequest: { count: async ({ where: { packageId } }: any) => browserPrints.filter((b) => b.packageId === packageId).length },
    packageBatchAttempt: { count: async ({ where: { packageId } }: any) => batchAttempts.filter((a) => a.packageId === packageId).length },
    auditLog: { create: async ({ data }: any) => { audit.push(data); return data; } },
  };

  return {
    package: pkg,
    setTemplate: {
      findMany: async ({ where, select }: any) => {
        if (select?.itemList) return templates.map((t) => ({ id: t.id, itemList: t.itemList }));
        // name contains filter
        const q = where?.name;
        return templates.filter((t) => containsCI(t.name, q)).map((t) => ({ id: t.id }));
      },
    },
    department: {
      findMany: async ({ where }: any) => {
        const or = where?.OR ?? [];
        return departments
          .filter((d) => or.some((c: any) => (c.name && containsCI(d.name, c.name)) || (c.code && containsCI(d.code, c.code))))
          .map((d) => ({ id: d.id }));
      },
    },
    $transaction: async (cb: any) => cb(tx),
    _packages: packages,
    _audit: audit,
    _findAllCalls: findAllCalls,
  };
}

function makeSvc(db: ReturnType<typeof makeDb>) {
  return new PackagesService(db as any, {} as any, new AuditService(db as any));
}

const pkgRow = (o: any = {}) => ({
  id: 'DELIV-20260101-0001',
  setTemplateId: 'tpl-1',
  wrapType: 'SEAL',
  status: PackageStatus.PACKED,
  batchId: null,
  printedAt: null,
  reprintCount: 0,
  createdById: 'user-1',
  ...o,
});

describe('PackagesService.bulkDelete', () => {
  it('happy: PACKED ไม่มีประวัติ → ลบสำเร็จ + audit PACKAGE_DELETE ก่อนลบ', async () => {
    const db = makeDb({ packages: [pkgRow()] });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res).toEqual([{ packageId: 'DELIV-20260101-0001', success: true }]);
    expect(db._packages.has('DELIV-20260101-0001')).toBe(false); // ถูกลบจริง
    expect(db._audit).toEqual([
      {
        userId: 'user-1',
        action: 'PACKAGE_DELETE',
        targetId: 'DELIV-20260101-0001',
        metadata: { setTemplateId: 'tpl-1', wrapType: 'SEAL', createdById: 'user-1' },
      },
    ]);
  });

  it('non-PACKED → PKG_WRONG_STATUS (ไม่ลบ)', async () => {
    const db = makeDb({ packages: [pkgRow({ status: PackageStatus.STERILE })] });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_WRONG_STATUS' });
    expect(db._packages.has('DELIV-20260101-0001')).toBe(true);
    expect(db._audit).toEqual([]);
  });

  it('ไม่พบห่อ → PKG_NOT_FOUND', async () => {
    const db = makeDb({ packages: [] });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_NOT_FOUND' });
  });

  it('มี movement → PKG_HAS_HISTORY (ไม่ลบ)', async () => {
    const db = makeDb({
      packages: [pkgRow()],
      movements: [{ packageId: 'DELIV-20260101-0001' }],
    });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_HAS_HISTORY' });
    expect(db._packages.has('DELIV-20260101-0001')).toBe(true);
    expect(db._audit).toEqual([]);
  });

  it('printedAt != null → PKG_HAS_HISTORY', async () => {
    const db = makeDb({ packages: [pkgRow({ printedAt: new Date('2026-01-02') })] });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_HAS_HISTORY' });
  });

  it('batchId != null → PKG_HAS_HISTORY', async () => {
    const db = makeDb({ packages: [pkgRow({ batchId: 'batch-1' })] });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_HAS_HISTORY' });
  });

  it('reprintCount != 0 → PKG_HAS_HISTORY', async () => {
    const db = makeDb({ packages: [pkgRow({ reprintCount: 1 })] });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_HAS_HISTORY' });
  });

  it('มี print job → PKG_HAS_HISTORY', async () => {
    const db = makeDb({
      packages: [pkgRow()],
      printJobs: [{ packageId: 'DELIV-20260101-0001' }],
    });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.bulkDelete(['DELIV-20260101-0001'], 'user-1', tx));
    expect(res[0]).toMatchObject({ success: false, errorCode: 'PKG_HAS_HISTORY' });
  });

  it('มี browser print / batch attempt → PKG_HAS_HISTORY', async () => {
    const db = makeDb({
      packages: [pkgRow({ id: 'A-20260101-0001' }), pkgRow({ id: 'B-20260101-0001' })],
      browserPrints: [{ packageId: 'A-20260101-0001' }],
      batchAttempts: [{ packageId: 'B-20260101-0001' }],
    });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) =>
      svc.bulkDelete(['A-20260101-0001', 'B-20260101-0001'], 'user-1', tx),
    );
    expect(res.map((r: any) => r.errorCode)).toEqual(['PKG_HAS_HISTORY', 'PKG_HAS_HISTORY']);
  });

  it('id ผิดรูปแบบ → 400 PKG_ID_INVALID (reuse assertValidPackageId)', async () => {
    const db = makeDb({ packages: [] });
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.bulkDelete(['bad id!<script>'], 'user-1', tx)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('mixed: หลายห่อ — สำเร็จ/ปฏิเสธ แยกทีละรายการ (mirror ScanResult)', async () => {
    const db = makeDb({
      packages: [
        pkgRow({ id: 'A-20260101-0001' }), // clean → ลบได้
        pkgRow({ id: 'B-20260101-0001', status: PackageStatus.STERILE }), // wrong status
        pkgRow({ id: 'C-20260101-0001' }), // has movement
      ],
      movements: [{ packageId: 'C-20260101-0001' }],
    });
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) =>
      svc.bulkDelete(['A-20260101-0001', 'B-20260101-0001', 'C-20260101-0001'], 'user-1', tx),
    );
    expect(res).toEqual([
      { packageId: 'A-20260101-0001', success: true },
      { packageId: 'B-20260101-0001', success: false, error: expect.any(String), errorCode: 'PKG_WRONG_STATUS' },
      { packageId: 'C-20260101-0001', success: false, error: expect.any(String), errorCode: 'PKG_HAS_HISTORY' },
    ]);
    expect(db._packages.has('A-20260101-0001')).toBe(false);
    expect(db._packages.has('B-20260101-0001')).toBe(true);
    expect(db._packages.has('C-20260101-0001')).toBe(true);
  });
});

describe('PackagesService.findAll search', () => {
  const templates = [
    { id: 'tpl-1', name: 'ชุดทำแผล', itemList: ['กรรไกร', 'คีมจับ'] },
    { id: 'tpl-2', name: 'ชุดทำคลอด', itemList: ['ผ้าซับ'] },
  ];
  const departments = [
    { id: 'dept-1', name: 'ห้องคลอด', code: 'LR' },
    { id: 'dept-2', name: 'ห้องผ่าตัด', code: 'OR' },
  ];

  const whereOf = async (db: ReturnType<typeof makeDb>, q?: string) => {
    const svc = makeSvc(db);
    await svc.findAll(undefined, undefined, undefined, q);
    return db._findAllCalls[0].where as any;
  };

  it('search ว่าง/ไม่ส่ง → ไม่มี OR (พฤติกรรมเดิม)', async () => {
    const db = makeDb({ packages: [pkgRow()], templates, departments });
    expect((await whereOf(db, undefined)).OR).toBeUndefined();
    const db2 = makeDb({ packages: [pkgRow()], templates, departments });
    expect((await whereOf(db2, '   ')).OR).toBeUndefined();
  });

  it('match ชื่อชุด → matchedTemplateIds มี tpl ที่ชื่อ contains', async () => {
    const db = makeDb({ packages: [pkgRow()], templates, departments });
    const where = await whereOf(db, 'ทำแผล');
    const tplClause = where.OR.find((c: any) => 'setTemplateId' in c);
    expect(tplClause.setTemplateId.in).toContain('tpl-1');
    expect(tplClause.setTemplateId.in).not.toContain('tpl-2');
  });

  it('match อุปกรณ์ในชุด (itemList) → matchedTemplateIds มี tpl ที่มี item นั้น', async () => {
    const db = makeDb({ packages: [pkgRow()], templates, departments });
    const where = await whereOf(db, 'กรรไกร');
    const tplClause = where.OR.find((c: any) => 'setTemplateId' in c);
    expect(tplClause.setTemplateId.in).toEqual(['tpl-1']);
  });

  it('match id ห่อ → OR มี clause id contains (case-insensitive)', async () => {
    const db = makeDb({ packages: [pkgRow()], templates, departments });
    const where = await whereOf(db, 'deliv');
    const idClause = where.OR.find((c: any) => 'id' in c);
    expect(idClause.id).toEqual({ contains: 'deliv', mode: 'insensitive' });
  });

  it('match คลัง (ชื่อ/รหัสแผนก) → movements.some.departmentId.in', async () => {
    const db = makeDb({ packages: [pkgRow()], templates, departments });
    const where = await whereOf(db, 'คลอด'); // matches tpl-2 name AND dept-1 name
    const deptClause = where.OR.find((c: any) => 'movements' in c);
    expect(deptClause.movements.some.departmentId.in).toContain('dept-1');
    const byCode = await whereOf(makeDb({ packages: [pkgRow()], templates, departments }), 'OR');
    const codeClause = byCode.OR.find((c: any) => 'movements' in c);
    expect(codeClause.movements.some.departmentId.in).toContain('dept-2');
  });

  it('status/tag filter ยังถูกส่งควบคู่กับ OR (AND โดยปริยาย)', async () => {
    const db = makeDb({ packages: [pkgRow()], templates, departments });
    const svc = makeSvc(db);
    await svc.findAll(PackageStatus.PACKED, undefined, 'tag-1', 'ทำแผล');
    const where = db._findAllCalls[0].where as any;
    expect(where.status).toBe(PackageStatus.PACKED);
    expect(where.tags).toEqual({ some: { tagId: 'tag-1' } });
    expect(Array.isArray(where.OR)).toBe(true);
  });
});
