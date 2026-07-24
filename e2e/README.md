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

E2E_BASE_URL=http://localhost:8080 npm test            # smoke เท่านั้น (ไม่ต้องมี stack ครบ)
E2E_BASE_URL=http://localhost:8080 npm run test:e2e    # ทุก spec (ต้องมี stack จาก e2e-stack.sh)
E2E_BASE_URL=http://localhost:8080 npm run test:webkit # เฉพาะ Safari/WebKit
E2E_BASE_URL=http://localhost:8080 npm run test:headed
npm run report                                         # เปิดรายงานล่าสุด
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

**spec เต็ม (รันใน CI ทุกครั้ง — ไม่มี flag gate, ไม่มี test.skip/fixme):**
- `flow.spec` — login (ADMIN001) → shell หลัก, สร้างห่อผ่าน UI
- `auth.spec` — login ผิด, lockout (LOCK001), logout, reload คง session
- `scanner.spec` — camera error UI (headless), manual entry, charset validation
- `lifecycle.spec` — API+PG จริง: running number, batch pass/fail+recall, expired
  fail-closed, scan out/return/reprocess, tags, RBAC, idempotency, browser ห้าม ACK
- `browser-print.spec` — โหมด BROWSER_DIALOG (MACOS_BROWSER_PRINT_DIRECTIVE.md §14):
  UI เปิด sheet + preview + DIALOG_OPENED ก่อน print + refresh ไม่เปิดซ้ำ; API state
  machine (CREATED→DIALOG_OPENED→USER_CONFIRMED/CANCELLED), idempotency, reprint
  reason บังคับ, history แยก original/reprint, **ไม่แตะ Gateway job / Package.printedAt**

> Flutter web วาดด้วย canvas — E2E ต้องเปิด semantics ก่อน (ดู `tests/helpers.ts`)

## CI

`.github/workflows/ci.yml` job `e2e`: ยก Postgres service + API (node) + build/serve web
(`--dart-define=CSSD_API_URL=http://localhost:3000 --dart-define=CSSD_BROWSER_PRINT_ENABLED=true`)
แล้วรัน **ทุก spec × 3 รอบติด × 4 projects** (chromium, mobile-chrome, webkit, mobile-safari)
