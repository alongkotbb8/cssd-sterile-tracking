# MACOS BROWSER PRINT — IMPLEMENTATION DIRECTIVE

> เอกสารคำสั่งเร่งด่วนสำหรับ Dev/AI  
> สถานะ: **REQUIRED / BLOCKING / LOCKED**  
> เป้าหมาย: รองรับ Xprinter XP-420B ที่ต่อ USB กับ Mac และสั่งเปิดหน้าต่างพิมพ์จาก PWA พร้อมเก็บประวัติการสร้างและการกดสั่งพิมพ์อย่างตรวจสอบย้อนหลังได้

## 1. คำตัดสินด้านสถาปัตยกรรม

ให้เพิ่มโหมดพิมพ์ใหม่ชื่อ `BROWSER_DIALOG` โดยคงระบบ `PRINT_GATEWAY` เดิมไว้ครบถ้วน

โหมดทั้งสองต้องแยกความหมายและสถานะออกจากกัน:

- `BROWSER_DIALOG` — ใช้ Browser เปิด macOS system print dialog บน Mac เครื่องเดียวกับที่เสียบ XP-420B
- `PRINT_GATEWAY` — Gateway ส่งข้อมูลไปยัง OS printer queue และ ACK ผลตามกลไกเดิม

ห้ามลบ ลดความปลอดภัย หรือเปลี่ยนความหมายของ Print Gateway เพื่อทำงานนี้

โหมด Browser ที่อนุมัติในเอกสารนี้ไม่ใช่ WebUSB และไม่ใช่การสั่ง USB โดย JavaScript โดยตรง แต่เป็นการใช้ระบบพิมพ์มาตรฐานของ Browser/macOS

## 2. Workflow ที่ต้องรองรับ

```text
XP-420B ต่อ USB กับ Mac
        ↓
macOS ติดตั้ง Driver และเห็น Printer Queue
        ↓
ผู้ใช้เปิด PWA ด้วย Chrome หรือ Safari บน Mac เครื่องนั้น
        ↓
ผู้ใช้สร้างห่อหรือเปิดรายละเอียดห่อ
        ↓
ระบบสร้าง Browser Print Request ที่ Backend
        ↓
PWA แสดงตัวอย่าง Label
        ↓
ผู้ใช้กด “พิมพ์ผ่านเครื่องนี้”
        ↓
PWA บันทึก DIALOG_OPENED แล้วเปิด macOS Print Dialog
        ↓
ผู้ใช้เลือก XP-420B และกด Print
        ↓
ผู้ใช้ยืนยันผลด้วยตนเองใน PWA
```

ขอบเขตสำคัญ:

- Workflow นี้ใช้พิมพ์จาก Mac ที่เปิด PWA และเชื่อมต่อเครื่องพิมพ์อยู่
- iPhone, iPad หรือ Android ที่เปิด PWA ไม่สามารถควบคุม USB printer บน Mac โดยตรงด้วยโหมดนี้
- หากต้องการสั่งงานจากอุปกรณ์อื่นไปยังเครื่องพิมพ์บน Mac ต้องใช้ Print Gateway หรือระบบ network printing ที่ผ่านการออกแบบและทดสอบแยกต่างหาก

## 3. ข้อเท็จจริงที่ระบบต้องสื่ออย่างถูกต้อง

Browser สามารถยืนยันได้เพียง:

- Backend สร้างคำขอพิมพ์แล้ว
- PWA เรียกเปิดหน้าต่างพิมพ์แล้ว
- ผู้ใช้ยืนยันผลภายหลังด้วยตนเอง

Browser ไม่สามารถพิสูจน์โดยอัตโนมัติได้ว่า:

- ผู้ใช้เลือก XP-420B จริง
- ผู้ใช้กด Print หรือ Cancel ในหน้าต่างของระบบ
- กระดาษออกจากเครื่องจริง
- Label พิมพ์ครบและถูกต้อง
- เครื่องพิมพ์กระดาษหมด, offline หรือมีงานค้างใน queue

ดังนั้น:

- ห้ามตั้ง `printedAt` จากการเรียก `window.print()`
- ห้ามตั้งสถานะ Gateway เป็น `PRINTED`, `SENT` หรือ `ACK_UNKNOWN`
- ห้ามเรียก Print Gateway ACK endpoint จาก Browser
- ห้ามรายงานว่า “พิมพ์สำเร็จจริง” จาก callback หรือการปิด print dialog
- สถานะยืนยันโดยผู้ใช้ต้องแสดงว่าเป็น `USER_CONFIRMED` ไม่ใช่ hardware-confirmed

## 4. Feature Flag และ Configuration

ต้องมี feature flag เพื่อเปิดหรือปิดโหมดนี้โดยไม่กระทบ production mode เดิม เช่น:

```env
CSSD_BROWSER_PRINT_ENABLED=true
CSSD_PRINT_MODE=browser_dialog
```

Dev ต้องใช้ระบบ configuration ที่มีอยู่แล้วถ้ามี ห้ามสร้างค่าซ้ำซ้อนโดยไม่จำเป็น

ข้อกำหนด:

- ค่า default สำหรับ environment ที่ไม่กำหนดต้องปลอดภัย
- Production ห้ามเปิดโหมดโดยไม่ตั้งใจ
- UI ต้องซ่อนปุ่มเมื่อ feature ปิด
- Backend ต้องตรวจ feature flag ด้วย ห้ามพึ่งการซ่อน UI อย่างเดียว
- ต้องตรวจและปฏิเสธค่า mode ที่ไม่รู้จัก

## 5. Data Model

ให้เพิ่ม entity สำหรับประวัติ Browser Print หรือขยาย Print Job เดิมอย่างปลอดภัย โดยต้องไม่ทำให้ semantics ของ Gateway ปะปนกัน

ข้อมูลขั้นต่ำ:

```text
requestId
packageId
requestedByUserId
requestedAt
mode
templateVersion
copies
isReprint
reprintReason
dialogOpenedAt
userConfirmedAt
cancelledAt
createdFrom
userAgent
idempotencyKey
createdAt
updatedAt
```

สถานะของ Browser Print ต้องจำกัดเป็น:

```text
CREATED
DIALOG_OPENED
USER_CONFIRMED
CANCELLED
```

กฎบังคับ:

- ห้ามใช้ `PRINTED`, `SENT`, `MAYBE_SENT` หรือ `ACK_UNKNOWN` กับ Browser Print
- `copies` ต้องอยู่ในช่วง 1–10
- `reprintReason` ต้องบังคับเมื่อเป็น reprint
- ห้ามแก้ `packageId`, `requestedByUserId`, `requestedAt` หรือ `mode` หลังสร้าง
- การเปลี่ยนสถานะต้องเป็น state transition ที่กำหนดไว้เท่านั้น
- Migration ต้อง reversible และทดสอบกับฐานข้อมูลใหม่และฐานข้อมูลที่มีข้อมูลเดิม

## 6. State Transition

อนุญาต:

```text
CREATED → DIALOG_OPENED
CREATED → CANCELLED
DIALOG_OPENED → USER_CONFIRMED
DIALOG_OPENED → CANCELLED
```

ไม่อนุญาต:

- `CANCELLED` กลับไปสถานะอื่น
- `USER_CONFIRMED` กลับไปสถานะอื่น
- ข้ามจาก `CREATED` ไป `USER_CONFIRMED`
- ยืนยันซ้ำแล้วสร้าง Audit ซ้ำ
- เปิด dialog ซ้ำโดยใช้ request เดิมหลังหน้า refresh

ถ้าต้องพิมพ์ใหม่ ให้สร้าง request ใหม่ที่อ้างถึงงานก่อนหน้าและบันทึกเป็น reprint

## 7. Backend API

ให้สร้างหรือปรับ endpoint ตามแนวทางนี้:

```http
POST /api/v1/browser-print-requests
POST /api/v1/browser-print-requests/:id/dialog-opened
POST /api/v1/browser-print-requests/:id/confirm
POST /api/v1/browser-print-requests/:id/cancel
GET  /api/v1/browser-print-requests
GET  /api/v1/browser-print-requests/:id
```

ทุก mutation ต้อง:

- Require authentication
- ตรวจ RBAC
- รับ `Idempotency-Key`
- ใช้ atomic idempotency mechanism ของระบบ
- validate DTO ทุก field
- ป้องกัน IDOR
- เขียน AuditLog ใน transaction เดียวกับการเปลี่ยนข้อมูล
- ส่ง stable error code สำหรับ i18n
- ไม่คืนข้อมูลผู้ใช้หรือระบบเกินความจำเป็น

รายการประวัติต้องรองรับ:

- filter ตาม package
- filter ตามผู้ใช้
- filter ตาม status
- filter ตามช่วงเวลา
- pagination
- sort ล่าสุดก่อน

## 8. Audit Log ที่บังคับ

ต้องมี action อย่างน้อย:

```text
BROWSER_PRINT_REQUEST_CREATED
BROWSER_PRINT_DIALOG_OPENED
BROWSER_PRINT_USER_CONFIRMED
BROWSER_PRINT_CANCELLED
BROWSER_PRINT_REPRINT_REQUESTED
```

Audit metadata ต้องมี:

- request ID
- package ID
- mode
- copies
- template version
- previous status
- new status
- reprint flag
- reprint reason เมื่อมี
- actor user ID
- timestamp จาก backend

ห้ามเก็บ secret, access token หรือข้อมูลอ่อนไหวใน Audit metadata

## 9. กฎ Reprint

ให้ถือว่าเป็น reprint เมื่อห่อนั้นเคยมี:

- Browser request ที่เป็น `DIALOG_OPENED` หรือ `USER_CONFIRMED`
- Gateway job ที่ ACK เป็นพิมพ์สำเร็จตาม semantics เดิม

ก่อน reprint ต้อง:

- แสดงคำเตือนว่าห่อนี้เคยสั่งพิมพ์แล้ว
- แสดงวันเวลา ผู้สั่ง และสถานะล่าสุด
- บังคับกรอกเหตุผล
- สร้าง request ใหม่
- เพิ่มตัวนับ reprint ที่คำนวณจากประวัติฝั่ง Backend
- บันทึก AuditLog

ห้าม:

- เปิด dialog อัตโนมัติเมื่อ refresh
- retry อัตโนมัติจนเกิด label ซ้ำ
- reuse request เก่าเพื่อหลบการบันทึก reprint

## 10. PWA UX/UI

เพิ่มปุ่ม:

```text
พิมพ์ผ่านเครื่องนี้
```

ก่อนเปิดหน้าต่างพิมพ์ ต้องแสดง:

- เลขห่อ
- ชื่อชุด
- สถานะห่อ
- วันที่นึ่งและวันหมดอายุเมื่อมีสิทธิ์แสดง
- จำนวนสำเนา
- ตัวอย่าง Label
- คำเตือนหากเป็น reprint

Flow บังคับ:

1. PWA ขอสร้าง Browser Print Request จาก Backend
2. Backend คืน request และข้อมูล Label ที่เป็น authoritative
3. PWA แจ้ง Backend ว่ากำลังเปิด dialog
4. PWA เปิด system print dialog
5. เมื่อกลับสู่ PWA ให้ผู้ใช้เลือกผลด้วยตนเอง

ตัวเลือกหลังเปิด dialog:

- `กระดาษออกถูกต้อง` → `USER_CONFIRMED`
- `ไม่ได้พิมพ์ / ยกเลิก` → `CANCELLED`
- `ตรวจสอบภายหลัง` → คง `DIALOG_OPENED`

ข้อความ UI ต้องระบุชัด:

> ระบบ Browser ไม่สามารถตรวจสอบกระดาษที่ออกจากเครื่องได้ กรุณาตรวจ Label ก่อนยืนยัน

ห้ามถือว่าการ return จาก print plugin หรือ print dialog คือการพิมพ์สำเร็จ

## 11. Label Requirements

ต้องรองรับ Label ขนาดที่ใช้งานจริง โดยเริ่มต้นที่ 60 × 40 มม. และให้ configuration ปรับได้

ข้อกำหนด:

- รองรับ XP-420B ความละเอียด 203 DPI
- ใช้ PDF หรือ print layout ที่รักษาขนาดจริง
- ฟอนต์ไทยต้องแสดงถูกต้อง
- QR ต้องเก็บเฉพาะ `package_id`
- QR ต้องสแกนกลับเข้า PWA ได้
- ข้อมูลวันที่มาจาก Backend เท่านั้น
- Client ห้ามคำนวณวันหมดอายุเอง
- ห่อที่ยังไม่ผ่านการฆ่าเชื้อห้ามแสดงวันนึ่งหรือวันหมดอายุ
- ห่อที่ยังไม่ผ่านต้องแสดง `ยังไม่ผ่านการฆ่าเชื้อ`
- ห้ามให้ Browser header/footer ติดบน Label
- ต้องมี print stylesheet แยกจากหน้าจอปกติ
- ต้องไม่พิมพ์ navigation, button, snackbar หรือข้อมูล UI ที่ไม่ใช่ Label

หน้าคำแนะนำต้องบอกผู้ใช้ให้ตรวจ:

- Printer: Xprinter XP-420B
- Paper size: ขนาด Label ที่ตั้งไว้
- Scale: 100%
- Margins: None หรือตามค่าที่ทดสอบ
- Headers and footers: Off

## 12. Print History UI

เพิ่มประวัติการพิมพ์ที่ดูได้จากหน้ารายละเอียดห่อและหน้ารวมงานพิมพ์

ต้องแสดง:

- วันเวลา
- ผู้สั่ง
- Mode
- จำนวนสำเนา
- Template version
- สถานะ
- เหตุผล reprint
- ลิงก์หรือหมายเลข request

ข้อความสถานะภาษาไทย:

- `CREATED` — สร้างคำขอแล้ว
- `DIALOG_OPENED` — เปิดหน้าต่างพิมพ์แล้ว ยังไม่ยืนยันผล
- `USER_CONFIRMED` — ผู้ใช้ยืนยันว่ากระดาษออกแล้ว
- `CANCELLED` — ผู้ใช้แจ้งว่าไม่ได้พิมพ์หรือยกเลิก

ห้ามแสดง `USER_CONFIRMED` เป็น “เครื่องพิมพ์ยืนยันแล้ว”

## 13. Security Requirements

บังคับทั้งหมด:

- Authentication ทุก endpoint
- RBAC ตามบทบาท
- Object-level authorization ป้องกัน IDOR
- `Idempotency-Key` ทุก mutation
- Atomic state transition
- DTO allowlist และ length limit
- `copies` เป็น integer 1–10
- Backend เป็น source of truth
- เวลาใช้เวลาจาก Backend
- ห้าม Client เขียน `printedAt`
- ห้ามรับ arbitrary HTML หรือ URL สำหรับพิมพ์
- ห้ามโหลด remote font หรือ asset ที่ไม่อยู่ใน allowlist
- ห้ามใส่ secret ใน Flutter bundle
- ห้ามลด CSP/CORS เพื่อให้ฟีเจอร์ทำงาน
- ห้ามใช้ WebUSB
- ห้ามเปิด Bluetooth/A318BT กลับมา
- ห้ามเรียก Gateway ACK จาก Browser
- ต้อง rate limit endpoint ที่อาจถูกกดซ้ำ
- ต้อง log error โดยไม่เปิดเผย token หรือข้อมูลอ่อนไหว

## 14. Automated Tests

### Backend — ขั้นต่ำ 17 กรณี

1. สร้าง request สำเร็จ
2. ไม่มี auth ถูกปฏิเสธ
3. role ไม่ถูกต้องถูกปฏิเสธ
4. package ไม่มีอยู่จริงถูกปฏิเสธ
5. package ID ผิดรูปแบบถูกปฏิเสธ
6. copies ต่ำกว่า 1 ถูกปฏิเสธ
7. copies มากกว่า 10 ถูกปฏิเสธ
8. idempotency key เดิมไม่สร้างข้อมูลซ้ำ
9. idempotency key เดิมกับ payload ต่างกันถูกปฏิเสธ
10. `CREATED → DIALOG_OPENED` สำเร็จ
11. `DIALOG_OPENED → USER_CONFIRMED` สำเร็จ
12. `DIALOG_OPENED → CANCELLED` สำเร็จ
13. transition ผิดถูกปฏิเสธ
14. ผู้ใช้ไม่มีสิทธิ์อ่าน request ของผู้อื่นถูกปฏิเสธตาม policy
15. reprint ไม่มีเหตุผลถูกปฏิเสธ
16. ทุก mutation สร้าง AuditLog
17. Browser request ไม่แก้ Gateway `printedAt` หรือ ACK

### Flutter/PWA — ขั้นต่ำ 13 กรณี

1. feature ปิดแล้วไม่แสดงปุ่ม
2. feature เปิดแล้วแสดงปุ่ม
3. แสดง preview ถูกต้อง
4. Label ที่ยังไม่ sterile ไม่แสดงวัน
5. QR มีเฉพาะ package ID
6. สร้าง request ก่อนเรียก print
7. บันทึก dialog-opened ก่อนเรียก print
8. ไม่ auto-confirm หลัง dialog ปิด
9. ปุ่มยืนยันเรียก confirm endpoint
10. ปุ่มยกเลิกเรียก cancel endpoint
11. reprint บังคับเหตุผล
12. หน้า history แสดงสถานะถูกความหมาย
13. layout ไม่ล้นที่ Chrome/Safari และ text scale ตาม matrix เดิม

### E2E — ขั้นต่ำ 9 กรณี

1. login → สร้างห่อ → preview → สร้าง print request
2. request → dialog-opened
3. dialog-opened → user-confirmed
4. request → cancelled
5. refresh แล้วไม่เปิด dialog ซ้ำ
6. กดซ้ำด้วย idempotency key เดิมไม่สร้างงานซ้ำ
7. reprint แสดงคำเตือนและบังคับเหตุผล
8. history แสดง request เดิมและ reprint แยกกัน
9. Browser flow ไม่เปลี่ยน Gateway job state

Automated test ไม่สามารถแทน hardware verification ได้

## 15. Manual Hardware Acceptance — Mac + XP-420B

Dev/ผู้ทดสอบต้องบันทึกหลักฐานทุกข้อ:

1. macOS เห็น XP-420B ใน Printers & Scanners
2. พิมพ์ test page จาก macOS สำเร็จ
3. Chrome เปิด print dialog และเห็น XP-420B
4. Safari เปิด print dialog และเห็น XP-420B
5. ขนาด Label จริงตรงกับค่าที่กำหนด
6. ภาษาไทยไม่แตก ไม่หาย และไม่เป็นสี่เหลี่ยม
7. QR สแกนกลับได้ด้วย Chrome บน Android
8. QR สแกนกลับได้ด้วย Safari บน iPhone/iPad
9. วันนึ่งและวันหมดอายุถูกต้อง
10. Label ก่อนผ่านการฆ่าเชื้อไม่มีวันที่ต้องห้าม
11. History แสดง `DIALOG_OPENED` ก่อนยืนยัน
12. History แสดง `USER_CONFIRMED` หลังผู้ใช้ยืนยัน
13. Cancel แล้วแสดง `CANCELLED`
14. Reprint มี warning, reason และ Audit
15. ทดสอบต่อเนื่อง 10 ใบโดยไม่ซ้ำหรือข้าม
16. ทดสอบต่อเนื่อง 50 ใบก่อนอนุมัติ Pilot

หลักฐานขั้นต่ำ:

- รุ่น macOS
- รุ่น Chrome และ Safari
- รุ่น Driver
- ชื่อ Printer Queue
- ขนาดและชนิด Label
- ภาพ Label จริง
- ผลสแกน QR
- API/Audit evidence
- ปัญหาและวิธีแก้

## 16. เอกสารที่ต้องอัปเดต

Dev ต้องอัปเดต:

- `CSSD_MASTER_EXECUTION_DIRECTIVE.md`
- `AGENTS.md`
- `CLAUDE.md`
- `AI_DEVELOPMENT_GUARDRAILS.md`
- README ที่เกี่ยวข้อง
- `PROGRESS.md`
- คู่มือ Mac + XP-420B
- UAT checklist

ข้อความที่ต้องระบุ:

- Browser printing เป็น mode สำหรับ Mac ที่ต่อ USB และเปิด PWA อยู่บนเครื่องเดียวกัน
- Browser ไม่สามารถยืนยันผล hardware ได้
- Print Gateway ยังเป็นทางเลือกสำหรับการพิมพ์จากอุปกรณ์อื่นและการ ACK ผลระดับ queue
- ห้ามอ้างว่า Browser mode เป็น direct USB printing

## 17. Definition of Done

งานจะถือว่า code-complete เมื่อครบทั้งหมด:

- Migration ผ่านทั้งฐานข้อมูลใหม่และข้อมูลเดิม
- API, RBAC, IDOR guard และ idempotency ผ่าน
- AuditLog ครบทุก transition
- UI preview, print flow, result confirmation และ history ครบ
- Reprint warning และ reason ครบ
- Label rules ด้าน traceability ครบ
- Backend/Flutter/E2E tests ผ่าน
- Regression tests เดิมผ่าน
- Analyze, typecheck และ production build ผ่าน
- Dependency/advisory scan ไม่มี Critical หรือ High ที่ยังไม่ยอมรับอย่างเป็นทางการ
- CI/Security workflows ผ่านที่ commit SHA เดียวกัน

งานจะถือว่า hardware-verified เมื่อ:

- ผ่าน Manual Hardware Acceptance บน Mac + XP-420B
- มีหลักฐาน Label จริงและ QR scan
- ผ่านการทดสอบต่อเนื่อง 10 ใบ
- ผ่านการทดสอบต่อเนื่อง 50 ใบ

## 18. QA Gate และคำประกาศสถานะ

สถานะสูงสุดก่อนทดสอบเครื่องจริง:

```text
BROWSER_PRINT: CI_VERIFIED
HARDWARE: NOT VERIFIED
PILOT: NOT APPROVED
PRODUCTION: NOT APPROVED
```

ห้ามประกาศ `HARDWARE_VERIFIED`, `PILOT_APPROVED` หรือ `PRODUCTION_READY` จากผล automated test เพียงอย่างเดียว

## 19. สิ่งที่ห้ามทำเด็ดขาด

- ห้ามใช้ WebUSB เพื่อคุยกับ XP-420B
- ห้ามเปิด Bluetooth printer legacy กลับมา
- ห้ามลบ Print Gateway
- ห้ามให้ Browser เรียก Gateway ACK
- ห้ามตั้ง `printedAt` จาก Browser
- ห้ามเรียก dialog แล้วถือว่าพิมพ์สำเร็จ
- ห้าม retry อัตโนมัติจนเกิด Label ซ้ำ
- ห้ามสร้างเลขห่อฝั่ง Client
- ห้ามคำนวณวันหมดอายุฝั่ง Client
- ห้ามยัดข้อมูลทั้งหมดลง QR
- ห้ามลด Auth, RBAC, CSP, CORS หรือ validation
- ห้ามแก้ test เพื่อให้ผ่านโดยลด assertion
- ห้าม claim ผ่าน Gate โดยไม่มีหลักฐานที่ commit SHA เดียวกัน

## 20. รูปแบบรายงานส่ง QA

Dev ต้องส่งรายงานโดยใช้รูปแบบนี้:

```text
HEAD SHA:
Branch:
Files changed:
Migration result:
API tests:
Flutter tests:
E2E tests:
Analyze/typecheck:
Production build:
Dependency scan:
CI URL:
Security URL:

Browser print mode:
- Feature flag:
- Chrome:
- Safari:
- Request history:
- Reprint:
- Audit:

Hardware evidence:
- macOS version:
- Driver version:
- Printer queue:
- Label size:
- 10-label result:
- 50-label result:
- QR scan result:
- Evidence paths/URLs:

Known limitations:
Gate requested:
```

QA จะตรวจแบบ read-only และจะไม่อนุมัติ Gate ถ้าหลักฐานไม่ครบหรือไม่ตรงกับ HEAD SHA

