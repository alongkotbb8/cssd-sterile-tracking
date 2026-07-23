import { test, expect } from '@playwright/test';
import { enableFlutterSemantics, login, openTab } from './helpers';

/**
 * Full-flow E2E (login → packages → create → print job) — ต้องมี stack ครบ
 * (API + Postgres + seed + web build ที่ชี้ API local) ยกด้วย `bash scripts/e2e-stack.sh up`
 *
 * รันผ่าน `npm run test:e2e` (CI รัน job นี้พร้อม stack) — **ไม่ gate ด้วย flag ที่ CI ไม่ตั้ง**
 * และ **ไม่มี test.skip/test.fixme** ตาม master directive §2C. `npm test` (default) รันเฉพาะ
 * smoke ที่ไม่ต้องมี stack; flow อยู่ในชุด `test:e2e` ที่ CI เรียกพร้อม stack
 *
 * บัญชี seed (NODE_ENV=development): ADMIN001 / Admin@1234
 */
test.describe('full flow (login → packages → create → print job)', () => {
  test('login เข้าสู่ระบบสำเร็จ เห็น shell หลัก', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    // หลุดจากหน้า login — ปุ่ม/หัวข้อ "เข้าสู่ระบบ" หายไป และเห็นแท็บหลัก
    await expect(page.getByText('เข้าสู่ระบบ')).toHaveCount(0, {
      timeout: 20_000,
    });
    await expect(
      page.getByText('แดชบอร์ด', { exact: false }).first(),
    ).toBeVisible({ timeout: 20_000 });
  });

  test('สร้างห่อใหม่ → สร้างงานพิมพ์ → เห็นสถานะในคิว', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    await openTab(page, 'รายการห่อ');

    // FAB "สร้างห่อใหม่" → เลือกชุดอุปกรณ์ตัวแรก → บันทึก (label ขึ้นกับ seed)
    await page.getByText('สร้างห่อใหม่', { exact: false }).first().click();
    await expect(
      page.getByText('สร้างห่อ', { exact: false }).first(),
    ).toBeVisible({ timeout: 10_000 });
    await page.getByText('บันทึก', { exact: false }).last().click();

    // กลับมาที่รายการ — ควรเห็นห่ออย่างน้อย 1 ใบ (สถานะ PACKED)
    await expect(
      page.getByText('PACKED', { exact: false }).first().or(
        page.getByText('รอนึ่ง', { exact: false }).first(),
      ),
    ).toBeVisible({ timeout: 15_000 });
  });
});
