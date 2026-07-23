import { test, expect } from '@playwright/test';
import { login, openTab } from './helpers';

/**
 * QR Scanner — Safari/WebKit compatibility + manual-entry fallback (master directive §4B.1)
 *
 * ทดสอบพฤติกรรมที่ **ไม่ต้องใช้กล้องจริง** จึงรันได้ทั้ง chromium และ webkit:
 * - manual entry ใช้ได้เสมอแม้กล้องไม่พร้อม (§4B.1.9)
 * - ตรวจรูปแบบ QR ก่อนยิง API — รับเฉพาะ package_id (§4B.1.10)
 * - อ่าน QR/กรอกเลขแล้ว **ไม่ auto-submit** (§4B.1.12) — เข้ารายการรอผู้ใช้ยืนยัน
 *
 * หมายเหตุ (§4B.1.17-18): นี่คือการตรวจ UI/error/fallback เท่านั้น — **ไม่ใช่**
 * hardware camera verification; กล้อง QR จริงบน iPhone/iPad ต้องตรวจใน Gate 4 บนอุปกรณ์จริง
 */
test.describe('QR scanner (WebKit compat + manual fallback)', () => {
  test('manual entry: ปฏิเสธ QR ผิดรูปแบบ, รับเลขห่อที่ถูกต้อง (ไม่ auto-submit)', async ({
    page,
  }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    await openTab(page, 'สแกน');

    // ปุ่มพิมพ์เลขเองต้องมีเสมอ (fallback เมื่อกล้องใช้ไม่ได้บน Safari)
    const manualBtn = page
      .getByText('พิมพ์เลขห่อเอง', { exact: false })
      .first()
      .or(page.locator('[aria-label*="พิมพ์เลข"]').first());
    await expect(manualBtn).toBeVisible({ timeout: 20_000 });
    await manualBtn.click();

    // กรอก QR ผิดรูปแบบ → ต้องขึ้น error ตรวจอักขระ ไม่เพิ่มเข้ารายการ
    const dialogInput = page.locator('flt-semantics input, input').last();
    await dialogInput.fill('bad qr link https://evil');
    await page.getByText('เพิ่ม', { exact: false }).last().click();
    await expect(
      page.getByText('ใช้ได้เฉพาะตัวอักษร', { exact: false }).first(),
    ).toBeVisible({ timeout: 8_000 });

    // แก้เป็นเลขห่อที่ถูกต้อง → เพิ่มเข้ารายการ (ยังไม่ยืนยัน = ไม่ auto-submit)
    await dialogInput.fill('DELIV-20260101-0001');
    await page.getByText('เพิ่ม', { exact: false }).last().click();
    await expect(
      page.getByText('DELIV-20260101-0001', { exact: false }).first(),
    ).toBeVisible({ timeout: 10_000 });
  });
});
