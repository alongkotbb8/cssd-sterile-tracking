import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { IdempotencyService } from '../idempotency.service';

/**
 * Fake Prisma modelling FIX-02 แนวทาง A: reservation + mutation อยู่ใน
 * `$transaction` เดียวกัน — ถ้า callback throw จะ "rollback" (ลบแถวที่ create
 * ระหว่าง tx นั้นออก) จำลองพฤติกรรมจริงของ Postgres ที่ crash/error กลางคัน =
 * ไม่มีแถว PENDING ค้าง create() มี `await` คั่นก่อนเช็ค unique เพื่อให้ request
 * พร้อมกันสอง tx interleave ได้จริง
 *
 * ⚠️ ข้อจำกัดของ fake: create() ที่ชน key จะ throw P2002 ทันที (ไม่ block รอ tx
 * อีกตัว commit เหมือน Postgres จริง) ผู้แพ้ race จึงอาจเห็น PENDING แล้วได้ 409
 * แทนการ replay — พฤติกรรม replay จริงตรวจใน integration test (FIX-07)
 */
function p2002(): Prisma.PrismaClientKnownRequestError {
  const err: any = new Prisma.PrismaClientKnownRequestError('duplicate key', {
    code: 'P2002',
    clientVersion: 'test',
  });
  err.code = 'P2002';
  return err;
}

function makeFakePrisma() {
  const store = new Map<string, any>();

  const $transaction = async (cb: any) => {
    const createdKeys: string[] = [];
    const tx = {
      idempotentRequest: {
        async create({ data }: any) {
          await Promise.resolve(); // จุด interleave ของ request พร้อมกัน
          if (store.has(data.key)) throw p2002();
          store.set(data.key, { ...data });
          createdKeys.push(data.key);
          return store.get(data.key);
        },
        async update({ where: { key }, data }: any) {
          const row = store.get(key);
          Object.assign(row, data);
          return row;
        },
      },
    };
    try {
      return await cb(tx);
    } catch (e) {
      // rollback: ลบ reservation ที่เพิ่ง create ในทรานแซกชันนี้ (จำลอง Postgres rollback)
      for (const k of createdKeys) store.delete(k);
      throw e;
    }
  };

  return {
    idempotentRequest: {
      findUnique: async ({ where: { key } }: any) => store.get(key) ?? null,
      deleteMany: async ({ where }: any) => {
        let count = 0;
        for (const [k, row] of store.entries()) {
          if (where.status && row.status !== where.status) continue;
          if (where.expiresAt?.lt && row.expiresAt < where.expiresAt.lt) {
            store.delete(k);
            count++;
          }
        }
        return { count };
      },
    },
    $transaction,
    _store: store,
  };
}

describe('IdempotencyService — atomic single-transaction (FIX-02 approach A)', () => {
  it('runs fn(tx) and stores the response when the key is new', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true });
    const result = await svc.run('k1', 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    expect(result).toEqual({ ok: true });
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('replays the stored response for same key + same payload (no re-run)', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true, n: 1 });
    const first = await svc.run('k2', 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    const second = await svc.run('k2', 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    expect(second).toEqual(first);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('rejects when same key reused with a different payload', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true });
    await svc.run('k3', 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    await expect(svc.run('k3', 'u1', 'scan/out', 'POST', { a: 2 }, fn)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('rejects when same key is reused across a different endpoint/method', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true });
    await svc.run('k-ep', 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    await expect(
      svc.run('k-ep', 'u1', 'scan/in', 'POST', { a: 1 }, fn),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('rejects when a different user reuses the same key', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true });
    await svc.run('k4', 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    await expect(svc.run('k4', 'u2', 'scan/out', 'POST', { a: 1 }, fn)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('two concurrent requests with the same key execute fn exactly once', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    let running = 0;
    let maxConcurrent = 0;
    const fn = jest.fn().mockImplementation(async () => {
      running++;
      maxConcurrent = Math.max(maxConcurrent, running);
      await new Promise((r) => setTimeout(r, 5));
      running--;
      return { ok: true };
    });
    const settled = await Promise.allSettled([
      svc.run('k5', 'u1', 'scan/out', 'POST', { a: 1 }, fn),
      svc.run('k5', 'u1', 'scan/out', 'POST', { a: 1 }, fn),
    ]);
    expect(fn).toHaveBeenCalledTimes(1);
    expect(maxConcurrent).toBe(1);
    expect(settled.filter((s) => s.status === 'fulfilled')).toHaveLength(1);
  });

  it('crash BEFORE commit (fn throws) rolls back reservation → same key retryable, no duplicate', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const failing = jest.fn().mockRejectedValueOnce(new Error('boom'));
    const succeeding = jest.fn().mockResolvedValueOnce({ ok: true });
    await expect(svc.run('k6', 'u1', 'scan/out', 'POST', { a: 1 }, failing)).rejects.toThrow('boom');
    const result = await svc.run('k6', 'u1', 'scan/out', 'POST', { a: 1 }, succeeding);
    expect(result).toEqual({ ok: true });
    expect(succeeding).toHaveBeenCalledTimes(1);
  });

  it('NEVER re-runs fn when it finds a committed PENDING row — answers 409 instead (no blind rerun)', async () => {
    const prisma = makeFakePrisma();
    const svc = new IdempotencyService(prisma as any);
    // จำลองแถว PENDING ค้าง (เช่นจากโค้ดก่อน FIX-02) — ต้องไม่ rerun เด็ดขาด
    prisma._store.set('k7', {
      key: 'k7', userId: 'u1', endpoint: 'scan/out', method: 'POST',
      requestHash: (svc as any).hash({ a: 1 }), status: 'PENDING',
      expiresAt: new Date(Date.now() + 60_000),
    });
    const fn = jest.fn().mockResolvedValue({ ok: true });
    await expect(svc.run('k7', 'u1', 'scan/out', 'POST', { a: 1 }, fn)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(fn).not.toHaveBeenCalled();
  });

  it('bypasses idempotency but still runs fn in a transaction when no key given', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true });
    await svc.run(undefined, 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    await svc.run(undefined, 'u1', 'scan/out', 'POST', { a: 1 }, fn);
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it('rejects with 400 when required=true and no key given (audit ข้อ 2.8)', async () => {
    const svc = new IdempotencyService(makeFakePrisma() as any);
    const fn = jest.fn().mockResolvedValue({ ok: true });
    await expect(
      svc.run(undefined, 'u1', 'packages/create', 'POST', { a: 1 }, fn, { required: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(fn).not.toHaveBeenCalled();
  });

  it('cleanupExpired() deletes only expired DONE rows — NEVER touches PENDING (กฎห้ามละเมิด)', async () => {
    const prisma = makeFakePrisma();
    const svc = new IdempotencyService(prisma as any);
    prisma._store.set('old-done', { key: 'old-done', status: 'DONE', expiresAt: new Date(Date.now() - 60_000) });
    prisma._store.set('fresh-done', { key: 'fresh-done', status: 'DONE', expiresAt: new Date(Date.now() + 60_000) });
    // แถว PENDING ที่ "หมดอายุ" แล้ว — ต้องไม่ถูกลบเด็ดขาด (ห้ามลบ PENDING โดยไม่ตรวจ domain result)
    prisma._store.set('old-pending', { key: 'old-pending', status: 'PENDING', expiresAt: new Date(Date.now() - 60_000) });
    await svc.cleanupExpired();
    expect(prisma._store.has('old-done')).toBe(false); // ลบ DONE ที่หมดอายุ
    expect(prisma._store.has('fresh-done')).toBe(true); // คง DONE ที่ยังไม่หมดอายุ
    expect(prisma._store.has('old-pending')).toBe(true); // ⚠️ ต้องคง PENDING ไว้เสมอ
  });
});
