import { test, expect } from '@playwright/test';
import { byLabel, login, openTab, typeInto } from './helpers';

/**
 * QR Scanner — Safari/WebKit compatibility + manual-entry fallback (master directive §4B.1)
 *
 * ทดสอบพฤติกรรมที่ **ไม่ต้องใช้กล้องจริง** จึงรันได้ทั้ง chromium และ webkit:
 * - manual entry ใช้ได้เสมอแม้กล้องไม่พร้อม (§4B.1.9)
 * - ตรวจรูปแบบ QR ก่อนยิง API — รับเฉพาะ package_id (§4B.1.10)
 * - กรอกเลขแล้ว **ไม่ auto-submit** (§4B.1.12) — เข้ารายการรอผู้ใช้ยืนยัน
 *
 * selector ใช้ label จริงจาก ARB: แท็บ = navScan "สแกน", ปุ่ม = scanManualTooltip
 * "พิมพ์เลขห่อเอง", ยืนยัน dialog = commonAdd "เพิ่ม",
 * validation = scanManualCharset "ใช้ได้เฉพาะตัวอักษร ตัวเลข และขีด (-)"
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

    // ปุ่มพิมพ์เลขเองต้องมีเสมอ (fallback เมื่อกล้องใช้ไม่ได้บน Safari — §4B.1.9)
    const manualBtn = byLabel(page, 'พิมพ์เลขห่อเอง').first();
    await expect(manualBtn).toBeVisible({ timeout: 20_000 });
    await manualBtn.click();

    // dialog เปิด — กรอกค่าผิดรูปแบบ → ต้องขึ้น validation ไม่รับเข้ารายการ
    // (typeInto = click+keyboard เพราะ fill() ไม่ส่งค่าถึง Flutter controller)
    const dialogInput = page.locator('flt-semantics input, input').last();
    await dialogInput.waitFor({ state: 'attached', timeout: 10_000 });
    await typeInto(page, dialogInput, 'bad qr https://evil');
    await byLabel(page, 'เพิ่ม').last().click();
    await expect(byLabel(page, 'ใช้ได้เฉพาะตัวอักษร').first()).toBeVisible({
      timeout: 8_000,
    });

    // แก้เป็นเลขห่อรูปแบบถูกต้อง → ถูกเพิ่มเข้ารายการ (ไม่ auto-submit — §4B.1.12)
    await typeInto(page, dialogInput, 'DELIV-20260101-0001');
    await byLabel(page, 'เพิ่ม').last().click();
    await expect(byLabel(page, 'DELIV-20260101-0001').first()).toBeVisible({
      timeout: 10_000,
    });
  });
});
