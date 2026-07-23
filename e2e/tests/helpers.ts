import { Page, expect } from '@playwright/test';

/**
 * Flutter web วาดด้วย canvas — ต้องเปิด semantics ก่อน DOM จึงจะมี element ให้
 * Playwright โต้ตอบ (aria-label = label ของ widget) โดยคลิกปุ่มซ่อน "Enable accessibility"
 * ที่ Flutter ใส่ไว้ตอนบูต
 */
export async function enableFlutterSemantics(page: Page): Promise<void> {
  await expect(page.locator('flutter-view, flt-glass-pane')).toBeVisible({
    timeout: 20_000,
  });
  const placeholder = page.locator(
    'flt-semantics-placeholder, [aria-label="Enable accessibility"]',
  );
  try {
    await placeholder.first().click({ timeout: 5_000 });
  } catch {
    // บาง build เปิด semantics อัตโนมัติเมื่อ detect ว่าเป็น automation แล้ว — ข้ามได้
  }
  // รอ semantics host โผล่
  await page.locator('flt-semantics, flt-semantics-host').first().waitFor({
    timeout: 10_000,
  });
}

/** login ด้วย semantics (label ไทยจากหน้า login) */
export async function login(
  page: Page,
  employeeCode: string,
  password: string,
): Promise<void> {
  await page.goto('/');
  await enableFlutterSemantics(page);

  // TextField ของ Flutter web สร้าง <input> ใน flt-semantics — จับตามลำดับ/label
  const inputs = page.locator('flt-semantics input, input');
  await inputs.nth(0).fill(employeeCode);
  await inputs.nth(1).fill(password);

  await page.getByText('เข้าสู่ระบบ', { exact: false }).last().click();
  // รอหลุดจากหน้า login (ปุ่ม submit หาย)
  await expect(page.getByText('เข้าสู่ระบบ')).toHaveCount(0, { timeout: 20_000 });
}

/** เปิดแท็บใน bottom navigation ด้วย label ไทย (semantics) */
export async function openTab(page: Page, label: string): Promise<void> {
  await page.getByText(label, { exact: false }).first().click();
}
