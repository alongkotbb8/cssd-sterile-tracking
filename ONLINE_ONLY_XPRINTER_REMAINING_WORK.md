# สรุปงานคงเหลือ — Online-only และ Xprinter XP-420B

วันที่จัดทำ: 23 กรกฎาคม 2026  
ขอบเขต: Chrome PWA + NestJS API + PostgreSQL + Print Gateway + Xprinter XP-420B

## 1. ข้อกำหนดที่ยืนยันแล้ว

- ใช้งานผ่าน **Chrome PWA**
- ใช้เครื่องพิมพ์ **Xprinter XP-420B รุ่น USB**
- เครื่องพิมพ์ความละเอียด **203 DPI**
- ฉลากเป้าหมายขนาด **60 × 40 มม.**
- ใช้ Print Job Queue และ Print Gateway
- ยกเลิกการรองรับ Offline ทั้งหมด
- เมื่อไม่มีเครือข่าย ระบบต้อง **fail closed**
- PWA ห้ามกำหนดสถานะ `PRINTED` เอง
- QR ต้องบรรจุเฉพาะ `package_id`

สถาปัตยกรรมเป้าหมาย:

```text
Chrome PWA
  → HTTPS
NestJS API
  → PostgreSQL
  → Print Job Queue
  → HTTPS + Gateway Credential
Print Gateway
  → USB Printer Queue แบบ RAW
Xprinter XP-420B
```

## 2. สถานะระบบปัจจุบัน

ส่วนสำคัญที่มีแล้ว:

- Authentication และ RBAC
- Running number จาก backend
- คำนวณ expiry ฝั่ง backend
- State machine และการบล็อกของหมดอายุ
- Scan IN/OUT/RETURN
- Batch, CI/BI และ Recall
- Tagging
- Reports เบื้องต้น
- Atomic idempotency
- Print Job Queue
- Gateway authentication และ heartbeat
- Gateway key rotate/revoke
- Atomic claim, lease และ recovery
- Retry, dead letter และ `ACK_UNKNOWN`
- Backend ตัดสิน `PRINTED` หรือ `SIMULATED`
- PWA สร้างและติดตาม Print Job
- หน้ารายการและรายละเอียดงานพิมพ์
- ยกเลิกงานได้เฉพาะ `QUEUED`
- Supervisor resolve `ACK_UNKNOWN`
- กล้อง QR, debounce และ manual entry
- HTTPS/CORS/CSP/HSTS baseline

ผลทดสอบล่าสุดที่ยืนยันได้:

- API unit tests: **100/100 ผ่าน**
- Print Gateway tests: **25/25 ผ่าน**
- API build: **ผ่าน**
- Print Gateway build: **ผ่าน**

ข้อจำกัดของหลักฐาน:

- ยังไม่ได้ยืนยัน Flutter analyze/test ในรอบล่าสุด เนื่องจาก Flutter SDK ต้องเขียน cache นอก workspace
- PostgreSQL integration tests ต้องรันซ้ำใน environment ที่มี PostgreSQL พร้อมใช้งาน
- ยังไม่ได้ทดสอบ XP-420B จริง

## 3. ยกเลิก Offline ทั้งหมด

### 3.1 สิ่งที่ไม่ต้องพัฒนาต่อ

- Drift/IndexedDB สำหรับ workflow
- Cached package lookup สำหรับทำ mutation
- Mutation queue
- Background sync worker
- Conflict UI
- Pending sync counter
- Offline logout guard
- Reserved running-number pool สำหรับ client
- Offline/online transition tests
- Local print queue ที่อนุญาตให้สร้างงานใหม่ขณะ API ใช้งานไม่ได้

### 3.2 พฤติกรรม Online-only

เมื่อ PWA ติดต่อ API ไม่ได้:

- ห้าม OUT
- ห้าม RETURN
- ห้ามบันทึกผล Batch
- ห้ามสร้าง Package
- ห้ามสร้าง Print Job
- ห้ามคำนวณสถานะหรือ expiry จาก cache เพื่ออนุมัติ operation
- ห้ามแสดงผลสำเร็จก่อน backend ตอบ
- ต้องแสดงข้อความภาษาไทยว่าไม่สามารถเชื่อมต่อระบบ
- เก็บรายการที่ผู้ใช้เตรียมไว้ในหน่วยความจำของหน้าจอได้ชั่วคราว แต่ห้ามถือว่า commit แล้ว
- เมื่อเชื่อมต่อกลับมา ผู้ใช้เป็นผู้กดลองใหม่
- การ retry operation เดิมต้องรักษา `Idempotency-Key` เดิม

งานพิมพ์ที่สร้างและ commit อยู่ใน backend แล้วสามารถรอใน Print Job Queue จน Gateway กลับมาออนไลน์ได้ โดยไม่ถือว่าเป็น Offline workflow ของ PWA

### 3.3 งานเก็บกวาด

ตรวจการใช้งานก่อนพิจารณาถอด:

- `drift`
- `drift_flutter`
- `drift_dev`
- local database code
- sync queue code
- reserved number pool API

ห้ามลบ schema, migration หรือ endpoint แบบ destructive โดยไม่ได้รับอนุมัติ ต้องตรวจ consumer และจัดทำ forward-fix/rollback plan ก่อน

## 4. Xprinter XP-420B

ข้อมูลที่ยืนยัน:

- รุ่น: Xprinter XP-420B
- การเชื่อมต่อของเครื่องที่เลือก: USB
- ความละเอียด: 203 DPI
- รองรับ TSPL/TSPL2 emulation
- รองรับฉลาก 60 × 40 มม.

### 4.1 ส่วนที่ใช้ต่อได้

Label Renderer ปัจจุบันใช้:

- TSPL
- Bitmap
- 203 DPI
- ข้อความไทยจากฟอนต์ที่ bundle
- QR จาก `package_id`

จึงสามารถใช้แนวทางเดิมต่อได้ แต่ต้อง calibrate และพิสูจน์กับเครื่องจริง

### 4.2 ช่องว่างของ Transport

Gateway ปัจจุบันรองรับ:

- `ConsoleTransport`
- `SerialTransport`

XP-420B รุ่น USB โดยทั่วไปทำงานผ่าน USB Printer Class/Printer Queue ไม่ใช่ virtual serial port ดังนั้นต้องเพิ่ม transport เช่น:

```text
PrinterTransport
├── ConsoleTransport
├── SerialTransport
└── UsbSpoolTransport / RawPrintTransport
```

Transport ใหม่ต้อง:

- เลือก printer queue ด้วยชื่อคงที่
- ส่ง TSPL แบบ RAW
- ไม่เปิด browser print dialog
- กำหนด timeout
- ป้องกัน command/shell injection
- ไม่ log credential หรือข้อมูลละเอียดอ่อน
- จำแนกผล `NOT_SENT`, `MAYBE_SENT` และ `SENT`
- ห้าม auto-retry เมื่อเป็น `MAYBE_SENT`

วิธี implementation ต้องเลือกตาม OS ของเครื่อง Gateway:

- Windows: Windows Printer Spooler/RAW queue
- macOS/Linux: CUPS raw queue

ข้อมูลที่ยังต้องยืนยัน: **เครื่องที่รัน Print Gateway ใช้ Windows, macOS หรือ Linux**

### 4.3 Backend capability

เพิ่ม transport mode เช่น:

```text
USB_SPOOL
```

ค่าของ Gateway จริงควรเป็น:

```text
environment=PRODUCTION
transportMode=USB_SPOOL
canConfirmRealPrint=true
```

ต้องรักษากฎ:

- Console/Test/Development → `SIMULATED`
- Production + real transport เท่านั้น → `PRINTED`
- เปลี่ยน capability ได้เฉพาะ ADMIN
- Capability change ต้องมี Audit Log
- Gateway ที่ถูก revoke ต้อง ACK ไม่ได้

### 4.4 Configuration

ตัวอย่าง configuration เป้าหมาย:

```env
NODE_ENV=production
PRINTER_MODEL=XP-420B
PRINTER_TRANSPORT=usb_spool
PRINTER_QUEUE_NAME=CSSD-XP420B-01
PRINTER_DPI=203
LABEL_WIDTH_MM=60
LABEL_HEIGHT_MM=40
```

ต้องยืนยันค่ากับกระดาษจริง:

- `SIZE`
- `GAP` หรือ `BLINE`
- `DIRECTION`
- `REFERENCE`
- `DENSITY`
- `SPEED`
- Bitmap ประมาณ 480 × 320 pixels ที่ 203 DPI

## 5. Hardware Verification

ก่อน Pilot ต้องผ่าน:

- OS และ driver พบ XP-420B
- Printer queue ใช้ชื่อคงที่
- ส่ง TSPL RAW ได้
- ภาษาไทยไม่เป็น tofu/สี่เหลี่ยม
- QR มีเฉพาะ `package_id`
- QR readability ≥ 99.5%
- ฉลาก 60 × 40 มม. ไม่ล้น
- Gap calibration ไม่เลื่อน
- ทิศทางฉลากถูกต้อง
- พิมพ์ต่อเนื่อง 100–500 ใบ
- ทดสอบกระดาษหมด
- ทดสอบฝาเปิด หาก hardware รายงานได้
- ปิด/เปิดเครื่อง
- ถอด USB ก่อนส่ง
- ถอด USB ระหว่างส่ง
- API/network interruption
- Gateway restart
- ไม่มี automatic duplicate print
- เก็บ Golden Label Sample

ข้อควรเข้าใจ:

> Printer spooler รับข้อมูลสำเร็จไม่ได้ยืนยันว่ากระดาษออกจริง นิยาม `PRINTED` ต้องระบุใน SOP ว่าเป็นการส่งข้อมูลสำเร็จตามหลักฐานที่อุปกรณ์รองรับ และผู้ปฏิบัติงานต้องตรวจฉลากจริง

## 6. Gateway Production Readiness

งานที่ยังเหลือ:

- XP-420B USB transport
- Unit tests ของ transport
- Error classification tests
- Auto-start หลังเปิดเครื่อง
- Restart เมื่อ process crash
- Structured logging
- Log rotation
- Gateway version reporting
- Heartbeat monitoring
- Alert เมื่อ Gateway offline
- Printer queue health
- Dead-letter/ACK_UNKNOWN alerts
- Key rotation/revoke drill
- Installer หรือ deployment procedure
- Operation และ troubleshooting guide

## 7. Chrome PWA

### 7.1 Network UX สำหรับ Online-only

- แสดง Online/Disconnected
- ปิดปุ่มยืนยันเมื่อ API ติดต่อไม่ได้
- แสดง timeout และ retry อย่างชัดเจน
- ห้ามล้างรายการที่ผู้ใช้เตรียมไว้ทันทีเมื่อ network error
- ป้องกันการกดส่งซ้ำ
- รักษา Idempotency-Key สำหรับ operation เดิม
- แสดงผลสำเร็จ/ไม่ผ่านรายห่อ
- ห้ามแสดง “พิมพ์สำเร็จ” ก่อน Gateway ACK

### 7.2 Automated tests ที่ยังขาด

- Camera allow/deny/re-allow
- Chrome Site Settings recovery
- กล้องหน้า/หลัง
- Torch capability
- QR duplicate debounce
- Malicious/oversized QR
- Background/resume
- Reload ระหว่าง mutation
- Multiple tabs
- Slow/disconnected network
- Print Job polling
- `ACK_UNKNOWN`
- Cancel/reprint workflow
- Responsive layout
- Accessibility
- Chrome Android end-to-end
- Stale service worker

### 7.3 i18n

- ย้ายข้อความ user-facing ที่ hard-code ไป ARB/i18n
- ตรวจข้อความ error และ safety warning ภาษาไทย
- ห้าม hard-code ข้อความใหม่ใน widget/service

## 8. Backend และ Integration Tests

เพิ่มหรือยืนยัน:

- PostgreSQL integration suite
- Migration บนฐานข้อมูลที่มีข้อมูล
- Expired OUT ถูกบล็อก 100%
- Scan IN/OUT/RETURN concurrency
- Duplicate Movement
- Batch pass/fail transaction rollback
- Recall และตำแหน่งปัจจุบันของห่อ
- FEFO: วันเท่ากัน, null, หมดอายุ
- State transition ทุกเส้นทาง
- RBAC matrix ทุก endpoint
- Audit completeness
- IDOR
- Print Job spoofing
- Fake Gateway ACK
- Gateway revoke/recovery
- Idempotency ข้าม endpoint/method
- Request body/array size limits

## 9. Security ที่ยังเหลือ

- Session revocation/remote logout
- Login success/failure Audit Log
- Rate limiting ที่รองรับหลาย API instance
- JWT expiry/replay tests
- Inactive-user tests
- IDOR tests ครบระบบ
- Oversized/malicious payload tests
- XSS และ token storage review
- Dependency vulnerability scan
- Secret scan
- OWASP API scenarios
- Gateway impersonation tests
- CSP/HSTS verification บน deployment จริง
- Penetration test

## 10. Operations และ Go-live

- Backup encryption
- Restore drill
- Audit retention/archive policy
- API/DB/Gateway monitoring
- Alert สำหรับ dead letter และ `ACK_UNKNOWN`
- SOP เมื่อ PWA ล่ม
- SOP เมื่อ API/DB ล่ม
- SOP เมื่อ network ล่ม
- SOP เมื่อ XP-420B ล่ม/กระดาษหมด
- UAT workflow เต็มวงจร
- Pilot จำกัดหนึ่งจุดและหนึ่งเครื่องพิมพ์ก่อน
- Critical defect = 0
- High defect = 0

## 11. เอกสารที่ต้องปรับ

- `AGENTS.md`
- `AI_DEVELOPMENT_GUARDRAILS.md`
- `HARDWARE_VERIFICATION.md`
- Print Gateway README
- `.env.example`
- SRS/API documentation
- QA/Pilot checklist
- SOP
- `PROGRESS.md`

ต้อง:

- เปลี่ยน A318BT เป็น Xprinter XP-420B
- เปลี่ยน Serial-only เป็น USB printer queue
- ระบุ Online-only
- ตัด Offline milestone/acceptance criteria
- ระบุ spooler semantics
- เพิ่มขั้นตอนติดตั้ง driver และ queue

## 12. ลำดับการทำงาน

1. ปรับเอกสารเป็น Online-only และ XP-420B
2. ยืนยัน OS ของเครื่อง Print Gateway
3. ออกแบบและสร้าง XP-420B USB transport
4. เพิ่ม backend `USB_SPOOL`
5. เพิ่ม unit/integration/security tests
6. ตั้งค่า driver และ printer queue
7. ทำ Hardware Verification
8. ทำ Chrome PWA automated tests
9. ปิด Security/Operations
10. UAT
11. Pilot

## 13. ระยะเวลาโดยประมาณเมื่อใช้ AI

| งาน | ระยะเวลา |
|---|---:|
| Online-only cleanup และเอกสาร | 1–2 วัน |
| XP-420B USB integration | 2–5 วัน |
| PWA/API automated tests | 3–6 วัน |
| Hardware verification | 2–4 วัน |
| Security/Operations/UAT preparation | 4–8 วัน |

รวมโดยประมาณ: **2–4 สัปดาห์**

ตัวแปรหลัก:

- OS ของเครื่อง Print Gateway
- Driver/RAW printing ของ XP-420B
- กระดาษและค่า Gap
- การเข้าถึงเครื่องจริง
- เวลา UAT หน้างาน

## 14. Pilot Gate

ห้ามเปิด Pilot จนกว่า:

- XP-420B USB transport ผ่าน test
- Hardware Verification ผ่าน
- QR readability ≥ 99.5%
- ไม่มี duplicate print จาก automatic retry
- Expired OUT ถูกบล็อก 100%
- Print Job traceability ครบ
- PostgreSQL integration tests ผ่าน
- RBAC และ IDOR tests ผ่าน
- Backup/restore drill ผ่าน
- Critical defect = 0
- High defect = 0
- UAT ได้รับอนุมัติ
- มี SOP กรณี PWA/API/network/printer ล่ม

---

เอกสารนี้เป็นแผนงานและขอบเขตการพัฒนา ไม่แทน SOP โรงพยาบาล การทดสอบฮาร์ดแวร์จริง Security Assessment, Penetration Test หรือ UAT
