# CSSD PWA — Browser E2E (Playwright)

Smoke + PWA checks สำหรับเวอร์ชันเว็บ/PWA ของแอป (Flutter web) — เป็น **scaffold**
พร้อมต่อยอด flow เต็ม (login → สแกน → พิมพ์) ตอนมี stack ครบ

## ยก stack อัตโนมัติ (แนะนำ)

```bash
# จาก repo root — ยก Postgres (docker compose) + migrate/seed + API + build/serve web
bash scripts/e2e-stack.sh up
# ... รันเทส (ดูด้านล่าง) ...
bash scripts/e2e-stack.sh down   # หยุด + ลบ container
```
ต้องมี: docker, Node 20, Flutter (stable) ; script ใช้บัญชี seed `ADMIN001 / Admin@1234`

## รันเทส

```bash
cd e2e
npm install
npm run install:browsers                              # ติดตั้ง Chromium + WebKit

E2E_BASE_URL=http://localhost:8080 npm test           # smoke (default) ทุก project
E2E_BASE_URL=http://localhost:8080 E2E_FLOW=1 npm test # smoke + full flow
E2E_BASE_URL=http://localhost:8080 npm run test:webkit # เฉพาะ Safari/WebKit
E2E_BASE_URL=http://localhost:8080 npm run test:headed
npm run report                                        # เปิดรายงานล่าสุด
```

> PWA ต้องรันผ่าน `localhost`/https (secure context) — localhost ใช้ได้

**Projects (Playwright):** `chromium` (Desktop Chrome), `mobile-chrome` (Pixel 7),
`webkit` (Desktop Safari), `mobile-safari` (iPhone 14) — ตาม master directive §2D/§4B.1.15.
WebKit ตรวจ compatibility ของ Safari (UI/error/fallback) เท่านั้น; **กล้อง QR จริงบน iPhone/iPad
ต้องทดสอบบนอุปกรณ์ Apple จริงใน Gate 4** (§4A/§4B.1.18 — browser automation ไม่พิสูจน์ permission/
camera driver/lifecycle ของอุปกรณ์จริง)

## ครอบอะไรบ้าง

**smoke** (รันเสมอ + ใน CI):
- PWA โหลด + Flutter bootstrap (ไม่มี console error ร้ายแรง)
- PWA manifest ถูกต้อง (installable) + service worker ลงทะเบียน

**flow** (`E2E_FLOW=1` เท่านั้น — ยัง **ต้อง validate selector กับ build จริง**):
- login (ADMIN001) เข้าสู่ระบบ → เห็น shell หลัก
- สร้างห่อ → สร้างงานพิมพ์ → เห็นสถานะในคิว
- (fixme) สแกน manual entry → reprocess ห่อที่ส่งคืน

> Flutter web วาดด้วย canvas — E2E ต้องเปิด semantics ก่อน (ดู `tests/helpers.ts`)
> flow ยัง gate ไว้เพราะยังไม่ได้ verify selector กับ build จริง (ไม่มี browser/stack
> ในสภาพแวดล้อมพัฒนา) — CI จึงรันเฉพาะ smoke

## CI

`.github/workflows/ci.yml` job `e2e`: ยก Postgres service + API (node) + build/serve web
(`--dart-define=CSSD_API_URL=http://localhost:3000`) แล้วรัน **smoke** (flow gate ไว้)
