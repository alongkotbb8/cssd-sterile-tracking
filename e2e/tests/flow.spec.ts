import { test, expect } from '@playwright/test';
import { enableFlutterSemantics, login } from './helpers';

/**
 * Full-flow E2E — ต้องมี stack ครบ (API + Postgres + seed + web build ที่ชี้ API local)
 * ยกด้วย `bash scripts/e2e-stack.sh up` แล้วรันด้วย `E2E_FLOW=1`
 *
 * gate ด้วย E2E_FLOW: การขับ Flutter web ผ่าน semantics ยัง **ต้องปรับ selector กับ build
 * จริง** (ยังไม่ verify ในสภาพแวดล้อมพัฒนา — ไม่มี browser/stack) จึงไม่รันใน CI default
 * (smoke.spec รันเสมอ) เปิดเมื่อพร้อม validate: `E2E_FLOW=1`
 *
 * บัญชี seed (NODE_ENV=development): ADMIN001 / Admin@1234
 */
const flowEnabled = !!process.env.E2E_FLOW;

test.describe('full flow (login → packages → create → print job)', () => {
  test.skip(!flowEnabled, 'ตั้ง E2E_FLOW=1 + ยก stack ก่อน (scripts/e2e-stack.sh up)');

  test('login เข้าสู่ระบบสำเร็จ เห็น shell หลัก', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    // หลัง login เห็นแท็บหลัก (เช่น "รายการ"/"สแกน") — ยืนยันหลุดจากหน้า login
    await expect(page.getByText('เข้าสู่ระบบ')).toHaveCount(0, {
      timeout: 15_000,
    });
  });

  test('สร้างห่อใหม่ → สร้างงานพิมพ์ → เห็นสถานะในคิว', async ({ page }) => {
    await login(page, 'ADMIN001', 'Admin@1234');
    await enableFlutterSemantics(page);

    // ไปหน้ารายการห่อ → กด "สร้างห่อใหม่" (FAB) → เลือก template → บันทึก
    await page.getByText('รายการ', { exact: false }).first().click();
    await page.getByText('สร้างห่อใหม่', { exact: false }).first().click();
    // เลือกชุดอุปกรณ์ตัวแรก + บันทึก (label ขึ้นกับ seed/master data)
    await page.getByText('บันทึก', { exact: false }).last().click();

    // เปิดห่อที่เพิ่งสร้าง → สั่งพิมพ์ → งานพิมพ์ถูกสร้าง (QUEUED/รอพิมพ์)
    // NOTE: selector ปลายทางต้อง validate กับ build จริง (Flutter semantics)
  });

  // scan → reprocess ต้องใช้กล้อง/QR ซึ่งไม่เสถียรใน headless — ใช้ manual entry แทน
  // ตอน validate flow จริง (ปุ่ม "พิมพ์เลขห่อเอง" ในหน้าสแกน) — เปิดเมื่อ selector พร้อม
  test.fixme('สแกน (manual entry) → reprocess ห่อที่ส่งคืน', async () => {
    // 1) โหมด "ส่งคืน": manual entry เลขห่อ ISSUED → RETURNED
    // 2) โหมด "Reprocess": manual entry เลขห่อ RETURNED → PACKED
    // ต้อง seed ห่อสถานะ ISSUED ไว้ก่อน (ผ่าน API) แล้วค่อยเดินผ่าน UI
  });
});
