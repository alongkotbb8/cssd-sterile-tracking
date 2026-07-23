import { test, expect } from '@playwright/test';
import { byLabel, login, openTab } from './helpers';

/**
 * Full-flow E2E (login → packages → create) — ต้องมี stack ครบ
 * (API + Postgres + seed + web build ที่ชี้ API local) ยกด้วย `bash scripts/e2e-stack.sh up`
 *
 * รันผ่าน `npm run test:e2e` (CI รัน job นี้พร้อม stack) — **ไม่ gate ด้วย flag ที่ CI ไม่ตั้ง**
 * และ **ไม่มี test.skip/test.fixme** ตาม master directive §2C. `npm test` (default) รันเฉพาะ
 * smoke ที่ไม่ต้องมี stack; flow อยู่ในชุด `test:e2e` ที่ CI เรียกพร้อม stack
 *
 * selector ใช้ label จริงจาก ARB (lib/l10n/app_th.arb) ผ่าน byLabel (aria-label ของ
 * Flutter semantics): แท็บ = navPackages "รายการ", FAB = pkgCreateNew "สร้างห่อใหม่",
 * ปุ่มบันทึก = cpSaveOne "บันทึก + ออกเลขรัน", สำเร็จ = cpCreatedOne "สร้างห่อสำเร็จ",
 * สถานะ = statusPacked "แพ็กแล้ว"
 *
 * บัญชี seed (NODE_ENV=development): ADMIN001 / Admin@1234
 */
test.describe('full flow (login → packages → create)', () => {
  test('login เข้าสู่ระบบสำเร็จ เห็น shell หลัก', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    // login() รอช่องรหัสผ่านหายแล้ว — ยืนยันต่อว่าเห็นแท็บหลัก (แดชบอร์ด)
    await expect(byLabel(page, 'แดชบอร์ด').first()).toBeVisible({
      timeout: 20_000,
    });
  });

  test('สร้างห่อใหม่ → เห็นผลสำเร็จ/สถานะแพ็กแล้วในรายการ', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    await openTab(page, 'รายการ');

    // FAB "สร้างห่อใหม่" → sheet เปิด → เลือกชุดอุปกรณ์ก่อน (ปุ่มบันทึก disabled
    // จนกว่าจะเลือก template — พิสูจน์จาก trace CI: aria-disabled="true")
    await byLabel(page, 'สร้างห่อใหม่').first().click();
    await expect(byLabel(page, 'ชุดถอนฟัน').first()).toBeVisible({
      timeout: 10_000,
    });
    await byLabel(page, 'ชุดถอนฟัน').first().click();
    await byLabel(page, 'บันทึก').last().click();

    // เห็น snackbar สำเร็จ หรือสถานะ "แพ็กแล้ว" ของห่อที่เพิ่งสร้างในรายการ
    await expect(
      byLabel(page, 'สร้างห่อสำเร็จ').first().or(byLabel(page, 'แพ็กแล้ว').first()),
    ).toBeVisible({ timeout: 20_000 });
  });
});
