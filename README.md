# CSSD Sterile Instrument Tracking System

ระบบตามรอยอุปกรณ์หัตถการปลอดเชื้อ | Flutter + NestJS + PostgreSQL

> ดูสถานะความคืบหน้าล่าสุด/checklist เฟส 1-3 ที่ [PROGRESS.md](./PROGRESS.md) — อัปเดตทุกครั้งที่มีการแก้ไข

## Structure

```
cssd/
├── apps/
│   ├── api/          NestJS backend + Prisma
│   └── mobile/       Flutter app (Android + iOS)
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

## Printer: FlashLabel A318BT
- Protocol: TSPL (203 DPI, 60×40 mm label)
- Connection: Bluetooth Classic SPP + USB
- Default in dev: `MockPrinterAdapter` (prints TSPL to debug console)
- Production: `FlashLabelA318Adapter` — selected via Settings page in app

## Running tests
```bash
cd apps/api && yarn test
```
