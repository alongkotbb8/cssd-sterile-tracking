# CSSD Print Gateway

Worker service ที่ claim งานพิมพ์จาก CSSD API แล้วส่ง TSPL ไปเครื่องพิมพ์ label จริง
(ดู `AI_DEVELOPMENT_GUARDRAILS.md` ส่วน Print Job Design และ Milestone 2)

**หลักการสำคัญ:** PWA ไม่พิมพ์ตรงและไม่ตั้งสถานะ `PRINTED` เอง — สร้างแค่ `PrintJob`
แล้วรอ gateway (บริการนี้) มา claim/พิมพ์/ยืนยันผลจริงเท่านั้น

## Setup

```bash
cd apps/print-gateway
npm install
cp .env.example .env
```

ถ้าเครื่องยังไม่มี system library ของ `canvas` (ใช้ render label เป็นภาพเพื่อรองรับ
ภาษาไทย — ดูหัวข้อด้านล่าง) ให้ติดตั้งก่อน `npm install`:

- macOS: `brew install pkg-config cairo pango libpng jpeg giflib librsvg`
- Debian/Ubuntu: `apt-get install libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev`

1. ให้ ADMIN ลงทะเบียน gateway ผ่าน `POST /print-jobs/gateways` (body: `{"name": "CSSD ชั้น 2"}`)
   — จะได้ `apiKey` รูปแบบ `{keyId}.{secret}` **แสดงครั้งเดียว เก็บให้ดี**
2. ใส่ค่านั้นลง `.env` ที่ `GATEWAY_API_KEY`
3. ตั้ง `API_BASE_URL` ให้ชี้ไป CSSD API ที่ใช้งานจริง (production ต้องเป็น `https://`
   เท่านั้น — ดูหัวข้อ Security ด้านล่าง)

```bash
npm run dev     # หรือ npm run build && npm start
```

## Print job state machine

```
QUEUED → CLAIMED → PRINTING → SENT → PRINTED   (สำเร็จจริง — real transport)
                            → SENT → SIMULATED (transport เป็น console/mock เท่านั้น)
FAILED (ก่อนถึง SENT) → RETRYING → QUEUED (ครบจำนวนครั้ง → DEAD_LETTER)
ค้างเกิน lease timeout:
  CLAIMED         → QUEUED       (ยังไม่เริ่มพิมพ์ ปลอดภัย)
  PRINTING/SENT   → ACK_UNKNOWN  (ไม่รู้ว่าถึงเครื่องพิมพ์จริงหรือยัง ห้าม auto-retry
                                   ต้องให้ SUPERVISOR/ADMIN ตัดสินผ่าน
                                   POST /print-jobs/:id/resolve)
QUEUED → CANCELLED (ยกเลิกได้ก่อน claim เท่านั้น)
```

**ทำไมต้องมี SENT คั่นระหว่าง PRINTING กับ PRINTED**: ถ้า gateway ยืนยันพิมพ์สำเร็จ
(`ack`) แล้วโดนตีความว่าล้มเหลวเพราะ network หลุดพอดีตอนแจ้ง backend อาจโดน retry
ซ้ำ = พิมพ์ label 2 ใบ (ปัญหาจริงที่พบจาก QA audit) วิธีแก้: แยกเป็น 2 การยืนยัน
(`markSent` ทันทีที่ `transport.send()` คืนผลสำเร็จ แล้วค่อย `ack`) — หลังจุดที่ยืนยัน
ว่าส่งสำเร็จแล้ว **ห้าม `fail()`/retry อัตโนมัติเด็ดขาด** ถ้า network หลุดระหว่างแจ้ง
backend ให้ job ค้างแล้วกลายเป็น `ACK_UNKNOWN` ให้คนตัดสินใจแทนการเดา

## Printer transport

ตั้งผ่าน `PRINTER_TRANSPORT`:

- **`console`** (default, dev เท่านั้น) — log คำสั่ง TSPL ออกทาง console แทนการส่ง
  เครื่องพิมพ์จริง (เทียบเท่า `MockPrinterAdapter` ฝั่ง Flutter) ACK จะตั้งเป็น
  `SIMULATED` เสมอ **ไม่ใช่** `PRINTED` (กันสับสนว่าพิมพ์จริงทั้งที่เป็นแค่ทดสอบ
  pipeline) — **ห้ามใช้บน production**: `config.ts` จะปฏิเสธการสตาร์ททันทีถ้า
  `NODE_ENV=production` และ `PRINTER_TRANSPORT=console`
- **`serial`** — ส่ง TSPL จริงผ่าน USB/Serial (`serialport` npm package) ต้องตั้ง
  `PRINTER_SERIAL_PATH` (เช่น `/dev/tty.usbserial-xxxx`) และ
  `PRINTER_SERIAL_BAUD_RATE` (ให้ตรงกับเครื่องพิมพ์ ค่าเริ่มต้นทั่วไป 9600)

เพิ่ม transport อื่น (เช่น network/IP printer) โดย implement `PrinterTransport`
(`src/transports/transport.ts`) — ต้องตั้ง `isSimulated=false` เสมอสำหรับ
transport ที่พิมพ์จริง

## Label rendering (ภาษาไทย)

`label-renderer.ts` render label ทั้งใบเป็นภาพด้วย `canvas` (ฟอนต์ Sarabun ที่แนบมา
ใน `assets/fonts/` — ชุดเดียวกับที่ใช้ฝั่งมือถือ) แล้วแปลงเป็น TSPL `BITMAP` — วิธี
เดียวกับ `apps/mobile/lib/core/printer/label_renderer.dart` ที่ยืนยันแล้วว่าพิมพ์
ภาษาไทยได้จริง เพราะคำสั่ง TSPL `TEXT`/`QRCODE` แบบ native ใช้ฟอนต์ในตัวเครื่องซึ่ง
ไม่มีอักษรไทย วิธีนี้ยังปิดช่องโหว่ TSPL string injection ไปด้วย (ไม่มี TEXT/QRCODE
ที่รับ string จาก payload ไปต่อ command ตรงๆ อีกแล้ว — ทั้งใบเป็น bitmap เดียว)

ก่อนพิมพ์ทุกครั้ง gateway จะคำนวณ SHA-256 ของ payload ใหม่แล้วเทียบกับ `payloadHash`
ที่ backend ส่งมา (ต้องตรงกันแบบ sort-key เสมอ เพราะ Postgres jsonb ไม่รับประกัน
ลำดับคีย์) ถ้าไม่ตรง = ปฏิเสธการพิมพ์ทันที (`PAYLOAD_HASH_MISMATCH`) ไม่มีการ
retry อัตโนมัติ

## Security

- Auth: `X-Gateway-Key: {keyId}.{secret}` เท่านั้น (ไม่ใช่ JWT ผู้ใช้)
- `API_BASE_URL` (FIX-06 — Private IP ไม่ใช่ข้อยกเว้นใน production):
  - `NODE_ENV=production` → **`https://` เท่านั้น** (แม้ localhost/LAN IP ก็ปฏิเสธ `http://`)
  - `NODE_ENV=development`/`test` → `http://` ได้เฉพาะ `localhost`/`127.0.0.1`/`::1` เท่านั้น
    (ปลายทางอื่น รวม LAN IP ต้องใช้ `https://`)
  - `config.ts` ปฏิเสธการสตาร์ทถ้าไม่ผ่าน — กัน `X-Gateway-Key` รั่วแบบ plaintext บนสาย
- `packageId`/ข้อความบน label ผ่านการตรวจ format + ตัด control character ก่อน
  render ทุกครั้ง (defense-in-depth แม้ backend สร้างข้อมูลเองก็ตาม)

## ข้อจำกัดที่รู้อยู่ (known limitations)

- **ผูกกับปุ่มพิมพ์ใน PWA/มือถือแล้ว** (Phase 2) — ปุ่มพิมพ์สร้าง `PrintJob` ผ่าน backend
  (แนบ `Idempotency-Key`) แล้วมีหน้า poll สถานะ `QUEUED→CLAIMED→PRINTING→SENT→PRINTED`
  + จัดการ `FAILED/DEAD_LETTER/SIMULATED/ACK_UNKNOWN`, ยกเลิกเฉพาะ QUEUED, reprint reason,
  หน้า supervisor resolve — เส้นทางพิมพ์ตรง (Bluetooth/System) ถูกปลดจาก UI เหลือเป็น
  legacy fallback ระดับโค้ดเท่านั้น (ดู `apps/mobile/lib/features/print_jobs/`)
  **ยังเหลือ:** ทดสอบ E2E จริง (PWA↔API↔Gateway↔เครื่องพิมพ์) — ต้องรัน server + FIX-08
- **Integration test กับ Postgres จริง** — มีแล้ว (FIX-07) อยู่ที่ `apps/api/test/integration/`
  รันด้วย `npm run test:integration` ฝั่ง API (แยกจาก `npm test` เพื่อไม่บังคับให้
  CI/ทุกคนต้องมี Postgres) ครอบคลุม claim `FOR UPDATE SKIP LOCKED`, concurrent ACK,
  cancel-vs-claim, resolve ACK_UNKNOWN, REQUEUE ซ้ำ, idempotency 10-concurrent + crash
  rollback กับ Postgres จริง — ต้องมี local Postgres ตาม `DATABASE_URL` (suite สร้าง/ลบ
  DB `cssd_inttest` เอง) ยังไม่ผูกเข้า CT pipeline (ต้องเพิ่ม Postgres service ใน CI ก่อน)
- **Hardware soak test กับเครื่อง Xprinter จริง** ยังไม่ได้ทำ (ไม่มีเครื่องในสภาพแวดล้อม
  พัฒนา) — ดูขั้นตอน + แบบฟอร์มที่ `HARDWARE_VERIFICATION.md` (ต้องผ่านก่อนเปิด Pilot)
