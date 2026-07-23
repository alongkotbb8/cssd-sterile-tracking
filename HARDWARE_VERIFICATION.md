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
- `PRINTER_TRANSPORT=serial`, ตั้ง `PRINTER_SERIAL_PATH` + `PRINTER_SERIAL_BAUD_RATE` ให้ตรงเครื่อง
- ลงทะเบียน gateway ผ่าน ADMIN โดยตั้ง capability จริง:
  `POST /print-jobs/gateways { name, environment: "PRODUCTION", transportMode: "SERIAL", canConfirmRealPrint: true }`
- ยืนยันว่า `NODE_ENV=production` + `API_BASE_URL` เป็น `https://` (ไม่งั้น gateway จะไม่สตาร์ท)

## 0.1 ยืนยันรุ่น/โปรโตคอล Xprinter ก่อน (สำคัญ — ต่างจาก A318BT เดิม)

- **รุ่นเครื่อง Xprinter:** __________ (เช่น XP-370B / XP-420B / XP-460B ฯลฯ)
- **command dialect:** เป็น **TSPL/TSPL2** หรือไม่? (ถ้าเป็น ESC/POS ล้วน ต้องเพิ่ม transport/renderer ใหม่)
- **การเชื่อมต่อ:** USB-Serial (COM), USB-printer-class, Bluetooth, หรือ Network/LAN?
  - ถ้าไม่ใช่ Serial (เช่น USB printer-class หรือ network) → `SerialTransport` ใช้ตรง ๆ ไม่ได้ ต้องเพิ่ม transport ใหม่ (implement `PrinterTransport` เดิม — NOT_SENT/MAYBE_SENT/SENT ต้องครบ)
- **baud rate / DPI / ความกว้าง label:** ตรงกับที่ตั้งไว้ (203 DPI, 60×40mm) หรือไม่? ปรับ config ถ้าต่าง
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
