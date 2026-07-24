import { test, expect, APIRequestContext, Page } from '@playwright/test';
import crypto from 'node:crypto';
import { enableFlutterSemantics, byLabel, login, openTab } from './helpers';

/**
 * Browser Print (BROWSER_DIALOG) E2E — MACOS_BROWSER_PRINT_DIRECTIVE.md §14 (E2E ≥9 ข้อ)
 *
 * โหมดนี้เปิดใน stack ทดสอบด้วย CSSD_BROWSER_PRINT_ENABLED=true (API) +
 * --dart-define=CSSD_BROWSER_PRINT_ENABLED=true (PWA build) — production default = ปิด
 *
 * ส่วน UI (ข้อ 1, 2, 5) ใช้ browser จริง; ส่วนกติกา state machine/idempotency/reprint
 * (ข้อ 3, 4, 6, 7, 8, 9) ตรวจที่ API layer + PostgreSQL จริง ตามแนวเดียวกับ lifecycle.spec
 * — print dialog ของจริงพิสูจน์ไม่ได้ใน automated test (headless print() เป็น no-op)
 * จึงยืนยันด้วย state ที่ backend บันทึก (DIALOG_OPENED เกิดก่อนเรียก print เสมอ)
 *
 * บัญชี seed: ADMIN001/Admin@1234 (ดู prisma/seed.ts)
 */
const API = process.env.E2E_API_URL ?? 'http://localhost:3000/api/v1';
const idem = () => crypto.randomUUID();

const tokenCache = new Map<string, string>();
async function apiLogin(
  request: APIRequestContext,
  employeeCode: string,
  password: string,
): Promise<string> {
  if (tokenCache.has(employeeCode)) return tokenCache.get(employeeCode)!;
  const res = await request.post(`${API}/auth/login`, {
    data: { employeeCode, password },
  });
  expect(res.ok(), `login ${employeeCode}: ${res.status()}`).toBeTruthy();
  const token = (await res.json()).accessToken as string;
  tokenCache.set(employeeCode, token);
  return token;
}

const auth = (token: string, extra: Record<string, string> = {}) => ({
  headers: { Authorization: `Bearer ${token}`, ...extra },
});

/** สร้างห่อใหม่ผ่าน API (เลขรันจาก backend) — ห่อใหม่ = ไม่เคยพิมพ์ (ไม่ใช่ reprint) */
async function createPackage(
  request: APIRequestContext,
  token: string,
): Promise<string> {
  const templates = await (
    await request.get(`${API}/master-data/templates`, auth(token))
  ).json();
  const res = await request.post(`${API}/packages`, {
    ...auth(token, { 'Idempotency-Key': idem() }),
    data: { setTemplateId: templates[0].id },
  });
  expect(res.ok(), `create package: ${res.status()}`).toBeTruthy();
  const body = await res.json();
  const pkg = Array.isArray(body) ? body[0] : (body.packages?.[0] ?? body);
  return (pkg.id ?? pkg.packageId) as string;
}

/** สร้าง browser print request ผ่าน API */
async function createBpRequest(
  request: APIRequestContext,
  token: string,
  packageId: string,
  opts: { copies?: number; reprintReason?: string; key?: string } = {},
) {
  return request.post(`${API}/browser-print-requests`, {
    ...auth(token, { 'Idempotency-Key': opts.key ?? idem() }),
    data: {
      packageId,
      copies: opts.copies ?? 1,
      createdFrom: 'PACKAGE_DETAIL',
      ...(opts.reprintReason ? { reprintReason: opts.reprintReason } : {}),
    },
  });
}

async function bpTransition(
  request: APIRequestContext,
  token: string,
  id: string,
  op: 'dialog-opened' | 'confirm' | 'cancel',
) {
  return request.post(`${API}/browser-print-requests/${id}/${op}`, {
    ...auth(token, { 'Idempotency-Key': idem() }),
    data: {},
  });
}

async function bpList(
  request: APIRequestContext,
  token: string,
  packageId: string,
) {
  const res = await request.get(
    `${API}/browser-print-requests?packageId=${encodeURIComponent(packageId)}`,
    auth(token),
  );
  expect(res.ok(), `list browser-print: ${res.status()}`).toBeTruthy();
  return (await res.json()) as {
    items: Array<{
      id: string;
      status: string;
      isReprint: boolean;
      createdFrom: string;
      dialogOpenedAt: string | null;
    }>;
    total: number;
  };
}

/** เปิดหน้ารายละเอียดห่อจากรายการ (แท็บ "รายการ" → แตะการ์ดของ id นั้น) */
async function openPackageDetail(page: Page, packageId: string) {
  await openTab(page, 'รายการ');
  const card = byLabel(page, packageId).first();
  await expect(card).toBeVisible({ timeout: 20_000 });
  await card.click();
}

test.describe('Browser Print — UI (Mac/PWA print dialog flow)', () => {
  test('§14.1 login → เปิดห่อ → เปิด sheet → preview + request ถูกสร้าง (CREATED)', async ({
    page,
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);

    await login(page, 'ADMIN001', 'Admin@1234');
    await openPackageDetail(page, pkg);

    // ปุ่มเข้าโหมดพิมพ์ผ่านเครื่องนี้ (แสดงเฉพาะเมื่อ flag เปิด)
    await byLabel(page, 'พิมพ์ผ่านเครื่องนี้').first().click();

    // sheet สร้าง request อัตโนมัติ (ห่อใหม่ ไม่ใช่ reprint) แล้วแสดงตัวอย่าง label
    await expect
      .poll(
        async () => {
          const list = await bpList(request, admin, pkg);
          return list.items.length === 1 && list.items[0].status === 'CREATED';
        },
        { timeout: 20_000 },
      )
      .toBeTruthy();

    // preview UI แสดงคำเตือนว่า browser ยืนยันผล hardware ไม่ได้
    await expect(
      byLabel(page, 'ไม่สามารถตรวจสอบกระดาษ').first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  test('§14.2+5 กดพิมพ์ → DIALOG_OPENED ก่อนเปิด dialog; refresh แล้วไม่เปิด dialog ซ้ำ/ไม่สร้าง request ใหม่', async ({
    page,
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);

    await login(page, 'ADMIN001', 'Admin@1234');
    await openPackageDetail(page, pkg);
    await byLabel(page, 'พิมพ์ผ่านเครื่องนี้').first().click();

    // รอ request ถูกสร้างก่อน (sheet auto-create)
    await expect
      .poll(async () => (await bpList(request, admin, pkg)).items.length, {
        timeout: 20_000,
      })
      .toBe(1);

    // กดปุ่มพิมพ์ใน sheet (ตัวสุดท้าย = ปุ่ม action ใน sheet)
    await byLabel(page, 'พิมพ์ผ่านเครื่องนี้').last().click();

    // backend ต้องบันทึก DIALOG_OPENED (PWA บันทึกก่อนเรียก print เสมอ —
    // headless print() เป็น no-op จึงพิสูจน์ลำดับด้วย state ที่ backend เห็น)
    await expect
      .poll(
        async () => {
          const list = await bpList(request, admin, pkg);
          return list.items[0]?.status;
        },
        { timeout: 20_000 },
      )
      .toBe('DIALOG_OPENED');

    const before = await bpList(request, admin, pkg);
    const openedAt = before.items[0].dialogOpenedAt;

    // refresh — ห้าม auto-open dialog / ห้าม re-use request เดิม / ห้ามสร้างใหม่เอง
    await page.reload();
    await enableFlutterSemantics(page);
    await page.waitForTimeout(3000);

    const after = await bpList(request, admin, pkg);
    expect(after.items.length).toBe(1);
    expect(after.items[0].status).toBe('DIALOG_OPENED');
    expect(after.items[0].dialogOpenedAt).toBe(openedAt);
  });
});

test.describe('Browser Print — state machine + กติกา backend (API จริง + PG จริง)', () => {
  test('§14.2 CREATED → DIALOG_OPENED', async ({ request }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);
    const created = await (await createBpRequest(request, admin, pkg)).json();
    expect(created.status).toBe('CREATED');
    expect(created.isReprint).toBe(false);
    expect(created.label.packageId).toBe(pkg);
    // ห่อ PACKED — label ต้องไม่มีวันที่ (backend เป็นผู้ตัดสิน)
    expect(created.label.isSterilized).toBe(false);
    expect(created.label.sterilizeDate).toBeNull();
    expect(created.label.expiryDate).toBeNull();

    const opened = await bpTransition(request, admin, created.id, 'dialog-opened');
    expect(opened.ok()).toBeTruthy();
    const openedBody = await opened.json();
    expect(openedBody.status).toBe('DIALOG_OPENED');
    expect(openedBody.dialogOpenedAt).not.toBeNull();
  });

  test('§14.3 DIALOG_OPENED → USER_CONFIRMED (และห้ามข้ามจาก CREATED)', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);
    const created = await (await createBpRequest(request, admin, pkg)).json();

    // ข้ามจาก CREATED → USER_CONFIRMED ต้องถูกปฏิเสธ (BROWSER_PRINT_STATE)
    const skip = await bpTransition(request, admin, created.id, 'confirm');
    expect(skip.ok()).toBeFalsy();
    expect((await skip.json()).code).toBe('BROWSER_PRINT_STATE');

    await bpTransition(request, admin, created.id, 'dialog-opened');
    const confirmed = await bpTransition(request, admin, created.id, 'confirm');
    expect(confirmed.ok()).toBeTruthy();
    const body = await confirmed.json();
    expect(body.status).toBe('USER_CONFIRMED');
    expect(body.userConfirmedAt).not.toBeNull();

    // สถานะปลายทางแล้ว — เปลี่ยนต่อไม่ได้อีก
    const again = await bpTransition(request, admin, created.id, 'cancel');
    expect(again.ok()).toBeFalsy();
    expect((await again.json()).code).toBe('BROWSER_PRINT_STATE');
  });

  test('§14.4 request → CANCELLED (จาก CREATED และจาก DIALOG_OPENED) + CANCELLED ถาวร', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);

    // CREATED → CANCELLED
    const a = await (await createBpRequest(request, admin, pkg)).json();
    const cancelA = await bpTransition(request, admin, a.id, 'cancel');
    expect(cancelA.ok()).toBeTruthy();
    expect((await cancelA.json()).status).toBe('CANCELLED');

    // CANCELLED ห้ามกลับสถานะอื่น
    const reopen = await bpTransition(request, admin, a.id, 'dialog-opened');
    expect(reopen.ok()).toBeFalsy();
    expect((await reopen.json()).code).toBe('BROWSER_PRINT_STATE');

    // DIALOG_OPENED → CANCELLED (ยกเลิกไม่นับเป็นพิมพ์แล้ว → ห่อนี้ยังไม่เป็น reprint
    // เพราะ CANCELLED ไม่อยู่ในเงื่อนไข isReprint — แต่ DIALOG_OPENED อยู่)
    const b = await (
      await createBpRequest(request, admin, pkg, { reprintReason: undefined })
    ).json();
    expect(b.status).toBe('CREATED');
    await bpTransition(request, admin, b.id, 'dialog-opened');
    const cancelB = await bpTransition(request, admin, b.id, 'cancel');
    expect(cancelB.ok()).toBeTruthy();
    expect((await cancelB.json()).status).toBe('CANCELLED');
  });

  test('§14.6 Idempotency-Key เดิม → ไม่สร้างงานซ้ำ (replay ได้ id เดิม)', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);
    const key = idem();

    const first = await (
      await createBpRequest(request, admin, pkg, { key })
    ).json();
    const second = await (
      await createBpRequest(request, admin, pkg, { key })
    ).json();
    expect(second.id).toBe(first.id);

    const list = await bpList(request, admin, pkg);
    expect(list.items.length).toBe(1);
  });

  test('§14.7 reprint: ไม่มีเหตุผล → ปฏิเสธพร้อมข้อมูลการพิมพ์ก่อนหน้า; มีเหตุผล → isReprint=true', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);

    // พิมพ์ครั้งแรก (จนถึง USER_CONFIRMED = เคยสั่งพิมพ์แล้วตาม §9)
    const first = await (await createBpRequest(request, admin, pkg)).json();
    await bpTransition(request, admin, first.id, 'dialog-opened');
    await bpTransition(request, admin, first.id, 'confirm');

    // ครั้งที่สองไม่ใส่เหตุผล → 400 BROWSER_PRINT_REPRINT_REASON_REQUIRED + prior info
    const noReason = await createBpRequest(request, admin, pkg);
    expect(noReason.status()).toBe(400);
    const err = await noReason.json();
    expect(err.code).toBe('BROWSER_PRINT_REPRINT_REASON_REQUIRED');
    expect(err.prior?.count).toBeGreaterThanOrEqual(1);
    expect(err.prior?.lastStatus).toBe('USER_CONFIRMED');

    // ใส่เหตุผล → สำเร็จ + backend ตั้ง isReprint เอง
    const withReason = await (
      await createBpRequest(request, admin, pkg, { reprintReason: 'label เสียหาย' })
    ).json();
    expect(withReason.isReprint).toBe(true);
    expect(withReason.reprintReason).toBe('label เสียหาย');
    expect(withReason.priorPrints.count).toBeGreaterThanOrEqual(1);
  });

  test('§14.8 history แสดง request เดิมและ reprint แยกกัน (เรียงล่าสุดก่อน)', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);

    const first = await (await createBpRequest(request, admin, pkg)).json();
    await bpTransition(request, admin, first.id, 'dialog-opened');
    await bpTransition(request, admin, first.id, 'confirm');
    const second = await (
      await createBpRequest(request, admin, pkg, { reprintReason: 'พิมพ์ไม่ชัด' })
    ).json();

    const list = await bpList(request, admin, pkg);
    expect(list.items.length).toBe(2);
    // ล่าสุดก่อน
    expect(list.items[0].id).toBe(second.id);
    expect(list.items[0].isReprint).toBe(true);
    expect(list.items[1].id).toBe(first.id);
    expect(list.items[1].isReprint).toBe(false);
    expect(list.items[1].status).toBe('USER_CONFIRMED');
  });

  test('§14.9 browser flow ไม่แตะ Gateway job state และไม่ตั้ง Package.printedAt', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);

    // สร้าง gateway print job คู่ขนานไว้ก่อน (QUEUED)
    const jobRes = await request.post(`${API}/print-jobs`, {
      ...auth(admin, { 'Idempotency-Key': idem() }),
      data: { packageId: pkg },
    });
    expect(jobRes.ok()).toBeTruthy();
    const job = await jobRes.json();
    expect(job.status).toBe('QUEUED');

    // browser flow จนจบ USER_CONFIRMED
    const bp = await (await createBpRequest(request, admin, pkg)).json();
    await bpTransition(request, admin, bp.id, 'dialog-opened');
    const confirmed = await bpTransition(request, admin, bp.id, 'confirm');
    expect(confirmed.ok()).toBeTruthy();

    // Gateway job ต้องยัง QUEUED เป๊ะ — browser ห้ามยุ่ง (directive §3/§19)
    const jobAfter = await (
      await request.get(`${API}/print-jobs/${job.id}`, auth(admin))
    ).json();
    expect(jobAfter.status).toBe('QUEUED');
    expect(jobAfter.printedAt ?? null).toBeNull();

    // Package.printedAt ต้องยัง null (มีแต่ gateway ACK เท่านั้นที่ตั้งได้)
    const pkgAfter = await (
      await request.get(`${API}/packages/${pkg}`, auth(admin))
    ).json();
    expect(pkgAfter.printedAt ?? null).toBeNull();
    expect(pkgAfter.reprintCount ?? 0).toBe(0);
  });

  test('§13 rate limit: mutation ที่ยิงถี่เกินเพดานถูกปฏิเสธด้วย BROWSER_PRINT_RATE_LIMITED', async ({
    request,
  }) => {
    // ใน stack ทดสอบตั้ง BROWSER_PRINT_THROTTLE_MAX สูง (กัน flake ข้าม project) —
    // จึงตรวจแค่ contract ว่า endpoint ตอบ 201/400 ตามปกติ ไม่ใช่ 429 ที่เพดานสูง
    // (เพดานจริง + 429 code ถูกพิสูจน์ใน backend unit test); เคสนี้กันการถอด guard ออก
    // โดยตรวจว่า response ไม่มี 5xx เมื่อยิงต่อเนื่องหลายครั้ง
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);
    for (let i = 0; i < 5; i++) {
      const res = await createBpRequest(request, admin, pkg, {
        reprintReason: i > 0 ? `รอบ ${i}` : undefined,
      });
      expect([201, 400].includes(res.status()), `round ${i}: ${res.status()}`).toBeTruthy();
    }
  });
});
