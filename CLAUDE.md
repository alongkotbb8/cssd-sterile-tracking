# CLAUDE.md — ระบบบันทึกเข้า–ออกและตามรอยอุปกรณ์หัตถการปลอดเชื้อ

> ไฟล์นี้คือบริบทถาวรของโปรเจกต์ Claude Code จะอ่านไฟล์นี้อัตโนมัติทุก session
> เก็บ **กฎโดเมน + สถาปัตยกรรม + ข้อตกลงการเขียนโค้ด** อ่านก่อนเขียนหรือแก้โค้ดเสมอ

---

## 1. โปรเจกต์นี้คืออะไร

ระบบ CSSD / Sterile Supply Tracking ที่ทำงานหลักบนมือถือ (Android + iOS)
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
   - โหมดออฟไลน์: จองเลขล่วงหน้าเป็น pool แล้ว sync (ห้าม gen เลขที่มือถือเองแบบสุ่ม)
3. **QR เก็บแค่ `package_id` (unique id) อย่างเดียว** รายละเอียดอื่น (ชนิดชุด/วันนึ่ง/วันหมดอายุ) ดึงจาก DB หรือ cache — ห้ามยัดข้อมูลทั้งหมดลง QR
4. **FEFO**: เวลาแนะนำเบิก ให้เรียงของที่ใกล้หมดอายุก่อน
5. **ตอนสแกนเบิก ถ้า `expiry_date < now` → บล็อก + แสดง "ห้ามใช้" สีแดง** ห้ามปล่อยให้เบิกของหมดอายุผ่านได้
6. **เบิกออกต้องเลือกแผนกปลายทาง (`dept_id`) เสมอ** ; **ชื่อผู้รับ (`receiver_name`) เป็น optional (nullable)**
7. **ส่งคืน (return) ต้องบันทึกแผนกที่ส่งของกลับมา** เพื่อปิดวงจรครบ และทำรายงานอัตราการส่งคืนต่อแผนก
8. **รอบนึ่ง (SterilizationBatch)**: ทุกห่อผูกกับ batch_id ถ้า batch ผล indicator ไม่ผ่าน ต้อง **recall** ทุกห่อในรอบนั้นได้ทันที พร้อมแสดงตำแหน่งปัจจุบันของแต่ละห่อ

### สถานะของห่อ (Package.status) — state machine
```
PACKED → STERILE → ISSUED → RETURNED → (reprocess) → PACKED ...
                 ↘ EXPIRED (เมื่อเกิน expiry_date ขณะยังอยู่ในคลัง)
ทุกสถานะ → DISCARDED (ชำรุด/ทิ้ง)
```
อนุญาตให้เปลี่ยนสถานะตามลูกศรเท่านั้น เขียน guard กันการ transition ที่ผิด

---

## 3. สถาปัตยกรรมและ Tech Stack ที่ใช้

> ถ้าจะเปลี่ยน stack ให้ถามผู้ใช้ก่อน อย่าเปลี่ยนเอง

- **Mobile:** Flutter (Dart) — cross-platform เดียวจบ
  - QR scanning: `mobile_scanner`
  - Offline storage: `drift` (SQLite) + sync queue
  - Bluetooth printer: `flutter_blue_plus` + adapter ส่ง ZPL/CPCL
  - State management: Riverpod
- **Backend:** NestJS (TypeScript) + Prisma ORM + **PostgreSQL**
  - Auth: JWT + role-based guard (CSSD / SUPERVISOR / ADMIN)
  - REST API (เปิดทาง GraphQL ไว้ทีหลังได้)
- **Notifications:** Firebase Cloud Messaging (เตือนใกล้หมดอายุ / ลืมสรุปรายวัน)
- **Reports:** สร้างฝั่ง server เป็น PDF + Excel
- **Repo layout (monorepo):**
  ```
  /apps/mobile     # Flutter app
  /apps/api        # NestJS backend
  /packages/shared # type/constant ที่ใช้ร่วม (รหัสสถานะ, enum)
  /docs            # SRS + diagram
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
- **Printer = adapter pattern** มี `PrinterAdapter` interface และ `MockPrinterAdapter` (พิมพ์ลง log/ไฟล์) เป็นค่าเริ่มต้น เพื่อพัฒนาได้โดยไม่มีฮาร์ดแวร์จริง ค่อยเพิ่ม `ZebraAdapter` ทีหลัง

---

## 6. สิ่งที่ยังไม่ยืนยัน (ASSUMPTIONS — ถามผู้ใช้ก่อนถ้าจะกระทบ)

- โรงพยาบาลเดียว (ยังไม่ทำ multi-tenant ในเฟส 1)
- ยังไม่ผูกกับเคส/ผู้ป่วย (เฟส 3) — ดังนั้นเฟส 1 ยังไม่ต้องกังวล PDPA ระดับผู้ป่วย
- ยี่ห้อเครื่องพิมพ์ label ยังไม่ระบุ → ใช้ MockPrinterAdapter ไปก่อน
- ปริมาณชุด/วันและจำนวนผู้ใช้พร้อมกันยังไม่ทราบ → ออกแบบให้ขยายได้แต่ไม่ over-engineer

---

## 7. ลำดับการพัฒนา (อย่าทำทุกอย่างพร้อมกัน)

**เฟส 1 (MVP):** auth+roles → master data → สร้างชุด/เลขรัน/พิมพ์ (mock) → สแกนเข้า-ออก+ปลายทาง+ผู้รับ → คำนวณ+เตือนหมดอายุ → แดชบอร์ดโดนัท → รายงานรายสัปดาห์
**เฟส 2:** batch นึ่ง + recall, return loop เต็มรูปแบบ, offline-first สมบูรณ์, รายงานเชิงลึก, ZebraAdapter จริง
**เฟส 3:** ผูกเคส/ผู้ป่วย, เชื่อม HIS, พอร์ทัลแผนกปลายทาง

ทำเฟส 1 ให้เดินได้ end-to-end ก่อนค่อยขยับเฟสถัดไป
