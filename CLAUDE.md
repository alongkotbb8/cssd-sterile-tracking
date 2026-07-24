# CLAUDE.md — ระบบบันทึกเข้า–ออกและตามรอยอุปกรณ์หัตถการปลอดเชื้อ

> ไฟล์นี้คือบริบทถาวรของโปรเจกต์ Claude Code จะอ่านไฟล์นี้อัตโนมัติทุก session
> เก็บ **กฎโดเมน + สถาปัตยกรรม + ข้อตกลงการเขียนโค้ด** อ่านก่อนเขียนหรือแก้โค้ดเสมอ

> ⚠️ **SINGLE SOURCE OF TRUTH = [`CSSD_MASTER_EXECUTION_DIRECTIVE.md`](CSSD_MASTER_EXECUTION_DIRECTIVE.md)** (2026-07-23)
> + addendum ด้านการพิมพ์: [`MACOS_BROWSER_PRINT_DIRECTIVE.md`](MACOS_BROWSER_PRINT_DIRECTIVE.md) (2026-07-24)
> เอกสารนั้นมีอำนาจเหนือไฟล์นี้และแผนเก่าเมื่อขัดแย้งกัน. Baseline ที่ล็อกแล้ว:
> **ระบบเป็น online-only PWA — Chrome + Safari บน iPhone/iPad (สแกน QR + workflow หลัก) เป็นเป้าหมายหลัก** (ไม่ใช่ mobile app), backend เป็นแหล่งความจริงเดียว,
> การพิมพ์มี **2 โหมดที่อนุมัติ**: (1) **`PRINT_GATEWAY`** — Print Gateway → Linux/CUPS →
> Xprinter XP-420B (`usb_spool`) พร้อม hardware ACK (เส้นทางหลัก ใช้จากอุปกรณ์ใดก็ได้);
> (2) **`BROWSER_DIALOG`** — macOS system print dialog บน **Mac ที่เสียบ XP-420B และเปิด PWA
> เครื่องเดียวกัน** หลัง feature flag `CSSD_BROWSER_PRINT_ENABLED` (default **off**) — browser
> พิสูจน์ผล hardware ไม่ได้ ผู้ใช้ยืนยันเอง (`USER_CONFIRMED`) และ**ไม่ใช่** direct USB/WebUSB.
> **ยกเลิกจาก scope: offline mutation/queue/number-pool, drift/SQLite, Bluetooth direct-print เป็นช่องทาง Pilot,
> FlashLabel A318BT, Zebra, mobile-first.** โค้ด legacy คงไว้ได้เฉพาะหลัง feature flag (default off) และผู้ใช้ปกติเข้าไม่ถึง.

---

## 1. โปรเจกต์นี้คืออะไร

ระบบ CSSD / Sterile Supply Tracking ที่ทำงานหลักบน **PWA แบบ online-only** (Flutter Web — Chrome + Safari บน iPhone/iPad)
— build มือถือ (Android/iOS) ยังทำได้จากโค้ดเดียวกันแต่ **ไม่ใช่ช่องทางหลักของ Pilot** —
ติดตามชุดอุปกรณ์หัตถการ (ทำฟัน ทำคลอด ทำแผล ฯลฯ) ตลอดวงจร:
แพ็ก → นึ่งฆ่าเชื้อ → คลังปลอดเชื้อ → เบิกออกไปแผนกปลายทาง → ส่งคืน → reprocess

หัวใจของระบบไม่ใช่แค่ "นับเข้า-ออก" แต่คือ **traceability ราย่อห่อ** เพราะเป็นงานความปลอดภัยผู้ป่วย

---

## 2. กฎโดเมนสำคัญ (DOMAIN RULES — ห้ามทำผิด)

1. **อายุการปลอดเชื้อ**
   - ห่อซีล (`SEAL`) = วันที่นึ่ง + **180 วัน**
   - ห่อผ้า (`CLOTH`) = วันที่นึ่ง + **7 วัน**
   - `expiry_date` ต้องคำนวณอัตโนมัติฝั่ง backend ตอนสร้าง/นึ่ง ห้ามให้ผู้ใช้กรอกเอง
2. **เลขรัน (running number) สร้างจาก BACKEND เท่านั้น** เพื่อกันเลขซ้ำเมื่อหลายเครื่อง/หลายคนพิมพ์พร้อมกัน
   - รูปแบบ: `{SET_CODE}-{YYYYMMDD}-{SEQ4}` เช่น `DELIV-20260630-0007`
   - ~~โหมดออฟไลน์: จองเลขล่วงหน้าเป็น pool แล้ว sync~~ **ยกเลิก — ระบบ online-only ออกเลขตอนสร้างจริงเท่านั้น** [SUPERSEDED §1.2] (ห้าม gen เลขที่ client เองแบบสุ่มเช่นเดิม)
3. **QR เก็บแค่ `package_id` (unique id) อย่างเดียว** รายละเอียดอื่น (ชนิดชุด/วันนึ่ง/วันหมดอายุ) ดึงจาก DB หรือ cache — ห้ามยัดข้อมูลทั้งหมดลง QR
4. **FEFO**: เวลาแนะนำเบิก ให้เรียงของที่ใกล้หมดอายุก่อน
5. **ตอนสแกนเบิก ถ้า `expiry_date < now` → บล็อก + แสดง "ห้ามใช้" สีแดง** ห้ามปล่อยให้เบิกของหมดอายุผ่านได้
6. **เบิกออกต้องเลือกแผนกปลายทาง (`dept_id`) เสมอ** ; **ชื่อผู้รับ (`receiver_name`) เป็น optional (nullable)**
7. **ส่งคืน (return) ต้องบันทึกแผนกที่ส่งของกลับมา** เพื่อปิดวงจรครบ และทำรายงานอัตราการส่งคืนต่อแผนก
8. **รอบนึ่ง (SterilizationBatch)** — ลำดับต้องถูกหลัก traceability:
   `เปิดรอบ (PENDING) → สแกนห่อเข้ารอบ (ผูก batch_id, ห่อยังเป็น PACKED) → นึ่ง → SUPERVISOR/ADMIN บันทึกผล CI/BI`
   - ผล **ผ่าน** → ห่อทุกใบในรอบเป็น STERILE + คำนวณ expiry + Movement IN (ใน transaction เดียว)
   - ผล **ไม่ผ่าน** → ห่อคง PACKED และถูกปลดจากรอบ + **recall** ห่อเก่าจากรอบนั้นที่หมุนเวียนอยู่ทันที พร้อมแสดงตำแหน่งปัจจุบัน
   - **ห้าม** ผูกห่อเข้ารอบที่บันทึกผลไปแล้ว (retroactive binding) และ endpoint บันทึกผลจำกัด SUPERVISOR/ADMIN เท่านั้น
9. **Label ของห่อที่ยังไม่ผ่านการนึ่ง ห้ามแสดงวันนึ่ง/วันหมดอายุ** (แม้โดยประมาณ) — พิมพ์แถบ "ยังไม่ผ่านการฆ่าเชื้อ" แทน วันที่บน label ต้องมาจาก backend หลังรอบนึ่งผ่านแล้วเท่านั้น
10. **นิยามวันหมดอายุ**: `expiry_date` = วันสุดท้ายที่ใช้ได้ (ใช้ได้ตลอดวันหมดอายุ บล็อกตั้งแต่ 00:00 UTC วันถัดไป) — logic รวมที่ `apps/api/src/common/expiry.ts` ห้ามเทียบวันที่เองที่อื่น
11. **ทุกครั้งที่พิมพ์ label ต้องบันทึก** `printedAt`/`reprintCount` + AuditLog — **ทางเดียว** คือ Print Gateway เรียก `POST /print-gateway/jobs/:id/ack` (ดูข้อ 3) **ห้าม** client (PWA/มือถือ) เรียกตั้งค่านี้เองเด็ดขาด (เปิด print dialog สำเร็จ ≠ พิมพ์สำเร็จจริง)
    - โหมด **`BROWSER_DIALOG`** (MACOS_BROWSER_PRINT_DIRECTIVE.md) เก็บประวัติของตัวเองใน
      `BrowserPrintRequest` (`CREATED → DIALOG_OPENED → USER_CONFIRMED | CANCELLED`) —
      `USER_CONFIRMED` = ผู้ใช้ยืนยันเอง **ไม่ใช่ hardware-confirmed**, ห้ามใช้สถานะ
      `PRINTED/SENT/ACK_UNKNOWN` กับโหมดนี้ และ**ห้ามแตะ** `printedAt`/`reprintCount` เด็ดขาด
      (แต่การเป็น reprint นับรวมประวัติทั้งสองโหมด และบังคับ `reprintReason` เหมือนกัน)
12. **ทุก mutation สำคัญ** (สร้าง package, scan in/out/return, เปิดรอบนึ่ง/บันทึกผล, สร้าง print job) **ต้องรับ header `Idempotency-Key`** และประมวลผลแบบ atomic (ห้าม find→execute→store ที่ไม่ atomic) — ดู `apps/api/src/common/idempotency/idempotency.service.ts`

### สถานะของห่อ (Package.status) — state machine
```
PACKED → STERILE → ISSUED → RETURNED → (reprocess) → PACKED ...
   ↕              ↘ EXPIRED (เมื่อเกิน expiry_date ขณะยังอยู่ในคลัง)
PACKED_OUT (ส่งออกโดยยังไม่ฆ่าเชื้อ เช่น ส่ง รพ.อื่น — รับคืนแล้วกลับเป็น PACKED ทันที ไม่ต้อง reprocess)
ทุกสถานะ → DISCARDED (ชำรุด/ทิ้ง)
```
อนุญาตให้เปลี่ยนสถานะตามลูกศรเท่านั้น เขียน guard กันการ transition ที่ผิด
- ปลายทางของ `PACKED_OUT` ใช้ตาราง `Department` เดิม โดยสถานที่ภายนอกใช้ `type = 'external'`

---

## 3. สถาปัตยกรรมและ Tech Stack ที่ใช้

> ถ้าจะเปลี่ยน stack ให้ถามผู้ใช้ก่อน อย่าเปลี่ยนเอง

- **PWA (หลัก) / Mobile:** Flutter (Dart) — เป้าหมาย Pilot = **Chrome PWA (Flutter Web) online-only**;
  build มือถือได้จากโค้ดเดียวกันแต่ไม่ใช่ช่องทาง Pilot
  - QR scanning: `mobile_scanner` (กล้อง Chrome) + manual entry เป็น fallback
  - **Online-only:** ~~offline storage (`drift`/SQLite + sync queue)~~ **ยกเลิกทั้งหมด** — เน็ตหลุด = fail closed,
    เลขรันออกจาก backend ตอนสร้างจริงเท่านั้น (ไม่มี offline pool) [SUPERSEDED โดย master directive §1.2]
  - Bluetooth direct print (`flutter_blue_plus` + `print_bluetooth_thermal`) = **legacy fallback ระดับโค้ดเท่านั้น**
    หลัง feature flag `CSSD_ENABLE_LEGACY_PRINT` (default off ใน release) — ผู้ใช้ปกติเข้าไม่ถึง; เส้นทางจริงคือ Print Gateway
  - State management: Riverpod
- **Backend:** NestJS (TypeScript) + Prisma ORM + **PostgreSQL**
  - Auth: JWT + role-based guard (CSSD / SUPERVISOR / ADMIN)
  - REST API (เปิดทาง GraphQL ไว้ทีหลังได้)
- **Print Gateway** (`apps/print-gateway`, Node/TS) — บริการแยกต่างหาก claim งานพิมพ์จาก
  API แล้วส่ง TSPL ไปเครื่องพิมพ์จริง (`serialport` ผ่าน USB/Serial จริง หรือ `console`
  mock สำหรับ dev เท่านั้น — ห้ามใช้ console บน production) มี credential ของตัวเอง
  (`X-Gateway-Key`, ไม่ใช่ user JWT) **PWA ไม่พิมพ์ตรงและไม่ตั้งสถานะ PRINTED เอง** —
  สร้าง `PrintJob` แล้วรอ Gateway claim/พิมพ์/ACK เท่านั้น (สถานะ:
  `QUEUED → CLAIMED → PRINTING → SENT → PRINTED`, มี `FAILED → RETRYING → DEAD_LETTER`,
  `CANCELLED`, `SIMULATED`, `ACK_UNKNOWN`, `RESOLVED_PRINTED`/`RESOLVED_REQUEUED` — ดู
  `apps/print-gateway/README.md` สำหรับ state machine เต็ม)
  ภาษาไทยบน label render เป็น bitmap เหมือนมือถือแล้ว (canvas + ฟอนต์ Sarabun)
  PWA ผูกปุ่มพิมพ์เข้ากับ Print Job Queue แล้ว (Phase 2) — `apps/mobile/lib/features/print_jobs/`
  (สร้าง job + poll สถานะ + supervisor resolve); เส้นทางพิมพ์ตรงเดิมเป็น legacy fallback เท่านั้น
- **Browser Print (`BROWSER_DIALOG`)** — โหมดเสริมตาม `MACOS_BROWSER_PRINT_DIRECTIVE.md`:
  PWA บน **Mac เครื่องเดียวกับที่เสียบ XP-420B** เปิด macOS system print dialog (PDF ขนาด label
  จริง 60×40 มม. embed bitmap จาก `label_renderer`) — backend เก็บ `BrowserPrintRequest`
  (`browser-print-requests` API: create/dialog-opened/confirm/cancel/list) แยกจาก PrintJob
  เด็ดขาด. Browser ยืนยันผล hardware ไม่ได้ → ผู้ใช้เลือกผลเอง (`USER_CONFIRMED`/`CANCELLED`/
  ค้าง `DIALOG_OPENED`). เปิดใช้ด้วย `CSSD_BROWSER_PRINT_ENABLED=true` ทั้ง backend (env) และ
  PWA (dart-define) — **default ปิดทั้งคู่**; iPhone/iPad/Android ใช้โหมดนี้ควบคุม USB printer
  บน Mac ไม่ได้ (ต้องใช้ Print Gateway). ห้าม WebUSB, ห้ามเรียก Gateway ACK จาก browser
- **Notifications:** Firebase Cloud Messaging (เตือนใกล้หมดอายุ / ลืมสรุปรายวัน)
- **Reports:** สร้างฝั่ง server เป็น PDF + Excel
- **Repo layout (monorepo):**
  ```
  /apps/mobile         # Flutter app (Chrome PWA หลัก + build มือถือได้)
  /apps/api            # NestJS backend
  /apps/print-gateway  # Print Gateway worker (Node/TS)
  /packages/shared     # type/constant ที่ใช้ร่วม (รหัสสถานะ, enum)
  /docs                # SRS + diagram
  ```

---

## 4. โมเดลข้อมูลหลัก (ดู /docs/SRS สำหรับรายละเอียด)

- **Package** — package_id, set_template_id, wrap_type(SEAL|CLOTH), sterilize_date, expiry_date, status, batch_id
- **SetTemplate** — template_id, name, item_list[], default_wrap_type
- **SterilizationBatch** — batch_id, machine_id, round_no, datetime, ci_result, bi_result, status
- **Movement** — movement_id, package_id, type(IN|OUT|RETURN), datetime, user_id, dept_id, receiver_name?(nullable)
- **Department** — dept_id, code, name, type
- **User** — user_id, name, role, status
- **AuditLog** — log_id, user_id, action, target, datetime

> `Movement.receiver_name` nullable ; `Movement` แบบ RETURN ให้ `dept_id` = แผนกที่ส่งของกลับ

---

## 5. ข้อตกลงการเขียนโค้ด (Conventions)

- ภาษา UI = ไทย ; ข้อความ user-facing แยกเป็นไฟล์ i18n (อย่า hard-code ปนในโค้ด)
- ทุก endpoint ที่เปลี่ยนข้อมูลต้องเขียน **AuditLog**
- เขียน test คู่กับฟีเจอร์: unit test logic โดเมน (คำนวณ expiry, FEFO, state transition) ให้ครบ
- ห้ามใส่ secret/คีย์ลงโค้ด ใช้ `.env` + `.env.example`
- commit เล็ก ๆ ข้อความสื่อความหมาย ; เปิด PR ต่อฟีเจอร์
- **Printer:** เส้นทางหลัก = **Print Gateway → Linux/CUPS → Xprinter XP-420B (`usb_spool`)**;
  เส้นทางเสริมที่อนุมัติ = **`BROWSER_DIALOG`** (macOS print dialog บน Mac ที่ต่อเครื่องพิมพ์,
  หลัง flag `CSSD_BROWSER_PRINT_ENABLED`, ผู้ใช้ยืนยันผลเอง — ดู §3). ฝั่ง Flutter มี
  `PrinterAdapter` interface + `MockPrinterAdapter` (พิมพ์ลง log/ไฟล์) สำหรับ dev และ Bluetooth/System adapter เดิม =
  legacy fallback หลัง flag เท่านั้น. ~~ZebraAdapter~~ **ยกเลิก: Zebra ไม่ใช่เครื่องพิมพ์เป้าหมาย** [SUPERSEDED §1.2]

---

## 6. สิ่งที่ยังไม่ยืนยัน (ASSUMPTIONS — ถามผู้ใช้ก่อนถ้าจะกระทบ)

- โรงพยาบาลเดียว (ยังไม่ทำ multi-tenant ในเฟส 1)
- ยังไม่ผูกกับเคส/ผู้ป่วย (เฟส 3) — ดังนั้นเฟส 1 ยังไม่ต้องกังวล PDPA ระดับผู้ป่วย
- เครื่องพิมพ์ label เป้าหมาย = **Xprinter XP-420B** (USB, 203 DPI, TSPL/TSPL2) — renderer TSPL
  bitmap เข้ากันได้ แต่ USB มักเป็น **printer-class ไม่ใช่ COM/serial** → ใช้ transport `usb_spool`
  (raw TSPL เข้า OS printer queue)
  - **host ของ Pilot (ตัดสินแล้ว): Raspberry Pi/Linux + CUPS `lp -o raw`** — posix path;
    Windows `lpr` = **unsupported** จนกว่าจะผ่าน hardware verification (gateway ล็อก win32 ไว้
    ต้อง opt-in `PRINTER_ALLOW_UNVERIFIED_WINDOWS_SPOOL=true`; ยังไม่ลบ = fallback)
  - ต้องผ่าน FIX-08 กับเครื่องจริงก่อน Pilot (ดู `HARDWARE_VERIFICATION.md` ข้อ 0.1); dev ใช้ console/mock
- ปริมาณชุด/วันและจำนวนผู้ใช้พร้อมกันยังไม่ทราบ → ออกแบบให้ขยายได้แต่ไม่ over-engineer

---

## 7. ลำดับการพัฒนา (อย่าทำทุกอย่างพร้อมกัน)

**เฟส 1 (MVP):** auth+roles → master data → สร้างชุด/เลขรัน/พิมพ์ (mock) → สแกนเข้า-ออก+ปลายทาง+ผู้รับ → คำนวณ+เตือนหมดอายุ → แดชบอร์ดโดนัท → รายงานรายสัปดาห์
**เฟส 2:** batch นึ่ง + recall, return loop เต็มรูปแบบ, Print Gateway + XP-420B (`usb_spool`) จริง, รายงานเชิงลึก
  — ~~offline-first, ZebraAdapter~~ **ยกเลิก (online-only + XP-420B)** [SUPERSEDED §1.2]
**เฟส 3:** ผูกเคส/ผู้ป่วย, เชื่อม HIS, พอร์ทัลแผนกปลายทาง

ทำเฟส 1 ให้เดินได้ end-to-end ก่อนค่อยขยับเฟสถัดไป
