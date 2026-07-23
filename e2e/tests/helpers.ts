import { Locator, Page, expect } from '@playwright/test';

/**
 * Flutter web วาดด้วย canvas — ต้องเปิด semantics ก่อน DOM จึงจะมี element ให้
 * Playwright โต้ตอบ (aria-label = label ของ widget) โดยกดปุ่มซ่อน
 * "Enable accessibility" (flt-semantics-placeholder) ที่ Flutter ใส่ไว้ตอนบูต
 *
 * ปุ่มนี้เป็น element ซ่อน (ขนาด 0/นอกจอ) — คลิกปกติไม่ผ่าน actionability check
 * ต้อง `force: true` และ fallback เป็น dispatch MouseEvent ตรง ๆ
 */
export async function enableFlutterSemantics(page: Page): Promise<void> {
  // Flutter รุ่นใหม่ render ทั้ง <flutter-view> และ <flt-glass-pane> — ใช้ .first()
  // กัน strict mode violation (locator เจอ 2 elements)
  await expect(page.locator('flutter-view, flt-glass-pane').first()).toBeVisible({
    timeout: 20_000,
  });
  const placeholder = page
    .locator('flt-semantics-placeholder, [aria-label="Enable accessibility"]')
    .first();
  try {
    await placeholder.click({ force: true, timeout: 5_000 });
  } catch {
    // click ไม่ผ่าน (element ซ่อนสนิท) → ยิง event ตรง ๆ; ถ้าไม่มี placeholder
    // (บาง build เปิด semantics อัตโนมัติ) ก็ข้ามได้
    await placeholder
      .evaluate((el) =>
        el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })),
      )
      .catch(() => {});
  }
  // รอ semantics tree ถูกสร้างจริง (มี node ลูก) — ตัว host มีอยู่เสมอแต่ถูกซ่อน
  // จึงต้องรอแบบ attached ไม่ใช่ visible
  await page
    .locator('flt-semantics-host flt-semantics, flt-semantics')
    .first()
    .waitFor({ state: 'attached', timeout: 15_000 });
}

/**
 * จับ element จากข้อความ — Flutter semantics ใส่ label เป็น `aria-label`
 * (ไม่ใช่ text content เสมอไป) จึงต้อง match ทั้งสองแบบ
 */
export function byLabel(page: Page, text: string): Locator {
  return page
    .locator(`[aria-label*="${text}"]`)
    .or(page.getByText(text, { exact: false }));
}

/** login ด้วย semantics (label ไทยจากหน้า login) */
export async function login(
  page: Page,
  employeeCode: string,
  password: string,
): Promise<void> {
  await page.goto('/');
  await enableFlutterSemantics(page);

  // TextField ของ Flutter web สร้าง <input> ใน flt-semantics — จับตามลำดับ
  const inputs = page.locator('flt-semantics input, input');
  await inputs.nth(0).waitFor({ state: 'attached', timeout: 15_000 });
  await inputs.nth(0).fill(employeeCode);
  await inputs.nth(1).fill(password);

  await byLabel(page, 'เข้าสู่ระบบ').last().click();
  // รอหลุดจากหน้า login — ช่องรหัสผ่านหายไป (unique ต่อหน้า login;
  // คำว่า "เข้าสู่ระบบ" อาจโผล่ที่อื่นเช่น snackbar/log จึงไม่ใช้เช็ค count 0)
  await expect(byLabel(page, 'รหัสผ่าน')).toHaveCount(0, { timeout: 20_000 });
}

/** เปิดแท็บใน bottom navigation ด้วย label ไทย (semantics) */
export async function openTab(page: Page, label: string): Promise<void> {
  await byLabel(page, label).first().click();
}
