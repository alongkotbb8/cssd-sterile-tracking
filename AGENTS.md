# AGENTS.md — ระบบบันทึกเข้า–ออกและตามรอยอุปกรณ์หัตถการปลอดเชื้อ

> ไฟล์นี้คือบริบทถาวรของโปรเจกต์ Codex จะอ่านไฟล์นี้อัตโนมัติทุก session
> เก็บ **กฎโดเมน + สถาปัตยกรรม + ข้อตกลงการเขียนโค้ด** อ่านก่อนเขียนหรือแก้โค้ดเสมอ

> ⚠️ **SINGLE SOURCE OF TRUTH = [`CSSD_MASTER_EXECUTION_DIRECTIVE.md`](CSSD_MASTER_EXECUTION_DIRECTIVE.md)** (2026-07-23) —
> เมื่อขัดแย้งกัน เอกสารนั้นมีอำนาจเหนือไฟล์นี้. Baseline: online-only PWA — Chrome + Safari บน iPhone/iPad (หลัก), backend เป็นแหล่งความจริงเดียว,
> พิมพ์ผ่าน Print Gateway → Linux/CUPS → Xprinter XP-420B (`usb_spool`) เท่านั้น; **ยกเลิก offline/Bluetooth Pilot/A318BT/Zebra/mobile-first**.

---

## 1. โปรเจกต์นี้คืออะไร

ระบบ CSSD / Sterile Supply Tracking ที่ใช้งานหลักผ่าน **Chrome PWA** (Flutter web;
โค้ดฐานเดียวกันรองรับ Android/iOS ด้วย) — **online-only**
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
   - ระบบเป็น online-only: ออกเลขจาก backend ตอนสร้างจริงเท่านั้น (ไม่มี offline pool)
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
11. **ทุกครั้งที่พิมพ์ label ต้องบันทึก** `printedAt`/`reprintCount` + AuditLog — **ทางเดียว** คือ Print Gateway เรียก `POST /print-gateway/jobs/:id/ack` **ห้าม** client (PWA/มือถือ) ตั้งค่านี้เองเด็ดขาด (เปิด print dialog สำเร็จ ≠ พิมพ์สำเร็จจริง)
12. **ทุก mutation สำคัญต้องรับ header `Idempotency-Key`** และประมวลผลแบบ atomic (ห้าม find→execute→store ที่ไม่ atomic) — ดู `apps/api/src/common/idempotency/idempotency.service.ts`

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

- **Mobile/PWA:** Flutter (Dart) — cross-platform เดียวจบ (Android/iOS + web/Chrome PWA)
  - QR scanning: `mobile_scanner`
  - **Online-only** — ตัด offline-first ทั้งหมด (ไม่มี drift/SQLite/sync queue); เน็ตหลุด = fail closed
  - Bluetooth printer ต่อตรง: legacy fallback ระดับโค้ดเท่านั้น (ปุ่มพิมพ์ใช้ Print Job Queue → Gateway)
  - State management: Riverpod
- **Backend:** NestJS (TypeScript) + Prisma ORM + **PostgreSQL**
  - Auth: JWT + role-based guard (CSSD / SUPERVISOR / ADMIN)
  - REST API (เปิดทาง GraphQL ไว้ทีหลังได้)
- **Print Gateway** (`apps/print-gateway`, Node/TS) — บริการแยก claim งานพิมพ์จาก API
  แล้วส่ง TSPL ไปเครื่องพิมพ์จริง มี credential ของตัวเอง (`X-Gateway-Key`) PWA ไม่พิมพ์ตรง
  และไม่ตั้งสถานะ PRINTED เอง — ดู `apps/print-gateway/README.md`
- **Notifications:** Firebase Cloud Messaging (เตือนใกล้หมดอายุ / ลืมสรุปรายวัน)
- **Reports:** สร้างฝั่ง server เป็น PDF + Excel
- **Repo layout (monorepo):**
  ```
  /apps/mobile         # Flutter app (มือถือ + PWA)
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
- **Printer = Print Gateway + transport pattern** — Gateway (`apps/print-gateway`) มี interface
  `PrinterTransport` และ implementation: `ConsoleTransport` (mock, dev), `UsbSpoolTransport`
  (Xprinter XP-420B USB → OS printer queue, ทางหลักบน production), `SerialTransport` (ถ้า driver
  สร้าง virtual COM); ทุกตัวจำแนกผลเป็น NOT_SENT/MAYBE_SENT/SENT
  (ฝั่ง Flutter มี `PrinterAdapter` Bluetooth/System เดิม = legacy fallback ระดับโค้ดเท่านั้น)

---

## 6. สิ่งที่ยืนยันแล้ว / ยังไม่ยืนยัน (ถามผู้ใช้ก่อนถ้าจะกระทบ)

ยืนยันแล้ว:
- เครื่องพิมพ์ label = **Xprinter XP-420B** (USB, 203 DPI, TSPL) — USB เป็น printer-class →
  Gateway ใช้ transport `usb_spool` (raw → OS printer queue); dev ใช้ console/mock
  (**ต้องยืนยัน host OS ของ Gateway + ชื่อ printer queue จริงตอน hardware verification**)
- ระบบเป็น **online-only** (ตัด offline-first)

ยังไม่ยืนยัน (ASSUMPTIONS):
- โรงพยาบาลเดียว (ยังไม่ทำ multi-tenant ในเฟส 1)
- ยังไม่ผูกกับเคส/ผู้ป่วย (เฟส 3) — ดังนั้นเฟส 1 ยังไม่ต้องกังวล PDPA ระดับผู้ป่วย
- ปริมาณชุด/วันและจำนวนผู้ใช้พร้อมกันยังไม่ทราบ → ออกแบบให้ขยายได้แต่ไม่ over-engineer

---

## 7. ลำดับการพัฒนา (อย่าทำทุกอย่างพร้อมกัน)

**เฟส 1 (MVP):** auth+roles → master data → สร้างชุด/เลขรัน/พิมพ์ (mock) → สแกนเข้า-ออก+ปลายทาง+ผู้รับ → คำนวณ+เตือนหมดอายุ → แดชบอร์ดโดนัท → รายงานรายสัปดาห์
**เฟส 2:** batch นึ่ง + recall, return loop เต็มรูปแบบ, รายงานเชิงลึก, Print Gateway + Xprinter
XP-420B (`usb_spool`) จริง — **ตัด offline-first (ระบบเป็น online-only)**
**เฟส 3:** ผูกเคส/ผู้ป่วย, เชื่อม HIS, พอร์ทัลแผนกปลายทาง

ทำเฟส 1 ให้เดินได้ end-to-end ก่อนค่อยขยับเฟสถัดไป
