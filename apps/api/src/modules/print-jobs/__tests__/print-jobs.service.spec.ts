import { BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { PrintJobStatus, UserRole } from '@prisma/client';
import { AuditService } from '../../../common/audit/audit.service';
import { PrintJobsService } from '../print-jobs.service';

/**
 * Fake Prisma client แบบมี state จริง — `updateMany({where,data})` ทำงานเป็น
 * compare-and-swap จริงบน in-memory map เพื่อทดสอบ CAS/race condition ได้ตรงๆ
 * (ยังไม่ครอบคลุม `FOR UPDATE SKIP LOCKED` ของ Postgres จริง — ดู integration test)
 */
function matchesWhere(row: any, where: Record<string, any>): boolean {
  return Object.entries(where).every(([k, v]) => {
    if (v === null) return row[k] === null || row[k] === undefined;
    if (v && typeof v === 'object' && 'in' in v) return (v as any).in.includes(row[k]);
    if (v && typeof v === 'object' && 'lt' in v) return row[k] < (v as any).lt;
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

function makeDb(
  jobRows: any[] = [],
  packageRows: any[] = [],
  queryRawResult: any[] = [],
  gateway: any = { id: 'printer-1', environment: 'PRODUCTION', transportMode: 'SERIAL', canConfirmRealPrint: true },
) {
  const jobs = new Map(jobRows.map((j) => [j.id, { ...j }]));
  const packages = new Map(packageRows.map((p) => [p.id, { ...p }]));
  const audit: any[] = [];
  let nextId = jobs.size + 1;

  const printJob = {
    findUnique: async ({ where: { id } }: any) => (jobs.has(id) ? { ...jobs.get(id) } : null),
    findUniqueOrThrow: async ({ where: { id } }: any) => {
      if (!jobs.has(id)) throw new Error(`job ${id} not found`);
      return { ...jobs.get(id) };
    },
    updateMany: async ({ where, data }: any) => {
      const row = jobs.get(where.id);
      if (!row || !matchesWhere(row, where)) return { count: 0 };
      applyData(row, data);
      return { count: 1 };
    },
    create: async ({ data }: any) => {
      const id = `job-${nextId++}`;
      const row = { id, attemptCount: 0, resolvedAt: null, ...data };
      jobs.set(id, row);
      return { ...row };
    },
    findMany: async ({ where }: any) => [...jobs.values()].filter((r) => matchesWhere(r, where)),
  };

  const pkg = {
    findUnique: async ({ where: { id } }: any) => (packages.has(id) ? { ...packages.get(id) } : null),
    findUniqueOrThrow: async ({ where: { id } }: any) => ({ ...packages.get(id) }),
    update: async ({ where: { id }, data }: any) => {
      const row = packages.get(id);
      applyData(row, data);
      return { ...row };
    },
  };

  const printerDevice = {
    findUnique: async () => ({ ...gateway, isActive: true }),
    findUniqueOrThrow: async () => ({ ...gateway }),
    create: async ({ data }: any) => ({ id: 'new-gw', ...data }),
    update: async ({ data }: any) => {
      applyData(gateway, data);
      return { ...gateway };
    },
  };

  const tx = {
    printJob,
    package: pkg,
    printerDevice,
    auditLog: { create: async (args: any) => { audit.push(args.data); return args.data; } },
    $queryRaw: async () => queryRawResult,
  };

  return {
    printJob,
    package: pkg,
    printerDevice,
    $transaction: async (cb: any) => cb(tx),
    $queryRaw: async () => queryRawResult,
    _jobs: jobs,
    _packages: packages,
    _audit: audit,
  };
}

function makeSvc(db: ReturnType<typeof makeDb>) {
  return new PrintJobsService(db as any, new AuditService(db as any));
}

describe('PrintJobsService.createJob — server-derived isReprint (FIX-02: runs in caller tx)', () => {
  const pkgRow = (printedAt: Date | null) => ({
    id: 'pkg-1',
    printedAt,
    setTemplate: { name: 'ชุดทำแผล' },
    wrapType: 'SEAL',
  });

  it('first print: isReprint=false', async () => {
    const db = makeDb([], [pkgRow(null)]);
    const svc = makeSvc(db);
    const job = await db.$transaction((tx: any) => svc.createJob('pkg-1', 'user-1', {}, tx));
    expect(job.isReprint).toBe(false);
    expect(job.reprintReason).toBeNull();
  });

  it('rejects when already printed and no reprintReason given', async () => {
    const db = makeDb([], [pkgRow(new Date())]);
    const svc = makeSvc(db);
    await expect(
      db.$transaction((tx: any) => svc.createJob('pkg-1', 'user-1', {}, tx)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('forces isReprint=true server-side when package.printedAt is set', async () => {
    const db = makeDb([], [pkgRow(new Date())]);
    const svc = makeSvc(db);
    const job = await db.$transaction((tx: any) =>
      svc.createJob('pkg-1', 'user-1', { reprintReason: 'label เดิมชำรุด' }, tx),
    );
    expect(job.isReprint).toBe(true);
    expect(job.reprintReason).toBe('label เดิมชำรุด');
  });
});

describe('PrintJobsService.findOne — ownership (IDOR fix)', () => {
  const job = { id: 'job-1', requestedById: 'owner-1', status: PrintJobStatus.QUEUED };

  it('owner can view their own job', async () => {
    const svc = makeSvc(makeDb([job]));
    await expect(svc.findOne('job-1', 'owner-1', UserRole.CSSD)).resolves.toMatchObject({ id: 'job-1' });
  });

  it('a different CSSD user cannot view someone else\'s job', async () => {
    const svc = makeSvc(makeDb([job]));
    await expect(svc.findOne('job-1', 'someone-else', UserRole.CSSD)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('SUPERVISOR can view any job', async () => {
    const svc = makeSvc(makeDb([job]));
    await expect(svc.findOne('job-1', 'sup-1', UserRole.SUPERVISOR)).resolves.toMatchObject({ id: 'job-1' });
  });
});

describe('PrintJobsService.cancel — QUEUED only', () => {
  it('cancels a QUEUED job owned by the caller', async () => {
    const svc = makeSvc(makeDb([{ id: 'job-1', requestedById: 'owner-1', status: PrintJobStatus.QUEUED }]));
    await expect(svc.cancel('job-1', 'owner-1', UserRole.CSSD)).resolves.toEqual({ cancelled: true });
  });

  it('rejects cancelling a CLAIMED job — may be mid-print', async () => {
    const svc = makeSvc(makeDb([{ id: 'job-1', requestedById: 'owner-1', status: PrintJobStatus.CLAIMED }]));
    await expect(svc.cancel('job-1', 'owner-1', UserRole.CSSD)).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('PrintJobsService.claim — requestedPrinterId (pool) vs printerId', () => {
  it('claims a pool job (requestedPrinterId=null) for any gateway', async () => {
    const db = makeDb(
      [{ id: 'job-1', requestedPrinterId: null, printerId: null, status: PrintJobStatus.QUEUED, requestedById: 'u1', attemptCount: 0 }],
      [],
      [{ id: 'job-1' }],
    );
    const claimed = await makeSvc(db).claim('printer-1');
    expect(claimed?.status).toBe(PrintJobStatus.CLAIMED);
    expect(claimed?.printerId).toBe('printer-1');
    expect(claimed?.requestedPrinterId).toBeNull();
  });

  it('returns null when the job was already claimed (lost the CAS race)', async () => {
    const db = makeDb(
      [{ id: 'job-1', requestedPrinterId: null, printerId: null, status: PrintJobStatus.CLAIMED, requestedById: 'u1', attemptCount: 1 }],
      [],
      [{ id: 'job-1' }],
    );
    const claimed = await makeSvc(db).claim('printer-2');
    expect(claimed).toBeNull();
    expect(db._jobs.get('job-1')!.printerId).not.toBe('printer-2');
  });
});

describe('PrintJobsService — PRINTING → SENT → PRINTED pipeline + CAS + backend-decided simulation (FIX-05)', () => {
  const baseJob = () => ({
    id: 'job-1', packageId: 'pkg-1', printerId: 'printer-1', requestedById: 'u1',
    status: PrintJobStatus.CLAIMED, attemptCount: 1, isReprint: false,
  });

  it('markPrinting(): CLAIMED → PRINTING', async () => {
    const svc = makeSvc(makeDb([baseJob()]));
    expect((await svc.markPrinting('job-1', 'printer-1')).status).toBe(PrintJobStatus.PRINTING);
  });

  it('markPrinting(): rejects from QUEUED', async () => {
    const svc = makeSvc(makeDb([{ ...baseJob(), status: PrintJobStatus.QUEUED }]));
    await expect(svc.markPrinting('job-1', 'printer-1')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('markSent(): PRINTING → SENT, idempotent on repeat', async () => {
    const svc = makeSvc(makeDb([{ ...baseJob(), status: PrintJobStatus.PRINTING }]));
    expect((await svc.markSent('job-1', 'printer-1')).status).toBe(PrintJobStatus.SENT);
    expect((await svc.markSent('job-1', 'printer-1')).status).toBe(PrintJobStatus.SENT);
  });

  it('ack() rejects directly from PRINTING — must go through SENT', async () => {
    const svc = makeSvc(makeDb([{ ...baseJob(), status: PrintJobStatus.PRINTING }]));
    await expect(svc.ack('job-1', 'printer-1')).rejects.toBeInstanceOf(BadRequestException);
  });

  const realGw = { id: 'printer-1', environment: 'PRODUCTION', transportMode: 'SERIAL', canConfirmRealPrint: true };

  it('ack(): SENT → PRINTED for a PRODUCTION+SERIAL+canConfirm gateway, sets package.printedAt', async () => {
    const db = makeDb(
      [{ ...baseJob(), status: PrintJobStatus.SENT }],
      [{ id: 'pkg-1', printedAt: null, reprintCount: 0 }],
      [],
      { ...realGw },
    );
    const result = await makeSvc(db).ack('job-1', 'printer-1');
    expect(result.status).toBe(PrintJobStatus.PRINTED);
    expect(db._packages.get('pkg-1')!.printedAt).toBeInstanceOf(Date);
  });

  it('ack(): SENT → SIMULATED when canConfirmRealPrint=false — never touches Package (FIX-05)', async () => {
    const db = makeDb(
      [{ ...baseJob(), status: PrintJobStatus.SENT }],
      [{ id: 'pkg-1', printedAt: null, reprintCount: 0 }],
      [],
      { id: 'printer-1', environment: 'PRODUCTION', transportMode: 'SERIAL', canConfirmRealPrint: false },
    );
    const result = await makeSvc(db).ack('job-1', 'printer-1');
    expect(result.status).toBe(PrintJobStatus.SIMULATED);
    expect(db._packages.get('pkg-1')!.printedAt).toBeNull();
    expect(db._packages.get('pkg-1')!.reprintCount).toBe(0);
  });

  it('ack(): SIMULATED even if a CONSOLE gateway somehow has canConfirmRealPrint=true (re-check all 3 at ACK)', async () => {
    const db = makeDb(
      [{ ...baseJob(), status: PrintJobStatus.SENT }],
      [{ id: 'pkg-1', printedAt: null, reprintCount: 0 }],
      [],
      { id: 'printer-1', environment: 'DEVELOPMENT', transportMode: 'CONSOLE', canConfirmRealPrint: true },
    );
    const result = await makeSvc(db).ack('job-1', 'printer-1');
    expect(result.status).toBe(PrintJobStatus.SIMULATED);
    expect(db._packages.get('pkg-1')!.printedAt).toBeNull();
  });

  it('ack(): SIMULATED for a non-PRODUCTION gateway even with SERIAL transport', async () => {
    const db = makeDb(
      [{ ...baseJob(), status: PrintJobStatus.SENT }],
      [{ id: 'pkg-1', printedAt: null, reprintCount: 0 }],
      [],
      { id: 'printer-1', environment: 'TEST', transportMode: 'SERIAL', canConfirmRealPrint: true },
    );
    expect((await makeSvc(db).ack('job-1', 'printer-1')).status).toBe(PrintJobStatus.SIMULATED);
  });

  it('ack(): increments reprintCount when isReprint=true and real print', async () => {
    const db = makeDb(
      [{ ...baseJob(), status: PrintJobStatus.SENT, isReprint: true }],
      [{ id: 'pkg-1', printedAt: new Date('2026-01-01'), reprintCount: 1 }],
      [],
      { ...realGw },
    );
    await makeSvc(db).ack('job-1', 'printer-1');
    expect(db._packages.get('pkg-1')!.reprintCount).toBe(2);
  });

  it('ack() rejects when job belongs to a different gateway', async () => {
    const svc = makeSvc(makeDb([{ ...baseJob(), status: PrintJobStatus.SENT }]));
    await expect(svc.ack('job-1', 'other-printer')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('CRITICAL: two concurrent ack() on the same SENT job increment Package only once (CAS)', async () => {
    const db = makeDb(
      [{ ...baseJob(), status: PrintJobStatus.SENT, isReprint: true }],
      [{ id: 'pkg-1', printedAt: new Date('2026-01-01'), reprintCount: 1 }],
      [],
      { ...realGw },
    );
    const svc = makeSvc(db);
    const results = await Promise.all([
      svc.ack('job-1', 'printer-1').catch((e) => e),
      svc.ack('job-1', 'printer-1').catch((e) => e),
    ]);
    expect(results.filter((r) => !(r instanceof Error))).toHaveLength(1);
    expect(results.filter((r) => r instanceof Error)).toHaveLength(1);
    expect(db._packages.get('pkg-1')!.reprintCount).toBe(2);
  });
});

describe('PrintJobsService — gateway capability invariant (FIX-05)', () => {
  it('registerGateway rejects canConfirmRealPrint=true with CONSOLE transport', async () => {
    const svc = makeSvc(makeDb());
    await expect(
      svc.registerGateway('bad', 'admin-1', {
        environment: 'PRODUCTION' as any,
        transportMode: 'CONSOLE' as any,
        canConfirmRealPrint: true,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('registerGateway rejects canConfirmRealPrint=true with non-PRODUCTION environment', async () => {
    const svc = makeSvc(makeDb());
    await expect(
      svc.registerGateway('bad', 'admin-1', {
        environment: 'DEVELOPMENT' as any,
        transportMode: 'SERIAL' as any,
        canConfirmRealPrint: true,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('registerGateway allows PRODUCTION + SERIAL + canConfirmRealPrint=true', async () => {
    const svc = makeSvc(makeDb());
    await expect(
      svc.registerGateway('good', 'admin-1', {
        environment: 'PRODUCTION' as any,
        transportMode: 'SERIAL' as any,
        canConfirmRealPrint: true,
      }),
    ).resolves.toMatchObject({ canConfirmRealPrint: true });
  });

  it('updateGatewayCapability rejects turning on canConfirmRealPrint for a CONSOLE gateway', async () => {
    const gw = { id: 'printer-1', environment: 'DEVELOPMENT', transportMode: 'CONSOLE', canConfirmRealPrint: false };
    const svc = makeSvc(makeDb([], [], [], gw));
    await expect(
      svc.updateGatewayCapability('printer-1', 'admin-1', { canConfirmRealPrint: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('updateGatewayCapability allows canConfirmRealPrint=true only when promoted to PRODUCTION+SERIAL together', async () => {
    const gw = { id: 'printer-1', environment: 'DEVELOPMENT', transportMode: 'CONSOLE', canConfirmRealPrint: false };
    const svc = makeSvc(makeDb([], [], [], gw));
    await expect(
      svc.updateGatewayCapability('printer-1', 'admin-1', {
        environment: 'PRODUCTION' as any,
        transportMode: 'SERIAL' as any,
        canConfirmRealPrint: true,
      }),
    ).resolves.toMatchObject({ canConfirmRealPrint: true });
  });
});

describe('PrintJobsService.reportIndeterminate — MAYBE_SENT → ACK_UNKNOWN (FIX-04)', () => {
  const j = (status: PrintJobStatus) => ({
    id: 'job-1', packageId: 'pkg-1', printerId: 'printer-1', requestedById: 'u1', status, attemptCount: 1,
  });

  it('PRINTING → ACK_UNKNOWN (never auto-retry)', async () => {
    const db = makeDb([j(PrintJobStatus.PRINTING)]);
    const res = await makeSvc(db).reportIndeterminate('job-1', 'printer-1', 'TRANSPORT_MAYBE_SENT', 'drain error');
    expect(res.status).toBe(PrintJobStatus.ACK_UNKNOWN);
  });

  it('CLAIMED → ACK_UNKNOWN', async () => {
    const db = makeDb([j(PrintJobStatus.CLAIMED)]);
    expect((await makeSvc(db).reportIndeterminate('job-1', 'printer-1', 'X')).status).toBe(
      PrintJobStatus.ACK_UNKNOWN,
    );
  });

  it('rejects once already SENT (past the point of no return)', async () => {
    const db = makeDb([j(PrintJobStatus.SENT)]);
    await expect(makeSvc(db).reportIndeterminate('job-1', 'printer-1', 'X')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('idempotent when already ACK_UNKNOWN', async () => {
    const db = makeDb([j(PrintJobStatus.ACK_UNKNOWN)]);
    expect((await makeSvc(db).reportIndeterminate('job-1', 'printer-1', 'X')).status).toBe(
      PrintJobStatus.ACK_UNKNOWN,
    );
  });
});

describe('PrintJobsService.fail — only before SENT, CAS-guarded', () => {
  const j = (o: any = {}) => ({
    id: 'job-1', packageId: 'pkg-1', printerId: 'printer-1', requestedById: 'u1',
    status: PrintJobStatus.PRINTING, attemptCount: 1, isReprint: false, ...o,
  });

  it('requeues to QUEUED (via RETRYING) when attemptCount < max, clears printerId', async () => {
    const db = makeDb([j({ attemptCount: 1 })]);
    const res = await makeSvc(db).fail('job-1', 'printer-1', 'PAPER_OUT');
    expect(res.status).toBe(PrintJobStatus.QUEUED);
    expect(db._jobs.get('job-1')!.printerId).toBeNull();
  });

  it('DEAD_LETTER once attemptCount reaches max', async () => {
    const db = makeDb([j({ attemptCount: 3 })]);
    expect((await makeSvc(db).fail('job-1', 'printer-1', 'X')).status).toBe(PrintJobStatus.DEAD_LETTER);
  });

  it('rejects fail() once the job has reached SENT', async () => {
    const db = makeDb([j({ status: PrintJobStatus.SENT })]);
    await expect(makeSvc(db).fail('job-1', 'printer-1', 'X')).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('PrintJobsService.resolveAckUnknown — one-time resolution (FIX-03)', () => {
  const ackUnknownJob = () => ({
    id: 'job-1', packageId: 'pkg-1', printerId: 'printer-1', requestedPrinterId: null,
    requestedById: 'u1', status: PrintJobStatus.ACK_UNKNOWN, attemptCount: 1, isReprint: false,
    resolvedAt: null,
  });

  it('CONFIRM_PRINTED → RESOLVED_PRINTED + updates package.printedAt', async () => {
    const db = makeDb([ackUnknownJob()], [{ id: 'pkg-1', printedAt: null, reprintCount: 0 }]);
    const res = await makeSvc(db).resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', 'พบใบพิมพ์จริง');
    expect(res.status).toBe(PrintJobStatus.RESOLVED_PRINTED);
    expect(db._packages.get('pkg-1')!.printedAt).toBeInstanceOf(Date);
  });

  it('REQUEUE → RESOLVED_REQUEUED + a new job linked via requeuedFromJobId', async () => {
    const db = makeDb(
      [ackUnknownJob()],
      [{ id: 'pkg-1', printedAt: null, setTemplate: { name: 'ชุดทำแผล' }, wrapType: 'SEAL' }],
    );
    const requeued = await makeSvc(db).resolveAckUnknown('job-1', 'sup-1', 'REQUEUE', 'พิมพ์ใหม่');
    expect(requeued.id).not.toBe('job-1');
    expect(requeued.requeuedFromJobId).toBe('job-1');
    expect(db._jobs.get('job-1')!.status).toBe(PrintJobStatus.RESOLVED_REQUEUED);
    expect(db._jobs.get('job-1')!.resolvedById).toBe('sup-1');
  });

  it('CONFIRM_PRINTED twice → second call rejected, reprintCount not double-incremented', async () => {
    const db = makeDb(
      [{ ...ackUnknownJob(), isReprint: true }],
      [{ id: 'pkg-1', printedAt: new Date('2026-01-01'), reprintCount: 1 }],
    );
    const svc = makeSvc(db);
    await svc.resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', 'ok');
    await expect(
      svc.resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', 'ok again'),
    ).rejects.toBeInstanceOf(BadRequestException); // status no longer ACK_UNKNOWN → precheck rejects
    expect(db._packages.get('pkg-1')!.reprintCount).toBe(2);
  });

  it('concurrent CONFIRM_PRINTED → only one succeeds (CAS on resolvedAt IS NULL)', async () => {
    const db = makeDb([{ ...ackUnknownJob(), isReprint: true }], [{ id: 'pkg-1', printedAt: new Date(), reprintCount: 1 }]);
    const svc = makeSvc(db);
    const results = await Promise.all([
      svc.resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', 'a').catch((e) => e),
      svc.resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', 'b').catch((e) => e),
    ]);
    expect(results.filter((r) => !(r instanceof Error))).toHaveLength(1);
    expect(results.filter((r) => r instanceof ConflictException)).toHaveLength(1);
    expect(db._packages.get('pkg-1')!.reprintCount).toBe(2);
  });

  it('rejects resolving a job that is not ACK_UNKNOWN', async () => {
    const db = makeDb([{ ...ackUnknownJob(), status: PrintJobStatus.PRINTED }]);
    await expect(
      makeSvc(db).resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', 'note'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects when no note given', async () => {
    const db = makeDb([ackUnknownJob()]);
    await expect(
      makeSvc(db).resolveAckUnknown('job-1', 'sup-1', 'CONFIRM_PRINTED', ''),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('PrintJobsService.recoverStaleLeases — CLAIMED vs PRINTING/SENT split', () => {
  const stale = new Date(Date.now() - 11 * 60_000);

  it('CLAIMED past timeout → QUEUED (safe)', async () => {
    const db = makeDb([{ id: 'job-1', requestedById: 'u1', printerId: 'printer-1', status: PrintJobStatus.CLAIMED, claimedAt: stale }]);
    await makeSvc(db).recoverStaleLeases();
    expect(db._jobs.get('job-1')!.status).toBe(PrintJobStatus.QUEUED);
    expect(db._jobs.get('job-1')!.printerId).toBeNull();
  });

  it('PRINTING past timeout → ACK_UNKNOWN (unsafe to retry)', async () => {
    const db = makeDb([{ id: 'job-1', requestedById: 'u1', printerId: 'printer-1', status: PrintJobStatus.PRINTING, printingAt: stale }]);
    await makeSvc(db).recoverStaleLeases();
    expect(db._jobs.get('job-1')!.status).toBe(PrintJobStatus.ACK_UNKNOWN);
  });

  it('SENT past timeout → ACK_UNKNOWN', async () => {
    const db = makeDb([{ id: 'job-1', requestedById: 'u1', printerId: 'printer-1', status: PrintJobStatus.SENT, sentAt: stale }]);
    await makeSvc(db).recoverStaleLeases();
    expect(db._jobs.get('job-1')!.status).toBe(PrintJobStatus.ACK_UNKNOWN);
  });
});

describe('PrintJobsService.rotateGatewayKey (Phase 5)', () => {
  it('rotates keyId+secret and returns a new apiKey (device id unchanged)', async () => {
    const gw: any = { id: 'printer-1', name: 'gw', keyId: 'old', apiKeyHash: 'oldhash',
      environment: 'PRODUCTION', transportMode: 'SERIAL', canConfirmRealPrint: true };
    const db = makeDb([], [], [], gw);
    const res = await makeSvc(db).rotateGatewayKey('printer-1', 'admin-1');
    expect(res.id).toBe('printer-1'); // device id ไม่เปลี่ยน (งานที่อ้างอิงไม่พัง)
    expect(res.apiKey).toMatch(/^[a-f0-9]+\.[a-f0-9]+$/);
    expect(gw.keyId).not.toBe('old'); // keyId ถูกหมุน
    expect(gw.apiKeyHash).not.toBe('oldhash'); // hash ใหม่ (key เดิมใช้ไม่ได้)
  });

  it('rejects rotating a revoked gateway', async () => {
    const gw: any = { id: 'printer-1', name: 'gw', revokedAt: new Date() };
    const db = makeDb([], [], [], gw);
    await expect(makeSvc(db).rotateGatewayKey('printer-1', 'admin-1'))
        .rejects.toBeInstanceOf(BadRequestException);
  });
});
