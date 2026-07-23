# M1/M2 Re-audit — เอกสารกำกับการแก้ไขก่อน Pilot

วันที่จัดทำ: 22 กรกฎาคม 2026  
ขอบเขต: Database Migration, Idempotency, Print Job, Print Gateway, Chrome PWA และ Hardware Verification

> AI และนักพัฒนาต้องอ่าน `AGENTS.md`, `AI_DEVELOPMENT_GUARDRAILS.md`, `M1_M2_REQUIRED_FIXES.md` และไฟล์นี้ก่อนลงมือ  
> ทำงานทีละหัวข้อ เขียน test คู่กับการแก้ไข และห้ามรายงานว่าเสร็จหากยังไม่ได้ทดสอบตาม Acceptance Criteria

## 1. เป้าหมายของรอบนี้

แก้ความเสี่ยงที่ยังเหลือหลัง M1/M2 โดยมีเป้าหมายหลัก:

1. Migration ต้องใช้ได้กับฐานข้อมูลที่มีข้อมูลอยู่แล้ว
2. Idempotency ต้องไม่ rerun mutation ที่อาจสำเร็จแล้ว
3. ACK_UNKNOWN ต้อง resolve ได้เพียงครั้งเดียว
4. Transport error ต้องไม่สร้าง Label ซ้ำ
5. Backend ต้องเป็นผู้ตัดสิน Simulation/Production mode
6. Gateway Production ต้องใช้ HTTPS
7. ต้องมี PostgreSQL concurrency tests
8. ต้องทดสอบเครื่องพิมพ์จริงก่อนเชื่อม PWA สำหรับ Pilot

## 2. กฎห้ามละเมิด

- ห้าม auto-retry เมื่ออาจส่งข้อมูลถึงเครื่องพิมพ์แล้ว
- ห้ามถือว่า `write()` error แปลว่าไม่มี byte ใดถูกส่ง
- ห้ามให้ Gateway request กำหนดเองว่า ACK เป็น simulated หรือ real
- ห้าม reclaim Idempotency `PENDING` แล้วเรียก mutation ซ้ำโดยไม่ reconciliation
- ห้ามเพิ่ม required database column โดยไม่มี backfill strategy
- ห้ามเปลี่ยนสถานะ `ACK_UNKNOWN` หรือสร้างงานใหม่ซ้ำโดยไม่มี CAS
- ห้ามใช้ HTTP ใน Production แม้อยู่ใน Private LAN
- ห้ามทดสอบ Console/Mock กับ Production database
- ห้าม deploy ก่อน PostgreSQL integration tests และ migration dry run ผ่าน

## 3. FIX-01 — แก้ Migration `expiresAt`

### ปัญหา

Migration ปัจจุบันเพิ่ม `expiresAt TIMESTAMP NOT NULL` โดยไม่มี default ทำให้ migration ล้มเหลวหาก `idempotent_requests` มีข้อมูล

ไฟล์ที่เกี่ยวข้อง:

- `apps/api/prisma/migrations/20260722072226_m1_m2_audit_fixes/migration.sql`
- `apps/api/prisma/schema.prisma`

### วิธีแก้บังคับ

ทำ migration เป็นลำดับ:

```sql
ALTER TABLE idempotent_requests ADD COLUMN expiresAt TIMESTAMP(3);

UPDATE idempotent_requests
SET expiresAt = CASE
  WHEN status = 'DONE' THEN createdAt + INTERVAL '24 hours'
  ELSE createdAt + INTERVAL '5 minutes'
END
WHERE expiresAt IS NULL;

ALTER TABLE idempotent_requests
ALTER COLUMN expiresAt SET NOT NULL;
```

จากนั้นจึงสร้าง index

### ข้อกำหนดเพิ่มเติม

- ห้ามใช้ destructive reset เพื่อแก้ migration
- ต้องทดสอบทั้งฐานข้อมูลว่างและฐานข้อมูลที่มี PENDING/DONE
- ต้องบันทึกจำนวนแถวก่อนและหลัง migration
- ต้องมี rollback หรือ forward-fix plan

### Acceptance Criteria

- Migration ผ่านบนฐานข้อมูลว่าง
- Migration ผ่านบนฐานข้อมูลที่มีข้อมูลเดิม
- จำนวน record ไม่หาย
- ทุก record มี `expiresAt`
- Schema และ migration ตรงกัน
- Migration รันซ้ำตามกลไก Prisma โดยไม่สร้าง schema เพี้ยน

## 4. FIX-02 — แก้ Idempotency Crash Recovery

### ปัญหา

เมื่อ mutation สำเร็จ แต่ process ตายก่อนเปลี่ยน Idempotency เป็น `DONE` แถวจะค้าง `PENDING` เมื่อหมด TTL โค้ดปัจจุบันอาจเรียก mutation ซ้ำ

ผลกระทบที่เป็นไปได้:

- Package ซ้ำ
- Print Job ซ้ำ
- Batch ซ้ำ
- Running number กระโดด
- Movement/Audit ซ้ำ

### แนวทางที่อนุญาต

เลือกหนึ่งแนวทางและบันทึกเหตุผล:

#### แนวทาง A — Transaction เดียวกัน

Idempotency reservation, domain mutation, Audit Log และ response record อยู่ใน database transaction เดียวกัน

ข้อดี: atomic ชัดเจน  
ข้อควรระวัง: response ต้อง serialize และเก็บใน transaction ได้

#### แนวทาง B — Operation ID/Unique Link

เพิ่ม idempotency key หรือ operation ID ลงในตาราง domain ที่ mutation สร้าง เช่น `PrintJob.idempotencyKey` แล้วสร้าง unique constraint

เมื่อพบ PENDING หมดอายุ:

1. ค้นหา domain record ด้วย operation ID
2. ถ้าพบ ให้สร้าง response จาก record เดิมและ mark DONE
3. ถ้าไม่พบ จึงพิจารณารัน mutation

#### แนวทาง C — Outbox/Command Table

เก็บ command และผลลัพธ์เป็น state machine แล้ว worker เป็นผู้ประมวลผล เหมาะกับงานที่ซับซ้อนแต่ไม่ควร over-engineerโดยไม่มีเหตุผล

### สิ่งที่ห้ามทำ

- ห้าม timeout แล้วเรียก `fn()` ซ้ำทันที
- ห้ามลบ PENDING โดยไม่ตรวจ domain result
- ห้ามใช้เวลาอย่างเดียวตัดสินว่า mutation ไม่สำเร็จ

### Acceptance Criteria

- Crash ก่อน mutation → retry ทำงานได้หนึ่งครั้ง
- Crash ระหว่าง mutation → ไม่สร้างข้อมูลซ้ำ
- Crash หลัง mutation แต่ก่อน DONE → replay ผลเดิมได้
- Request พร้อมกัน key เดียวกัน → mutation เกิดครั้งเดียว
- Key เดิม payload ต่างกัน → 409
- User อื่นใช้ key เดิม → ไม่เห็น response ข้ามผู้ใช้
- มี integration test กับ PostgreSQL จริง

## 5. FIX-03 — ป้องกัน Resolve ACK_UNKNOWN ซ้ำ

### ปัญหา

การตัดสินใจ `REQUEUE` เก็บสถานะงานเดิมเป็น `ACK_UNKNOWN` และ CAS ไม่ตรวจ `resolvedAt` จึงสามารถเรียกซ้ำและสร้าง Print Job ใหม่หลายงาน

### วิธีแก้บังคับ

CAS ต้องมีเงื่อนไขอย่างน้อย:

```text
id = jobId
status = ACK_UNKNOWN
resolvedAt IS NULL
```

เลือกการเก็บสถานะหนึ่งแบบ:

#### แบบแนะนำ

เพิ่มสถานะ:

- `RESOLVED_PRINTED`
- `RESOLVED_REQUEUED`

#### แบบขั้นต่ำ

คง `ACK_UNKNOWN` แต่ `resolvedAt` ต้องไม่เป็น null และทุก endpoint ต้อง reject งานที่ resolve แล้ว

### กฎ

- `CONFIRM_PRINTED` ทำได้ครั้งเดียว
- `REQUEUE` สร้างงานใหม่ได้เพียงหนึ่งงาน
- งานใหม่ต้องเชื่อมกลับงานเดิมด้วย `sourceJobId` หรือ `requeuedFromJobId`
- ต้องบันทึก resolver, note, decision และเวลาตัดสินใจ
- การ resolve และสร้างงานใหม่ต้องอยู่ใน transaction เดียวกัน

### Acceptance Criteria

- Resolve request ซ้ำไม่เพิ่ม `reprintCount`
- REQUEUE ซ้ำไม่สร้างงานใหม่เพิ่ม
- Concurrent resolve สอง request สำเร็จเพียงหนึ่ง
- ตรวจสอบสายสัมพันธ์งานเดิมกับงานใหม่ได้
- มี Audit Log เพียงชุดเดียวต่อ resolution

## 6. FIX-04 — แยก Transport Error เป็น `NOT_SENT` และ `MAYBE_SENT`

### ปัญหา

เมื่อเรียก Serial `write()` แล้วเกิด callback/drain error อาจมีบางส่วนหรือทั้งหมดถูกส่งไปแล้ว การ retry อัตโนมัติอาจพิมพ์ซ้ำ

### State/Result ที่ต้องมี

Transport ควรคืนผลหรือ throw typed error:

```text
NOT_SENT
MAYBE_SENT
SENT
```

ตัวอย่างการจัดประเภท:

- เปิด port ไม่ได้ก่อนเรียก write → `NOT_SENT`
- Validation/render error ก่อน write → `NOT_SENT`
- เริ่ม write แล้ว callback error → `MAYBE_SENT`
- write สำเร็จแต่ drain error → `MAYBE_SENT`
- write/drain สำเร็จ → `SENT`

### Backend behavior

- `NOT_SENT` → fail/retry ได้
- `MAYBE_SENT` → `ACK_UNKNOWN` ห้าม auto-retry
- `SENT` → mark SENT แล้ว ACK

### ข้อควรระวัง

`drain()` สำเร็จหมายถึง OS/driver รับข้อมูล ไม่ได้ยืนยันว่ากระดาษออกจริง หากเครื่องพิมพ์ไม่มี status protocol ต้องระบุ semantics ว่า `PRINTED` หมายถึง “Gateway ส่งข้อมูลสำเร็จตามหลักฐานที่อุปกรณ์รองรับ”

### Acceptance Criteria

- เปิด port ไม่ได้ → retry ได้
- write partial/error → ไม่ auto-retry
- drain error → ไม่ auto-retry
- Network หลุดหลัง send → ACK_UNKNOWN
- Gateway restart ระหว่าง write → ACK_UNKNOWN หลัง lease timeout
- Unit test ครบทุก transport result
- Hardware test ด้วยการถอดสายระหว่าง write

## 7. FIX-05 — Backend เป็นผู้ตัดสิน Simulation Mode

### ปัญหา

ACK DTO รับ `simulated` จาก Gateway แล้ว backend เชื่อค่าดังกล่าว Gateway ที่ผิดพลาดหรือถูกยึดสามารถส่ง `simulated=false` เพื่ออัปเดต Package เป็นพิมพ์จริง

### วิธีแก้บังคับ

เพิ่มข้อมูลใน `PrinterDevice` หรือ Gateway registration:

- `environment`: `DEVELOPMENT | TEST | PRODUCTION`
- `transportMode`: `CONSOLE | SERIAL | BLUETOOTH | ...`
- `canConfirmRealPrint`: boolean ที่ backend เป็นผู้กำหนด

เมื่อ ACK:

- Backend อ่าน capability จาก Gateway record
- Console/Test Gateway → `SIMULATED` เท่านั้น
- Production real transport → สามารถ `PRINTED`
- ห้ามรับ `simulated` จาก request เป็นแหล่งความจริง

### Security เพิ่มเติม

- การเปลี่ยน environment/transport ต้อง ADMIN เท่านั้น
- เปลี่ยน capability ต้องมี Audit Log
- Production Gateway credential ห้ามใช้กับ test Gateway

### Acceptance Criteria

- Console Gateway ส่ง ACK แบบใดก็ไม่สามารถทำให้ Package เป็น PRINTED
- Production Gateway ถูกกำหนด capability จาก backend
- Gateway ที่ถูก revoke ACK ไม่ได้
- Capability change มี Audit Log
- มี authorization tests

## 8. FIX-06 — บังคับ HTTPS ใน Production

### ปัญหา

Gateway Production ยังยอม HTTP สำหรับ Private IP ทำให้ `X-Gateway-Key` เดินทางแบบ plaintext ใน LAN

### กฎบังคับ

```text
NODE_ENV=production → API_BASE_URL ต้องเป็น https:// เท่านั้น
NODE_ENV=development/test → http:// อนุญาตเฉพาะ localhost/127.0.0.1
```

Private IP ไม่ใช่เหตุผลให้ยอม HTTP ใน Production

### Acceptance Criteria

- Production + HTTP localhost → start ไม่ได้
- Production + HTTP private IP → start ไม่ได้
- Production + HTTP public IP → start ไม่ได้
- Production + HTTPS → start ได้
- Development + localhost HTTP → start ได้
- Config tests ครบทุกกรณี

## 9. FIX-07 — PostgreSQL Integration/Concurrency Tests

Unit test ด้วย fake Prisma ไม่เพียงพอ ต้องเพิ่ม test suite ที่ใช้ PostgreSQL จริง

### Test cases บังคับ

#### Idempotency

- 10 request พร้อมกัน key เดียวกัน
- key เดิม payload ต่างกัน
- crash before/after mutation
- stale PENDING recovery

#### Print Job

- Gateway สองตัว claim พร้อมกัน
- ACK สอง request พร้อมกัน
- Cancel ชนกับ Claim
- Lease recovery ชนกับ ACK
- Resolve ACK_UNKNOWN พร้อมกัน
- REQUEUE request ซ้ำ

#### Migration

- Database ว่าง
- Database มี idempotency rows
- Database มี print jobs ทุกสถานะ

### Acceptance Criteria

- ไม่มี duplicate Package/Movement/PrintJob
- ไม่มี double `reprintCount`
- Claim หนึ่งงานสำเร็จได้ Gateway เดียว
- Resolve หนึ่งงานสำเร็จเพียงครั้งเดียว
- Test ทำซ้ำหลายรอบโดยผลคงที่

## 10. FIX-08 — Hardware Verification

### สิ่งที่ต้องทดสอบกับ A318BT จริง

- ตรวจว่า USB ปรากฏเป็น Serial/COM port จริง
- ยืนยัน baud rate และ serial parameters
- พิมพ์ Bitmap 60 × 40 มม.
- ข้อความไทย
- QR readability
- Label ก่อนนึ่งแสดงคำเตือน
- Label หลังนึ่งแสดงวันที่จาก backend
- พิมพ์ต่อเนื่อง 100–500 ใบ
- ปิด/เปิดเครื่องพิมพ์
- ถอดสายก่อน write
- ถอดสายระหว่าง write
- ถอดสายหลัง write ก่อน ACK
- Gateway restart
- Network interruption

### หลักฐานที่ต้องเก็บ

- รุ่น/serial ของเครื่องทดสอบ
- OS/Gateway version
- Transport config
- Label sample ที่อนุมัติ
- จำนวนสำเร็จ/ล้มเหลว
- QR scan success rate
- Error log ที่ไม่มี secret

### Acceptance Criteria

- QR readability ≥ 99.5%
- ภาษาไทยไม่เป็น tofu/สี่เหลี่ยม
- ไม่มี label duplicate จาก automatic retry
- ทดสอบต่อเนื่องผ่านตามจำนวนที่กำหนด
- มี Golden Label Sample

## 11. งาน PWA หลังแก้ Backend/Gateway

ห้ามเชื่อมปุ่มพิมพ์ก่อน FIX-01 ถึง FIX-07 ผ่าน

เมื่อผ่านแล้วให้สร้าง:

- PrintJob model/repository
- Printer selection
- สร้าง Print Job พร้อม Idempotency-Key
- Poll status
- แสดง QUEUED/CLAIMED/PRINTING/SENT/PRINTED
- แสดง SIMULATED เฉพาะ development
- แสดง ACK_UNKNOWN และคำแนะนำติดต่อ Supervisor
- Dead-letter UI
- Cancel เฉพาะ QUEUED
- Reprint reason dialog
- Supervisor resolution UI
- หยุดใช้ `recordPrint()` จาก PWA

## 12. ลำดับการพัฒนา

```text
1. FIX-01 Migration
2. FIX-02 Idempotency crash recovery
3. FIX-03 ACK_UNKNOWN one-time resolution
4. FIX-04 Transport typed result
5. FIX-05 Backend-controlled simulation
6. FIX-06 Production HTTPS
7. FIX-07 PostgreSQL integration tests
8. FIX-08 Hardware verification
9. PWA Print Job integration
10. UAT/Security review
```

## 13. Definition of Done ต่อ Fix

แต่ละ Fix ถือว่าเสร็จเมื่อ:

- มี test ที่ fail ก่อนแก้หรือพิสูจน์ defect ได้
- Implementation เล็กและตรงปัญหา
- Unit tests ผ่าน
- PostgreSQL integration tests ผ่านเมื่อเกี่ยวข้อง
- Type check/lint/build ผ่าน
- มี Audit Log เมื่อเป็น mutation/security event
- ไม่มี secret ใน log
- มี migration/rollback plan เมื่อ schema เปลี่ยน
- มี known limitations
- ผ่าน review โดยมนุษย์

## 14. สิ่งที่ AI ต้องรายงานหลังทำงาน

```text
Fix ID:
ไฟล์ที่เปลี่ยน:
ปัญหาเดิม:
แนวทางที่ใช้:
เหตุผลด้านความปลอดภัย:
Tests ที่เพิ่ม:
Tests ที่รันและผลลัพธ์:
Migration impact:
Known limitations:
สิ่งที่ยังไม่ได้ทดสอบ:
พร้อม Pilot หรือไม่:
```

## 15. Pilot Gate

ห้ามเริ่ม Pilot จนกว่า:

- FIX-01 ถึง FIX-07 ผ่านทั้งหมด
- FIX-08 มีผลทดสอบเครื่องจริง
- Critical defect = 0
- High defect = 0
- Migration dry run ผ่าน
- PostgreSQL concurrency tests ผ่าน
- Gateway Production ใช้ HTTPS
- Console Gateway ทำให้ Package เป็น PRINTED ไม่ได้
- ACK_UNKNOWN resolve ได้ครั้งเดียว
- MAYBE_SENT ไม่ auto-retry
- UAT ได้รับอนุมัติ

## 16. Prompt สำหรับสั่ง AI แก้ไข

```text
อ่าน AGENTS.md, AI_DEVELOPMENT_GUARDRAILS.md,
M1_M2_REQUIRED_FIXES.md และ M1_M2_REAUDIT_FIX_DIRECTIVE.md ให้ครบ

ทำ Fix ตามลำดับทีละ Fix เท่านั้น เริ่มจาก read-only inspection
ห้ามเปลี่ยนกฎโดเมน state machine RBAC expiry QR payload หรือ stack เอง
เขียน test เพื่อพิสูจน์ defect ก่อนหรือพร้อม implementation
ห้าม auto-retry งานพิมพ์ที่อาจส่งถึงเครื่องแล้ว
ห้าม reclaim idempotency แล้ว rerun mutation โดยไม่มี reconciliation
หากต้อง destructive migration, เพิ่ม dependency, เปลี่ยน architecture
หรือแตะ Production ให้หยุดขออนุมัติ

หลังทำเสร็จให้รายงานตามหัวข้อในส่วนที่ 14
ห้ามกล่าวว่าเสร็จหรือพร้อม Pilot หาก Acceptance Criteria ยังไม่ครบ
```

---

เอกสารนี้เป็น Development/Security Directive ไม่แทน SOP โรงพยาบาล การทดสอบเครื่องพิมพ์จริง Penetration Test หรือ UAT
