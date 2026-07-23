import { test, expect } from '@playwright/test';

/**
 * Smoke + PWA checks — ยืนยันว่า PWA โหลดขึ้น, เป็น PWA จริง (manifest + service worker),
 * และไม่มี console error ร้ายแรงตอนบูต ออกแบบให้ทนต่อการเปลี่ยน UI (ไม่ผูกกับ selector
 * เฉพาะเจาะจงมาก) — เป็นฐานให้ต่อยอด flow เต็ม (login → สแกน → พิมพ์) ตอนมี stack ครบ
 */

test('PWA โหลดขึ้นและ Flutter bootstrap สำเร็จ', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });

  await page.goto('/');
  // Flutter web ใส่ <flt-glass-pane>/<flutter-view> เมื่อ engine บูตเสร็จ
  await expect(page.locator('flutter-view, flt-glass-pane')).toBeVisible({
    timeout: 20_000,
  });

  // ต้องไม่มี error ร้ายแรงจากการโหลด (กรอง noise ที่ไม่เกี่ยวข้อง เช่น favicon/font)
  const fatal = errors.filter(
    (e) => !/favicon|manifest\.json 404|font|Tracking Prevention/i.test(e),
  );
  expect(fatal, `console errors:\n${fatal.join('\n')}`).toHaveLength(0);
});

test('มี PWA manifest ที่ถูกต้อง (installable)', async ({ page, request }) => {
  await page.goto('/');
  const href = await page
    .locator('link[rel="manifest"]')
    .getAttribute('href', { timeout: 15_000 });
  expect(href, 'ต้องมี <link rel="manifest">').toBeTruthy();

  const res = await request.get(new URL(href!, page.url()).toString());
  expect(res.ok()).toBeTruthy();
  const manifest = await res.json();
  expect(manifest.name ?? manifest.short_name).toBeTruthy();
  expect(Array.isArray(manifest.icons) && manifest.icons.length).toBeTruthy();
});

test('ลงทะเบียน service worker (offline shell / installable)', async ({ page }) => {
  await page.goto('/');
  const hasSW = await page.evaluate(
    () => 'serviceWorker' in navigator,
  );
  expect(hasSW, 'เบราว์เซอร์ต้องรองรับ service worker').toBeTruthy();
  // flutter_service_worker.js ถูก register โดย flutter bootstrap — รอ active
  const registered = await page
    .waitForFunction(
      () => navigator.serviceWorker.getRegistrations().then((r) => r.length > 0),
      { timeout: 15_000 },
    )
    .then(() => true)
    .catch(() => false);
  expect(registered, 'ควรมี service worker ลงทะเบียน (PWA)').toBeTruthy();
});
