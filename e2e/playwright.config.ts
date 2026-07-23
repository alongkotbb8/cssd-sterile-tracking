import { defineConfig, devices } from '@playwright/test';

/**
 * E2E ยิงไปที่ PWA ที่ build + serve ไว้แล้ว (Flutter web) — ตั้ง base URL ผ่าน
 * env `E2E_BASE_URL` (ค่าเริ่มต้น http://localhost:8080) ดูวิธีรันใน README.md
 *
 * หมายเหตุ: ยังไม่ auto-start web server (Flutter web build หนัก + ต้องมี backend
 * แยก) — รัน stack เองก่อนแล้วค่อย `npm test` (ดู README)
 */
const baseURL = process.env.E2E_BASE_URL ?? 'http://localhost:8080';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // มือถือ (PWA เป้าหมายหลัก) — เปิดใช้เมื่อ smoke desktop ผ่านแล้ว
    { name: 'mobile-chrome', use: { ...devices['Pixel 7'] } },
  ],
});
