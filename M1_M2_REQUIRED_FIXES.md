# M1/M2 — รายการที่ต้องแก้ก่อน Pilot

วันที่สรุป: 22 กรกฎาคม 2026  
ขอบเขต: Chrome PWA, QR Scanner, Print Job Backend และ Print Gateway

## สถานะปัจจุบัน

| Milestone | ความคืบหน้าโดยประมาณ | สถานะ |
|---|---:|---|
| M1 — Chrome PWA/Scan | 75–80% | ใช้ทดสอบภายในได้ |
| M2 — Print Job Backend | 70–75% | ต้องแก้ concurrency และ authorization |
| M2 — Print Gateway จริง | 25–35% | มี framework แต่ยังเป็น Console Mock |
| Online Pilot โดยรวม | 60–65% | ยังไม่ควรใช้กับงานจริง |

## 1. ต้องแก้ทันที — Critical

### 1.1 ป้องกันการพิมพ์ซ้ำเมื่อ ACK หาย

หลังส่งข้อมูลไปเครื่องพิมพ์แล้ว หาก network หลุด ระบบห้ามนำงานกลับไปพิมพ์อัตโนมัติทันที เพราะเครื่องพิมพ์อาจรับข้อมูลและพิมพ์ Label ออกมาแล้ว

สถานะที่ควรเพิ่ม:

```text
CLAIMED → PRINTING → SENT → PRINTED
                         ↘ ACK_UNKNOWN
```

กฎ:

- เมื่อ `transport.send()` สำเร็จ ต้องเปลี่ยนเป็น `SENT`
- หาก ACK ไป backend ไม่สำเร็จ ต้องเป็น `ACK_UNKNOWN`
- ห้าม auto-retry งาน `SENT/ACK_UNKNOWN`
- ต้องให้ Gateway ตรวจสอบหรือเจ้าหน้าที่ตัดสินใจก่อน retry
- การ retry ต้องมี Audit Log และเหตุผล

### 1.2 ห้าม ConsoleTransport แจ้งว่าพิมพ์จริง

ConsoleTransport เป็น Mock แต่ปัจจุบันสามารถทำให้งานเป็น `PRINTED` และอัปเดต `Package.printedAt` ได้

ต้องแก้ให้:

- Production เริ่มระบบด้วย `PRINTER_TRANSPORT=console` ไม่ได้
- Dry-run ห้ามเรียก ACK แบบพิมพ์จริง
- ใช้สถานะ `SIMULATED` หรือเก็บผลเฉพาะ test environment
- ห้ามข้อมูลทดสอบปะปนกับฐานข้อมูล Production

### 1.3 แก้ Concurrent ACK

ACK สอง request ที่เข้าพร้อมกันอาจเห็นสถานะ `PRINTING` เหมือนกัน และเพิ่ม `reprintCount` ซ้ำ

ต้องใช้:

- Row lock หรือ CAS ภายใน transaction
- `updateMany` พร้อมเงื่อนไขสถานะเดิม
- อัปเดต Package เฉพาะ request ที่เปลี่ยนสถานะ Print Job สำเร็จ
- ACK ซ้ำต้องคืนผลเดิมโดยไม่เพิ่ม counter

### 1.4 สร้าง Transport เครื่องพิมพ์จริง

ต้องเลือกและ implement อย่างน้อยหนึ่งแบบ:

1. USB/Serial — แนะนำสำหรับเครื่องพิมพ์ประจำจุด
2. Bluetooth Classic — ใช้เมื่อ USB ไม่เหมาะสม

Transport ต้องมี:

- connect/disconnect
- reconnect
- write timeout
- error mapping
- configuration validation
- safe shutdown
- hardware test

### 1.5 สร้าง Label ภาษาไทยแบบ Bitmap

ห้ามพึ่ง TSPL `TEXT` สำหรับข้อความภาษาไทย

ต้อง:

- Render Label เป็น monochrome bitmap
- ใช้ฟอนต์ Sarabun ที่ bundle มากับ Gateway
- ส่งผ่านคำสั่ง TSPL `BITMAP`
- QR ต้องมีเฉพาะ `package_id`
- ทดสอบความคมชัดและการตัดข้อความบน Label 60 × 40 มม.

## 2. ต้องแก้ก่อนเชื่อมปุ่ม PWA — High

### 2.1 แก้ IDOR ของ `GET /print-jobs/:id`

กฎการมองเห็น:

- CSSD เห็นเฉพาะ Print Job ที่ตนเองสร้าง
- SUPERVISOR/ADMIN เห็นทั้งหมด
- ผู้ไม่มีสิทธิ์ต้องได้รับ 403 หรือ 404

ต้องมี authorization test ครบทุก role

### 2.2 ให้ Backend ตัดสินว่าเป็น Reprint

ห้ามเชื่อ `isReprint` จาก client

```text
isReprint = package.printedAt != null
```

กฎ:

- ครั้งแรกไม่ต้องมีเหตุผล reprint
- ถ้า Package เคยพิมพ์แล้ว ต้องบังคับ `reprintReason`
- Client ไม่สามารถหลบการกรอกเหตุผลด้วย `isReprint=false`
- Audit Log ต้องบันทึกเหตุผล ผู้สั่ง และจำนวนครั้ง

### 2.3 ยกเลิกได้เฉพาะงาน QUEUED

ห้ามผู้ใช้ยกเลิกงาน `CLAIMED` หรือ `PRINTING` เพราะ Gateway อาจเริ่มส่งข้อมูลไปเครื่องพิมพ์แล้ว

Pilot รุ่นแรกควรอนุญาต:

```text
QUEUED → CANCELLED
```

หากต้องการยกเลิกหลัง claim ต้องออกแบบ cancellation handshake เพิ่มภายหลัง

### 2.4 ตรวจ Payload Hash ที่ Gateway

ก่อนพิมพ์ Gateway ต้อง:

1. Canonicalize payload
2. คำนวณ SHA-256
3. เปรียบเทียบกับ `payloadHash`
4. ปฏิเสธงานเมื่อไม่ตรง
5. รายงาน error เป็น `PAYLOAD_HASH_MISMATCH`
6. บันทึก Security Audit Log

### 2.5 ป้องกัน TSPL Injection

- Validate Package ID ตามรูปแบบ running number
- จำกัดความยาวทุก field
- ปฏิเสธ CR/LF, NUL และ control characters
- ห้ามนำข้อความจาก client ต่อเป็นคำสั่ง TSPL โดยตรง
- ใช้ Bitmap สำหรับข้อความทั้งหมดเมื่อเป็นไปได้

### 2.6 แก้ Lease Recovery

ต้องแยก:

- งานกลางที่เดิมไม่มี printer เจาะจง: เมื่อ lease หมด ให้ล้าง assignment เพื่อให้ Gateway อื่น claim ได้
- งานที่ผู้ใช้ระบุ printer: คง printer เดิมและแจ้งเตือนว่า Gateway offline

ควรเก็บ `requestedPrinterId` แยกจาก `claimedByGatewayId` เพื่อไม่ให้ความหมายปะปนกัน

### 2.7 แก้ Idempotency ค้าง PENDING

กรณี process ล่มหลัง mutation สำเร็จ แต่ก่อนบันทึก response จะทำให้ key ค้าง `PENDING`

ต้องมี:

- `expiresAt` หรือ lease timeout
- recovery/reconciliation job
- owner/request hash/endpoint/method
- การตรวจผล mutation เดิมก่อนตัดสินใจ retry
- ห้าม rerun mutation โดยอัตโนมัติหากอาจสำเร็จไปแล้ว

### 2.8 บังคับ Idempotency-Key

Mutation สำคัญต้อง reject request ที่ไม่มี key:

- Package create
- Scan in/out/return
- Batch result
- Print Job create
- Print Job retry/reprint

ควรตอบ `400 Bad Request` เมื่อ header หายหรือรูปแบบไม่ถูกต้อง

## 3. ต้องทำ Tests ก่อน Pilot

### 3.1 PostgreSQL Integration Tests

ต้องทดสอบกับ PostgreSQL จริง:

- สอง Gateway claim พร้อมกัน
- ACK พร้อมกัน
- ACK ซ้ำ
- Cancel ชนกับ Claim
- Lease timeout ชนกับ ACK
- Gateway crash หลังส่งพิมพ์
- Idempotency request พร้อมกัน
- Process crash ระหว่าง mutation
- Key เดิม payload เดิม
- Key เดิม payload ต่างกัน
- User อื่นใช้ key เดิม

### 3.2 Route Tests

- ยืนยันว่า `/print-jobs/gateways/list` ไม่ถูกจับเป็น `GET /print-jobs/:id`
- จัด static routes ก่อน dynamic route
- ทดสอบ ownership ของ `GET /print-jobs/:id`

### 3.3 Gateway Security Tests

- Gateway key ผิด
- Gateway ถูก revoke
- Gateway A พยายาม ACK งานของ Gateway B
- Gateway ACK งานที่ไม่ได้ claim
- ACK จากสถานะผิด
- Payload hash ไม่ตรง
- Brute-force gateway key
- ตรวจว่า log ไม่มี secret

## 4. Security/Operations ที่ต้องทำ

### 4.1 บังคับ HTTPS

- Production Gateway ต้องไม่เริ่มหาก `API_BASE_URL` เป็น HTTP
- อนุญาต HTTP ได้เฉพาะ localhost ใน development/test
- ห้ามส่ง `X-Gateway-Key` ผ่าน plaintext network

### 4.2 Gateway Protection

- Rate limiting
- Failed-auth monitoring
- API-key rotation
- Revoke credential
- แยก credential ต่อ Gateway
- จำกัด Gateway ให้รับเฉพาะ Printer ที่กำหนด
- ไม่ log key/token/header
- พิจารณา short-lived token หรือ mTLS ใน Production

### 4.3 Monitoring

ต้องมี alert สำหรับ:

- Gateway heartbeat หาย
- Queue ค้าง
- `DEAD_LETTER`
- `ACK_UNKNOWN`
- Failure ซ้ำ
- Payload hash mismatch
- Gateway authentication failure
- Printer offline/paper out หาก hardware รองรับ

## 5. งาน M1 ที่ยังต้องเก็บ

### 5.1 Camera Permission สำหรับ Chrome

- หลีกเลี่ยงการขอกล้องซ้ำจาก permission library และ scanner library
- ให้ scanner library จัดการ `getUserMedia` บน Web
- แสดงขั้นตอน Chrome Site Settings เมื่อ permission ถูกปฏิเสธ
- ตรวจ capability ก่อนแสดง torch/zoom
- ทดสอบ background/resume, reload และหลาย tab

### 5.2 Manual Entry

- Validate running-number format
- จำกัดความยาว
- ระบุ `manualEntry=true`
- มี Audit Log
- พิจารณาจำกัดสิทธิ์หรือแสดงคำเตือนตาม SOP

## 6. ลำดับการลงมือ

```text
1. แก้ duplicate-print ambiguity หลัง send/ACK
2. ปิด ConsoleTransport ไม่ให้ ACK เป็น PRINTED
3. แก้ Concurrent ACK
4. แก้ IDOR, Reprint และ Cancel
5. แก้ Idempotency และบังคับ Header
6. เพิ่ม PostgreSQL integration tests
7. สร้าง Real Printer Transport
8. สร้าง Bitmap Thai Label
9. ตรวจ Payload Hash และ TSPL input
10. ทดสอบ A318BT จริง 100–500 ใบ
11. เชื่อมปุ่มพิมพ์ Chrome PWA กับ Print Job
12. UAT และ Security Review ก่อน Pilot
```

## 7. Acceptance Criteria ก่อนเชื่อมปุ่ม PWA

- Print Job หนึ่งงานไม่เพิ่ม `reprintCount` เกินหนึ่งครั้ง
- ACK ซ้ำไม่เปลี่ยนข้อมูล
- CSSD อ่าน Print Job ของผู้อื่นไม่ได้
- Backend เป็นผู้ตัดสิน reprint
- ยกเลิกได้เฉพาะ `QUEUED`
- Console/Dry-run ไม่อัปเดต `printedAt`
- Payload hash mismatch ถูกปฏิเสธ
- Idempotency-Key เป็น required
- PostgreSQL concurrency tests ผ่าน

## 8. Acceptance Criteria ก่อน Pilot จริง

- มี Real Printer Transport
- ภาษาไทยและ QR พิมพ์ถูกต้อง
- QR readability อย่างน้อย 99.5%
- ทดสอบต่อเนื่อง 100–500 Label
- Network หลุดหลัง send ไม่ทำให้ auto-print ซ้ำ
- Gateway restart แล้วงานไม่สูญหาย
- Gateway revoke ทำงานทันที
- Critical defects = 0
- High defects = 0
- Audit Log ครบทุก Print Job transition
- ผ่าน UAT กับเจ้าหน้าที่ CSSD

## 9. ข้อสรุป

ตอนนี้ควรหยุดเพิ่ม UI หรือฟีเจอร์ใหม่ชั่วคราว และแก้แกนความถูกต้องของ Print Job ก่อน เป้าหมายสำคัญที่สุดคือ:

> หนึ่ง Print Job ต้องไม่พิมพ์เกินหนึ่งครั้งโดยไม่ตั้งใจ, ต้องบันทึก `PRINTED` เฉพาะเมื่อมีหลักฐานเพียงพอ และเมื่อไม่ทราบว่าเครื่องพิมพ์รับงานไปแล้วหรือไม่ ต้องหยุดให้มนุษย์ตรวจแทนการ retry อัตโนมัติ

หลังแก้รายการ Critical/High และผ่าน PostgreSQL integration tests แล้ว จึงเริ่มสร้าง Real Transport, Bitmap Label และเชื่อมปุ่มพิมพ์ใน Chrome PWA
