import { test, expect } from '@playwright/test';
import { byLabel, enableFlutterSemantics, login, typeInto } from './helpers';

/**
 * Authentication UI E2E (master directive §2B Authentication)
 * - login ผิด → เห็นข้อความ error (i18n errLoginInvalid)
 * - account lockout: ใส่รหัสผิดซ้ำ → เห็นข้อความบัญชีถูกล็อก (ใช้บัญชี LOCK001
 *   ที่ seed แยกไว้ ไม่กระทบบัญชีที่เทสอื่นใช้; ข้าม project ก็ยัง assert ได้เพราะ
 *   เมื่อล็อกแล้วทุก attempt ตอบข้อความล็อกทันที)
 * - logout ออกจากเครื่องนี้ → กลับหน้า login
 * - refresh/reload ระหว่างใช้งาน → session อยู่ครบ ไม่เด้งกลับ login (§2B Chrome/PWA)
 */

async function fillLogin(page: import('@playwright/test').Page, code: string, pw: string) {
  const inputs = page.locator('flt-semantics input, input');
  await inputs.nth(0).waitFor({ state: 'attached', timeout: 15_000 });
  await typeInto(page, inputs.nth(0), code);
  await typeInto(page, inputs.nth(1), pw);
  await byLabel(page, 'เข้าสู่ระบบ').last().click();
}

test.describe('authentication', () => {
  test('login ผิด → แสดง error และยังอยู่หน้า login', async ({ page }) => {
    await page.goto('/');
    await enableFlutterSemantics(page);
    // ใช้รหัสพนักงานที่ไม่มีจริง — ข้อความ error เดียวกัน (timing-safe) และไม่ไป
    // เพิ่ม failedLoginCount ของบัญชีจริงที่เทสอื่นใช้อยู่
    await fillLogin(page, 'NOSUCH999', 'wrong-password');
    await expect(byLabel(page, 'ไม่ถูกต้อง').first()).toBeVisible({
      timeout: 15_000,
    });
    // ยังอยู่หน้า login (ช่องรหัสผ่านยังอยู่)
    await expect(byLabel(page, 'รหัสผ่าน').first()).toBeVisible();
  });

  test('account lockout: รหัสผิดซ้ำหลายครั้ง → บัญชีถูกล็อกชั่วคราว', async ({ page }) => {
    await page.goto('/');
    await enableFlutterSemantics(page);
    // เกณฑ์ backend = 5 ครั้ง; ยิง 6 ครั้งแล้วรอข้อความ "ถูกล็อก" (ถ้าโดนล็อกจาก
    // project อื่นก่อนแล้ว attempt แรก ๆ ก็ตอบข้อความล็อกเลย — assertion เดียวกัน)
    for (let i = 0; i < 6; i++) {
      await fillLogin(page, 'LOCK001', `wrong-${i}`);
      const locked = await byLabel(page, 'ถูกล็อก')
        .first()
        .isVisible()
        .catch(() => false);
      if (locked) break;
      await expect(byLabel(page, 'ไม่ถูกต้อง').or(byLabel(page, 'ถูกล็อก')).first())
        .toBeVisible({ timeout: 15_000 });
    }
    await expect(byLabel(page, 'ถูกล็อก').first()).toBeVisible({ timeout: 15_000 });
  });

  test('logout เครื่องนี้ → กลับหน้า login', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    await byLabel(page, 'ตั้งค่า').first().click();
    // ปุ่ม "ออกจากระบบ" (เครื่องนี้) → dialog ยืนยัน → กดยืนยัน
    await byLabel(page, 'ออกจากระบบ').first().scrollIntoViewIfNeeded().catch(() => {});
    await byLabel(page, 'ออกจากระบบ').first().click();
    await byLabel(page, 'ออกจากระบบ').last().click();
    // กลับหน้า login (ช่องรหัสผ่านกลับมา)
    await expect(byLabel(page, 'รหัสผ่าน').first()).toBeVisible({ timeout: 20_000 });
  });

  test('reload ระหว่างใช้งาน → session คงอยู่ (ไม่เด้งกลับ login)', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    await expect(byLabel(page, 'แดชบอร์ด').first()).toBeVisible({ timeout: 20_000 });

    await page.reload();
    await enableFlutterSemantics(page);
    // ยังเห็น shell หลัก และไม่กลับไปหน้า login
    await expect(byLabel(page, 'แดชบอร์ด').first()).toBeVisible({ timeout: 20_000 });
    await expect(byLabel(page, 'รหัสผ่าน')).toHaveCount(0, { timeout: 10_000 });
  });
});
