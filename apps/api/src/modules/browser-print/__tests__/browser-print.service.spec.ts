import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { BrowserPrintStatus, Prisma, UserRole } from '@prisma/client';
import { AuditService } from '../../../common/audit/audit.service';
import { IdempotencyService } from '../../../common/idempotency/idempotency.service';
import { BrowserPrintService } from '../browser-print.service';

/**
 * MACOS_BROWSER_PRINT_DIRECTIVE.md §14 (Backend ขั้นต่ำ 17 กรณี) — แต่ละเทสกำกับ
 * "§14.x" ไว้ในชื่อ (กรณี 2 อยู่ใน browser-print.rbac.spec.ts, กรณี 6–7 อยู่ใน
 * browser-print.dto.spec.ts)
 *
 * Fake Prisma แบบ stateful เหมือน print-jobs.service.spec.ts — updateMany เป็น
 * compare-and-swap จริงบน in-memory map + idempotentRequest delegate จำลอง P2002
 * เพื่อทดสอบ IdempotencyService.run ตัวจริง (replay/conflict) กับ service นี้
 */
function matchesWhere(row: any, where: Record<string, any> = {}): boolean {
  return Object.entries(where).every(([k, v]) => {
    if (v === null) return row[k] === null || row[k] === undefined;
    if (v && typeof v === 'object') {
      if ('in' in v) return (v as any).in.includes(row[k]);
      let ok = true;
      if ('gte' in v) ok = ok && row[k] >= (v as any).gte;
      if ('lte' in v) ok = ok && row[k] <= (v as any).lte;
      if ('lt' in v) ok = ok && row[k] < (v as any).lt;
      return ok;
    }
    return row[k] === v;
  });
}

function applyData(row: any, data: Record<string, any>): void {
  for (const [k, val] of Object.entries(data)) {
    if (val && typeof val === 'object' && 'increment' in (val as any)) {
      row[k] = (row[k] ?? 0) + (val as any).increment;
    } else {
      row[k] = val;
    }
  }
}

const USERS: Record<string, { name: string }> = {
  'user-1': { name: 'สมชาย' },
  'user-2': { name: 'สมหญิง' },
  'admin-1': { name: 'แอดมิน' },
};

function makeDb(requestRows: any[] = [], packageRows: any[] = []) {
  const requests = new Map(requestRows.map((r) => [r.id, { ...r }]));
  const packages = new Map(packageRows.map((p) => [p.id, { ...p }]));
  const audit: any[] = [];
  const idem = new Map<string, any>();
  let nextId = requests.size + 1;

  const withUser = (row: any) => ({
    ...row,
    requestedBy: USERS[row.requestedByUserId] ? { name: USERS[row.requestedByUserId].name } : null,
  });

  const browserPrintRequest = {
    findUnique: async ({ where: { id }, include }: any) => {
      const r = requests.get(id);
      if (!r) return null;
      return include?.requestedBy ? withUser({ ...r }) : { ...r };
    },
    findMany: async ({ where = {}, orderBy, skip = 0, take, include }: any) => {
      let rows = [...requests.values()].filter((r) => matchesWhere(r, where));
      if (orderBy) {
        const [[k, dir]] = Object.entries(orderBy) as [string, string][];
        rows = rows
          .slice()
          .sort((a, b) => (a[k] > b[k] ? 1 : a[k] < b[k] ? -1 : 0) * (dir === 'desc' ? -1 : 1));
      }
      rows = rows.slice(skip, take !== undefined ? skip + take : undefined);
      return rows.map((r) => (include?.requestedBy ? withUser({ ...r }) : { ...r }));
    },
    count: async ({ where = {} }: any) =>
      [...requests.values()].filter((r) => matchesWhere(r, where)).length,
    updateMany: async ({ where, data }: any) => {
      const row = requests.get(where.id);
      if (!row || !matchesWhere(row, where)) return { count: 0 };
      applyData(row, data);
      row.updatedAt = new Date();
      return { count: 1 };
    },
    create: async ({ data, include }: any) => {
      const id = `bpr-${nextId++}`;
      const now = new Date();
      const row = {
        id,
        status: BrowserPrintStatus.CREATED,
        requestedAt: now,
        dialogOpenedAt: null,
        userConfirmedAt: null,
        cancelledAt: null,
        createdAt: now,
        updatedAt: now,
        ...data,
      };
      requests.set(id, row);
      return include?.requestedBy ? withUser({ ...row }) : { ...row };
    },
  };

  const pkg = {
    findUnique: async ({ where: { id } }: any) => (packages.has(id) ? { ...packages.get(id) } : null),
    // §14.17 — browser print ห้ามแตะ Package เด็ดขาด: เรียกเมื่อไหร่ = เทสพัง
    update: async () => {
      throw new Error('browser-print must NEVER update Package (printedAt/reprintCount)');
    },
    updateMany: async () => {
      throw new Error('browser-print must NEVER update Package (printedAt/reprintCount)');
    },
  };

  // §14.17 — ห้ามแตะ print job / gateway state ทุกกรณี
  const neverTouch = () => {
    throw new Error('browser-print must NEVER touch PrintJob/Gateway state');
  };
  const printJob = {
    findUnique: neverTouch, findMany: neverTouch, create: neverTouch,
    update: neverTouch, updateMany: neverTouch,
  };

  const idempotentRequest = {
    create: async ({ data }: any) => {
      if (idem.has(data.key)) {
        // จำลอง unique constraint จริงของ Postgres — ให้ IdempotencyService.run
        // ตัวจริงเข้าเส้นทาง replay/conflict
        throw new Prisma.PrismaClientKnownRequestError('Unique constraint failed on key', {
          code: 'P2002',
          clientVersion: 'test',
        } as any);
      }
      idem.set(data.key, { ...data });
      return { ...data };
    },
    update: async ({ where: { key }, data }: any) => {
      const row = idem.get(key);
      applyData(row, data);
      return { ...row };
    },
    findUnique: async ({ where: { key } }: any) => (idem.has(key) ? { ...idem.get(key) } : null),
  };

  const tx = {
    browserPrintRequest,
    package: pkg,
    printJob,
    idempotentRequest,
    auditLog: {
      create: async (args: any) => {
        audit.push(args.data);
        return args.data;
      },
    },
  };

  return {
    browserPrintRequest,
    package: pkg,
    printJob,
    idempotentRequest,
    $transaction: async (cb: any) => cb(tx),
    _requests: requests,
    _packages: packages,
    _audit: audit,
    _idem: idem,
  };
}

function makeSvc(db: ReturnType<typeof makeDb>, enabled = true) {
  const prev = process.env.CSSD_BROWSER_PRINT_ENABLED;
  if (enabled) process.env.CSSD_BROWSER_PRINT_ENABLED = 'true';
  else delete process.env.CSSD_BROWSER_PRINT_ENABLED;
  try {
    return new BrowserPrintService(db as any, new AuditService(db as any));
  } finally {
    if (prev === undefined) delete process.env.CSSD_BROWSER_PRINT_ENABLED;
    else process.env.CSSD_BROWSER_PRINT_ENABLED = prev;
  }
}

const pkgRow = (o: any = {}) => ({
  id: 'pkg-1',
  status: 'STERILE',
  wrapType: 'SEAL',
  sterilizeDate: new Date('2026-07-01T00:00:00Z'),
  expiryDate: new Date('2026-12-28T00:00:00Z'),
  printedAt: null,
  reprintCount: 0,
  setTemplate: { name: 'ชุดทำแผล' },
  ...o,
});

const reqRow = (o: any = {}) => ({
  id: 'bpr-1',
  packageId: 'pkg-1',
  requestedByUserId: 'user-1',
  requestedAt: new Date('2026-07-24T01:00:00Z'),
  mode: 'BROWSER_DIALOG',
  templateVersion: '1',
  copies: 1,
  isReprint: false,
  reprintReason: null,
  status: BrowserPrintStatus.CREATED,
  dialogOpenedAt: null,
  userConfirmedAt: null,
  cancelledAt: null,
  createdFrom: 'PACKAGE_DETAIL',
  userAgent: 'UA',
  idempotencyKey: 'k-old',
  createdAt: new Date('2026-07-24T01:00:00Z'),
  updatedAt: new Date('2026-07-24T01:00:00Z'),
  ...o,
});

const createDto = (o: any = {}) => ({
  packageId: 'pkg-1',
  copies: 2,
  createdFrom: 'PACKAGE_DETAIL',
  ...o,
});

describe('BrowserPrintService.create', () => {
  it('§14.1 สร้าง request สำเร็จ — คืน row + label authoritative + priorPrints ว่าง', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) =>
      svc.create(createDto() as any, 'user-1', 'Mozilla/5.0 (Macintosh)', 'key-1', tx),
    );
    expect(res).toMatchObject({
      packageId: 'pkg-1',
      requestedByUserId: 'user-1',
      requestedByName: 'สมชาย',
      mode: 'BROWSER_DIALOG',
      templateVersion: '1', // ค่าคงที่ templateVersion = '1'
      copies: 2,
      isReprint: false,
      reprintReason: null,
      status: BrowserPrintStatus.CREATED,
      createdFrom: 'PACKAGE_DETAIL',
    });
    // label: วันที่ตรงจาก DB — client ห้ามคำนวณเอง
    expect(res.label).toEqual({
      packageId: 'pkg-1',
      templateName: 'ชุดทำแผล',
      wrapType: 'SEAL',
      status: 'STERILE',
      sterilizeDate: new Date('2026-07-01T00:00:00Z'),
      expiryDate: new Date('2026-12-28T00:00:00Z'),
      isSterilized: true,
    });
    expect(res.priorPrints).toEqual({
      count: 0, lastAt: null, lastByName: null, lastStatus: null, lastSource: null,
    });
    // row ที่เก็บจริงมี userAgent + idempotencyKey (แต่ response ไม่คืนออกไป)
    const stored = db._requests.get(res.id)!;
    expect(stored.userAgent).toBe('Mozilla/5.0 (Macintosh)');
    expect(stored.idempotencyKey).toBe('key-1');
    expect((res as any).userAgent).toBeUndefined();
    expect((res as any).idempotencyKey).toBeUndefined();
  });

  it('§14.1 label ของห่อยังไม่ sterile — วันที่เป็น null + isSterilized=false (ห้าม fabricate)', async () => {
    const db = makeDb([], [pkgRow({ status: 'PACKED', sterilizeDate: null, expiryDate: null })]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) =>
      svc.create(createDto() as any, 'user-1', 'UA', 'key-1', tx),
    );
    expect(res.label.sterilizeDate).toBeNull();
    expect(res.label.expiryDate).toBeNull();
    expect(res.label.isSterilized).toBe(false);
  });

  it('ตัด userAgent ให้ไม่เกิน 300 ตัวอักษร', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) =>
      svc.create(createDto() as any, 'user-1', 'x'.repeat(400), 'key-1', tx),
    );
    expect(db._requests.get(res.id)!.userAgent).toHaveLength(300);
  });

  it('§14.4 package ไม่มีอยู่จริง → 404 PKG_NOT_FOUND', async () => {
    const db = makeDb([], []);
    const svc = makeSvc(db);
    const p = db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx));
    await expect(p).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx)),
    ).rejects.toMatchObject({ response: { code: 'PKG_NOT_FOUND' } });
  });

  it('§14.5 package ID ผิดรูปแบบ → 400 PKG_ID_INVALID (reuse package-id.util)', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) =>
        svc.create(createDto({ packageId: 'bad id!<script>' }) as any, 'user-1', 'UA', 'k', tx),
      ),
    ).rejects.toMatchObject({ response: { code: 'PKG_ID_INVALID' } });
  });

  it('ห่อ DISCARDED → 400 PKG_DISCARDED (นโยบายเดียวกับฝั่ง packages)', async () => {
    const db = makeDb([], [pkgRow({ status: 'DISCARDED' })]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx)),
    ).rejects.toMatchObject({ response: { code: 'PKG_DISCARDED' } });
  });

  it('§14.15 reprint (มี browser prior DIALOG_OPENED) ไม่มีเหตุผล → 400 + prior summary', async () => {
    const prior = reqRow({
      id: 'bpr-old',
      status: BrowserPrintStatus.DIALOG_OPENED,
      dialogOpenedAt: new Date('2026-07-24T02:00:00Z'),
    });
    const db = makeDb([prior], [pkgRow()]);
    const svc = makeSvc(db);
    const p = db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx));
    await expect(p).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx)),
    ).rejects.toMatchObject({
      response: {
        code: 'BROWSER_PRINT_REPRINT_REASON_REQUIRED',
        prior: {
          count: 1,
          lastByName: 'สมชาย',
          lastStatus: BrowserPrintStatus.DIALOG_OPENED,
          lastSource: 'BROWSER',
        },
      },
    });
  });

  it('§14.15 reprint (gateway เคย ACK — package.printedAt) ไม่มีเหตุผล → 400 + prior GATEWAY', async () => {
    const printedAt = new Date('2026-07-20T03:00:00Z');
    const db = makeDb([], [pkgRow({ printedAt, reprintCount: 0 })]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx)),
    ).rejects.toMatchObject({
      response: {
        code: 'BROWSER_PRINT_REPRINT_REASON_REQUIRED',
        prior: { count: 1, lastAt: printedAt, lastByName: null, lastStatus: 'PRINTED', lastSource: 'GATEWAY' },
      },
    });
  });

  it('§14.15 reprint พร้อมเหตุผล → สำเร็จ, isReprint=true (backend-computed), audit REPRINT_REQUESTED', async () => {
    const prior = reqRow({ id: 'bpr-old', status: BrowserPrintStatus.USER_CONFIRMED,
      userConfirmedAt: new Date('2026-07-24T02:30:00Z') });
    const db = makeDb([prior], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) =>
      svc.create(createDto({ reprintReason: 'label เดิมชำรุด' }) as any, 'user-1', 'UA', 'k', tx),
    );
    expect(res.isReprint).toBe(true);
    expect(res.reprintReason).toBe('label เดิมชำรุด');
    expect(res.priorPrints).toMatchObject({ count: 1, lastSource: 'BROWSER',
      lastStatus: BrowserPrintStatus.USER_CONFIRMED });
    expect(db._audit.map((a) => a.action)).toEqual([
      'BROWSER_PRINT_REQUEST_CREATED',
      'BROWSER_PRINT_REPRINT_REQUESTED',
    ]);
  });
});

describe('BrowserPrintService + IdempotencyService ตัวจริง (P2002 emulation)', () => {
  const dto = createDto();

  it('§14.8 idempotency key เดิม (payload เดิม) → replay response เดิม ไม่สร้างแถวซ้ำ', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const idem = new IdempotencyService(db as any);
    const run = () =>
      idem.run('key-1', 'user-1', 'browser-print/create', 'POST', dto, (tx) =>
        svc.create(dto as any, 'user-1', 'UA', 'key-1', tx), { required: true });
    const first = await run();
    const second = await run();
    expect(second.id).toBe(first.id);
    expect(db._requests.size).toBe(1); // ไม่เกิดคำขอซ้ำ
    expect(db._audit.filter((a) => a.action === 'BROWSER_PRINT_REQUEST_CREATED')).toHaveLength(1);
  });

  it('§14.9 idempotency key เดิมแต่ payload ต่างกัน → 409 Conflict ไม่รันซ้ำ', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const idem = new IdempotencyService(db as any);
    await idem.run('key-1', 'user-1', 'browser-print/create', 'POST', dto, (tx) =>
      svc.create(dto as any, 'user-1', 'UA', 'key-1', tx), { required: true });
    const different = createDto({ copies: 9 });
    await expect(
      idem.run('key-1', 'user-1', 'browser-print/create', 'POST', different, (tx) =>
        svc.create(different as any, 'user-1', 'UA', 'key-1', tx), { required: true }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(db._requests.size).toBe(1);
  });

  it('ไม่ส่ง Idempotency-Key → 400 (required)', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const idem = new IdempotencyService(db as any);
    await expect(
      idem.run(undefined, 'user-1', 'browser-print/create', 'POST', dto, (tx) =>
        svc.create(dto as any, 'user-1', 'UA', 'x', tx), { required: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('BrowserPrintService — state machine (CAS)', () => {
  it('§14.10 CREATED → DIALOG_OPENED สำเร็จ + ตั้ง dialogOpenedAt จากนาฬิกา backend', async () => {
    const db = makeDb([reqRow()], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'user-1', tx));
    expect(res.status).toBe(BrowserPrintStatus.DIALOG_OPENED);
    expect(res.dialogOpenedAt).toBeInstanceOf(Date);
    expect(res.requestedByName).toBe('สมชาย');
  });

  it('§14.11 DIALOG_OPENED → USER_CONFIRMED สำเร็จ + ตั้ง userConfirmedAt', async () => {
    const db = makeDb([reqRow({ status: BrowserPrintStatus.DIALOG_OPENED })], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.confirm('bpr-1', 'user-1', tx));
    expect(res.status).toBe(BrowserPrintStatus.USER_CONFIRMED);
    expect(res.userConfirmedAt).toBeInstanceOf(Date);
  });

  it('§14.12 DIALOG_OPENED → CANCELLED สำเร็จ + ตั้ง cancelledAt', async () => {
    const db = makeDb([reqRow({ status: BrowserPrintStatus.DIALOG_OPENED })], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.cancel('bpr-1', 'user-1', tx));
    expect(res.status).toBe(BrowserPrintStatus.CANCELLED);
    expect(res.cancelledAt).toBeInstanceOf(Date);
  });

  it('§14.12 CREATED → CANCELLED ก็อนุญาต', async () => {
    const db = makeDb([reqRow()], [pkgRow()]);
    const svc = makeSvc(db);
    const res = await db.$transaction((tx: any) => svc.cancel('bpr-1', 'user-1', tx));
    expect(res.status).toBe(BrowserPrintStatus.CANCELLED);
  });

  it('§14.13 CREATED → confirm (ข้าม DIALOG_OPENED) ถูกปฏิเสธ BROWSER_PRINT_STATE', async () => {
    const db = makeDb([reqRow()], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.confirm('bpr-1', 'user-1', tx)),
    ).rejects.toMatchObject({ response: { code: 'BROWSER_PRINT_STATE' } });
  });

  it('§14.13 USER_CONFIRMED เป็น terminal — cancel ถูกปฏิเสธ', async () => {
    const db = makeDb([reqRow({ status: BrowserPrintStatus.USER_CONFIRMED })], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.cancel('bpr-1', 'user-1', tx)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('§14.13 CANCELLED เป็น terminal — dialog-opened ถูกปฏิเสธ', async () => {
    const db = makeDb([reqRow({ status: BrowserPrintStatus.CANCELLED })], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'user-1', tx)),
    ).rejects.toMatchObject({ response: { code: 'BROWSER_PRINT_STATE' } });
  });

  it('§14.13 เปิด dialog ซ้ำ request เดิม (เช่นหลัง refresh) ถูกปฏิเสธ — ต้องสร้าง request ใหม่', async () => {
    const db = makeDb([reqRow({ status: BrowserPrintStatus.DIALOG_OPENED })], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'user-1', tx)),
    ).rejects.toMatchObject({ response: { code: 'BROWSER_PRINT_STATE' } });
  });

  it('§14.13 concurrent dialog-opened ×2 → สำเร็จแค่ตัวเดียว (CAS updateMany)', async () => {
    const db = makeDb([reqRow()], [pkgRow()]);
    const svc = makeSvc(db);
    const results = await Promise.all([
      db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'user-1', tx)).catch((e: any) => e),
      db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'user-1', tx)).catch((e: any) => e),
    ]);
    expect(results.filter((r) => !(r instanceof Error))).toHaveLength(1);
    expect(
      results.filter((r) => r instanceof ConflictException || r instanceof BadRequestException),
    ).toHaveLength(1);
    // audit ของ transition เกิดครั้งเดียว (ยืนยันซ้ำต้องไม่สร้าง audit ซ้ำ)
    expect(db._audit.filter((a) => a.action === 'BROWSER_PRINT_DIALOG_OPENED')).toHaveLength(1);
  });

  it('request ไม่มีอยู่ → 404 BROWSER_PRINT_NOT_FOUND', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.confirm('missing', 'user-1', tx)),
    ).rejects.toMatchObject({ response: { code: 'BROWSER_PRINT_NOT_FOUND' } });
  });

  it('transition โดยคนที่ไม่ใช่เจ้าของ (แม้ ADMIN) → 403 BROWSER_PRINT_FORBIDDEN', async () => {
    const db = makeDb([reqRow()], [pkgRow()]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'admin-1', tx)),
    ).rejects.toMatchObject({ response: { code: 'BROWSER_PRINT_FORBIDDEN' } });
  });
});

describe('BrowserPrintService — ownership / IDOR (§14.14, §14.3)', () => {
  it('§14.14 เจ้าของอ่าน request ตัวเองได้', async () => {
    const svc = makeSvc(makeDb([reqRow()], []));
    await expect(svc.findOne('bpr-1', 'user-1', UserRole.CSSD)).resolves.toMatchObject({
      id: 'bpr-1',
      requestedByName: 'สมชาย',
    });
  });

  it('§14.14 CSSD คนอื่นอ่าน request ของผู้อื่นถูกปฏิเสธ 403', async () => {
    const svc = makeSvc(makeDb([reqRow()], []));
    await expect(svc.findOne('bpr-1', 'user-2', UserRole.CSSD)).rejects.toMatchObject({
      response: { code: 'BROWSER_PRINT_FORBIDDEN' },
    });
  });

  it('§14.14 SUPERVISOR/ADMIN อ่านของใครก็ได้', async () => {
    const svc = makeSvc(makeDb([reqRow()], []));
    await expect(svc.findOne('bpr-1', 'sup-1', UserRole.SUPERVISOR)).resolves.toMatchObject({ id: 'bpr-1' });
    await expect(svc.findOne('bpr-1', 'admin-1', UserRole.ADMIN)).resolves.toMatchObject({ id: 'bpr-1' });
  });

  it('§14.3 non-privileged ระบุ userId ที่ไม่ใช่ตัวเอง → 403 BROWSER_PRINT_FORBIDDEN', async () => {
    const svc = makeSvc(makeDb([reqRow()], []));
    await expect(svc.list('user-2', UserRole.CSSD, { userId: 'user-1' } as any)).rejects.toMatchObject({
      response: { code: 'BROWSER_PRINT_FORBIDDEN' },
    });
  });

  it('non-privileged ถูกบังคับเห็นเฉพาะของตัวเอง แม้ไม่ส่ง filter', async () => {
    const rows = [
      reqRow({ id: 'bpr-1', requestedByUserId: 'user-1' }),
      reqRow({ id: 'bpr-2', requestedByUserId: 'user-2' }),
    ];
    const svc = makeSvc(makeDb(rows, []));
    const res = await svc.list('user-2', UserRole.CSSD, {} as any);
    expect(res.items.map((i: any) => i.id)).toEqual(['bpr-2']);
    expect(res.total).toBe(1);
  });

  it('SUPERVISOR filter ตาม userId/status ได้ + pagination + เรียงล่าสุดก่อน', async () => {
    const rows = [
      reqRow({ id: 'bpr-1', createdAt: new Date('2026-07-24T01:00:00Z') }),
      reqRow({ id: 'bpr-2', createdAt: new Date('2026-07-24T02:00:00Z') }),
      reqRow({ id: 'bpr-3', createdAt: new Date('2026-07-24T03:00:00Z') }),
    ];
    const svc = makeSvc(makeDb(rows, []));
    const res = await svc.list('sup-1', UserRole.SUPERVISOR, { userId: 'user-1', page: 1, pageSize: 2 } as any);
    expect(res.items.map((i: any) => i.id)).toEqual(['bpr-3', 'bpr-2']); // createdAt desc
    expect(res).toMatchObject({ total: 3, page: 1, pageSize: 2 });
    const page2 = await svc.list('sup-1', UserRole.SUPERVISOR, { page: 2, pageSize: 2 } as any);
    expect(page2.items.map((i: any) => i.id)).toEqual(['bpr-1']);
  });

  it('default pageSize = 20 และ filter ช่วงเวลา from/to ทำงาน', async () => {
    const rows = [
      reqRow({ id: 'bpr-1', createdAt: new Date('2026-07-01T00:00:00Z') }),
      reqRow({ id: 'bpr-2', createdAt: new Date('2026-07-15T00:00:00Z') }),
      reqRow({ id: 'bpr-3', createdAt: new Date('2026-07-24T00:00:00Z') }),
    ];
    const svc = makeSvc(makeDb(rows, []));
    const res = await svc.list('user-1', UserRole.CSSD, {
      from: '2026-07-10T00:00:00Z',
      to: '2026-07-20T00:00:00Z',
    } as any);
    expect(res.items.map((i: any) => i.id)).toEqual(['bpr-2']);
    expect(res.pageSize).toBe(20);
  });
});

describe('BrowserPrintService — audit ครบทุก mutation (§14.16)', () => {
  it('§14.16 create/dialog-opened/confirm/cancel เขียน AuditLog ใน tx เดียวกัน พร้อม metadata ครบ', async () => {
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const created = await db.$transaction((tx: any) =>
      svc.create(createDto() as any, 'user-1', 'UA', 'k1', tx),
    );
    await db.$transaction((tx: any) => svc.dialogOpened(created.id, 'user-1', tx));
    await db.$transaction((tx: any) => svc.confirm(created.id, 'user-1', tx));
    const another = await db.$transaction((tx: any) =>
      svc.create(createDto({ reprintReason: 'พิมพ์ใหม่' }) as any, 'user-1', 'UA', 'k2', tx),
    );
    await db.$transaction((tx: any) => svc.cancel(another.id, 'user-1', tx));

    expect(db._audit.map((a) => a.action)).toEqual([
      'BROWSER_PRINT_REQUEST_CREATED',
      'BROWSER_PRINT_DIALOG_OPENED',
      'BROWSER_PRINT_USER_CONFIRMED',
      'BROWSER_PRINT_REQUEST_CREATED',
      'BROWSER_PRINT_REPRINT_REQUESTED', // ใบที่สองเป็น reprint (มี USER_CONFIRMED ก่อนหน้า)
      'BROWSER_PRINT_CANCELLED',
    ]);
    const confirmLog = db._audit.find((a) => a.action === 'BROWSER_PRINT_USER_CONFIRMED')!;
    expect(confirmLog.userId).toBe('user-1');
    expect(confirmLog.metadata).toMatchObject({
      requestId: created.id,
      packageId: 'pkg-1',
      mode: 'BROWSER_DIALOG',
      copies: 2,
      templateVersion: '1',
      previousStatus: BrowserPrintStatus.DIALOG_OPENED,
      newStatus: BrowserPrintStatus.USER_CONFIRMED,
      isReprint: false,
    });
    // ห้ามมี secret/token ใน metadata
    expect(JSON.stringify(db._audit)).not.toContain('idempotencyKey');
  });
});

describe('BrowserPrintService — ไม่แตะ Gateway semantics (§14.17)', () => {
  it('§14.17 ครบทั้ง flow browser print แล้ว package.printedAt/reprintCount ไม่เปลี่ยน และไม่แตะ printJob', async () => {
    // fake package.update/printJob.* ทุกเมธอด throw ถ้าถูกเรียก — แค่รันผ่านก็พิสูจน์แล้ว
    const db = makeDb([], [pkgRow()]);
    const svc = makeSvc(db);
    const created = await db.$transaction((tx: any) =>
      svc.create(createDto() as any, 'user-1', 'UA', 'k1', tx),
    );
    await db.$transaction((tx: any) => svc.dialogOpened(created.id, 'user-1', tx));
    await db.$transaction((tx: any) => svc.confirm(created.id, 'user-1', tx));
    expect(db._packages.get('pkg-1')!.printedAt).toBeNull();
    expect(db._packages.get('pkg-1')!.reprintCount).toBe(0);
  });
});

describe('BrowserPrintService — feature flag (directive §4)', () => {
  it('flag ปิด (unset) → ทุก endpoint 403 BROWSER_PRINT_DISABLED', async () => {
    const db = makeDb([reqRow()], [pkgRow()]);
    const svc = makeSvc(db, false);
    const expectDisabled = (p: Promise<unknown>) =>
      expect(p).rejects.toMatchObject({ response: { code: 'BROWSER_PRINT_DISABLED' } });
    await expectDisabled(
      db.$transaction((tx: any) => svc.create(createDto() as any, 'user-1', 'UA', 'k', tx)),
    );
    await expectDisabled(db.$transaction((tx: any) => svc.dialogOpened('bpr-1', 'user-1', tx)));
    await expectDisabled(db.$transaction((tx: any) => svc.confirm('bpr-1', 'user-1', tx)));
    await expectDisabled(db.$transaction((tx: any) => svc.cancel('bpr-1', 'user-1', tx)));
    await expectDisabled(svc.findOne('bpr-1', 'user-1', UserRole.CSSD));
    await expectDisabled(svc.list('user-1', UserRole.CSSD, {} as any));
    expect(() => svc.assertEnabled()).toThrow(ForbiddenException);
  });

  it("ค่า env ที่ไม่รู้จัก (เช่น '1', 'yes') → fail fast ตอนบูต", () => {
    const prev = process.env.CSSD_BROWSER_PRINT_ENABLED;
    process.env.CSSD_BROWSER_PRINT_ENABLED = 'yes';
    try {
      const db = makeDb();
      expect(() => new BrowserPrintService(db as any, new AuditService(db as any))).toThrow(
        /CSSD_BROWSER_PRINT_ENABLED/,
      );
    } finally {
      if (prev === undefined) delete process.env.CSSD_BROWSER_PRINT_ENABLED;
      else process.env.CSSD_BROWSER_PRINT_ENABLED = prev;
    }
  });
});
