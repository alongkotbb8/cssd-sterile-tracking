# AI Development Guardrails — CSSD Sterile Tracking

> เอกสารนี้เป็นข้อบังคับสำหรับ AI และนักพัฒนาทุกคนที่ทำงานกับระบบนี้  
> ต้องอ่าน `AGENTS.md` และไฟล์นี้ให้ครบก่อนวางแผน เขียน แก้ หรือ review โค้ด  
> หากข้อกำหนดขัดกัน ให้ใช้กฎที่ปลอดภัยต่อผู้ป่วยและเข้มงวดกว่า และหยุดถามผู้ใช้ก่อนเปลี่ยนพฤติกรรมระบบ

## 1. เป้าหมายระบบ

สร้างระบบ CSSD ที่ใช้งานหลักผ่าน **Chrome PWA + กล้องสแกน QR + Print Gateway** โดยไม่ต้องติดตั้ง Mobile Application และต้องรักษา traceability รายห่อครบวงจร

เส้นทางหลัก:

```text
Chrome PWA
  → NestJS API
  → PostgreSQL
  → Print Job Queue
  → Print Gateway
  → เครื่องพิมพ์ Label
```

การใช้งานต้องครอบคลุม:

- Authentication และ RBAC
- Master data
- สร้างห่อและเลขรันจาก backend
- สแกนห่อเข้ารอบนึ่ง
- บันทึกผล CI/BI
- เบิกออกและระบุแผนกปลายทาง
- ส่งคืนและระบุแผนกที่ส่งคืน
- Recall ราย batch
- FEFO และการบล็อกของหมดอายุ
- Label และ QR
- Print/Reprint traceability
- Tagging
- Dashboard และ Reports
- Audit Log
- Offline queue ในเฟสที่ได้รับอนุมัติ

## 2. หลักการที่ห้ามละเมิด

1. ความปลอดภัยผู้ป่วยสำคัญกว่าความสะดวกและความเร็ว
2. เมื่อข้อมูลไม่แน่นอนให้ fail closed
3. ห้ามสร้างหรือคาดเดาข้อมูลการนึ่งและวันหมดอายุ
4. ห้ามเชื่อข้อมูลหรือสิทธิ์จาก UI โดยไม่ตรวจซ้ำที่ backend
5. ทุก mutation สำคัญต้อง atomic, idempotent และมี Audit Log
6. ห้ามถือว่าเปิด Print Dialog เท่ากับพิมพ์สำเร็จ
7. ห้ามให้ PWA ตั้งสถานะ Print Job เป็น `PRINTED`
8. ห้ามใช้ข้อมูลผู้ป่วยหรือข้อมูล Production ใน development/test
9. ห้ามใส่ secret, token, password หรือ private key ลง repository
10. ห้ามเปลี่ยน stack, state machine หรือกฎโดเมนโดยไม่ได้รับอนุมัติ

## 3. กฎโดเมนบังคับ

### 3.1 อายุการปลอดเชื้อ

- `SEAL` = วันที่นึ่ง + 180 วัน
- `CLOTH` = วันที่นึ่ง + 7 วัน
- backend เป็นผู้คำนวณ `sterilize_date` และ `expiry_date`
- client ห้ามส่ง `expiry_date` เพื่อกำหนดค่าเอง
- `expiry_date` คือวันสุดท้ายที่ยังใช้ได้ เว้นแต่ผู้ใช้ยืนยัน SOP อื่นเป็นลายลักษณ์อักษร
- เมื่อหมดอายุแล้วต้องบล็อก OUT ทุกช่องทาง

### 3.2 Running number

- สร้างจาก backend เท่านั้น
- รูปแบบ `{SET_CODE}-{YYYYMMDD}-{SEQ4}`
- ห้ามสุ่มหรือสร้างเลขบน client
- Offline ต้องใช้เลขจาก pool ที่ backend จองไว้เท่านั้น
- ต้องมี unique constraint และ concurrency test

### 3.3 QR

- QR บรรจุเฉพาะ `package_id`
- ห้ามใส่ชื่อชุด วันนึ่ง วันหมดอายุ สถานะ หรือข้อมูลบุคคลลง QR
- ต้อง validate รูปแบบและจำกัดความยาวก่อน lookup

### 3.4 FEFO

- รายการแนะนำเบิกต้องเรียง expiry ใกล้ที่สุดก่อน
- ต้องมี test กรณีวันเท่ากัน, null และหมดอายุ

### 3.5 Department

- OUT ต้องมี `dept_id`
- `receiver_name` เป็น nullable
- RETURN ต้องมี `dept_id` ของแผนกที่ส่งคืน
- `PACKED_OUT` ควรใช้ปลายทางชนิด `external`; หากจะยอมให้ชนิดอื่นต้องขออนุมัติ

### 3.6 Sterilization Batch

ลำดับบังคับ:

```text
สร้างห่อ PACKED
→ ผูกห่อเข้า Batch PENDING
→ ดำเนินการนึ่ง
→ SUPERVISOR/ADMIN บันทึก CI/BI
→ PASSED: ห่อเป็น STERILE และคำนวณ expiry
→ FAILED: ห้ามเป็น STERILE และต้องจัดการ recall/reprocess ตาม SOP
```

- ห้ามเพิ่มห่อย้อนหลังเข้า batch ที่บันทึกผลแล้ว
- CSSD role ห้ามรับรอง CI/BI
- การผ่าน batch, เปลี่ยน package, สร้าง movement และ audit ต้องอยู่ใน transaction
- Batch failed ต้องค้นและแสดงตำแหน่งปัจจุบันของทุกห่อได้

### 3.7 State machine

```text
PACKED → STERILE → ISSUED → RETURNED → PACKED
PACKED → PACKED_OUT → PACKED
ทุกสถานะ → DISCARDED
STERILE ที่เกิน expiry → ถือว่า EXPIRED สำหรับการใช้งานและต้องบล็อก OUT
```

- ห้าม transition นอกเหนือจากที่กำหนด
- ทุก transition ต้องมี guard ฝั่ง backend
- ทุก transition ต้องมี unit/integration test

## 4. Architecture เป้าหมาย

### 4.1 Chrome PWA

รับผิดชอบ:

- UI ภาษาไทย
- กล้องสแกน QR
- แสดงผล lookup และสถานะ
- เก็บรายการก่อนยืนยัน
- ส่ง mutation พร้อม Idempotency-Key
- แสดงผลสำเร็จ/ล้มเหลวรายห่อ
- สร้าง Print Job request
- แสดงสถานะ Print Job จาก backend
- Offline queue เมื่อได้รับอนุมัติให้พัฒนาเฟสนั้น

PWA ห้าม:

- คำนวณวันหมดอายุเป็นแหล่งความจริง
- เปลี่ยนสถานะ package โดยตรง
- สร้าง running number เอง
- ยืนยันว่าพิมพ์สำเร็จ
- เก็บ Gateway secret

### 4.2 Backend API

รับผิดชอบ:

- Authentication/RBAC
- Validation
- Domain guards
- Transactions
- Idempotency
- Audit Log
- FEFO
- Batch/Recall
- Print Job Queue
- Reports
- Gateway authentication

### 4.3 Print Gateway

รับผิดชอบ:

- Authentication ด้วย credential แยกต่อ Gateway
- Heartbeat
- Claim Print Job แบบ atomic
- ส่ง TSPL/Bitmap ไปเครื่องพิมพ์
- Retry ที่ควบคุมได้
- รายงาน success/failure กลับ backend
- เก็บ local queue ชั่วคราวเมื่อ network ขัดข้อง
- Auto-start และ recover หลัง restart

Gateway ห้าม:

- รับงานที่ไม่ได้ผูกกับ printer ของตน
- เปลี่ยนข้อมูล label เอง
- ส่ง `PRINTED` โดยไม่เคย claim job
- log secret หรือ Authorization header
- เปิด endpoint unauthenticated ใน LAN

## 5. Print Job Design บังคับ

สถานะขั้นต่ำ:

```text
QUEUED → CLAIMED → PRINTING → PRINTED
                     ↘ FAILED → RETRYING → DEAD_LETTER
QUEUED/CLAIMED → CANCELLED
```

ข้อมูลขั้นต่ำ:

- `job_id`
- `package_id`
- `printer_id`
- `requested_by`
- `status`
- `attempt_count`
- `is_reprint`
- `reprint_reason`
- `payload_hash`
- `created_at`
- `claimed_at`
- `printed_at`
- `failed_at`
- `error_code`

กฎ:

- Reprint ต้องมีเหตุผล
- Retry ต้องใช้ `job_id` เดิม
- Gateway claim ต้องใช้ compare-and-swap หรือ database locking
- `printedAt` และ `reprintCount` อัปเดตเมื่อ Gateway ACK สำเร็จเท่านั้น
- Print Job และ Audit Log ต้อง commit ร่วมกัน
- ACK ซ้ำต้องไม่เพิ่ม reprint count
- Payload ต้องสร้างจากข้อมูล backend และตรวจ hash
- งานค้างต้องมี lease timeout และ recovery

## 6. Idempotency บังคับ

ทุก mutation จาก PWA ต้องส่ง `Idempotency-Key` โดยเฉพาะ:

- สร้าง Package
- Scan in batch
- Scan out
- Scan return
- สร้าง Print Job
- Retry/Reprint
- บันทึกผล batch

Idempotency record ต้องผูกกับ:

- key
- user ID หรือ Gateway ID
- endpoint
- HTTP method
- request hash
- response
- status
- created/expiry time

ห้ามใช้ flow แบบ `find → execute → store` ที่ไม่ atomic เพราะ request พร้อมกันอาจผ่านทั้งคู่

ต้องทดสอบ:

- key เดิม + payload เดิม → response เดิม
- key เดิม + payload ต่างกัน → reject
- request พร้อมกันสองตัว → execute เพียงครั้งเดียว
- user อื่นใช้ key เดิม → ไม่เห็น response ของกันและกัน

## 7. Chrome PWA และกล้อง

- Production ต้องใช้ HTTPS
- ห้ามอนุญาต PWA HTTPS เรียก HTTP API/Gateway เพราะ Chrome จะบล็อก Mixed Content
- Web camera ควรให้ scanner library จัดการ `getUserMedia` โดยตรง
- หลีกเลี่ยงการเปิดกล้องสองรอบจาก permission library และ scanner library
- เลือกกล้องหลังเป็นค่าเริ่มต้น
- ตรวจ capability ก่อนแสดง torch/zoom
- เมื่อ permission ถูกปฏิเสธ ให้แสดงขั้นตอน Chrome Site Settings
- ต้องมี fallback manual entry หรือ keyboard scanner
- Manual entry ต้องมี validation, RBAC ตามความเสี่ยง และ Audit Log
- ต้อง debounce QR เดิม
- ต้องหยุด camera เมื่อออกจากหน้าและ recover เมื่อกลับมา
- ต้องทดสอบหลาย tab, reload, background/resume และ browser update

## 8. Offline-first

> ⚠️ **ยกเลิกตามการตัดสินใจล่าสุด (23 ก.ค. 2026) — ระบบเป็น Online-only**
> (ดู `ONLINE_ONLY_XPRINTER_REMAINING_WORK.md`) ไม่พัฒนา offline-first แล้ว: ไม่มี
> drift/IndexedDB, mutation queue, sync worker, conflict UI, reserved number pool ฝั่ง client
> เน็ตหลุด = **fail closed** (ห้ามทำ mutation, ห้ามแสดงสำเร็จก่อน backend ตอบ, retry รักษา
> Idempotency-Key เดิม) หัวข้อด้านล่างเก็บไว้เป็นบันทึกอ้างอิงเดิมเท่านั้น

ห้ามเรียกว่ารองรับ Offline จนกว่าจะมีครบ:

- IndexedDB/Drift storage
- cached master data
- cached package lookup ที่มี timestamp
- mutation queue
- sync worker
- Idempotency-Key คงเดิมเมื่อ retry
- conflict state และ conflict UI
- จำนวนรายการรอ sync
- logout guard เมื่อมีรายการค้าง
- reserved running-number pool
- automated tests สำหรับ offline/online transition

กฎ fail closed:

- หากยืนยันสถานะล่าสุดหรือวันหมดอายุไม่ได้ ห้าม OUT
- Conflict ห้ามถูกเขียนทับเงียบ ๆ
- ห้ามสร้างเลขใหม่เมื่อ pool หมด

## 9. Security Baseline

### Authentication

- JWT secret จาก secret manager/env เท่านั้น
- Access token ต้องมีอายุ
- ตรวจ user status และ role ใหม่ทุก request สำคัญ
- มี account lockout/progressive delay
- รองรับ revoke session หรือ remote logout ก่อน Production

### Authorization

- ตรวจที่ backend ทุก endpoint
- UI visibility ไม่ถือเป็น security control
- เขียน RBAC matrix และ automated authorization tests
- CI/BI และ Recall จำกัด SUPERVISOR/ADMIN
- Master data จำกัดตาม role ที่กำหนด

### Transport

- HTTPS/WSS เท่านั้นใน Production
- เปิด HSTS
- CORS ใช้ allowlist แบบ exact origin
- ห้ามใช้ wildcard CORS ร่วมกับ credential

### Web security headers

- Content-Security-Policy
- `frame-ancestors 'none'`
- Strict-Transport-Security
- Referrer-Policy
- X-Content-Type-Options
- Permissions-Policy โดยอนุญาต camera เฉพาะ self

### Input/Output

- DTO validation ทุก endpoint
- จำกัด array size, string length และ request body
- Encode/escape output
- ห้ามส่ง stack trace หรือ database error ให้ client
- ห้าม log password, token, secret หรือข้อมูลละเอียดอ่อน

### Data

- Audit Log เป็น append-only
- ห้ามลบ Audit Log จาก UI ทั่วไป
- กำหนด retention/archive policy ก่อน cleanup
- Backup ต้องเข้ารหัสและทดสอบ restore
- ห้ามใช้ production dump ใน test

### Dependencies

- เพิ่ม dependency เท่าที่จำเป็น
- ตรวจผู้ดูแล, release history, vulnerability และ license
- ใช้ lockfile
- ห้าม upgrade major version แบบรวมหลาย package โดยไม่มี regression test

## 10. Threats ที่ต้องมี Test

- IDOR
- privilege escalation
- JWT replay/expiry
- inactive user
- brute force
- injection
- oversized payload
- duplicate scan
- concurrent scan
- request replay
- idempotency key collision
- Print Job spoofing
- fake Gateway ACK
- Gateway credential theft/revocation
- XSS และ token theft
- Clickjacking
- malicious QR input
- offline conflict
- stale PWA cache
- dependency compromise

## 11. Audit Log บังคับ

ทุกเหตุการณ์ต่อไปนี้ต้องมี Audit Log:

- Login success/failure ตามนโยบายที่ไม่เปิดเผยข้อมูลเกินจำเป็น
- Package create/discard
- Batch create/result/recall
- Scan in/out/return
- Expired scan blocked
- Manual entry
- Tag add/remove
- Print request/claim/success/failure/cancel/retry/reprint
- Gateway register/revoke
- Master data change
- User/role/status change
- Report export ที่มีข้อมูลสำคัญ
- Archive/cleanup

Mutation หลักและ Audit Log ต้องอยู่ใน transaction เดียวกัน

## 12. Testing Requirements

### Unit tests

- Expiry SEAL/CLOTH
- FEFO
- State machine
- Batch pass/fail
- Recall
- Idempotency
- Print Job transitions
- Retry/reprint count

### Integration tests

- Database constraints
- Transaction rollback
- Concurrent requests
- RBAC matrix
- Audit completeness
- Gateway claim/lease/ACK

### PWA tests

- Camera allow/deny/re-allow
- Front/back camera
- QR duplicate debounce
- background/resume
- refresh during mutation
- multiple tabs
- slow/offline network
- stale service worker
- accessibility and responsive layout

### Hardware tests

- Xprinter XP-420B connection (USB printer-class → `usb_spool`; ดู `HARDWARE_VERIFICATION.md`)
- Label 60 × 40 mm
- Thai text
- QR readability
- 100–500 consecutive labels
- printer off/on
- paper out/cover open หาก hardware รายงานได้
- Gateway restart
- network interruption
- duplicate retry

### Security tests

- OWASP API scenarios
- unauthorized roles
- IDOR
- replay
- brute force
- malicious payload
- Gateway impersonation
- dependency vulnerability scan

## 13. Definition of Done

ฟีเจอร์ถือว่าเสร็จเมื่อครบทุกข้อ:

- Requirement และ acceptance criteria ชัดเจน
- มี threat analysis ตามความเสี่ยง
- มี test ก่อนหรือพร้อม implementation
- ผ่าน lint/type check
- ผ่าน unit/integration tests
- ผ่าน authorization tests
- Mutation มี Audit Log
- ไม่มี secret ใน code/log
- มี migration และ rollback plan หากเปลี่ยน schema
- มีเอกสาร API/operation
- มีข้อความ UI ภาษาไทยใน i18n
- ผ่าน review โดยมนุษย์
- ไม่มี Critical/High defect ที่เกี่ยวข้องค้างอยู่

ห้ามรายงานว่า “เสร็จ” เพียงเพราะ compile ผ่าน

## 14. Human Approval Gates

AI ต้องหยุดและขออนุมัติก่อน:

- เปลี่ยน state machine
- เปลี่ยนกฎ expiry
- เปลี่ยนผู้มีสิทธิ์ CI/BI หรือ Recall
- เปลี่ยน QR payload
- เปลี่ยน running-number format
- เปลี่ยน stack/database/framework
- เพิ่ม dependency ที่กระทบ Production
- ทำ destructive migration
- ลบ/cleanup/archive ข้อมูล
- จัดการ Production secrets
- Deploy Production
- เปลี่ยน Backup/Retention policy
- ยอมรับความเสี่ยง Critical/High

## 15. Git และการเปลี่ยนแปลง

- ตรวจ `git status` ก่อนเริ่ม
- รักษางานเดิมของผู้ใช้
- ห้าม reset, checkout ทับ หรือ cleanup ไฟล์ของผู้ใช้
- เปลี่ยนทีละฟีเจอร์
- commit เล็กและมีความหมาย
- ห้ามรวม refactor ที่ไม่เกี่ยวข้องกับ security fix/feature
- สรุปไฟล์ที่แก้, เหตุผล, test และ known limitations ทุกครั้ง
- Database migration ต้อง additive เมื่อเป็นไปได้
- ต้องมี rollback/forward-fix plan

## 16. ลำดับการพัฒนาบังคับ

### Milestone 1 — Online PWA Pilot

1. Chrome camera flow
2. QR validation/debounce/manual fallback
3. PWA Idempotency-Key
4. Atomic backend idempotency
5. Scan result summary/retry failed items
6. HTTPS/CSP/security headers
7. End-to-end tests

### Milestone 2 — Print Gateway Pilot

1. Printer/PrintJob schema
2. Print Job APIs
3. Gateway authentication/heartbeat
4. Atomic claim and lease
5. A318BT adapter
6. ACK/failure/retry/dead-letter
7. Print audit/reprint reason
8. Hardware soak test

### Milestone 3 — Offline

1. IndexedDB/local database
2. Cached master data
3. Mutation queue
4. Sync/conflict UI
5. Reserved number pool
6. Offline security and concurrency tests

### Milestone 4 — Reports/Operations

1. Excel exports
2. Recall/return/print/security reports
3. Monitoring and alerts
4. Backup/restore drill
5. UAT and pilot sign-off

ห้ามเริ่มทุก milestone พร้อมกันโดยไม่มีเหตุผลและผู้รับผิดชอบชัดเจน

## 17. Go-Live Gate

Production ต้องผ่าน:

- Critical defects = 0
- High defects = 0
- QR readability ≥ 99.5%
- Expired package blocked = 100%
- ไม่มี duplicate Movement ใน concurrency/retry tests
- Print Job traceability ครบ
- Recall แสดงตำแหน่งครบ
- RBAC tests ผ่านทุก role
- Backup/restore ผ่าน
- Gateway revoke/recovery ผ่าน
- Penetration test ไม่มี Critical/High ค้าง
- UAT ได้รับการอนุมัติจากผู้รับผิดชอบ CSSD
- มี SOP เมื่อ PWA, API, network หรือ printer ล่ม

## 18. รูปแบบการทำงานของ AI ต่อหนึ่งฟีเจอร์

AI ต้องทำตามลำดับ:

```text
1. อ่าน AGENTS.md และไฟล์นี้
2. ตรวจโค้ดและ git status
3. สรุป requirement/assumption/risk
4. ระบุไฟล์ที่จะเปลี่ยน
5. เขียนหรือปรับ test
6. Implement แบบเล็กที่สุด
7. รัน test/lint/type check
8. ทำ security review ของ diff
9. ตรวจ regression ต่อ state machine/RBAC/Audit
10. สรุปผล หลักฐาน Known limitations และงานถัดไป
```

หาก test รันไม่ได้ ต้องระบุสาเหตุ ห้ามกล่าวอ้างว่าผ่าน

## 19. Prompt เริ่มงานที่แนะนำ

```text
อ่าน AGENTS.md และ AI_DEVELOPMENT_GUARDRAILS.md ให้ครบก่อนทำงาน
ทำเฉพาะ Milestone/ฟีเจอร์ที่ได้รับมอบหมาย
ห้ามเปลี่ยนกฎโดเมน state machine RBAC expiry QR payload หรือ stack เอง
เริ่มด้วย read-only inspection และสรุป risk/acceptance criteria
เขียน test คู่ implementation และตรวจ security ของ diff
หากต้องทำ destructive action, migration เสี่ยง, เพิ่ม dependency หรือแตะ Production ให้หยุดขออนุมัติ
รายงานผลตาม Definition of Done และห้ามกล่าวว่าเสร็จหากยังไม่ได้ทดสอบ
```

---

เอกสารนี้ไม่แทน SOP โรงพยาบาล การอนุมัติจากผู้เชี่ยวชาญ CSSD การทดสอบฮาร์ดแวร์จริง Security assessment หรือ UAT
