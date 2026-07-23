# CSSD — สรุปสถานะก่อน Pilot (Pre-Pilot Summary)

ปรับปรุงล่าสุด: 2026-07-23 · สถานะ: **ยังไม่ deploy** · เอกสารนี้คือภาพรวมฉบับเดียว รวมทุกงานที่ทำ + สิ่งที่เหลือก่อนเปิด Pilot

---

## 1. ระบบนี้คืออะไร (ย่อ)

CSSD / Sterile Supply Tracking — ติดตามชุดอุปกรณ์ปลอดเชื้อราย่อห่อ ตลอดวงจร
แพ็ก → นึ่ง → คลังปลอดเชื้อ → เบิก → คืน → reprocess (งานความปลอดภัยผู้ป่วย)
Stack: Flutter (มือถือ + Chrome PWA) · NestJS + Prisma + PostgreSQL · Print Gateway (Node/TS) แยกต่างหาก

## 2. งานที่ทำเสร็จในรอบนี้ (ทั้งหมดยัง verify ด้วย test แล้ว)

### M1/M2 Re-audit (FIX-01 → FIX-07) — ดู `M1_M2_REAUDIT_FIX_SUMMARY.md`
- **FIX-01** migration `expiresAt` แบบ backfill-safe (3-step) — พิสูจน์บน DB ว่าง/มีข้อมูล/ผ่าน Prisma
- **FIX-02** idempotency crash-recovery แบบ single-transaction (reservation+mutation+audit+response อะตอมมิก, ไม่ rerun, thread `tx` ทุก mutation)
- **FIX-03** ACK_UNKNOWN resolve ได้ครั้งเดียว (RESOLVED_* + `resolvedAt IS NULL` CAS + `requeuedFromJobId @unique`)
- **FIX-04** transport typed result NOT_SENT / MAYBE_SENT / SENT (MAYBE_SENT → ACK_UNKNOWN ห้าม auto-retry)
- **FIX-05** backend ตัดสิน simulation (PrinterDevice.canConfirmRealPrint + invariant + re-check ตอน ACK)
- **FIX-06** production HTTPS เข้ม (Private IP ก็ไม่ยอม http)
- **FIX-07** PostgreSQL integration/concurrency tests **12/12** (real DB)
- **แก้หลัง review:** FIX-02 cleanup ลบเฉพาะ DONE (ไม่แตะ PENDING) · FIX-05 invariant + re-check 3 ค่าตอน ACK · idempotency ตรวจ endpoint+method

### Phase 2 — PWA Print Job Integration — ดู `apps/mobile/lib/features/print_jobs/`
- ปุ่มพิมพ์สร้าง `PrintJob` ผ่าน backend (แนบ `Idempotency-Key`) → poll สถานะ `QUEUED→CLAIMED→PRINTING→SENT→PRINTED`
- จัดการ `FAILED/DEAD_LETTER/SIMULATED/ACK_UNKNOWN` · ยกเลิกเฉพาะ QUEUED · reprint reason · หน้า supervisor resolve (role-gated)
- **ปิดเส้นทางพิมพ์ตรง** (Bluetooth/System) เหลือเป็น legacy fallback ระดับโค้ด · PWA ไม่ตั้ง PRINTED เอง

### Phase 3 — QR scanner / PWA completeness (online-only)
- กล้องเว็บผ่าน getUserMedia (ต้อง https) · สิทธิ์ + คำแนะนำเปิดใหม่แบบ web-aware · กล้องหลัง default + ปุ่มสลับกล้อง
- (มีอยู่แล้วจาก M1: manual entry, ผลรายชิ้น, บล็อกหมดอายุ, กันสแกนซ้ำ)
- **ตัด offline-first** (online-only ตามที่ยืนยัน)

### Phase 5 — Security & Operational Readiness — ดู `OPERATIONAL_READINESS.md`
- Gateway key lifecycle: register / **rotate-key (ใหม่)** / revoke — ทุกอย่าง ADMIN + AuditLog
- RBAC/IDOR ครบทุก print-job endpoint + regression test (`@Roles` metadata)
- helmet / body-limit / prod-CORS / Swagger opt-in / login throttle + account lockout (ทำแล้ว)

## 3. หลักฐานการทดสอบ (ดู `TEST_EVIDENCE.md`)

| ชุดทดสอบ | ผล | หมายเหตุ |
|---|---|---|
| API unit (`npx jest`) | **100/100** | idempotency, print-jobs, RBAC, rotate, notifications, domain |
| API integration (`npm run test:integration`) | **12/12** | Postgres จริง — concurrency (claim/ACK/resolve/idempotency) |
| Print Gateway unit | **25/25** | poll-loop NOT_SENT/MAYBE_SENT/SENT, config, label |
| Mobile (`flutter analyze` + `flutter test`) | **สะอาด + 4/4** | ยังไม่ E2E จริง |
| Migration dry-run (fresh DB) + populated | ผ่าน | `migrate status` = up to date ไม่ drift |

ต้องมี PostgreSQL พร้อมตาม `DATABASE_URL` ถึงจะ reproduce integration ได้ (dev: PG 16.14 @ localhost)

## 4. Pilot Gate — สถานะ (จาก `M1_M2_REAUDIT_FIX_DIRECTIVE.md` ข้อ 15)

| เงื่อนไข | สถานะ |
|---|---|
| FIX-01 → FIX-07 ผ่าน | ✅ |
| Console Gateway → PRINTED ไม่ได้ | ✅ (canConfirmRealPrint + re-check) |
| ACK_UNKNOWN resolve ครั้งเดียว | ✅ |
| MAYBE_SENT ไม่ auto-retry | ✅ |
| Gateway production ใช้ HTTPS | ✅ (บังคับใน config) |
| Migration dry-run ผ่าน | ✅ |
| PostgreSQL concurrency tests ผ่าน | ✅ 12/12 |
| **FIX-08 ผลทดสอบเครื่องจริง (Xprinter)** | ❌ รอทีม (ดู `HARDWARE_VERIFICATION.md`) |
| **E2E จริง PWA↔API↔Gateway↔เครื่องพิมพ์** | ❌ รอรัน server ทั้งชุด |
| **Browser test (Android Chrome/iOS WebKit)** | ❌ รอทีม (ดู `PWA_BROWSER_TESTING.md`) |
| **Backup/restore drill** | ❌ รอทีม |
| **UAT อนุมัติ** | ❌ รอทีม |

**สรุป: ยังไม่พร้อมเปิด Pilot** — โค้ด (FIX-01→07 + PWA + security) พร้อมและผ่าน test แล้ว แต่ยังติดงานที่ต้องทำบนของจริง (Xprinter, E2E, browser, backup, UAT)

## 5. สิ่งที่เหลือก่อน Pilot (เป็นงานทีม/ฮาร์ดแวร์ — AI ทำแทนไม่ได้)

1. **FIX-08 Xprinter XP-420B จริง** (USB, 203 DPI, TSPL) — soak test ตาม `HARDWARE_VERIFICATION.md`
   - ✅ สร้าง `UsbSpoolTransport` แล้ว (cross-platform: posix CUPS `lp -o raw` / win32 `lpr`, injection-safe,
     NOT_SENT/MAYBE_SENT/SENT ครบ, unit tests ผ่าน) + backend `USB_SPOOL` transport mode
   - ⚠️ ยังไม่ทดสอบกับเครื่อง/OS จริง — โดยเฉพาะ **path Windows ยังไม่ verify** (lpr ต้องเปิด LPR feature
     หรืออาจต้องเปลี่ยนวิธี); ต้องยืนยัน host OS + ชื่อ printer queue + calibrate gap ตอน hardware verification
2. **E2E ทั้งชุด** — รัน API + Gateway + PWA + เครื่องพิมพ์จริง แล้วเดินครบ flow แพ็ก→พิมพ์→นึ่ง→สแกนเข้า→เบิก→คืน + recall
3. **Browser test** ตาม `PWA_BROWSER_TESTING.md` (Android Chrome หลัก + iOS WebKit แยก)
4. **Ops** ตาม `OPERATIONAL_READINESS.md` — backup/restore drill, monitoring alerts, SOP เป็นคู่มือ, ตัดสิน global rate limit + deployment topology
5. **UAT** + เปิด Pilot จำกัดจุดเดียว/เครื่องเดียวก่อน

## 6. ดัชนีเอกสาร

| ไฟล์ | เนื้อหา |
|---|---|
| `PRE_PILOT_SUMMARY.md` | ← ฉบับนี้ (ภาพรวม) |
| `M1_M2_REAUDIT_FIX_SUMMARY.md` | รายละเอียด FIX-01→08 + Pilot Gate |
| `TEST_EVIDENCE.md` | ผลรันทดสอบจริง + คำสั่ง reproduce |
| `OPERATIONAL_READINESS.md` | RBAC audit, key lifecycle, ops, SOP |
| `HARDWARE_VERIFICATION.md` | checklist ทดสอบ Xprinter จริง (FIX-08) |
| `PWA_BROWSER_TESTING.md` | checklist ทดสอบเบราว์เซอร์ (Phase 3) |
| `PROGRESS.md` | changelog ตามลำดับเวลา |
| `CLAUDE.md` / `AGENTS.md` | กฎโดเมน + สถาปัตยกรรม (persistent context) |

## 7. หมายเหตุ deployment

- **ยังไม่ deploy / ยังไม่แตะ production** — โค้ดอยู่ใน branch รอ review/PR
- Migration ที่เพิ่ม (unreleased): `20260722072226`, `20260722140000`, `20260722150000` — additive + backfill-safe ทั้งหมด
- ก่อน deploy: `prisma migrate deploy` บน production DB (dry-run + populated test ผ่านแล้ว), เปลี่ยนรหัส seed, ตั้ง env (`NODE_ENV=production`, HTTPS, CORS_ORIGINS, GATEWAY_API_KEY)
