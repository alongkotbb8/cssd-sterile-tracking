import { test, expect, APIRequestContext } from '@playwright/test';
import crypto from 'node:crypto';

/**
 * Package/Print lifecycle E2E — ยิง **API จริง + PostgreSQL จริง** ของ stack ที่ CI ยกขึ้น
 * (ไม่ mock layer ใด — browser UI ครอบคน-flow ใน flow/scanner.spec แล้ว ส่วนกติกาโดเมน
 * ที่ต้องจัด state หลายขั้น ตรวจที่ API layer ตาม §2D "DB/API/UI assertions สอดคล้องกัน")
 *
 * ครอบ master directive §2B:
 * - running number จาก backend, scan in → batch, batch pass → STERILE+expiry,
 *   batch fail → recall ผ่าน attempt history (ยังเห็นหลัง batchId เปลี่ยน),
 *   expired ถูกบล็อก fail-closed, scan out ต้องมี department,
 *   PACKED_OUT เฉพาะ external, return + department, reprocess RETURNED→PACKED,
 *   tag attach/filter/detach
 * - RBAC: CSSD ห้ามบันทึกผล/resolve, Idempotency-Key เดิมไม่สร้างซ้ำ,
 *   browser (user JWT) ACK print job เองไม่ได้, token เก่าถูกปฏิเสธหลัง logout-all
 *
 * บัญชี seed: ADMIN001/Admin@1234, SUP001/Sup@1234, STAFF001/Staff@1234 (CSSD)
 * fixture seed: DRESS-20260101-9999 = ห่อ STERILE ที่หมดอายุแล้ว
 */
const API = process.env.E2E_API_URL ?? 'http://localhost:3000/api/v1';

const idem = () => crypto.randomUUID();

async function apiLogin(
  request: APIRequestContext,
  employeeCode: string,
  password: string,
): Promise<string> {
  const res = await request.post(`${API}/auth/login`, {
    data: { employeeCode, password },
  });
  expect(res.ok(), `login ${employeeCode}: ${res.status()}`).toBeTruthy();
  return (await res.json()).accessToken as string;
}

const auth = (token: string, extra: Record<string, string> = {}) => ({
  headers: { Authorization: `Bearer ${token}`, ...extra },
});

/** สร้างห่อใหม่ (ADMIN) — คืน package id (เลขรันจาก backend) */
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
  // รองรับทั้งรูปแบบ single/array response
  const pkg = Array.isArray(body) ? body[0] : (body.packages?.[0] ?? body);
  return (pkg.id ?? pkg.packageId) as string;
}

/** เปิดรอบนึ่ง (PENDING) — คืน batch id */
async function createBatch(
  request: APIRequestContext,
  token: string,
): Promise<string> {
  const sterilizers = await (
    await request.get(`${API}/master-data/sterilizers`, auth(token))
  ).json();
  const res = await request.post(`${API}/batches`, {
    ...auth(token, { 'Idempotency-Key': idem() }),
    data: {
      sterilizerId: sterilizers[0].id,
      // สุ่มช่วงกว้าง — กันชนกันเมื่อหลาย project/worker เปิดรอบพร้อมกัน
      roundNo: crypto.randomInt(1, 1_000_000),
      startedAt: new Date().toISOString(),
    },
  });
  expect(res.ok(), `create batch: ${res.status()}`).toBeTruthy();
  return (await res.json()).id as string;
}

async function scan(
  request: APIRequestContext,
  token: string,
  path: 'in' | 'out' | 'return' | 'reprocess',
  data: Record<string, unknown>,
) {
  const res = await request.post(`${API}/scan/${path}`, {
    ...auth(token, { 'Idempotency-Key': idem() }),
    data,
  });
  expect(res.ok(), `scan/${path}: ${res.status()} ${await res.text()}`).toBeTruthy();
  const body = await res.json();
  return (Array.isArray(body) ? body : body.results) as Array<{
    packageId: string;
    success: boolean;
    error?: string;
  }>;
}

async function lookupStatus(
  request: APIRequestContext,
  token: string,
  id: string,
): Promise<string> {
  const res = await request.get(`${API}/packages/${id}`, auth(token));
  expect(res.ok()).toBeTruthy();
  return (await res.json()).status as string;
}

test.describe('package lifecycle (API จริง + Postgres จริง)', () => {
  test('เลขรันมาจาก backend ตามรูปแบบ {SET}-{YYYYMMDD}-{SEQ4}', async ({ request }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const id = await createPackage(request, admin);
    expect(id).toMatch(/^[A-Z0-9]+-\d{8}-\d{4}$/);
  });

  test('วงจรเต็ม: PACKED → เข้ารอบ → ผล CI/BI ผ่าน → STERILE+expiry → ISSUED → RETURNED → reprocess → PACKED', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const sup = await apiLogin(request, 'SUP001', 'Sup@1234');
    const pkg = await createPackage(request, admin);
    const batch = await createBatch(request, admin);

    // scan in → ผูกรอบ, ห่อยังเป็น PACKED (ยังไม่ฆ่าเชื้อ)
    const inRes = await scan(request, admin, 'in', { packageIds: [pkg], batchId: batch });
    expect(inRes[0].success, inRes[0].error).toBeTruthy();
    expect(await lookupStatus(request, admin, pkg)).toBe('PACKED');

    // SUPERVISOR บันทึกผลผ่าน → ทุกห่อในรอบเป็น STERILE + expiry จาก backend
    const result = await request.post(`${API}/batches/${batch}/result`, {
      ...auth(sup, { 'Idempotency-Key': idem() }),
      data: { ciResult: true, biResult: true },
    });
    expect(result.ok(), await result.text()).toBeTruthy();
    const after = await (await request.get(`${API}/packages/${pkg}`, auth(admin))).json();
    expect(after.status).toBe('STERILE');
    expect(after.expiryDate, 'backend ต้องคำนวณ expiry').toBeTruthy();

    // เบิกออก (ต้องมี department) → ISSUED
    const depts = await (await request.get(`${API}/departments`, auth(admin))).json();
    const internal = depts.find((d: { type: string }) => d.type !== 'external');
    const outRes = await scan(request, admin, 'out', {
      packageIds: [pkg],
      departmentId: internal.id,
    });
    expect(outRes[0].success, outRes[0].error).toBeTruthy();
    expect(await lookupStatus(request, admin, pkg)).toBe('ISSUED');

    // ส่งคืน (บันทึกแผนกต้นทาง) → RETURNED → reprocess → PACKED
    const retRes = await scan(request, admin, 'return', {
      packageIds: [pkg],
      departmentId: internal.id,
    });
    expect(retRes[0].success, retRes[0].error).toBeTruthy();
    expect(await lookupStatus(request, admin, pkg)).toBe('RETURNED');

    const reRes = await scan(request, admin, 'reprocess', { packageIds: [pkg] });
    expect(reRes[0].success, reRes[0].error).toBeTruthy();
    expect(await lookupStatus(request, admin, pkg)).toBe('PACKED');
  });

  test('batch fail → recall ผ่าน attempt history และยังเห็นหลัง batchId เปลี่ยน', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const sup = await apiLogin(request, 'SUP001', 'Sup@1234');
    const pkg = await createPackage(request, admin);
    const failBatch = await createBatch(request, admin);

    await scan(request, admin, 'in', { packageIds: [pkg], batchId: failBatch });
    const result = await request.post(`${API}/batches/${failBatch}/result`, {
      ...auth(sup, { 'Idempotency-Key': idem() }),
      data: { ciResult: false },
    });
    expect(result.ok(), await result.text()).toBeTruthy();

    // ห่อคง PACKED และถูกปลดจากรอบ
    const after = await (await request.get(`${API}/packages/${pkg}`, auth(admin))).json();
    expect(after.status).toBe('PACKED');
    expect(after.batchId ?? null).toBeNull();

    // รายงาน recall เห็นห่อนี้ (ผ่าน PackageBatchAttempt ไม่ใช่ batchId ปัจจุบัน)
    const recalls1 = await (await request.get(`${API}/reports/recalls`, auth(sup))).text();
    expect(recalls1, 'recall report ต้องมีห่อจากรอบที่ fail').toContain(pkg);

    // ผูกเข้ารอบใหม่ (batchId เปลี่ยน) → รายงาน recall ของรอบเก่าต้องยังเห็นห่อนี้
    const newBatch = await createBatch(request, admin);
    await scan(request, admin, 'in', { packageIds: [pkg], batchId: newBatch });
    const recalls2 = await (await request.get(`${API}/reports/recalls`, auth(sup))).text();
    expect(recalls2, 'ประวัติ recall ต้องไม่หายเมื่อ current batchId เปลี่ยน').toContain(pkg);
  });

  test('ห่อหมดอายุถูกบล็อกแบบ fail-closed (seed: DRESS-20260101-9999)', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const depts = await (await request.get(`${API}/departments`, auth(admin))).json();
    const internal = depts.find((d: { type: string }) => d.type !== 'external');

    const res = await scan(request, admin, 'out', {
      packageIds: ['DRESS-20260101-9999'],
      departmentId: internal.id,
    });
    expect(res[0].success, 'ห่อหมดอายุต้องเบิกไม่ได้').toBeFalsy();
    // fail-closed: สถานะห้ามกลายเป็น ISSUED
    expect(await lookupStatus(request, admin, 'DRESS-20260101-9999')).not.toBe('ISSUED');
  });

  test('scan out ไม่ส่ง department → 400 และ PACKED_OUT ใช้ได้เฉพาะ external', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');

    // ไม่มี departmentId → DTO validation ปัดตก
    const noDept = await request.post(`${API}/scan/out`, {
      ...auth(admin, { 'Idempotency-Key': idem() }),
      data: { packageIds: ['DELIV-20260101-0001'] },
    });
    expect(noDept.status()).toBe(400);

    // PACKED (ยังไม่ฆ่าเชื้อ) → ออกได้เฉพาะปลายทาง external
    const pkg = await createPackage(request, admin);
    const depts = await (await request.get(`${API}/departments`, auth(admin))).json();
    const internal = depts.find((d: { type: string }) => d.type !== 'external');
    const external = depts.find((d: { type: string }) => d.type === 'external');
    expect(external, 'seed ต้องมี external department').toBeTruthy();

    const toInternal = await scan(request, admin, 'out', {
      packageIds: [pkg],
      departmentId: internal.id,
    });
    expect(toInternal[0].success, 'PACKED → แผนกภายใน ต้องถูกปฏิเสธ').toBeFalsy();

    const toExternal = await scan(request, admin, 'out', {
      packageIds: [pkg],
      departmentId: external.id,
    });
    expect(toExternal[0].success, toExternal[0].error).toBeTruthy();
    expect(await lookupStatus(request, admin, pkg)).toBe('PACKED_OUT');
  });

  test('tag: สร้าง → ติดห่อ → กรองเจอ → ถอด → กรองไม่เจอ', async ({ request }) => {
    const sup = await apiLogin(request, 'SUP001', 'Sup@1234');
    const pkg = await createPackage(request, await apiLogin(request, 'ADMIN001', 'Admin@1234'));

    const tagRes = await request.post(`${API}/master-data/tags`, {
      ...auth(sup),
      data: { name: `e2e-${crypto.randomUUID().slice(0, 8)}`, colorHex: '#2F6BED' },
    });
    expect(tagRes.ok(), await tagRes.text()).toBeTruthy();
    const tag = await tagRes.json();

    const set = await request.put(`${API}/packages/${pkg}/tags`, {
      ...auth(sup),
      data: { tagIds: [tag.id] },
    });
    expect(set.ok(), await set.text()).toBeTruthy();

    const filtered = await (
      await request.get(`${API}/packages?tagId=${tag.id}`, auth(sup))
    ).text();
    expect(filtered).toContain(pkg);

    await request.put(`${API}/packages/${pkg}/tags`, { ...auth(sup), data: { tagIds: [] } });
    const empty = await (
      await request.get(`${API}/packages?tagId=${tag.id}`, auth(sup))
    ).text();
    expect(empty).not.toContain(pkg);
  });
});

test.describe('authz + idempotency + print job (API จริง)', () => {
  test('RBAC: CSSD บันทึกผลรอบนึ่ง/resolve print job ไม่ได้ (403)', async ({ request }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const staff = await apiLogin(request, 'STAFF001', 'Staff@1234');
    const batch = await createBatch(request, admin);

    const result = await request.post(`${API}/batches/${batch}/result`, {
      ...auth(staff, { 'Idempotency-Key': idem() }),
      data: { ciResult: true },
    });
    expect(result.status(), 'CSSD ต้องถูกปฏิเสธ (บันทึกผล = SUPERVISOR/ADMIN)').toBe(403);

    // RolesGuard ปัดตกก่อนถึง handler → 403 แม้ id ไม่มีจริง
    const resolve = await request.post(`${API}/print-jobs/some-id/resolve`, {
      ...auth(staff),
      data: { outcome: 'PRINTED' },
    });
    expect(resolve.status(), 'CSSD resolve ACK_UNKNOWN ไม่ได้').toBe(403);
  });

  test('Idempotency-Key เดิม → ไม่สร้าง print job ซ้ำ และ browser ACK เองไม่ได้', async ({
    request,
  }) => {
    const admin = await apiLogin(request, 'ADMIN001', 'Admin@1234');
    const pkg = await createPackage(request, admin);
    const key = idem();

    const first = await request.post(`${API}/print-jobs`, {
      ...auth(admin, { 'Idempotency-Key': key }),
      data: { packageId: pkg },
    });
    expect(first.ok(), await first.text()).toBeTruthy();
    const job1 = await first.json();

    // ยิงซ้ำด้วย key เดิม + payload เดิม → ได้งานเดิม (replay) ไม่สร้างใหม่
    const second = await request.post(`${API}/print-jobs`, {
      ...auth(admin, { 'Idempotency-Key': key }),
      data: { packageId: pkg },
    });
    expect(second.ok(), await second.text()).toBeTruthy();
    const job2 = await second.json();
    expect(job2.id).toBe(job1.id);

    // PWA/user JWT เรียก gateway ACK เอง → ต้องถูกปฏิเสธ (ต้องเป็น X-Gateway-Key เท่านั้น)
    const ack = await request.post(`${API}/print-gateway/jobs/${job1.id}/ack`, {
      ...auth(admin),
      data: {},
    });
    expect([401, 403]).toContain(ack.status());
  });

  test('token เก่าถูกปฏิเสธหลัง logout-all (session revocation)', async ({ request }) => {
    const token = await apiLogin(request, 'STAFF001', 'Staff@1234');
    // token ใช้ได้ก่อน revoke
    expect((await request.get(`${API}/packages`, auth(token))).ok()).toBeTruthy();

    const revoke = await request.post(`${API}/auth/logout-all`, auth(token));
    expect(revoke.ok()).toBeTruthy();

    const after = await request.get(`${API}/packages`, auth(token));
    expect(after.status(), 'token รุ่นเก่าต้องถูกปฏิเสธ').toBe(401);
  });
});
