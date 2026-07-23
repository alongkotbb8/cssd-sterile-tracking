import { ConflictException } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { makeClient, services, seedBase, truncateTx, SeedIds } from './harness';

/**
 * FIX-07 — Idempotency concurrency กับ PostgreSQL จริง (fake client พิสูจน์ตรรกะ
 * ได้ แต่ไม่พิสูจน์ row-lock/serialization จริงของ Postgres)
 */
describe('[integration] Idempotency กับ Postgres จริง', () => {
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

  const createPkg = (tx: any) => svc.packages.create({ setTemplateId: seed.setTemplateId }, seed.userId, tx);

  it('10 concurrent requests, same key → package สร้างครั้งเดียว, ทุก request ได้ response เดียวกัน (replay จริง)', async () => {
    const key = 'concurrent-key';
    const results = await Promise.all(
      Array.from({ length: 10 }, () =>
        svc.idem.run(key, seed.userId, 'packages/create', 'POST', { setTemplateId: seed.setTemplateId }, createPkg, {
          required: true,
        }),
      ),
    );
    const ids = new Set(results.map((r: any) => r.id));
    expect(ids.size).toBe(1); // ทุก request คืน package เดียวกัน
    expect(await prisma.package.count()).toBe(1); // สร้างจริงแค่ใบเดียว
    // เลขรันไม่กระโดด: seq = 1
    const seq = await prisma.runningNumberSequence.findFirst();
    expect(seq?.lastSeq).toBe(1);
  });

  it('key เดิม payload ต่างกัน → 409', async () => {
    const key = 'diff-payload';
    await svc.idem.run(key, seed.userId, 'packages/create', 'POST', { setTemplateId: seed.setTemplateId }, createPkg);
    await expect(
      svc.idem.run(key, seed.userId, 'packages/create', 'POST', { setTemplateId: 'OTHER' }, createPkg),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(await prisma.package.count()).toBe(1);
  });

  it('crash ระหว่าง mutation (fn throw หลังสร้าง แต่ก่อน DONE) → rollback หมด ไม่มีข้อมูลซ้ำ + retry ทำงานได้', async () => {
    const key = 'crash-key';
    // fn สร้าง package แล้ว throw — approach A ต้อง rollback ทั้ง package + reservation
    await expect(
      svc.idem.run(key, seed.userId, 'packages/create', 'POST', { setTemplateId: seed.setTemplateId }, async (tx) => {
        await createPkg(tx);
        throw new Error('crash before commit');
      }),
    ).rejects.toThrow('crash before commit');
    expect(await prisma.package.count()).toBe(0); // rollback แล้ว

    // retry ด้วย key เดิม (ไม่ throw) → ทำงานได้ 1 ครั้ง
    const ok = await svc.idem.run(key, seed.userId, 'packages/create', 'POST', { setTemplateId: seed.setTemplateId }, createPkg);
    expect(ok).toBeTruthy();
    expect(await prisma.package.count()).toBe(1);
  });

  it('committed PENDING ค้าง (จำลองแถวเก่า) → 409 ไม่ rerun เด็ดขาด', async () => {
    const key = 'stuck-pending';
    await prisma.idempotentRequest.create({
      data: {
        key, userId: seed.userId, endpoint: 'packages/create', method: 'POST',
        requestHash: (svc.idem as any).hash({ setTemplateId: seed.setTemplateId }),
        status: 'PENDING', expiresAt: new Date(Date.now() + 60_000),
      },
    });
    await expect(
      svc.idem.run(key, seed.userId, 'packages/create', 'POST', { setTemplateId: seed.setTemplateId }, createPkg),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(await prisma.package.count()).toBe(0); // ไม่ rerun
  });
});
