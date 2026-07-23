# CSSD PWA — Browser E2E (Playwright)

Smoke + PWA checks สำหรับเวอร์ชันเว็บ/PWA ของแอป (Flutter web) — เป็น **scaffold**
พร้อมต่อยอด flow เต็ม (login → สแกน → พิมพ์) ตอนมี stack ครบ

> สถานะ: scaffold — ยังไม่ auto-start web server (Flutter web build หนัก + ต้องมี
> backend แยก) ต้องรัน stack เองก่อนตามด้านล่าง ยังไม่ผูกใน CI จนกว่าจะมี
> environment ที่ build web + backend ได้ครบ

## เตรียม

```bash
cd e2e
npm install
npm run install:browsers   # ติดตั้ง Chromium ให้ Playwright
```

## รัน stack ที่จะทดสอบ (เทอร์มินัลแยก)

1. Backend (จำเป็นสำหรับ flow ที่ต้อง login — smoke ปัจจุบันยังไม่ต้อง):
   ```bash
   npm run -w apps/api start:prod   # หรือ dev
   ```
2. Build + serve PWA:
   ```bash
   cd apps/mobile
   flutter build web --release
   # เสิร์ฟไฟล์ static (เลือกอย่างใดอย่างหนึ่ง)
   npx http-server build/web -p 8080        # หรือ
   python3 -m http.server 8080 -d build/web
   ```
   > กล้อง/PWA ต้องรันผ่าน **https** หรือ `localhost` (secure context) — localhost ใช้ได้

## รันเทส

```bash
cd e2e
E2E_BASE_URL=http://localhost:8080 npm test          # headless
E2E_BASE_URL=http://localhost:8080 npm run test:headed
npm run report                                        # เปิดรายงานล่าสุด
```

## ครอบอะไรบ้าง (ปัจจุบัน)

- PWA โหลดขึ้น + Flutter engine bootstrap สำเร็จ (ไม่มี console error ร้ายแรง)
- มี PWA manifest ที่ถูกต้อง (installable)
- ลงทะเบียน service worker (offline shell / installable)

## TODO (ต่อยอด)

- [ ] login flow (ใส่ credential test → เข้าหน้าหลัก)
- [ ] สแกน (mock QR / manual entry) → เห็นผลรายการ
- [ ] สร้าง print job → เห็นสถานะใน queue
- [ ] ผูกเข้า CI พร้อม service backend + Postgres + build web (matrix)
