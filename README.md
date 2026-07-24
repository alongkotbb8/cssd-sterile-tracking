# CSSD Sterile Instrument Tracking System

ระบบตามรอยอุปกรณ์หัตถการปลอดเชื้อ | PWA (Flutter Web, online-only — Chrome + Safari iOS) + NestJS + PostgreSQL + Print Gateway → Xprinter XP-420B

> ⚠️ **Single source of truth = [CSSD_MASTER_EXECUTION_DIRECTIVE.md](./CSSD_MASTER_EXECUTION_DIRECTIVE.md)** — online-only, ไม่มี offline/Bluetooth/Zebra ใน scope
> ดูสถานะความคืบหน้าล่าสุด/checklist เฟส 1-3 ที่ [PROGRESS.md](./PROGRESS.md) — อัปเดตทุกครั้งที่มีการแก้ไข

## Structure

```
cssd/
├── apps/
│   ├── api/          NestJS backend + Prisma
│   └── mobile/       Flutter app — Chrome PWA (หลัก, online-only) + build Android/iOS ได้
├── packages/
│   └── shared/       enums, helpers, state machine constants
├── docs/             SRS + diagrams
├── docker-compose.yml  PostgreSQL local dev
└── CLAUDE.md         domain rules + coding conventions
```

## Quick Start

### 1. Database
```bash
docker compose up -d
```

### 2. API
```bash
cp apps/api/.env.example apps/api/.env
cd apps/api
yarn install
yarn prisma:migrate    # run migrations
yarn prisma:seed       # seed departments, templates, users
yarn dev               # http://localhost:3000
                       # Swagger → http://localhost:3000/api/docs
```

### 3. Flutter App
```bash
cd apps/mobile
flutter pub get
flutter run
```

## Default seed accounts
| role | employeeCode | password |
|------|-------------|----------|
| ADMIN | ADMIN001 | Admin@1234 |
| SUPERVISOR | SUP001 | Sup@1234 |
| CSSD staff | STAFF001 | Staff@1234 |

## Key API endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/v1/auth/login | เข้าสู่ระบบ |
| POST | /api/v1/packages | สร้างห่อ + ออกเลขรัน |
| GET  | /api/v1/packages/:id | ดูรายละเอียด + ประวัติ |
| POST | /api/v1/scan/in | สแกนเข้าคลัง (batch) |
| POST | /api/v1/scan/out | สแกนเบิกออก + ตรวจหมดอายุ |
| POST | /api/v1/scan/return | สแกนรับของส่งคืน |
| GET  | /api/v1/scan/lookup/:id | ดูข้อมูลจาก QR |
| POST | /api/v1/batches | เปิดรอบนึ่ง |
| POST | /api/v1/batches/:id/result | บันทึกผล CI/BI → auto recall |
| GET  | /api/v1/reports/dashboard | ข้อมูล donut charts |
| GET  | /api/v1/reports/weekly | รายงานรายสัปดาห์ |

## Printer: Xprinter XP-420B — 2 โหมดที่อนุมัติ
- Protocol: TSPL (203 DPI, 60×40 mm label)
- **โหมดหลัก `PRINT_GATEWAY`** — Print Job Queue → Print Gateway → เครื่องพิมพ์ + hardware ACK:
  USB printer-class → Gateway ส่ง raw TSPL เข้า OS printer queue (transport `usb_spool`);
  dev ใช้ `console` mock — PWA/มือถือไม่พิมพ์ตรงและไม่ตั้งสถานะ PRINTED เอง
  (ดู `apps/print-gateway/README.md`, `HARDWARE_VERIFICATION.md`)
- **โหมดเสริม `BROWSER_DIALOG`** ([MACOS_BROWSER_PRINT_DIRECTIVE.md](./MACOS_BROWSER_PRINT_DIRECTIVE.md)) —
  PWA บน **Mac ที่เสียบ XP-420B เครื่องเดียวกัน** เปิด macOS system print dialog (PDF ขนาด label จริง);
  browser พิสูจน์ผล hardware ไม่ได้ → ผู้ใช้ยืนยันเอง (`USER_CONFIRMED`) เก็บประวัติแยกใน
  `BrowserPrintRequest` และ**ไม่แตะ** `printedAt`; เปิดใช้ด้วย `CSSD_BROWSER_PRINT_ENABLED=true`
  (backend env + PWA dart-define, **default ปิด**) — ไม่ใช่ direct USB/WebUSB; อุปกรณ์อื่น
  (iPhone/iPad/Android) ใช้ Print Gateway เท่านั้น (ดู `docs/MAC_XP420B_BROWSER_PRINT.md`)
- Legacy: FlashLabel A318BT (Bluetooth direct-print) เหลือเป็น fallback ระดับโค้ดเท่านั้น

## Running tests
```bash
cd apps/api && yarn test
```
