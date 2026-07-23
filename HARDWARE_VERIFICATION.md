# FIX-08 — Hardware Verification (Xprinter) — ต้องทำกับเครื่องจริง

> ⚠️ ข้อนี้ **AI ทำแทนไม่ได้** เพราะไม่มีเครื่องพิมพ์จริงในสภาพแวดล้อมพัฒนา
> เอกสารนี้คือ **ขั้นตอน + แบบฟอร์มเก็บหลักฐาน** ให้ทีม (ที่มีเครื่องจริง) รันแล้วบันทึกผล
> ต้องผ่านครบก่อนเปิด Pilot (ดู Pilot Gate ใน `M1_M2_REAUDIT_FIX_DIRECTIVE.md` ข้อ 15)
>
> **หมายเหตุ:** เปลี่ยนเครื่องเป้าหมายเป็น **Xprinter** (จากเดิม FlashLabel A318BT) — Xprinter
> รุ่น label ส่วนใหญ่ใช้ TSPL/TSPL2 เหมือนกัน โค้ด gateway (bitmap + TSPL 203 DPI) จึงน่าจะใช้ได้
> แต่ **ต้องยืนยันกับรุ่นจริงก่อน** ตามข้อ 0.1

## 0. เตรียมก่อนทดสอบ

- ติดตั้ง Print Gateway บนเครื่องที่ต่อเครื่องพิมพ์จริง (`apps/print-gateway`)
- `PRINTER_TRANSPORT=usb_spool` + `PRINTER_QUEUE_NAME=<ชื่อ OS printer queue ที่ติดตั้งไว้>`
  (XP-420B USB มักเป็น printer-class → ใช้ usb_spool; ถ้า driver สร้าง virtual COM ค่อยใช้ serial)
- ลงทะเบียน gateway ผ่าน ADMIN โดยตั้ง capability จริง:
  `POST /print-jobs/gateways { name, environment: "PRODUCTION", transportMode: "USB_SPOOL", canConfirmRealPrint: true }`
- ยืนยันว่า `NODE_ENV=production` + `API_BASE_URL` เป็น `https://` (ไม่งั้น gateway จะไม่สตาร์ท)

## 0.1 ยืนยันรุ่น/โปรโตคอล Xprinter ก่อน (สำคัญ — ต่างจาก A318BT เดิม)

**รุ่นที่ใช้จริง: Xprinter XP-420B (USB, direct thermal label)** — ยืนยันสเปคกับคู่มือ/หน้าทดสอบ:

- **command dialect:** ตระกูล XP-4xx รองรับ **TSPL/TSPL2** (บางเฟิร์มแวร์มี EPL/ZPL ด้วย) →
  renderer bitmap + TSPL ของเราเข้ากันได้ **ยืนยันด้วยการพิมพ์ทดสอบ 1 ใบก่อน** (ถ้าไม่ตอบ TSPL ต้องเพิ่ม renderer)
- **DPI/ความกว้าง:** XP-420B = **203 DPI**, กว้างสูงสุด ~104mm (4") — label 60×40mm ของเราพิมพ์ได้
  ผ่านคำสั่ง `SIZE 60 mm,40 mm` + **calibrate gap/media** ที่เครื่องก่อน (ปุ่ม feed/auto-calibrate)
- **การเชื่อมต่อ = USB** — ⚠️ **จุดสำคัญ:** XP-420B ต่อ USB มักปรากฏเป็น **USB printer-class**
  (ผ่าน Windows/CD driver → spooler, Linux → `/dev/usb/lp0`, mac → CUPS) **ไม่ใช่ virtual COM/serial เสมอไป**
  - ถ้า**ไม่**เป็น COM port → `SerialTransport` ปัจจุบันผูกกับเครื่องไม่ได้ ต้องเพิ่ม transport ใหม่
    (implement `PrinterTransport` เดิม — NOT_SENT/MAYBE_SENT/SENT ให้ครบ) โดยเลือกวิธีตาม host OS:
    - **Windows** (น่าจะกรณีนี้ ใช้ driver จาก CD): ส่ง raw TSPL เข้า print spooler (RAW queue)
    - **Linux/Raspberry Pi**: เขียน raw ไป `/dev/usb/lp0` (usblp) หรือใช้ `usb`/libusb เขียน bulk endpoint
    - **mac**: CUPS raw queue
  - ถ้า driver **สร้าง virtual COM ให้** → `SerialTransport` ใช้ได้ (ยืนยัน path + baud)
- **ต้องตัดสินก่อน (blocker ของ transport):** host OS ที่รัน Print Gateway + วิธีที่ XP-420B ปรากฏ
  (COM / USB printer-class / CUPS) → เลือก/สร้าง transport ให้ตรง
- พิมพ์ label ทดสอบ 1 ใบ ยืนยัน bitmap + QR + ไทย ออกถูกต้องก่อนทำ soak test เต็ม

## 1. รายการที่ต้องทดสอบ (checklist)

| # | รายการ | ผ่าน? | หมายเหตุ |
|---|--------|-------|----------|
| 1 | USB ปรากฏเป็น Serial/COM port จริง (`ls /dev/tty.*` หรือ Device Manager) | ☐ | path = ______ |
| 2 | ยืนยัน baud rate / serial parameters ตรงกับเครื่อง | ☐ | baud = ______ |
| 3 | พิมพ์ Bitmap 60×40mm ออกมาเต็มใบ ไม่ล้นขอบ | ☐ | |
| 4 | ข้อความไทยคมชัด ไม่เป็น tofu/สี่เหลี่ยม (ชื่อชุด, "ยังไม่ผ่านการฆ่าเชื้อ") | ☐ | |
| 5 | QR อ่านได้ด้วยมือถือหลายรุ่น (สแกนกลับได้ = packageId) | ☐ | |
| 6 | Label ห่อ **ก่อนนึ่ง** แสดงแถบ "ยังไม่ผ่านการฆ่าเชื้อ" (ไม่มีวันที่) | ☐ | |
| 7 | Label ห่อ **หลังนึ่ง** แสดงวันนึ่ง/หมดอายุที่มาจาก backend | ☐ | |
| 8 | พิมพ์ต่อเนื่อง 100–500 ใบ ไม่มี label ซ้ำ/หาย | ☐ | จำนวน = ______ |
| 9 | ปิด/เปิดเครื่องพิมพ์ระหว่างคิว → กลับมาพิมพ์ต่อได้ | ☐ | |
| 10 | **ถอดสายก่อน write** → job = FAILED/RETRYING (retry ได้, ไม่ค้าง) | ☐ | คาดหวัง NOT_SENT |
| 11 | **ถอดสายระหว่าง write** → job = ACK_UNKNOWN (ไม่ auto-retry, ไม่พิมพ์ซ้ำ) | ☐ | คาดหวัง MAYBE_SENT |
| 12 | **ถอดสายหลัง write ก่อน ACK** → job = ACK_UNKNOWN หลัง lease timeout | ☐ | |
| 13 | Gateway restart ระหว่าง write → job = ACK_UNKNOWN หลัง lease timeout | ☐ | |
| 14 | Network interruption (gateway↔API) → ไม่มี label ซ้ำ | ☐ | |

## 2. เกณฑ์ผ่าน (Acceptance)

- QR readability ≥ **99.5%** (นับจากจำนวนใบที่สแกนกลับได้ / จำนวนที่พิมพ์)
- ภาษาไทยไม่เป็น tofu/สี่เหลี่ยมทุกใบ
- **ไม่มี label ซ้ำจาก automatic retry** (ข้อ 10–14 คือหัวใจ — MAYBE_SENT ต้องไม่ retry)
- ทดสอบต่อเนื่องผ่านตามจำนวนที่กำหนด (100–500 ใบ)
- มี **Golden Label Sample** ที่อนุมัติแล้ว (ถ่ายรูป/สแกนเก็บไว้)

## 3. หลักฐานที่ต้องเก็บ

```
รุ่น/serial เครื่องทดสอบ:
OS / Gateway version:
Transport config (path/baud):
Golden Label Sample (แนบรูป):
จำนวนพิมพ์สำเร็จ / ล้มเหลว:
QR scan success rate:
Error log (ลบ secret ออกก่อน):
ผู้ทดสอบ / วันที่:
```

## 4. หมายเหตุ semantics ที่ต้องเข้าใจก่อนแปลผล

- `drain()` สำเร็จ = OS/driver รับข้อมูลแล้ว **ไม่ได้ยืนยันว่ากระดาษออกจริง** — Xprinter ส่วนใหญ่ไม่มี
  status protocol กลับมา ดังนั้นนิยาม **`PRINTED` = "Gateway ส่งข้อมูลสำเร็จตามหลักฐานที่
  อุปกรณ์รองรับ"** (ไม่ใช่การยืนยันเชิงกลไกว่าหมึก/กระดาษออก) — ข้อนี้ต้องระบุใน SOP ให้ผู้ใช้
  ตรวจ label จริงด้วยตาเสมอ
- ข้อ 10 (NOT_SENT) กับ ข้อ 11 (MAYBE_SENT) คือความต่างที่ FIX-04 แก้ไว้ — ต้องเห็นผลต่างกันจริง
  บนเครื่อง (NOT_SENT retry ได้, MAYBE_SENT เข้า ACK_UNKNOWN ให้คนตัดสิน)

## 5. สถานะปัจจุบัน

- ยังไม่ได้ทดสอบ (รอเครื่องจริง) — **AI ไม่สามารถรันข้อนี้ได้**
- FIX-01 ถึง FIX-07 (โค้ด + integration test กับ Postgres จริง) ผ่านแล้ว — ดู `PROGRESS.md`
- เมื่อ FIX-08 ผ่านครบ + UAT อนุมัติ จึงเริ่มงาน PWA Print Job integration (ข้อ 11 ของ directive)
  แล้วจึงเปิด Pilot
