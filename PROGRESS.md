# PROGRESS.md — สถานะความคืบหน้าโปรเจกต์ CSSD

> ไฟล์นี้เป็น changelog ระดับสั้น ๆ ใช้ป้องกันความสับสนว่าทำอะไรไปแล้ว/ยัง
> **กติกา: ทุกครั้งที่แก้ไขโค้ด (ฟีเจอร์ใหม่/บั๊กฟิกซ์/เปลี่ยน config) ต้องอัปเดตไฟล์นี้ก่อนจบงาน**
> - ติ๊ก checklist ที่เกี่ยวข้อง
> - เพิ่มบรรทัดใน "Log การเปลี่ยนแปลง" (วันที่ + สรุปสั้น ๆ + ไฟล์หลักที่แตะ)
> - ถ้าเจอ assumption ใหม่ที่กระทบสถาปัตยกรรม ให้บันทึกไว้ในหมวด "ข้อสมมติที่ต้องยืนยัน"

---

## Checklist เฟส 1 (MVP)

- [x] โครง monorepo, README, docker-compose, .env.example
- [x] Prisma schema + migration + seed
- [x] Auth + role-based (CSSD/SUPERVISOR/ADMIN) + AuditLog
- [x] สร้างชุด + เลขรันจาก backend + พิมพ์ label (mock + FlashLabel A318 adapter จริง)
- [x] สแกนเข้า/ออก/คืน + เลือกแผนกปลายทาง + ผู้รับ optional + บล็อกของหมดอายุ
- [x] Mobile: สแกน QR, batch scan, แดชบอร์ดโดนัท, รายงานรายสัปดาห์ + PDF
- [x] **แจ้งเตือน FCM (ใกล้หมดอายุ + ลืมสรุปรายวัน)** — โครง backend + mobile ครบ (ดูหมายเหตุด้านล่าง)

## ตอบสนอง AI_DEVELOPMENT_GUARDRAILS.md — M1 (PWA Pilot) + M2 (Print Gateway) (2026-07-18)

ผู้ใช้ส่งเอกสาร `AI_DEVELOPMENT_GUARDRAILS.md` (+ `AGENTS.md`) เป็นข้อบังคับใหม่ที่เข้มกว่าเดิม
(traceability, idempotency แบบ atomic, Print Job Queue + Gateway แยกจาก PWA) สั่งให้ทำ
ตามนี้ **ยกเว้น Milestone 3 (Offline)** และ **Milestone 4 (Reports/Ops) รอจนกว่า M1+M2 จะถูกตรวจสอบก่อน**
**ยังไม่ deploy** ตามคำสั่ง

### M1 — เก็บตกจาก Online PWA Pilot

- **Idempotency แบบ atomic จริง** (ของเดิมเป็น find→execute→store ซึ่ง 2 request พร้อมกัน
  ผ่านได้ทั้งคู่) — เปลี่ยน `IdempotentRequest` ให้ insert แถว `PENDING` ก่อนเสมอ (unique
  constraint บน `key` = compare-and-swap จริงที่ระดับ DB), เพิ่ม `requestHash`/`method`/`status`
  — key ซ้ำ+payload ต่างกัน หรือ user ต่างกัน หรือกำลังรันอยู่ → 409 ทั้งหมด
  ทดสอบ concurrent request จริงด้วย fake client ที่ตั้งใจ interleave (`idempotency.service.spec.ts`)
  ยืนยันว่า fn รันแค่ครั้งเดียวจริง — ใช้กับ scan in/out/return, สร้าง package, เปิดรอบนึ่ง,
  บันทึกผล batch, สร้าง print job ครบทุกจุดที่ guardrails ระบุ
- **Security headers ครบ**: CSP (`frame-ancestors 'none'`, `object-src 'none'`), HSTS 1 ปี,
  Referrer-Policy `no-referrer`, Permissions-Policy `camera=(self)` (helmet ไม่มีให้ default
  ต้องเพิ่มเอง) — `main.ts`
- **Manual entry fallback**: ปุ่มพิมพ์เลขห่อเองในหน้าสแกน (validate รูปแบบ + backend lookup
  ซ้ำ) ติด flag `manualEntry` ส่งไป backend → เขียนลง AuditLog metadata แยกจากการสแกนจริง
  ตรวจสอบย้อนหลังได้ว่ารายการไหนพิมพ์เอง
- **หน้าสรุปผลหลังยืนยัน** แทน SnackBar อย่างเดียว — แสดงราย ห่อ สำเร็จ/ไม่ผ่านพร้อมเหตุผล
  + ปุ่ม "ลองใหม่เฉพาะที่ไม่ผ่าน", เสียง/แรงสั่นต่างกันระหว่างสำเร็จทั้งหมดกับมีรายการพลาด,
  ยืนยันก่อนล้างรายการที่สแกนไว้
- ทุก mutation หลัก (scan, สร้าง package, batch create/result) ส่ง `Idempotency-Key` (สุ่ม
  128 บิตต่อการกด 1 ครั้ง, ไม่ใช่ package uuid เพิ่ม) — `core/api/api_client.dart newIdempotencyKey()`

### M2 — Print Job Queue + Print Gateway (สถาปัตยกรรมใหม่)

**หลักการ:** PWA/มือถือสร้าง `PrintJob` เท่านั้น ไม่พิมพ์ตรงและไม่ตั้งสถานะ `PRINTED` เอง —
Gateway (บริการแยก, `apps/print-gateway`) ที่มี credential ของตัวเอง (`X-Gateway-Key`,
**ไม่ใช่** user JWT) เป็นผู้ claim/พิมพ์/ยืนยันผลจริงเท่านั้น

- **Schema ใหม่**: `PrintJob` (สถานะ `QUEUED→CLAIMED→PRINTING→PRINTED`, หรือ
  `FAILED→RETRYING→DEAD_LETTER`, หรือ `CANCELLED`; เก็บ `payload`+`payloadHash`,
  `attemptCount`, `isReprint`/`reprintReason`) และ `PrinterDevice` (`keyId` public +
  `apiKeyHash` แบบ bcrypt เหมือน password — ไม่เก็บ API key จริงไว้ที่ไหนเลยหลังสร้าง)
- **`GatewayAuthGuard`** แยกจาก JWT โดยสิ้นเชิง — header `X-Gateway-Key: {keyId}.{secret}`,
  lookup ด้วย `keyId` ตรงๆ (ไม่ bcrypt.compare วนทุกเครื่อง) แล้วเทียบ `secret` ด้วย bcrypt
- **Claim แบบ atomic จริง**: `SELECT ... FOR UPDATE SKIP LOCKED` ใน transaction — กัน 2
  gateway claim งานเดียวกันด้วย row lock ระดับ Postgres (ไม่ใช่แค่เช็ค status ที่แอป)
- **ACK คือทางเดียว** ที่ `Package.printedAt`/`reprintCount` จะถูกอัปเดต — ACK ซ้ำ (retry
  ของ gateway เอง) idempotent ไม่เพิ่ม reprintCount ซ้ำ, ตรวจว่า job ผูกกับ gateway ที่ ACK
  จริง (`assertOwnedByGateway`) กัน gateway อื่นมา ACK งานที่ไม่ใช่ของตัวเอง
- **Retry/DEAD_LETTER**: fail ครบ `MAX_ATTEMPTS=3` ครั้ง → `DEAD_LETTER` ต้องมีคนมาดูมือ
- **Lease timeout recovery**: cron ทุก 2 นาที คืนงาน `CLAIMED`/`PRINTING` ที่ค้างเกิน 10 นาที
  (gateway อาจ crash) กลับเข้าคิว `QUEUED` ให้ gateway ตัวอื่น claim ได้
- **Reprint ต้องมีเหตุผล** (`reprintReason` บังคับกรอกเมื่อ `isReprint=true` — DTO validation)
- **ลบ endpoint เก่าที่ขัด guardrails**: `POST /packages/:id/printed` (เดิมให้ client เรียกเอง
  หลัง `printLabel()` สำเร็จ — ตรงกับ anti-pattern ที่ guardrails ห้ามไว้ชัดเจน "ห้ามถือว่าเปิด
  Print Dialog เท่ากับพิมพ์สำเร็จ") ตัดออกทั้ง backend/mobile แล้ว
- **`apps/print-gateway`** (Node/TS ใหม่ทั้งแอป): heartbeat, poll+claim loop, TSPL builder
  (QR native ของเครื่องพิมพ์ — ไม่ต้อง rasterize, ใช้ `payload.packageId` เท่านั้นตรงกฎโดเมน),
  `PrinterTransport` interface + `ConsoleTransport` (mock เทียบเท่า `MockPrinterAdapter`
  ฝั่ง Flutter) — README มีขั้นตอน setup ครบ

## ตรวจ + แก้ตาม M1_M2_REQUIRED_FIXES.md (2026-07-22)

Audit รอบสองตรวจ Print Job Queue/Gateway ที่สร้างในรอบ M2 โดยเฉพาะ ให้คะแนน 60-65%
พร้อม Critical/High/Testing/Security findings — ตรวจกับโค้ดจริงแล้วยืนยันว่าทุกข้อเป็น
บั๊กจริง (ไม่ใช่ false positive) แก้ครบทุกข้อ:

- **แก้ duplicate-print ambiguity (Critical 1.1)**: เพิ่มสถานะ `SENT` คั่นระหว่าง
  `PRINTING`→`PRINTED` — gateway เรียก `markSent()` ทันทีที่ `transport.send()` คืนผล
  สำเร็จ **ก่อน** `ack()` เสมอ หลังจุดที่ยืนยันว่าส่งสำเร็จแล้ว **ห้าม `fail()`/retry
  อัตโนมัติเด็ดขาด** ถ้า network หลุดตอนแจ้ง backend (`markSent`/`ack` เอง throw) จะ log
  แล้วปล่อยให้ job ค้าง ไม่ retry ซ้ำ — lease recovery จะแปลง `PRINTING`/`SENT` ที่ค้างเกิน
  timeout เป็นสถานะใหม่ `ACK_UNKNOWN` (ต่างจาก `CLAIMED` ที่ยังปลอดภัยคืนเข้าคิวได้ตรงๆ)
  ต้องให้ SUPERVISOR/ADMIN ตัดสินใจผ่าน `POST /print-jobs/:id/resolve`
  (`resolveAckUnknown()` — เลือก "ยืนยันพิมพ์จริง" หรือ "เปิดงานพิมพ์ใหม่" พร้อมหมายเหตุ)
- **บล็อก mock/console transport ไม่ให้เป็น PRINTED จริง (Critical 1.2)**: เพิ่มสถานะ
  `SIMULATED` แยกจาก `PRINTED` ชัดเจน — `ack()` รับ `simulated` flag (มาจาก
  `transport.isSimulated`) ไม่แตะ `Package.printedAt`/`reprintCount` เมื่อ simulated;
  `config.ts` ปฏิเสธการสตาร์ท gateway ทันทีถ้า `NODE_ENV=production` และ
  `PRINTER_TRANSPORT=console`
- **แก้ concurrent ACK race (Critical 1.3)**: `markPrinting`/`markSent`/`ack`/`fail`
  เปลี่ยนจาก `update()` ตรงๆ เป็น `updateMany({where:{id,status:expected},...})` +
  เช็ค `count===1` (compare-and-swap ระดับ DB) — เขียน integration-style unit test
  จำลอง 2 ACK แข่งกันจริงด้วย fake Prisma client ยืนยันว่า `Package.reprintCount`
  เพิ่มแค่ครั้งเดียว ไม่ใช่สองครั้ง
- **Thai bitmap label rendering ที่ gateway (High)**: เพิ่ม `canvas` + `qrcode` npm
  package, แนบฟอนต์ Sarabun ชุดเดียวกับมือถือ (`assets/fonts/`) — `label-renderer.ts`
  render label ทั้งใบเป็นภาพเหมือน `label_renderer.dart` ฝั่งมือถือ ทดสอบจริงด้วย `jsqr`
  decode QR กลับมาเทียบ packageId + เช็คว่ามีพิกเซลดำจริง (ไม่ใช่ tofu ว่างเปล่า) — **วิธีนี้
  ปิดช่องโหว่ TSPL string injection ไปด้วย** (ไม่มี `TEXT`/`QRCODE` ที่รับ string จาก
  payload ไปต่อ command ตรงๆ อีกแล้ว ทั้งใบเป็น `BITMAP` เดียว)
- **Real printer transport (High)**: เพิ่ม `SerialTransport` (`serialport` npm package)
  ส่ง TSPL ผ่าน USB/Serial จริง — เลือกผ่าน `PRINTER_TRANSPORT=serial` +
  `PRINTER_SERIAL_PATH`/`PRINTER_SERIAL_BAUD_RATE`
- **แก้ IDOR ที่ `GET /print-jobs/:id` (High 2.1)**: `findOne()` รับ `userId`/`role`
  เพิ่ม ownership check เหมือน `listJobs()` เดิม (เจ้าของหรือ SUPERVISOR/ADMIN เท่านั้น)
- **isReprint คำนวณที่ backend เสมอ (High 2.2)**: `createJob()` เลิกรับ `isReprint` จาก
  client โดยสิ้นเชิง (ตัดออกจาก DTO) คำนวณจาก `package.printedAt !== null` เอง บังคับ
  ต้องมี `reprintReason` เมื่อเป็น reprint จริง
- **จำกัด cancel เหลือ QUEUED เท่านั้น (High 2.3)**: ตัด `CLAIMED` ออก (claim แล้วอาจพิมพ์
  ไปแล้ว ยกเลิกไม่ปลอดภัย)
- **Gateway ตรวจ payloadHash ก่อนพิมพ์ทุกครั้ง (High 2.4)**: คำนวณ SHA-256 ใหม่เทียบกับ
  `payloadHash` จาก backend ก่อนเรียก `transport.send()` — ไม่ตรง = ปฏิเสธทันที
  (`PAYLOAD_HASH_MISMATCH`) ไม่มี auto-retry แก้ `hashPayload` ทั้งสองฝั่งให้ sort key
  ก่อน stringify เสมอ (Postgres jsonb ไม่รับประกัน preserve key order ตอนอ่านกลับ)
- **แก้ semantics `printerId` ปนกันระหว่างงาน pool กับงานที่ระบุเครื่อง (High 2.6)**:
  แยกเป็น `requestedPrinterId` (สิ่งที่ผู้ใช้ระบุตอนสร้าง, immutable) กับ `printerId`
  (เครื่องที่ claim ไปแล้วจริง) — `claim()` จับคู่ด้วย `requestedPrinterId`,
  `recoverStaleLeases()` แยก `CLAIMED`(ปลอดภัย→`QUEUED`) จาก `PRINTING`/`SENT`
  (ไม่ปลอดภัย→`ACK_UNKNOWN`)
- **Idempotency ไม่ค้าง PENDING ถาวรอีกต่อไป (High 2.7)**: เพิ่ม `expiresAt` — แถว
  PENDING ที่ค้างเกิน TTL (5 นาที, เคย crash กลางคัน) reclaim ได้ด้วย key เดิมแทนที่จะบล็อก
  ตลอดไป, เพิ่ม cron ทำความสะอาดทุกชั่วโมง (`cleanupExpired`) ลบทั้ง PENDING ค้างและ DONE
  เก่าเกิน retention (24 ชม.)
- **บังคับ Idempotency-Key ในทุก mutation หลัก (High 2.8)**: `run()` รับ
  `{required: true}` — ไม่ส่ง key มา = 400 ทันที ใช้กับ package create, scan
  in/out/return, batch create/result, print job create ครบทุกจุด
- **Route ordering + gateway HTTPS enforcement (3.2/4.1)**: ย้าย static routes
  (`gateways/list`, `gateways`, `gateways/:id/revoke`) ไว้ก่อน dynamic `:id/*` ใน
  controller เพื่อความชัดเจน (segment count ต่างกันจึงไม่มี collision จริงอยู่แล้ว
  แต่ทำตามที่ audit ขอเพื่อความปลอดภัย/อ่านง่าย); `config.ts` ปฏิเสธ `API_BASE_URL` ที่
  เป็น `http://` ยกเว้น localhost/LAN (กัน `X-Gateway-Key` รั่วผ่านสาย)

### ⚠️ Known limitations (ตรงตาม Definition of Done — ห้ามบอกว่าเสร็จทั้งที่ยังไม่จริง)

1. **ยังไม่ได้ผูก Print Gateway กับปุ่มพิมพ์ในแอปมือถือ/PWA** — mobile ยังพิมพ์ตรงผ่าน
   `SystemPrintAdapter`/Bluetooth เดิม (ไม่สร้าง `PrintJob`) เพราะต้องเพิ่ม UI เลือก
   printer ที่ลงทะเบียนไว้ + polling สถานะงาน ซึ่งเป็นงานถัดไป
2. **Claim atomicity (`FOR UPDATE SKIP LOCKED`) พิสูจน์ตรรกะด้วย unit test (fake Prisma
   client ที่จำลอง compare-and-swap จริง) เท่านั้น** — มี local Postgres ที่ apply
   migration ทุกตัวแล้วและใช้ตรวจว่า schema ใช้งานได้จริง แต่**ตั้งใจไม่เพิ่ม integration
   test กับ Postgres จริงเข้า default test suite** เพราะจะเปลี่ยน contract ของ `npm test`
   ให้ทุกคน/CI ต้องมี Postgres ที่ migrate ตรงกันเป๊ะ (เป็นการตัดสินใจเรื่อง tooling/CI ที่
   ควรคุยกับทีมก่อน ไม่ใช่แค่โค้ดฟิกซ์) — ดูรายละเอียดใน `apps/print-gateway/README.md`
3. **CSP/HSTS ยังไม่ได้ทดสอบกับ Swagger UI จริง** (อาจต้องปรับ directive ถ้า Swagger UI แสดงผลผิดจากการที่ CSP เข้มไป)
4. **M3 (Offline-first) และ M4 ส่วนที่เหลือ (monitoring/alerts, backup/restore drill)** ยังไม่ทำตามคำสั่งผู้ใช้ในรอบนี้
5. **ยังไม่ deploy** (ตามคำสั่งผู้ใช้) — โค้ดทั้งหมดอยู่ใน working tree เท่านั้น รอ verify ก่อน

### Verification ที่ทำแล้ว
- `apps/api`: `npx tsc --noEmit` ผ่าน, `npx jest` ผ่าน **87/87** (เพิ่มจาก 61 — เพิ่ม/เขียนใหม่
  print-jobs state machine 33 เคส รวม concurrent-ACK race จริง, idempotency 12 เคส รวม
  TTL-reclaim + required-key)
- `apps/mobile`: `flutter analyze` ผ่าน ไม่มี issue (ไม่ได้แตะโค้ด mobile รอบนี้)
- `apps/print-gateway`: `npx tsc --noEmit` ผ่าน, `npx jest` ผ่าน **20/20** (label renderer
  6 เคส รวม decode QR จริงด้วย jsqr + เทียบ payloadHash, poll-loop 7 เคส รวม
  duplicate-print-ambiguity, config guards 6 เคส รวม HTTPS/production enforcement)
- Prisma migration `20260722072226_m1_m2_audit_fixes` apply กับ local Postgres 16 จริง
  สำเร็จ (`postgresql://cssd:cssd_dev_pw@localhost:5432/cssd_db`) — ยืนยันว่า schema
  ใช้งานได้จริงกับ Postgres ไม่ใช่แค่ผ่าน `prisma validate`

## ตรวจ + แก้ตาม M1_M2_REAUDIT_FIX_DIRECTIVE.md (2026-07-22)

Audit รอบสาม (directive กำกับก่อน Pilot) — ตรวจ 8 FIX + PWA gate + Hardware gate
ทำทีละ FIX ตามลำดับ พร้อม test คู่กับการแก้ และหยุดถามเมื่อเจอ fork สถาปัตยกรรม
(FIX-02 ผู้ใช้เลือกแนวทาง A: single transaction)

- **FIX-01 — Migration `expiresAt` backfill-safe**: migration เดิมเพิ่ม `NOT NULL`
  ตรงๆ (พังถ้าตารางมีข้อมูล) → แก้เป็น 3 ขั้น (add nullable → backfill DONE=+24h/
  อื่น=+5min → set NOT NULL) พิสูจน์ 3 สถานการณ์กับ Postgres จริง: DB ว่าง (migrate
  deploy ทั้งชุด), DB มีข้อมูล (isolated SQL 5→5 แถว), DB มีข้อมูลผ่าน Prisma จริง
  (4→4 แถว, `migrate status` = up to date ไม่ drift) — ไม่มีแถวหาย ทุกแถวมี expiresAt
- **FIX-02 — Idempotency crash recovery (แนวทาง A, single transaction)**: เดิม reclaim
  แถว PENDING ที่หมด TTL แล้ว **rerun mutation** (กฎห้ามละเมิดสั่งห้าม) → เปลี่ยนเป็น
  reservation + domain mutation + AuditLog + response อยู่ใน `$transaction` เดียวกัน
  (`idem.run` เปิด tx แล้วส่ง `tx` ให้ service ทุกตัว) crash = rollback ทั้งก้อน จึง
  ไม่มี PENDING commit เดี่ยว/mutation ครึ่งทาง/เลขรันกระโดด — ตัด logic rerun ทิ้ง
  ถ้าเจอ PENDING → 409 ไม่ rerun เด็ดขาด ต้อง thread `tx` ผ่าน scan(in/out/return),
  packages.create(+running-number), batches(create/recordResult+recall), print-jobs.createJob
  — **แก้เพิ่มหลัง review:** cron `cleanupExpired` จำกัดลบเฉพาะ `DONE` เท่านั้น ห้ามแตะ
  `PENDING` ที่หมดอายุ (กฎ "ห้ามลบ PENDING โดยไม่ตรวจ domain result")
- **FIX-03 — ACK_UNKNOWN resolve ครั้งเดียว**: CAS เดิมเช็คแค่ `status=ACK_UNKNOWN`
  (REQUEUE คงสถานะเดิม → เรียกซ้ำสร้างงานใหม่ได้หลายงาน) → เพิ่มสถานะ terminal
  `RESOLVED_PRINTED`/`RESOLVED_REQUEUED`, CAS เพิ่มเงื่อนไข `resolvedAt IS NULL`,
  งานใหม่ลิงก์กลับ `requeuedFromJobId` (`@unique` กันสร้างซ้ำแม้แข่งกัน), resolve +
  สร้างงานใหม่ใน transaction เดียว — resolve ซ้ำ/พร้อมกันสำเร็จได้ครั้งเดียว
- **FIX-04 — Transport typed result NOT_SENT/MAYBE_SENT/SENT**: `write()` error อาจมี
  byte ออกไปแล้วบางส่วน → เพิ่ม `TransportSendError(outcome)`; SerialTransport จัดประเภท
  (เปิด port ไม่ได้=NOT_SENT, write/drain error=MAYBE_SENT); poll-loop map: NOT_SENT→fail/
  retry, MAYBE_SENT→`reportMaybeSent()`→ACK_UNKNOWN (ห้าม retry), error ไม่ระบุชนิด→ถือเป็น
  MAYBE_SENT เสมอ (กฎ "ห้ามถือว่า write error = ไม่มี byte ออก"); เพิ่ม endpoint
  `POST /print-gateway/jobs/:id/maybe-sent` + service `reportIndeterminate` (CAS CLAIMED/
  PRINTING→ACK_UNKNOWN)
- **FIX-05 — Backend ตัดสิน simulation mode**: เดิม ack รับ `simulated` จาก request (gateway
  ปลอมได้) → ลบ flag ออกจาก request; เพิ่ม `environment`/`transportMode`/`canConfirmRealPrint`
  ใน `PrinterDevice` (backend เป็นเจ้าของ); เปลี่ยน capability ได้เฉพาะ ADMIN + AuditLog
  (`GATEWAY_CAPABILITY_CHANGE`); gateway ถูก revoke → auth ไม่ผ่าน → ACK ไม่ได้ (guard เดิม)
  — **แก้เพิ่มหลัง review:** เดิมตรวจแค่ `canConfirmRealPrint` ตัวเดียว (ตั้ง CONSOLE+true แล้ว
  ดัน PRINTED ได้) → เพิ่ม invariant validation (register/update: canConfirm=true ได้เฉพาะ
  PRODUCTION + ไม่ใช่ CONSOLE) **และ re-check ครบ 3 ค่าตอน ACK** (`canReallyConfirm`) —
  Console/Test/Dev → SIMULATED เสมอ แม้แถวในฐานข้อมูลจะขัดแย้ง
- **FIX-06 — Production HTTPS เข้มขึ้น**: เดิมยอม http ใน private LAN เสมอ → เปลี่ยนเป็น
  production=https เท่านั้น (แม้ localhost/private IP ก็ไม่ยอม), dev/test=http เฉพาะ
  localhost/127.0.0.1 — config test ครบทุกเคส
- **FIX-07 — PostgreSQL integration/concurrency tests**: เพิ่ม suite แยก (`npm run
  test:integration`, jest config + global setup/teardown สร้าง/ลบ DB `cssd_inttest` จริง)
  รันกับ Postgres จริง 11 เคส: idempotency 10-concurrent-same-key (→ 1 package, ทุก
  request replay response เดียวกัน, เลขรัน seq=1 ไม่กระโดด — พิสูจน์ row-lock+replay จริง
  ที่ fake ทำไม่ได้), crash rollback, committed-PENDING no-rerun, dual-claim (FOR UPDATE
  SKIP LOCKED), concurrent-ACK (reprintCount +1 ครั้งเดียว), cancel-vs-claim, concurrent
  resolve, REQUEUE-ซ้ำ, lease recovery — ผ่านทั้งหมด
- **FIX-08 — Hardware verification**: **AI ทำไม่ได้** (ไม่มีเครื่อง A318BT จริง) — จัดทำ
  ขั้นตอน+แบบฟอร์มเก็บหลักฐานไว้ที่ [HARDWARE_VERIFICATION.md](HARDWARE_VERIFICATION.md)
  ให้ทีมที่มีเครื่องจริงรัน (รวมเคสถอดสายก่อน/ระหว่าง/หลัง write เพื่อพิสูจน์ NOT_SENT vs
  MAYBE_SENT บนเครื่องจริง) — ต้องผ่านก่อนเปิด Pilot

### พฤติกรรมที่เปลี่ยน (บันทึกไว้)
- **Scan เป็น all-or-nothing ต่อ request แล้ว**: เดิมแต่ละห่อ commit แยกทรานแซกชัน
  (บางห่อสำเร็จ บางห่อพลาดได้) — ตอนนี้ทั้ง request อยู่ทรานแซกชันเดียว "ไม่ผ่าน" ปกติ
  (ไม่พบห่อ/สถานะผิด/หมดอายุ/CAS ชน) ยังรายงานรายห่อได้เหมือนเดิม (ไม่ throw) แต่ถ้าเกิด
  DB error จริงกลางคัน ทั้ง request จะ rollback แล้ว retry ด้วย idempotency-key เดิมได้สะอาด

### Verification ที่ทำแล้ว (รอบ re-audit + แก้หลัง review)
- `apps/api`: `npx tsc --noEmit` ผ่าน, unit `npx jest` **94/94**, integration
  `npm run test:integration` **12/12** (Postgres จริง 16.14 — ต้องมี DB พร้อมตาม
  `DATABASE_URL` ถึงจะ reproduce ได้)
- `apps/print-gateway`: `npx tsc --noEmit` ผ่าน, `npx jest` **25/25** (poll-loop รวม
  NOT_SENT/MAYBE_SENT/unknown-error mapping, config guards รวม FIX-06 ครบทุกเคส)
- Migrations ใหม่: `20260722140000_fix03_ackunknown_resolution`,
  `20260722150000_fix05_gateway_capability` (ทั้งคู่ additive, มี default/ backfill-safe) —
  apply กับ dev DB จริง, `prisma migrate status` = up to date ไม่ drift
- **ยังไม่ deploy** (ตามคำสั่งเดิม) — FIX-08 (hardware) + PWA Print Job integration + UAT
  ยังเหลือก่อนเปิด Pilot ตาม Pilot Gate

---

## ฟีเจอร์: ส่งออก/รับคืนชุดที่ยังไม่ฆ่าเชื้อ + แสดงตำแหน่งชุด (2026-07-16, v1.2.0+9)

รองรับ workflow ส่งชุด `PACKED` (แพ็กแล้วยังไม่ฆ่าเชื้อ) ออกไปสถานที่ภายนอก เช่น รพ.พญาไท แล้วตามสถานะคืน/ยังไม่คืนได้:

- **สถานะใหม่ `PACKED_OUT`** ใน state machine: `PACKED → PACKED_OUT → PACKED` (รับคืนแล้วพร้อมเข้ารอบนึ่งทันที ไม่ต้อง reprocess) — แยกจาก `ISSUED` เพราะเส้นทางคืนต่างกัน
- **โหมดเบิกออกเดิมรับทั้ง STERILE และ PACKED** — ถ้าสแกนของ PACKED จะขึ้นเตือนสีส้ม "⚠ ยังไม่ฆ่าเชื้อ" บนการ์ด (ไม่บล็อก), โหมดส่งคืนรับทั้ง ISSUED และ PACKED_OUT
- **สถานที่ภายนอก** ใช้ตาราง Department เดิม + `type='external'` (seed เพิ่ม "รพ.พญาไท" ตัวอย่าง) — ชื่อใน dropdown ต่อท้าย "(ภายนอก)"
- **`POST /departments`** endpoint ใหม่ (SUPERVISOR/ADMIN) + ปุ่ม "เพิ่มสถานที่" ในหน้าสแกน เปิด sheet สร้างสถานที่ใหม่ได้ทันที
- **การ์ดห่อแสดงตำแหน่งปัจจุบัน** "📍 อยู่ที่ ..." (จาก movement OUT ล่าสุด — เพิ่ม last movement ใน `GET /packages`) + filter ใหม่ "ส่งออกไม่ฆ่าเชื้อ"
- **หน้ารายละเอียด**: สถานะ PACKED_OUT แสดงการ์ดม่วง "ส่งออกโดยยังไม่ฆ่าเชื้อ · อยู่ที่ X · ยังไม่คืนคลัง" แทน stepper
- Dashboard summary เพิ่ม `packedOut` count; Movement ใช้ type OUT/RETURN เดิม (รายงานรายสัปดาห์ไม่กระทบ)
- Migration: `20260716040000_add_packed_out_status` (ALTER TYPE ADD VALUE) — Render รัน `prisma migrate deploy` อัตโนมัติตอน deploy

## Checklist เฟส 2 (บางส่วนเริ่มแล้ว — ยังไม่ครบ)

- [x] Recall อัตโนมัติเมื่อ batch ผล indicator ไม่ผ่าน (`batches.service.ts: recall()`)
- [x] Printer adapter จริง (FlashLabel A318 ผ่าน Bluetooth/USB, ไม่ใช่ Zebra ตามชื่อเดิมใน CLAUDE.md — ยึดยี่ห้อจริงที่ใช้งาน)
- [ ] Offline-first สมบูรณ์ (drift/SQLite + sync queue ฝั่ง mobile) — **ยังไม่ทำ**, เป็น dependency ประกาศไว้ใน pubspec แต่ไม่มีโค้ดใช้งานจริง

## เฟส 3 — ยังไม่เริ่ม
ผูกเคส/ผู้ป่วย, เชื่อม HIS, พอร์ทัลแผนกปลายทาง

---

## FCM Notification — รายละเอียดสิ่งที่ทำ (2026-07-15)

**Backend** (`apps/api/src/modules/notifications/`)
- `FcmToken` model ใหม่ใน Prisma (1 user : N devices) + migration `20260715090000_add_fcm_tokens`
- `FcmService` — ครอบ firebase-admin; ถ้าไม่ตั้ง `FIREBASE_PROJECT_ID` / `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY` ใน `.env` จะเข้าโหมด no-op (log แทนการยิงจริง) เหมือน pattern `MockPrinterAdapter`
- `NotificationsController` — `POST /api/v1/notifications/fcm-token` (ลงทะเบียน), `DELETE .../fcm-token` (ยกเลิก)
- `ExpiryReminderScheduler` — cron ทุกวัน 08:00 (Asia/Bangkok) เตือนห่อ STERILE ที่จะหมดอายุใน 2 วัน
- `DailySummaryReminderScheduler` — cron ทุกวัน 20:00 (Asia/Bangkok) เตือนสรุปข้อมูลประจำวัน
- Unit tests: `apps/api/src/modules/notifications/__tests__/notifications.spec.ts` (6 tests, ผ่านหมด)

**Mobile** (`apps/mobile/lib/core/notifications/fcm_service.dart`)
- `firebase_core` + `firebase_messaging` เพิ่มใน pubspec
- `FcmService.init()` เรียกใน `main.dart` ก่อน `runApp` — ถ้า `Firebase.initializeApp()` throw (ยังไม่มีไฟล์ config) จะ catch แล้วปิดฟีเจอร์เงียบ ๆ ไม่กระทบแอปส่วนอื่น
- แสดง local notification ตอนแอป foreground ผ่าน `flutter_local_notifications` (ของเดิมมีอยู่ใน pubspec แต่ไม่เคยถูกใช้ ตอนนี้ผูกใช้งานจริงแล้ว)
- ลงทะเบียน token อัตโนมัติหลัง login สำเร็จ (`main.dart` ผ่าน `ref.listen(authControllerProvider)`), ยกเลิก token ตอน logout (`auth_controller.dart`)
- Android: `google-services` gradle plugin ถูกเพิ่มไว้แต่ apply แบบมีเงื่อนไข (เช็คว่ามี `android/app/google-services.json` ก่อน) — กัน build พังตอนยังไม่มีไฟล์จริง

### ⚠️ สิ่งที่ต้องทำก่อนแจ้งเตือนจริง ๆ จะทำงาน (ยังไม่มีของจริง)
1. สร้างโปรเจกต์ Firebase จริง แล้วเพิ่ม:
   - Backend: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` ใน `apps/api/.env` (จาก service account JSON)
   - Mobile: วางไฟล์ `apps/mobile/android/app/google-services.json` และ `apps/mobile/ios/Runner/GoogleService-Info.plist`
2. iOS ต้องเปิด Push Notifications capability + อัปโหลด APNs key ใน Firebase Console (ยังไม่ได้ทำ เพราะต้องมี Apple Developer account)
3. ก่อนใช้งานจริงในองค์กร ควรทดสอบส่งจริงอย่างน้อย 1 รอบ (ตอนนี้ทดสอบได้แค่ logic query ผ่าน unit test ยังไม่เคยยิง push จริง)

### ข้อสมมติที่ต้องยืนยัน (ASSUMPTION)
- **"ลืมสรุปรายวัน"** — ในโดเมนยังไม่มี entity "สรุปรายวัน" ที่บันทึกว่าเสร็จหรือยัง จึงใช้กติกาง่าย ๆ ว่า: ถ้าวันนั้นมีการสแกนเข้า-ออก (`Movement`) อย่างน้อย 1 รายการ จะเตือนตอน 20:00 ทุกวันแบบ blanket (ไม่เช็คว่า "ทำสรุปแล้วหรือยัง") ถ้าต้องการ logic แม่นกว่านี้ (เช่น เช็คเฉพาะห่อที่ยัง ISSUED ค้างอยู่, หรือมี entity DailyReport แยก) ต้องคุยเพิ่มเพราะกระทบ schema
- ผู้รับแจ้งเตือนตอนนี้คือ **ทุก user ที่ status = ACTIVE** (ไม่แยกตาม role) — ถ้าต้องการจำกัดเฉพาะ SUPERVISOR/ADMIN หรือแยกตามแผนก ต้องปรับ `NotificationsService.sendToActiveUsers`

---

## บั๊กฟิกซ์: สแกนหาเครื่องพิมพ์ Bluetooth แล้ว crash (2026-07-15)

**อาการ:** กด "ค้นหา" ในหน้าเลือกเครื่องพิมพ์ → จอแดง `SecurityException: Need BLUETOOTH permission`

**สาเหตุ:** `AndroidManifest.xml` ไม่ได้ประกาศ permission Bluetooth ไว้เลยแม้แต่ตัวเดียว และโค้ดไม่ได้ขอ runtime permission ก่อนเรียก `FlutterBluePlus.startScan()`

**การแก้รอบ 1 (v1.1.1+3) — permission:**
1. เพิ่ม permission ใน manifest ครบทั้งสองยุค: `BLUETOOTH`/`BLUETOOTH_ADMIN`/`ACCESS_FINE_LOCATION` (Android ≤11, จำกัด `maxSdkVersion=30`) และ `BLUETOOTH_SCAN` (neverForLocation) + `BLUETOOTH_CONNECT` (Android 12+)
2. เพิ่ม `permission_handler` — ขอ runtime permission ก่อนสแกนทุกครั้ง ถ้าโดนปฏิเสธถาวรมีปุ่มลัดไปหน้าตั้งค่าแอป
3. เช็คว่า Bluetooth เปิดอยู่ก่อนสแกน (Android ขอเปิดให้อัตโนมัติผ่าน `turnOn()`)

**การแก้รอบ 2 (v1.1.2+4) — เปลี่ยนวิธีเชื่อมต่อให้เหมือนแอพเครื่องพิมพ์จริง:**
ตรวจซ้ำพบปัญหาเชิงสถาปัตยกรรม: A318BT เป็น **Bluetooth Classic (SPP)** แต่โค้ดเดิมใช้ `flutter_blue_plus` ซึ่งรองรับ **BLE เท่านั้น** → ต่อให้ permission ครบ ก็สแกนไม่เจอ/เชื่อมต่อไม่ได้กับเครื่องพิมพ์ Classic-only (แอพเครื่องพิมพ์จริงทั้งหมดใช้ SPP socket)
1. เพิ่ม `print_bluetooth_thermal` (^1.2.2) — เปิด RFCOMM/SPP socket แบบเดียวกับแอพ official
2. `FlashLabelA318Adapter` มี 2 โหมด: `.classic(name, mac)` = SPP (ทางหลัก) และ `.ble(device)` = BLE GATT (สำรอง สำหรับรุ่น dual-mode)
3. หน้าเลือกเครื่องพิมพ์: โชว์ "จับคู่ไว้แล้วในเครื่อง (แนะนำ)" อัตโนมัติทันทีที่เปิด sheet (จาก `pairedBluetooths` — Classic) + ปุ่มค้นหาสแกน BLE เป็นทางเสริม
4. กันเคสจริง: ตัด connection ค้างก่อนต่อใหม่, เช็ค socket ยังอยู่ก่อนเขียนทุกครั้ง, ข้อความ error บอกวิธีแก้เป็นภาษาไทย

**วิธีใช้กับเครื่องจริง (ขั้นตอนแนะนำ):** ติดตั้ง APK ใหม่ → เปิดเครื่องพิมพ์ → จับคู่ printer ใน ตั้งค่า > Bluetooth ของมือถือ → เข้าแอป ตั้งค่า > เครื่องพิมพ์ → เครื่องจะขึ้นในหมวด "จับคู่ไว้แล้วในเครื่อง" ทันที → แตะเลือก → พิมพ์ทดสอบ

---

## บั๊กฟิกซ์: ตรวจทั้งระบบ — ตัวอักษรไทยเพี้ยน + เชื่อมต่อไม่ติด (2026-07-15, v1.1.3+5)

อ่านโค้ด native ของ `print_bluetooth_thermal` ทั้งไฟล์เพื่อหาช่องโหว่ พบสาเหตุจริงหลายจุด:

### สาเหตุ A — ตัวอักษรไทยเพี้ยน (root cause)
คำสั่ง TSPL `TEXT ...,"font",...,"ข้อความ"` ใช้ **ฟอนต์ในตัวเครื่องพิมพ์** (font "1"–"5") ซึ่งเป็น ASCII/ละตินล้วน **ไม่มี glyph ภาษาไทย** + การส่ง UTF-8 ให้เครื่องตีความตาม code page ของมันเอง → ไทยกลายเป็นขยะ นี่คือข้อจำกัดของคำสั่ง TEXT เอง แก้ที่ระดับ encoding ไม่ได้
- **วิธีแก้:** เพิ่ม [label_renderer.dart](apps/mobile/lib/core/printer/label_renderer.dart) — render label **ทั้งใบเป็นภาพ** ด้วย Flutter canvas (ใช้ฟอนต์ในเครื่องที่รองรับไทยอยู่แล้ว) รวม QR (จาก qr_flutter) แล้วแปลงเป็น 1-bit ส่งผ่านคำสั่ง TSPL `BITMAP` — วิธีมาตรฐานเดียวกับแอพเครื่องพิมพ์จริงที่พิมพ์ภาษาไม่ใช่ละติน
- label 60×40mm @203DPI = 480×320 dots (60 bytes/แถว), BITMAP bit 0 = จุดดำ

### สาเหตุ B — เชื่อมต่อไม่ติด / ค้าง (พบช่องโหว่ในโค้ด native ของ library)
1. **native ค้างถาวรถ้าไม่มี BLUETOOTH_CONNECT (Android 12+):** โค้ด native มี `else if (!permissionGranted && sdk>=31) { return }` ที่ **ไม่ยิง result กลับ** → ทุก method (connect/pairedbluetooths/connectionStatus/writeBytes) ค้าง Future ตลอดไป → **แก้:** เพิ่ม `_ensureConnectPermission()` เช็ค/ขอสิทธิ์ก่อนเรียก native ทุกครั้ง ถ้าไม่ได้ก็ throw error ที่อ่านรู้เรื่องแทนการค้าง
2. **native connect() ไม่มี timeout:** RFCOMM `socket.connect()` บล็อกยาวถ้าเครื่องพิมพ์ปิด/นอกระยะ → **แก้:** ครอบ `.timeout(12s)` ฝั่ง Dart
3. **BLE scan ชนกับ Classic RFCOMM:** เปิด `flutter_blue_plus` BLE scan ค้างไว้ตอนเชื่อมต่อ Classic ทำให้ BT stack บางเครื่องรวน → **แก้:** `stopScan()` ก่อนเลือก/เชื่อมต่อเครื่องพิมพ์ทุกครั้ง
4. เช็ค Bluetooth เปิดอยู่ + ตัด socket ค้างก่อนต่อใหม่ + เช็ค connection ก่อนส่งทุกครั้ง (ตั้ง `_connected=false` เมื่อหลุด เพื่อให้รอบถัดไป reconnect)

**หมายเหตุพฤติกรรม library ที่รู้ไว้ (ไม่ต้องแก้):** `writeBytes` เติม `\n` นำหน้าเสมอ และ `connectionStatus` เขียน byte space ไปทดสอบ socket — ทั้งคู่อยู่ก่อน `SIZE`/`CLS` ของ TSPL จึงไม่กระทบภาพที่พิมพ์

**ยังต้องทดสอบกับเครื่องจริง:** ตำแหน่ง/ขนาดตัวอักษรบน label (ปรับพิกัดใน label_renderer.dart ได้), ความคมของ QR หลังพิมพ์จริง

---

## บั๊กฟิกซ์: หน้าสแกน QR กล้องขึ้น error ไม่แสดง preview (2026-07-15, v1.1.4+6)

**อาการ:** เข้าหน้าสแกน อนุญาตกล้องแล้ว แต่พื้นที่กล้องเป็นจอดำมีไอคอน "!" (error) ไม่แสดงภาพ

**สาเหตุ (พบในโค้ด mobile_scanner 5.2.3):**
- `MobileScanner.didChangeAppLifecycleState` มี `if (widget.controller != null) return;` — เมื่อเรา**ส่ง controller ของตัวเอง** widget จะ**ไม่จัดการ lifecycle ให้** (ไม่ start ใหม่เมื่อ resume) ดังนั้นถ้า `start()` ที่ถูกเรียกอัตโนมัติใน initState เกิด error (เช่น permission ยังไม่ถูกตัดสิน/timing) กล้องจะ**ค้างที่ error ตลอด ไม่ retry**
- ไม่มีการขอสิทธิ์กล้องอย่างชัดเจนก่อน start และไม่มี `errorBuilder` ให้ผู้ใช้ลองใหม่

**การแก้:**
1. ตั้ง `MobileScannerController(autoStart: false)` แล้ว **ขอสิทธิ์กล้อง (permission_handler) ก่อน** ค่อยสั่ง `start()` เอง
2. จัดการ lifecycle เอง (`WidgetsBindingObserver`): resume→start, paused/inactive→stop + subscribe `barcodes` stream เอง (ไม่ส่ง onDetect เข้า widget เพื่อเลี่ยง listener ซ้อน)
3. เพิ่ม UI ครบทุกสถานะ: กำลังโหลด / ถูกปฏิเสธ (ปุ่มอนุญาต หรือลัดไปตั้งค่าถ้าปฏิเสธถาวร) / กล้อง error (ปุ่มลองใหม่) — ไม่ปล่อยจอดำเฉย ๆ
4. เพิ่ม `CAMERA` permission + `uses-feature camera` ใน AndroidManifest
5. **iOS:** เพิ่ม `NSCameraUsageDescription` + `NSBluetoothAlwaysUsageDescription` + `NSBluetoothPeripheralUsageDescription` ใน Info.plist (เดิมไม่มีเลย → iOS จะ crash ทันทีเมื่อเปิดกล้อง/บลูทูธ)

---

## ตรวจทั้งระบบอีกรอบ (2026-07-15, v1.1.5+7) — เจอ 5 จุด แก้ครบ

หลังแก้ 3 บั๊กใหญ่ (printer, ไทย, กล้อง) ตรวจซ้ำทั้ง backend + mobile หาช่องโหว่ที่ยังไม่เจอ:

1. **[Mobile] หน้าสแกน: ปฏิเสธสิทธิ์กล้องแล้วไปเปิดใน "ตั้งค่าเครื่อง" กลับมาไม่หาย** — `didChangeAppLifecycleState` เดิมเช็คแค่ตอนได้สิทธิ์แล้ว (`if (_cameraGranted != true) return`) เลยไม่เคยเช็คซ้ำตอน resume ถ้ายังไม่เคยได้สิทธิ์ → ผู้ใช้กดปุ่ม "เปิดตั้งค่า" ไปอนุญาตแล้วกลับมาแอป ยังเห็นหน้า "ถูกปฏิเสธ" เดิม (ต้องออกจากหน้าแล้วกลับเข้าใหม่ถึงจะหาย) **แก้:** เช็คสิทธิ์ใหม่อัตโนมัติทุกครั้งที่ resume ถ้ายังไม่เคยได้สิทธิ์
2. **[Backend] FCM ส่งเกิน 500 token พังทั้งชุด** — Firebase `sendEachForMulticast()` จำกัด **500 tokens ต่อการเรียก 1 ครั้ง** แต่โค้ดเดิมส่งทุก token ในคำสั่งเดียว ถ้าผู้ใช้เยอะขึ้นในอนาคตจะ throw error ทำให้แจ้งเตือนไม่ออกเลยสักคน **แก้:** แบ่งเป็นชุดละ 500 tokens
3. **[Backend] initializeApp() ซ้ำจะ throw** — ถ้า `onModuleInit()` ถูกเรียกมากกว่า 1 ครั้งในโปรเซสเดียว (เช่น hot-reload ตอน dev) `admin.initializeApp()` throw "default app already exists" **แก้:** เช็ค `admin.apps.length` ก่อน ใช้ตัวเดิมถ้ามีอยู่แล้ว
4. **[Backend] ไม่มี validation ความยาว FCM token/deviceId** — DB คอลัมน์เป็น `VARCHAR(300)`/`VARCHAR(100)` แต่ DTO ไม่มี `@MaxLength` ถ้า client ส่งค่ายาวเกินจะได้ Prisma error 500 ดิบๆ แทนที่จะเป็น 400 ที่อ่านง่าย **แก้:** เพิ่ม `@MaxLength` ให้ตรงกับ schema
5. **[Mobile] ตรวจ POST_NOTIFICATIONS (Android 13+)** — เช็คแล้วไม่ใช่ช่องโหว่: plugin `firebase_messaging` ประกาศ permission นี้ในแมนิเฟสต์ของตัวเองอยู่แล้วและ merge เข้าแอปอัตโนมัติ, `FirebaseMessaging.instance.requestPermission()` เรียก runtime request ให้เองบน Android ครบอยู่แล้ว — ไม่ต้องแก้เพิ่ม

**ตรวจแล้วไม่พบปัญหา (จุดที่ตั้งใจดูเป็นพิเศษ):** scan.service.ts ใช้ compare-and-swap (`updateMany` + status ใน where) ป้องกัน race condition ของการสแกนซ้ำพร้อมกันถูกต้องดีอยู่แล้วทั้ง 3 endpoint (scanIn/scanOut/scanReturn), auth.service.ts มี timing-attack mitigation (bcrypt dummy hash) และ login throttle guard ครบ

---

## PWA (เว็บ) — deploy บน Cloudflare Pages (ไม่ใช่ Vercel)

**URL production:** https://sterelis-cssd.pages.dev/#/login
**Cloudflare Pages project:** `sterelis-cssd` (dashboard: `dash.cloudflare.com` → Pages → sterelis-cssd)

**⚠️ ไม่มี CI/CD ผูกไว้ — deploy ด้วยมือผ่าน `wrangler` CLI เท่านั้น** ก่อนหน้านี้ค้างอยู่ที่ commit `4e65d23` (เก่ากว่างานในเซสชันนี้ทั้งหมด) เพราะไม่มีใคร deploy ซ้ำหลัง commit ใหม่ๆ **ต้องจำ deploy เองทุกครั้งที่แก้โค้ด mobile แล้วอยากให้เว็บอัปเดตด้วย:**

```bash
cd apps/mobile
flutter build web --release
npx wrangler pages deploy build/web --project-name=sterelis-cssd --branch=main
```

เช็คว่า deploy ไปจริงและเป็นเวอร์ชันไหน: `curl https://sterelis-cssd.pages.dev/version.json`

### บั๊กเฉพาะเว็บที่เจอ + แก้แล้ว (2026-07-15, v1.1.5+7)
โค้ด mobile ใช้ `dart:io Platform` (เช่น `Platform.isAndroid`, `Platform.operatingSystem`) ซึ่ง **throw `UnsupportedError` ทันทีที่เรียกบนเว็บ** (ไม่ใช่แค่คืนค่า false) — เจอ 2 จุดที่จะพังจริงถ้าไม่ guard ด้วย `kIsWeb` ก่อน:

1. **`registerFcmToken()`** (`fcm_service.dart`) เรียก `Platform.operatingSystem` เพื่อสร้าง deviceId → **พังทันทีหลัง login สำเร็จทุกครั้งบนเว็บ** (ฟังก์ชันนี้ถูกเรียกอัตโนมัติผ่าน `ref.listen(authControllerProvider)` ใน `main.dart`)
2. **หน้าตั้งค่า > เครื่องพิมพ์** (`settings_page.dart`) เช็ค `Platform.isAndroid` ใน 3 จุด (`_loadPaired`, `_requestBluetoothPermissions`, `_scan`) → **พังทันทีที่เปิดหน้านี้บนเว็บ**

**แก้:** เพิ่ม `kIsWeb` (จาก `flutter/foundation.dart`) เช็คก่อน `Platform.*` ทุกจุด (short-circuit ป้องกันไม่ให้ evaluate `Platform` เลยบนเว็บ) และซ่อนปุ่ม "ค้นหา" Bluetooth printer บนเว็บ (เครื่องพิมพ์ Bluetooth Classic SPP ของ A318BT ใช้ไม่ได้ในเบราว์เซอร์อยู่แล้ว เป็นข้อจำกัดฮาร์ดแวร์/แพลตฟอร์ม ไม่ใช่บั๊ก) แสดงข้อความอธิบายแทนว่าเวอร์ชันเว็บใช้ Mock Printer ได้อย่างเดียว

ยืนยันด้วย `flutter build web --release` ผ่านสำเร็จไม่มี error หลังแก้ (ก่อนแก้คอมไพล์ผ่านเหมือนกัน แต่จะ throw ตอน **runtime** ในเบราว์เซอร์ ซึ่งเทสต์แบบ static analysis จับไม่ได้ — ต้องรู้พฤติกรรม `dart:io` บนเว็บถึงจะเจอ)

### บั๊กฟิกซ์: พิมพ์รายงาน PDF บนเว็บพัง — `MissingPluginException: printPdf` (2026-07-16)

**อาการ:** กดพิมพ์รายงานสรุปในเวอร์ชันเว็บ → แถบแดง `MissingPluginException(No implementation found for method printPdf on channel net.nfet.printing)`

**สาเหตุ:** `.dart_tool/flutter_build/<hash>/web_plugin_registrant.dart` เป็นไฟล์ที่ Flutter auto-generate รายชื่อ web plugin ที่ต้อง register — cache ตัวที่ค้างอยู่ (สร้างก่อนที่ session นี้จะเพิ่ม `printing`, `permission_handler`, `firebase_*` เข้า pubspec) **ไม่มี `PrintingPlugin.registerWith(registrar)` เลย** ทำให้ `PrintingPlatform.instance` fallback ไปใช้ `MethodChannelPrinting` ตัวเดิม (ของ mobile) ซึ่งยิง native channel ที่ไม่มีจริงในเบราว์เซอร์ → throw ทันทีที่กดพิมพ์

**แก้:** `flutter clean` + `flutter pub get` + build ใหม่ทั้งหมด บังคับให้ regenerate plugin registrant ให้ตรงกับ pubspec ปัจจุบัน (ตรวจแล้วว่ามี `PrintingPlugin.registerWith` ในไฟล์ที่ build จริงก่อน deploy) แล้ว deploy ใหม่

**ข้อควรระวังสำหรับอนาคต:** ถ้าเพิ่ม/ลบ plugin ใน pubspec.yaml แล้วจะ build web ต่อ ให้ `flutter clean` ก่อนเสมอ อย่าพึ่ง incremental build เฉยๆ — cache นี้ไม่ invalidate ให้อัตโนมัติเสมอไปเวลาจำนวน plugin เปลี่ยน

### บั๊กฟิกซ์: เลือกเครื่องพิมพ์ Bluetooth ไว้แล้ว แต่พิมพ์ไปตกที่ Mock Printer เสมอ (2026-07-16, v1.1.6+8)

**อาการ:** ตั้งค่าเลือก FlashLabel A318BT ไว้แล้ว แต่พอกดพิมพ์ฉลากกลับขึ้น "ส่งพิมพ์ไปยัง Mock Printer (Console) แล้ว"

**สาเหตุ:** `printerAdapterProvider` เป็น `StateProvider` ธรรมดา เก็บค่าไว้ใน **memory เท่านั้น ไม่เขียนลง storage เลย** ทุกครั้งที่แอปถูกปิด-เปิดใหม่ (หรือรีเฟรชหน้าเว็บ) provider จะ rebuild ใหม่แล้วกลับไปที่ default `MockPrinterAdapter()` เสมอ ทั้งที่ผู้ใช้เพิ่งเลือกเครื่องพิมพ์จริงไปในเซสชันก่อนหน้า

**แก้:** เปลี่ยน `printerAdapterProvider` เป็น `NotifierProvider` (`PrinterAdapterNotifier`) ที่:
- บันทึกการเลือกลง `SharedPreferences` (key `printer_selection`) ทุกครั้งที่เลือกเครื่องพิมพ์ในหน้าตั้งค่า
- ตอนเปิดแอปใหม่ อ่านค่าที่บันทึกไว้กลับมาสร้าง adapter ใหม่ให้ตรงกัน — สำหรับ BLE ใช้ `BluetoothDevice.fromId(mac)` เพื่อคืนค่า device reference ได้โดยไม่ต้องสแกนใหม่
- ยังไม่ได้ auto-connect ทันทีตอนเปิดแอป (connect แบบ lazy ตอนกดพิมพ์ครั้งแรกเหมือนเดิม) — แค่ "จำ" ว่าควรใช้เครื่องไหน ไม่ใช่ค้างที่ Mock

### ข้อจำกัดของเวอร์ชันเว็บที่รู้ไว้ (ไม่ต้องแก้ เป็นข้อจำกัดแพลตฟอร์มจริง)
- พิมพ์ label ผ่าน Bluetooth ไม่ได้ (ใช้ Mock Printer แทน) — ต้องใช้แอปมือถือ Android/iOS ถึงจะพิมพ์ label จริงได้
- FCM push notification บนเว็บต้องตั้งค่า Firebase web config (VAPID key) แยกจากมือถือ ยังไม่ได้ทำ (อยู่ในสโคปเดียวกับที่ยังไม่ได้สร้าง Firebase project จริงตามหมายเหตุด้านบน)

---

---

## บั๊กฟิกซ์รอบใหญ่: กล้อง genericError + ยกเครื่องระบบพิมพ์ (2026-07-16, v1.2.1+10)

รายงานจากเครื่องจริง (Xiaomi/MIUI): กล้องขึ้น `genericError`, กดเชื่อมเครื่องพิมพ์ Bluetooth ไม่ขอ permission และต่อไม่ติด, พิมพ์ไปตกที่ Mock ตลอด

### 1. กล้องสแกน genericError — race condition (แก้)
**สาเหตุ:** ตอนเปิดหน้าสแกน `initState → _initCamera()` ขอ permission (async) → ระบบเด้ง dialog ทำให้แอป pause→resume → `didChangeAppLifecycleState(resumed)` เห็น `_cameraGranted == null` เลยเรียก `_initCamera()` **ซ้ำอีกรอบพร้อมกัน** → `_cam.start()` ถูกเรียก 2 ครั้งซ้อน → mobile_scanner โยน `genericError`
**แก้:** เพิ่ม flag `_busy` กัน init/start ซ้อน + resume จะ re-init เฉพาะตอนไม่มีงานค้าง + แยก `_safeStart()` สำหรับ resume

### 2. ยกเครื่องระบบพิมพ์ — เพิ่ม "ระบบพิมพ์ของเครื่อง/เบราว์เซอร์" เป็นค่าเริ่มต้น + เอา Mock ออก
**ปัญหาเดิม:** default เป็น Mock (แค่ log ไม่พิมพ์จริง) ทำให้ทุกครั้งพิมพ์ไปตกที่ Mock อย่างงงๆ + Bluetooth ต่อตรง (Classic SPP) ต่อไม่ติดในหลายเครื่อง (ขึ้นกับ MIUI/รุ่นเครื่องพิมพ์/การจับคู่) + เว็บพิมพ์ label ไม่ได้เลย
**แก้:**
- เพิ่ม [`SystemPrintAdapter`](apps/mobile/lib/core/printer/system_print_adapter.dart) — render label เป็นภาพ (รองรับไทย) ฝังลง PDF 60×40mm แล้วเปิดหน้าต่างพิมพ์ผ่าน `Printing.layoutPdf` (แพ็กเกจ `printing`)
  - บนมือถือ: เปิด Android print dialog → เลือกเครื่องพิมพ์ผ่าน **แอปของผู้ผลิตเครื่องพิมพ์เอง / print service ที่ติดตั้งไว้** (Mopria ฯลฯ)
  - บนเว็บ: เปิดหน้าต่างพิมพ์ของเบราว์เซอร์
- ตั้งเป็น **ค่าเริ่มต้น** ใน `printer_provider.dart` (แทน Mock) — พิมพ์ได้จริงทุกแพลตฟอร์มตั้งแต่ติดตั้ง
- **ลบ Mock Printer ออกทั้งหมด** (`mock_printer_adapter.dart` ลบทิ้ง, เอาออกจากหน้าเลือกเครื่องพิมพ์) ตามที่ผู้ใช้ขอ ลดความสับสน
- Bluetooth ต่อตรง (FlashLabel A318BT SPP) ยังมีอยู่เป็น "ทางเลือก" สำหรับคนที่ต้องการส่ง TSPL ตรง

**ตอบคำถามเรื่องเว็บ + แอปเครื่องพิมพ์:** เบราว์เซอร์ต่อ Bluetooth Classic SPP ตรงไม่ได้ (ข้อจำกัด browser security) แต่ผ่าน `Printing.layoutPdf` จะเปิดหน้าต่างพิมพ์ของระบบ ซึ่งบน Android จะส่งต่อไปยัง print service — **รวมถึงแอปของเครื่องพิมพ์นั้นๆ ที่ลงทะเบียนเป็น print service ไว้** จึงพิมพ์ผ่านแอปของเครื่องพิมพ์ได้ (ทางอ้อมผ่าน OS ไม่ใช่ต่อ Bluetooth ตรงใน lib)

**หมายเหตุ:** เครื่องพิมพ์ label แบบ TSPL บางรุ่นอาจไม่มี Android print service ของตัวเอง → ต้องเช็คกับรุ่นจริง ถ้าไม่มี ให้ใช้ Bluetooth ต่อตรงแทน

---

## Log การเปลี่ยนแปลง

| วันที่ | สรุป | ไฟล์หลัก |
|---|---|---|
| 2026-07-23 | **Gate 2 §2B matrix เต็ม + §2D 3 รอบติด + §3B SBOM (`f42a802`,`d3a6083`):** เพิ่ม `lifecycle.spec.ts` (Playwright request → **API จริง + Postgres จริง** ไม่ mock): เลขรันจาก backend, วงจรเต็ม PACKED→in(batch)→CI/BI pass→STERILE+expiry→ISSUED→RETURNED→reprocess→PACKED, batch fail→recall ผ่าน **PackageBatchAttempt** (ยังเห็นหลัง batchId เปลี่ยน), **expired blocked fail-closed** (seed fixture `DRESS-20260101-9999`), scan-out ไร้ dept→400, PACKED→internal ปฏิเสธ/PACKED→external=PACKED_OUT, tag attach/filter/detach, **RBAC** CSSD ห้าม record result/resolve (403), **Idempotency-Key replay** ไม่สร้าง print job ซ้ำ, user JWT เรียก gateway ACK ไม่ได้, token เก่าถูกปฏิเสธหลัง logout-all. `auth.spec.ts` (UI): login ผิด, **account lockout** (seed user `LOCK001` แยกเฉพาะ), logout→กลับ login, reload คง session. `scanner.spec`: กล้องล้มเหลว (CI headless=denied) ต้องเห็น error UI+retry+manual entry. **seed**: LOCK001 + ห่อหมดอายุ. **CI**: e2e วน **3 รอบติด** (§2D), job `sbom` CycloneDX สำหรับ api+print-gateway (upload artifact §3B — `--ignore-npm-errors` เพราะ overrides ทำ npm ls รายงาน invalid โดยกลไก ไม่ใช่ silence scan). รวม **76 tests / 5 spec files** ไม่มี skip/fixme | `e2e/tests/{lifecycle,auth,scanner}.spec.ts`, `apps/api/prisma/seed.ts`, `.github/workflows/{ci,security-scan}.yml` |
| 2026-07-23 | **✅ CI เขียวครบ 7/7 jobs ที่ `bba878d` (PR #1 รอบ 5):** e2e **18/18 ผ่าน** ข้าม Desktop Chrome + Mobile Chrome (Pixel 7) + **WebKit/Safari** (smoke/PWA + login + สร้างห่อ + scanner manual-entry) + api-gateway/integration/mobile/npm-audit/secret-scan/flutter-audit ผ่านหมด. รอบ 4→5 แก้จากหลักฐาน trace: (1) WebKit `keyboard.type` ทำ `@` ใน password หลุด → เปลี่ยน `typeInto` เป็น `keyboard.insertText` (atomic) + settle 300ms หลัง click; (2) ปุ่มบันทึกใน create sheet `aria-disabled` จนกว่าจะเลือก template → spec คลิก chip 'ชุดถอนฟัน' ก่อน. สถานะ: **CI_VERIFIED ที่ `bba878d`** — รอ QA ตรวจ + ลงนาม Gate 1; Gate 2 workflows ยังครอบเฉพาะ auth/create/scanner (matrix เต็มตาม §2B เป็นงานถัดไป) | `e2e/tests/{helpers,flow}.ts` |
| 2026-07-23 | **Push + PR #1 + CI iteration (Gate 3 เริ่มจริง):** push `feat/pre-pilot-m1m2-pwa-security` + เปิด [PR #1](https://github.com/alongkotbb8/cssd-sterile-tracking/pull/1) หลังได้ `workflow` scope. **CI รอบ 1** (`ae3bb2e`): 5/7 ผ่าน — `npm-audit` ตก (39 vulns, 12H+1C) + `e2e` ตก (Flutter ใหม่ render `<flutter-view>`+`<flt-glass-pane>` คู่ → strict mode). **แก้ (`ed4b2b5`):** npm `overrides` เจาะจงรุ่น patch (tar^7.5.19 critical/bcrypt, multer^2.2.0, js-yaml@4^4.3.0, lodash^4.18.1, glob@10^10.5.0, picomatch@4^4.0.5, tmp^0.2.7) + regen lockfile (npm ไม่ re-resolve overrides บน lockfile เดิม) — ยืนยัน `npm audit --audit-level=high` exit 0, api 110/110, gateway 33/33; e2e ใช้ `.first()`. **CI รอบ 2:** npm-audit ✅, smoke ✅ ครบ 3 browsers, login-driven specs ตก (semantics placeholder เป็น element ซ่อน click ไม่ติด + รอ host แบบ visible ผิด) → **แก้ (`982ee5b`):** force-click + dispatchEvent fallback, รอ `flt-semantics` แบบ attached, เพิ่ม `byLabel()` (aria-label OR text — Flutter ใส่ label เป็น aria-label), sync selector กับ ARB จริง ("รายการ"/"บันทึก + ออกเลขรัน"/"สร้างห่อสำเร็จ"/"แพ็กแล้ว"/"เพิ่ม") | `package.json` (overrides), `package-lock.json`, `e2e/tests/*` |
| 2026-07-23 | **Gate 1 §1B — automated checks เพิ่ม (`dfa3f6e` + local):** (1) **static i18n check** (`i18n_static_check_test.dart`) สแกน string literal ทุกไฟล์ lib/ (strip comment) หาอักษรไทยนอก l10n — ทุกรายการต้องอยู่ใน allowlist ที่ระบุ file+pattern+เหตุผล+owner; จับของหลุดจริง 2 กลุ่มแล้วแก้: `'ห่อซีล'/'ห่อผ้า'` (label content → ย้ายเข้า `wrapTypeLabelText()` ใน label_renderer ตาม §1A.5), log ไทยใน fcm_service → อังกฤษ. Allowlist: label_renderer (SOP), _PrinterSheet + A318/system adapters (legacy หลัง flag, มีแผนลบหลัง Hardware Gate). (2) **layout tests** (`layout_test.dart`): Login+Settings @ 320px/Pixel 7/Desktop 1366 × text scale 1.0/1.3 × th/en = 24 เคส **ไม่มี overflow**. รวม test suite = **90 เคส** analyze สะอาด | `test/{i18n_static_check,layout}_test.dart`, `label_renderer.dart`, `create_package_sheet.dart`, `fcm_service.dart` |
| 2026-07-23 | **Gate 2 prep — Playwright E2E ข้าม Chrome/WebKit (directive §2C/§2D/§3B):** ลบ `test.skip`/`test.fixme` ออกจาก flow.spec (ผิด §2C) — flow เป็นเทสจริง (login→shell, สร้างห่อ→เห็นในรายการ). เพิ่ม `scanner.spec.ts` (WebKit compat + manual fallback: ปฏิเสธ QR ผิดรูปแบบ, รับเลขห่อถูกต้อง, ไม่ auto-submit — camera-independent รันได้ทั้ง chromium/webkit). `helpers.ts` เพิ่ม `openTab`. **สคริปต์:** `test`=smoke(ไม่ต้องมี stack), `test:e2e`=ทุก spec (CI เรียกพร้อม stack), `test:webkit`. สร้าง **e2e/package-lock.json** → CI ใช้ `npm ci` (§2A). **CI (ci.yml):** e2e job ติดตั้ง chromium+webkit, รันทุก spec ข้าม `chromium`+`mobile-chrome`+`webkit` (§3B), upload playwright-report artifact. gitignore playwright artifacts. **สถานะ:** specs+config parse ผ่าน (`playwright test --list` = 24 tests, ไม่มี skip/fixme) — **ยังไม่รันจริง** (ต้อง stack+browsers) → ให้ remote CI เป็นผู้ตรวจหลัง push | `e2e/tests/{flow,scanner,helpers}.ts`, `e2e/{package.json,package-lock.json}`, `.github/workflows/ci.yml`, `.gitignore` |
| 2026-07-23 | **Safari/iOS QR Scanner hardening (master directive §4B.1):** แยก logic กล้องเป็นโมดูล pure ทดสอบได้ `scanner_camera.dart` — `classifyScannerError` จำแนก error 7 ชนิด (permissionDenied/Revoked, insecureContext, noCamera, cameraInUse, unsupportedConstraint, generic) รองรับ DOMException ของ Safari WebKit (`NotAllowedError`/`NotReadableError`/`OverconstrainedError`/`SecurityError`), `ScanCooldown` กัน frame เดิมยิงซ้ำ (§4B.1.11), `scannerErrorMessage` i18n. Wire scan_page: errorBuilder แสดงข้อความ+ปุ่มตามชนิด error (revoked→เปิดตั้งค่า), ปุ่มไฟฉาย/สลับกล้อง **gate ด้วย capability จริงจาก controller value** (ไม่เดา user-agent §4B.1.7), `toggleTorch/switchCamera` await+catch ไม่ crash บน Safari (§4B.1.8), state "กำลังเปิดกล้อง", cooldown reset เมื่อล้าง/สลับโหมด. **ARB:** เพิ่ม scanErr*/scanStateInitializing/scanTorchFailed (th+en). **Test:** `scanner_camera_test.dart` 16 เคส (denied/revoked/insecure/noCamera/inUse/constraint/generic + cooldown + i18n). **Playwright:** เพิ่ม project `webkit`(Desktop Safari)+`mobile-safari`(iPhone 14), `install:browsers` ติดตั้ง chromium+webkit, README ระบุกล้องจริงต้องตรวจ Gate 4. เอกสาร SSOT อัปเดต target = Chrome + Safari iOS. analyze สะอาด · test **64/64** · build web --release ✓ | `scanner_camera.dart`, `scan_page.dart`, `l10n/*.arb`, `test/scanner_camera_test.dart`, `e2e/{playwright.config.ts,package.json,README.md}`, `CLAUDE/AGENTS/README.md` |
| 2026-07-23 | **Gate 1 residual (§1.3) — ปรับเอกสารเก่าให้ยึด master directive:** ตั้ง `CSSD_MASTER_EXECUTION_DIRECTIVE.md` เป็น **SINGLE SOURCE OF TRUTH** + เพิ่มแบนเนอร์อ้างอิงที่หัวเอกสารทั้ง 4 (`CLAUDE/AGENTS/README/AI_DEVELOPMENT_GUARDRAILS`). CLAUDE.md แก้จุดขัดแย้งจริง: mobile-first→**Chrome PWA online-only เป็นหลัก**, offline pool/`drift`/sync queue→`~~ยกเลิก~~ [SUPERSEDED §1.2]`, Bluetooth direct→**legacy fallback ระดับโค้ดหลัง flag** (default off), `ZebraAdapter`/offline-first เฟส2→ยกเลิก (แทนด้วย Gateway+XP-420B). README ปรับ tagline+โครงสร้างเป็น PWA online-only. AGENTS/GUARDRAILS reconciled อยู่แล้ว (task #59) เพิ่มแค่ SSOT pointer. ห้ามลบประวัติ — ใช้ strikethrough + SUPERSEDED ตาม §1.3 | `CLAUDE.md`, `README.md`, `AGENTS.md`, `AI_DEVELOPMENT_GUARDRAILS.md` |
| 2026-07-23 | **UI Design — ใช้ Pulse Healthcare Design System (`pulse-design-system.html`) เต็มรูปแบบ:** ต่อยอด theme เดิม (palette ตรงกับ Pulse อยู่แล้ว) ให้เป็นภาษาดีไซน์เดียวทั้งแอป — เพิ่ม token ที่ขาด (blue scale เต็ม 50–700, ink700, borderStrong, sky, star) + คลาส `AppSpacing`/`AppRadius`/`AppShadows` (sh-sm/md/lg/**blue** CTA) + `AppTheme.heroGradient`. รื้อ `ThemeData`: **ปุ่ม primary = pill + เงาเรืองฟ้า** (sh-blue), card มุมโค้ง lg(20), input มุมโค้ง md + focus ring ฟ้า, chip/dialog/bottomSheet(xl)/snackBar(floating ink900) theme, NavigationBar ปลอดโปร่ง indicator ฟ้าอ่อน, textTheme แมปสเกล Pulse (display/headline/title/body/label). **Font:** ลงทะเบียน **Sarabun** เป็น family UI จริงใน pubspec (แก้บั๊ก `fontFamily:'Anuphan'` ที่ไม่เคยถูก bundle → ไทยเรนเดอร์ด้วย fallback) — คง Sarabun แทน Plus Jakarta/Inter ของ Pulse เพราะรองรับ glyph ไทย+ออฟไลน์. ตรวจจริง: analyze สะอาด · test **48/48** · build web --release ✓ · preview หน้า login (desktop+mobile 375px) เรนเดอร์ตรง Pulse ไม่มี overflow ฟอนต์ไทยคม | `core/theme/app_theme.dart`, `pubspec.yaml` (fonts: Sarabun) |
| 2026-07-23 | **PRE_PILOT Gate 1 — แก้ตามผลตรวจ read-only (commit `3f04e06`):** ปิด Thai hard-coded ที่เหลือทั้งหมดให้เข้า ARB: (1) nav 5 เมนู (`navDashboard/Scan/Packages/PrintJobs/Settings`) ใน `app_router`; (2) `(ภายนอก)`→`deptExternalSuffix` ใน `models.displayName(l10n)`; (3) login error→`errLoginInvalid`; (4) generic API error→`apiErrorMessage(l10n, e)` (`errTimeout/errConnection/errGeneric{code}/errUnknown`, ข้อความจาก backend ส่งต่อตามเดิม) แก้ call site ~24 จุด/10 ไฟล์; (5) **server URL validation → localize ผ่าน ARB** (`urlErrFormat/urlErrAllowlist{hosts}/urlErrHttpsOnly/urlErrExternalHttps`) ตามคำสั่ง (เลิก allowlist เดิม); (6) FCM channel name/desc→`fcmChannelName/fcmChannelDesc` (lookup device locale ตอน init). **Test เพิ่ม (#7):** i18n error ภาษาอังกฤษ (`apiErrorMessage` en=connection/timeout/unknown, `errLoginInvalid` th≠en, server message ส่งต่อ) + release build ปิด legacy printer ด้วย `computeLegacyDirectPrintEnabled` (ตรรกะบริสุทธิ์). Allowlist ที่เหลือ (มีคำอธิบาย): `_PrinterSheet` legacy (หลัง flag), `label_renderer` (label content ตาม SOP). analyze สะอาด · test **48/48**. หมายเหตุ build web release มี warning WebAssembly (`flutter_secure_storage_web`) + Cupertino icons tree-shake = **non-blocking** บันทึกเป็น technical debt (`OPERATIONAL_READINESS.md §9`) | mobile: `app_router/models/auth_controller/api_client/settings_page/fcm_service/feature_flags.dart` + call sites (scan/create_package/package_detail/dashboard/packages/print_jobs/report), `l10n/*.arb`, `test/{i18n,logout,printer_feature_flag}` ; `OPERATIONAL_READINESS.md` |
| 2026-07-23 | **PRE_PILOT Gate 1 — i18n ปิดครบ + ตัด printer UX legacy ออกจาก Pilot:** i18n หน้าที่เหลือครบ (login, dashboard, create-package/template, package-detail, domain_widgets) — `packageStatusStyle`/`ScanMode`/`ReportPeriod`/`PrintJobStatusStyle`/lifecycle เป็นแบบรับ `AppLocalizations`. **Printer UX:** เพิ่ม `feature_flags.dart` (`legacyDirectPrintEnabled` default **false ใน release**), settings แสดง **Print Gateway → XP-420B เป็นเส้นทางหลัก** ชัดเจน + ซ่อน chooser Bluetooth/System (legacy) หลัง flag (ไม่ลบโค้ด). i18n-allowlist (มีคำอธิบายในโค้ด): `serverUrlValidationError` (admin config, pure fn), `_PrinterSheet` legacy (หลัง flag), `label_renderer` (label content ตาม SOP). **Test เพิ่ม:** widget locale th/en, i18n domain-critical (ห้ามใช้/หมดอายุ/ยังไม่ฆ่าเชื้อ/Recall/ACK_UNKNOWN) ทั้งสองภาษา, feature-flag (Pilot ไม่โชว์ legacy printer). flutter analyze สะอาด · test **45/45** | mobile: `login/dashboard/create_package_sheet/package_detail_page/domain_widgets/settings_page/feature_flags.dart`, `l10n/*.arb`, `test/{widget,i18n,printer_feature_flag,l10n_helper}` |
| 2026-07-23 | **i18n sweep ครบทุกหน้า (จบ #1):** ย้ายข้อความไทย hard-coded → gen-l10n (ARB th template + en) ครบ **reports** (สรุป/ช่วงเวลา/PDF/cleanup) และ **print jobs** (status labels + timeline + list/detail/submit sheet) — ต่อจาก settings/packages/scan/batches/dept ที่ทำก่อนหน้า. เปลี่ยน `ReportPeriod.label`/`PrintJobStatusStyle.of`/`kPrintProgressSteps` เป็นแบบรับ `AppLocalizations`. ทุกหน้าหลัก user-facing เป็น i18n แล้ว (en เป็น fallback, ค่าเริ่มต้นไทย). flutter analyze สะอาด · test **33/33** | `report_page.dart`, `print_job_status_style.dart`, `print_jobs_page.dart`, `print_job_detail_page.dart`, `submit_print_job_sheet.dart`, `l10n/*.arb` |
| 2026-07-23 | **CI integration + E2E stack (2 งาน):** **(3)** เพิ่ม job `integration` ใน `ci.yml` — Postgres 16 service + `test:integration` (พิสูจน์ migration + flow batch/scan/idempotency บน DB จริง). **(2)** E2E stack ครบ: `scripts/e2e-stack.sh up/down` (compose Postgres + migrate/seed + API node + build/serve PWA web ที่ชี้ API local ผ่าน `--dart-define=CSSD_API_URL`), job `e2e` ใน CI (ยก stack + รัน Playwright **smoke**), flow spec (login→create→print via Flutter semantics helper) **gate ด้วย `E2E_FLOW`** เพราะยังต้อง validate selector กับ build จริง (ไม่มี browser/stack ในเครื่องนี้). ทำ `kDefaultServerUrl` override ได้ด้วย dart-define (E2E ชี้ localhost โดยไม่ติด validation). flutter analyze สะอาด · integration ยังผ่าน **27/27** ในเครื่อง | `.github/workflows/ci.yml`, `scripts/e2e-stack.sh`, `e2e/tests/{helpers,flow}.ts`+`smoke`, `e2e/README.md`, `apps/mobile/lib/core/api/api_client.dart` |
| 2026-07-23 | **Fix P1 — logout-all ลูป 401/logout:** เดิม logout-all → revoke token → `logout()` ยิง unregister FCM ด้วย token ที่ถูกเพิกถอน → 401 → interceptor เรียก logout() ซ้ำ = ลูป. แก้: แยก **`clearLocalSession()` (ไม่ยิง API, idempotent)**; `logoutAllDevices` ยกเลิก FCM **ก่อน** revoke (token ยังใช้ได้) → logout-all → clearLocalSession; dio 401 interceptor เรียก `clearLocalSession()` แทน `logout()`. + Flutter test 3 เคส (logout-all ยิงครั้งเดียว/เคลียร์, revoked-token 401 ไม่ลูป/ไม่ยิง FCM ซ้ำ, clearLocalSession idempotent). flutter analyze สะอาด · test **33/33** | `auth_controller.dart`, `api_client.dart`, `test/logout_test.dart` |
| 2026-07-23 | **งานนอก Sections 1–2 (code tracks) — ทำครบ 4 ตัวที่ลงมือได้:** **(A) Session revocation** — `User.tokenVersion` (migration backfill-safe) ฝัง `ver` ใน JWT, `jwt.strategy` ปฏิเสธ token ที่ ver ไม่ตรง (เพิกถอนแล้ว), `POST /auth/logout-all` (self) + ADMIN `POST /auth/users/:id/revoke-sessions` (audit `SESSION_REVOKE`) + ปุ่ม "ออกจากระบบทุกอุปกรณ์" ในแอป; **(B) CI security** — `.github/workflows/security-scan.yml` (gitleaks + npm audit high+ + flutter pub outdated) + `ci.yml` (build/test) + `scripts/security-scan.sh`; **(C) Browser E2E** — `e2e/` Playwright scaffold (smoke: PWA boot/manifest/service-worker) + README (ยังไม่ผูก CI จนกว่ามี stack); **(D) i18n** — ตั้ง gen-l10n (ARB th/en, wiring `main.dart`) + แปลงหน้า **settings** เป็นหน้าอ้างอิง (หน้าที่เหลือทยอยย้าย). api unit **110/110**, gateway **33/33**, integration **27/27**, flutter analyze สะอาด + test 30/30 | `auth.{service,strategy,controller,module}.ts`+migration, `session-revocation.spec.ts`, `.github/workflows/*`, `scripts/security-scan.sh`, `e2e/**`, mobile `main.dart`/`l10n/**`/`l10n.yaml`/`settings_page.dart`/`auth_controller.dart` |
| 2026-07-23 | **Gateway host decision + migration caveat (pre-deploy):** ตัดสิน host Pilot = **Raspberry Pi/Linux + CUPS `lp -o raw`**; **ล็อก Windows `lpr` เป็น unsupported** — gateway โยน error ตอนสตาร์ทบน win32 ต้อง opt-in `PRINTER_ALLOW_UNVERIFIED_WINDOWS_SPOOL=true` (ขึ้น warning) ยังไม่ลบ (fallback) + test win32 gate. บันทึก **caveat migration backfill**: กู้ได้เฉพาะห่อที่ยังมี `batchId` — รอบ FAILED เก่าที่ล้าง batchId แล้วต้องกู้จาก AuditLog/backup ก่อน migrate (ขั้นตอนใน OPERATIONAL_READINESS §5.1). gateway test **33/33**, tsc สะอาด | `usb-spool-transport.ts`, `config.ts`, `index.ts`, `__tests__/usb-spool-transport.spec.ts`, migration `.sql` (comment), `HARDWARE_VERIFICATION.md`, gateway `README`/`.env.example`, `OPERATIONAL_READINESS.md`, `CLAUDE.md` |
| 2026-07-23 | **ปิดงานค้าง Sections 1–2 (6 ข้อ + resolvedAt bug):** **P0** — (1) recall ค้นผ่าน `PackageBatchAttempt` (ประวัติถาวร) ไม่ใช่ `batchId` ปัจจุบัน → ห่อที่ batchId ถูกปลด/เปลี่ยนยังถูก recall (กัน false-negative) โดยไม่ over-recall ผลผลิตดีของรอบอื่น; (2) `getPackages` + `reports.recalls` ดึงห่อจากประวัติ → ห่อที่ถูกปลด (FAILED/reprocess) ยังแสดงในรอบเดิม พร้อม `attemptResult`/`stillBound`; (3) migration เพิ่ม backfill `PackageBatchAttempt` (idempotent, result อิงสถานะรอบ, resolvedAt null เมื่อ PENDING). **P1** — (5) backend validate เลขห่อ (DTO `@Matches`/`@MaxLength` + lookup guard, กัน API-direct bypass); (6) tagging attach/detach `PUT /packages/:id/tags` + UI ในหน้ารายละเอียด (ติด/ถอด tag); (4) Reprocess เป็น scan mode ใน PWA (RETURNED→PACKED). **bug**: `resolvedAt` คง null จนกว่าจะตัดสิน (ไม่ตั้งตอน PENDING). unit **104/104** · integration **27/27** (+recall-history/getPackages/recalls/resolvedAt/lookup-guard) · flutter analyze สะอาด · test 30/30 | `batches.service.ts`, `reports.service.ts`, `scan.{service,controller}.ts`, `package-id.util.ts`(ใหม่), `packages.{controller}.ts`+`dto/set-tags.dto.ts`, migration `.sql`, mobile `scan_page.dart`/`package_detail_page.dart`/`repositories.dart`/`models.dart`, `package-id.util.spec.ts`+integration tests |
| 2026-07-23 | **S2 mobile (ปิดครบ 2 sections):** **2.3** pin/allowlist API URL ใน production — release ต่อได้เฉพาะ host ใน allowlist (`productionAllowedHosts`/`--dart-define=CSSD_ALLOWED_HOSTS`, default = host ของ `kDefaultServerUrl`) แม้เป็น https ก็ต้องอยู่ใน allowlist (กัน harvest JWT/ข้อมูลจากโดเมนปลอม); **2.4** validate เลขห่อจาก **QR** ก่อน lookup ด้วย `isValidPackageId` (charset เดียวกับพิมพ์เอง — กัน QR อื่น/ค่าขยะยิง lookup, เตือนแบบ throttle); **2.7** tag filter UI (`tagsProvider` + `_TagFilterBar` chips สีตาม tag, `packagesProvider` เปลี่ยน key เป็น `PackageQuery{status,tagId}`). `flutter analyze` สะอาด · `flutter test` ผ่านทั้งหมด (+`server_url_validation`/`package_id_validation`/`tag_filter`) | `settings_page.dart`, `scan_page.dart`, `packages_page.dart`, `repositories.dart`, `models.dart`, `test/{server_url_validation,package_id_validation,tag_filter}_test.dart` |
| 2026-07-23 | **Batch workflow + workflow/security (2 sections):** **S1** — batch **early-release** (ยืนยันแล้ว: CI ผ่าน→STERILE+PENDING_BI ถ้ายังไม่มี BI), **recordBiResult** ผล BI ทีหลัง (ผ่าน→PASSED / ไม่ผ่าน→FAILED+recall), **PackageBatchAttempt** ตารางประวัติผูกห่อ–รอบถาวร, **Reprocess** RETURNED→PACKED (ปลด batchId เข้ารอบใหม่ได้), **cleanup เลิกลบ Movement** (traceability). **S2 (backend)** — PACKED_OUT external-only (2.1), print-history ใช้ `PRINT_SUCCESS` (2.2), FCM unregister owner-scope (2.5), audit-in-tx discard/dept/template + ตัด markSterile ตาย (2.6), tag filter API (2.7). unit **100/100** · integration **22/22** (+batch/recall/reprocess/cleanup/PACKED_OUT) · build OK. **เหลือ S2 mobile: 2.3 API pin, 2.4 QR validate, 2.7 tag UI** | `schema.prisma`(+migration PENDING_BI/BatchAttempt), `batches.service/controller`, `scan.service/controller`, `packages.service/controller`, `reports.service`, `departments/master-data/notifications`, `test/integration/batches.int-spec.ts` (ใหม่) |
| 2026-07-23 | **Residual refs cleanup:** mark BT direct-print เป็น **legacy/deprecated** ชัดเจน (adapter, settings sheet, AndroidManifest, pubspec) — คงไว้เป็น fallback (ไม่ถอด deps/permission เพราะยัง demote ไม่ใช่ no-consumer); แก้ตัวอย่าง/คอมเมนต์ A318BT→XP-420B + serial=usb_spool-fallback (dto, serial-transport, root README) — comment/doc ล้วน ไม่แตะพฤติกรรม; tsc api/gateway + flutter analyze สะอาด | `flash_label_a318_adapter.dart`, `settings_page.dart`, `AndroidManifest.xml`, `pubspec.yaml`, `register-gateway.dto.ts`, `serial-transport.ts`, `README.md` |
| 2026-07-23 | **ปิด code defect #2/#3/#4 (จาก review):** #2 Idempotency-Key คงเดิมเมื่อ user กดลองใหม่ (repo รับ `idempotencyKey`, submit sheet เก็บ key ต่อห่อ → backend replay ไม่สร้าง print job ซ้ำ) + test; #3 PWA https เข้ม (release=https-only แม้ LAN, dev=http localhost/LAN) แยกเป็น `serverUrlValidationError` + test 8 เคส; #4 ถอด `POST /packages/reserve-pool` + DTO + service.reservePool + runningNum.reservePool (online-only, ไม่มี consumer — **คงตาราง NumberPoolReservation ไว้ ไม่ destructive**). #1 Windows spool ยังรอยืนยัน host OS. mobile **14/14** · api **100/100** · integration **12/12** · builds OK | `repositories.dart`, `submit_print_job_sheet.dart`, `settings_page.dart`, `test/{server_url_validation,print_job_idempotency}_test.dart` (ใหม่), `packages.controller/service.ts`, `running-number.service.ts`, ลบ `reserve-pool.dto.ts` |
| 2026-07-23 | **Online-only + XP-420B (ตาม ONLINE_ONLY_XPRINTER_REMAINING_WORK.md):** เพิ่ม backend `USB_SPOOL` transport mode + migration; สร้าง `UsbSpoolTransport` (cross-platform raw→OS printer queue: posix CUPS `lp -o raw` / win32 `lpr`, ไม่ใช้ shell + validate queue name, timeout, NOT_SENT/MAYBE_SENT/SENT) + config vars (queue/dpi/label size) + wiring; ตัด drift/offline deps (online-only); อัปเดตเอกสาร (AGENTS/GUARDRAILS/HW/README/.env.example → XP-420B/USB queue/online-only). gateway **32/32** · api **100/100** · flutter analyze สะอาด. ⚠️ Windows lpr path + hardware ยังไม่ verify | `schema.prisma`+migration, `apps/print-gateway/src/transports/usb-spool-transport.ts` (ใหม่), `config.ts`, `index.ts`, `__tests__/usb-spool-transport.spec.ts` (ใหม่), `apps/mobile/pubspec.yaml`, docs |
| 2026-07-23 | **Phase 5 — Security & Operational Readiness:** เพิ่ม gateway key rotation (`POST /gateways/:id/rotate-key`, ADMIN, key เดิมตายทันที, device id ไม่เปลี่ยน, AuditLog `GATEWAY_KEY_ROTATE`), RBAC regression test (`@Roles` metadata ทุก sensitive endpoint), ยืนยัน RBAC/IDOR ครบทุก print-job endpoint; สรุป ops (cert/backup drill/monitoring/SOP/rate-limit decision) เป็น [OPERATIONAL_READINESS.md](OPERATIONAL_READINESS.md) — unit **100/100**, integration **12/12**, tsc สะอาด | `print-jobs.service.ts` (rotateGatewayKey), `print-jobs.controller.ts`, `__tests__/print-jobs.rbac.spec.ts` (ใหม่), `OPERATIONAL_READINESS.md` (ใหม่) |
| 2026-07-23 | **Phase 3 — QR scanner/PWA completeness (online-only):** กล้องเว็บผ่าน getUserMedia (kIsWeb branch, ต้อง https), ขอสิทธิ์ + คำแนะนำเปิดใหม่แบบ web-aware (ไอคอนแม่กุญแจ ไม่ใช่ตั้งค่าเครื่อง), กล้องหลังเป็น default + ปุ่มสลับกล้อง; manual entry/ผลรายชิ้น/บล็อกหมดอายุ/กันสแกนซ้ำ มีอยู่แล้วจาก M1; **ตัด offline-first ตามที่ยืนยัน (online-only)**; ทดสอบ Android Chrome/iOS-WebKit เป็น manual checklist ([PWA_BROWSER_TESTING.md](PWA_BROWSER_TESTING.md)); เปลี่ยนเป้าเครื่องพิมพ์เป็น **Xprinter** (อัปเดต hardware doc + flag ยืนยันรุ่น/dialect) — `flutter analyze` สะอาด | `scan_page.dart`, `label-renderer.ts`, `HARDWARE_VERIFICATION.md`, `PWA_BROWSER_TESTING.md` (ใหม่), `CLAUDE.md` |
| 2026-07-23 | **Phase 2 — PWA Print Job Integration:** ผูกปุ่มพิมพ์เข้ากับ Print Job Queue (สร้าง job ผ่าน backend + `Idempotency-Key`, ปิดเส้นทางพิมพ์ตรง), หน้าติดตามสถานะ poll `QUEUED→CLAIMED→PRINTING→SENT→PRINTED` + `FAILED/DEAD_LETTER/SIMULATED/ACK_UNKNOWN`, เลือก gateway, ยกเลิกเฉพาะ QUEUED, reprint reason, หน้า supervisor resolve ACK_UNKNOWN (role-gated), tab "งานพิมพ์" — `flutter analyze` สะอาด + widget tests 4/4 ผ่าน (ยังไม่ E2E จริง รอ server+FIX-08) | `apps/mobile/lib/core/models/models.dart` (PrintJob/PrinterGateway), `apps/mobile/lib/core/api/repositories.dart` (PrintJobRepository+providers), `apps/mobile/lib/features/print_jobs/**` (ใหม่), `app_router.dart`, `create_package_sheet.dart`/`packages_page.dart`/`package_detail_page.dart` (rewire) |
| 2026-07-22 | **P1 closeout:** idempotency ตรวจ endpoint+method, gateway README HTTPS (FIX-06), integration tests reproduced 12/12, [TEST_EVIDENCE.md](TEST_EVIDENCE.md) | `idempotency.service.ts`, `apps/print-gateway/README.md`, `TEST_EVIDENCE.md` |
| 2026-07-22 | **ตรวจ+แก้ตาม M1_M2_REAUDIT_FIX_DIRECTIVE.md (FIX-01→08):** migration backfill-safe, idempotency crash-recovery แบบ single-transaction (thread tx ทุก mutation), ACK_UNKNOWN resolve ครั้งเดียว (RESOLVED_* + requeuedFromJobId), transport NOT_SENT/MAYBE_SENT/SENT typed result, backend ตัดสิน simulation (PrinterDevice.canConfirmRealPrint), production HTTPS เข้ม, **PostgreSQL integration tests จริง 11 เคส**, hardware verification เป็นเอกสารให้ทีมรัน — ยังไม่ deploy | `apps/api/prisma/schema.prisma` (+2 migrations), `apps/api/src/common/idempotency/*`, `apps/api/src/modules/{scan,packages,batches,print-jobs}/*`, `apps/api/test/integration/*` (ใหม่), `apps/print-gateway/src/{config,poll-loop,api-client,transports}/*`, `HARDWARE_VERIFICATION.md` (ใหม่) |
| 2026-07-22 | **ตรวจ+แก้ตาม M1_M2_REQUIRED_FIXES.md ทุกข้อ:** เพิ่มสถานะ SENT/SIMULATED/ACK_UNKNOWN แก้ duplicate-print, CAS จริงใน ack/fail/markSent/markPrinting, Thai bitmap label ที่ gateway (canvas+qrcode+Sarabun, ทดสอบ decode QR จริง), Serial transport จริง, แก้ IDOR/isReprint/cancel/idempotency required-key/lease-recovery semantics, gateway HTTPS enforcement — ยังไม่ deploy | `apps/api/prisma/schema.prisma`, `apps/api/src/modules/print-jobs/*`, `apps/api/src/common/idempotency/idempotency.service.ts`, `apps/print-gateway/src/*` |
| 2026-07-18 | **M2:** สร้าง Print Job Queue + Print Gateway ใหม่ทั้งระบบ (atomic claim, gateway auth แยกจาก JWT, ACK-only printedAt, lease timeout, retry/DEAD_LETTER) — ลบ endpoint พิมพ์ที่ client ยืนยันเองซึ่งขัด guardrails, ยังไม่ deploy | `apps/api/prisma/schema.prisma`, `apps/api/src/modules/print-jobs/*` (ใหม่), `apps/print-gateway/*` (แอปใหม่ทั้งตัว), `apps/mobile/lib/features/packages/presentation/widgets/create_package_sheet.dart` |
| 2026-07-18 | **M1:** idempotency ให้ atomic จริง (CAS แทน find→execute→store), security headers ครบ (CSP/HSTS/Permissions-Policy), manual entry fallback, หน้าสรุปผลสแกน+retry-failed+ยืนยันก่อนล้างรายการ | `apps/api/src/common/idempotency/*`, `apps/api/src/main.ts`, `apps/api/src/modules/scan/*`, `apps/mobile/lib/features/scan/presentation/pages/scan_page.dart`, `apps/mobile/lib/core/api/*` |
| 2026-07-16 | **Fix:** กล้อง genericError (race ตอนขอ permission) + เพิ่ม SystemPrintAdapter (พิมพ์ผ่าน OS/เบราว์เซอร์ → แอปเครื่องพิมพ์) เป็นค่าเริ่มต้น + ลบ Mock, bump v1.2.1+10 | `apps/mobile/lib/features/scan/presentation/pages/scan_page.dart`, `apps/mobile/lib/core/printer/system_print_adapter.dart` (ใหม่), `printer_provider.dart`, `label_renderer.dart`, `settings_page.dart` |
| 2026-07-16 | **Feature:** ส่งออก/รับคืนชุด PACKED ที่ยังไม่ฆ่าเชื้อไปสถานที่ภายนอก + สถานะ PACKED_OUT + การ์ดแสดงตำแหน่ง + POST /departments + ปุ่มเพิ่มสถานที่, bump v1.2.0+9 | `packages/shared/src/index.ts`, `apps/api/prisma/schema.prisma`, `apps/api/src/modules/scan/scan.service.ts`, `apps/api/src/modules/departments/*`, `apps/mobile/lib/features/scan/presentation/pages/scan_page.dart`, `apps/mobile/lib/features/packages/presentation/pages/*` |
| 2026-07-16 | **Fix:** เลือกเครื่องพิมพ์ Bluetooth ไว้แล้วพิมพ์ไปตกที่ Mock เสมอ — printerAdapterProvider ไม่เคย persist เลย เปลี่ยนเป็น NotifierProvider + SharedPreferences, bump v1.1.6+8 | `apps/mobile/lib/core/printer/printer_provider.dart`, `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart` |
| 2026-07-16 | **Fix:** พิมพ์รายงาน PDF บนเว็บพัง (`MissingPluginException: printPdf`) — cache plugin registrant เก่าไม่มี PrintingPlugin, แก้ด้วย `flutter clean` + build ใหม่ + deploy | ไม่มีไฟล์ source เปลี่ยน — เป็น build-cache issue ล้วนๆ |
| 2026-07-15 | **Deploy PWA + แก้บั๊กเฉพาะเว็บ:** เจอ `Platform.*` (dart:io) throw บนเว็บที่หน้า login/ตั้งค่า → guard ด้วย `kIsWeb`, ซ่อน UI printer Bluetooth บนเว็บ, deploy เข้า Cloudflare Pages (`sterelis-cssd`) ที่ค้างมา 3 วัน ให้เป็น v1.1.5+7 | `apps/mobile/lib/core/notifications/fcm_service.dart`, `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart` |
| 2026-07-15 | **ตรวจทั้งระบบรอบ 2:** แก้ camera-permission recheck on resume, FCM token chunking (500 limit), duplicate Firebase app guard, DTO length validation, bump v1.1.5+7 | `apps/mobile/lib/features/scan/presentation/pages/scan_page.dart`, `apps/api/src/modules/notifications/fcm.service.ts`, `apps/api/src/modules/notifications/dto/register-token.dto.ts` |
| 2026-07-15 | **Fix:** หน้าสแกนกล้องขึ้น error — ขอ permission ก่อน start + จัดการ lifecycle เอง + errorBuilder/retry + CAMERA manifest + iOS usage keys, bump v1.1.4+6 | `apps/mobile/lib/features/scan/presentation/pages/scan_page.dart`, `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/ios/Runner/Info.plist` |
| 2026-07-15 | **Fix:** ตัวอักษรไทยเพี้ยน (render label เป็น bitmap แทน TSPL TEXT) + อุดช่องโหว่เชื่อมต่อค้าง/ไม่ติด (permission guard, connect timeout, stop BLE scan), bump v1.1.3+5 | `apps/mobile/lib/core/printer/label_renderer.dart` (ใหม่), `apps/mobile/lib/core/printer/flash_label_a318_adapter.dart`, `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart` |
| 2026-07-15 | **Fix:** เชื่อมต่อเครื่องพิมพ์ผ่าน Bluetooth Classic SPP (ทางเดียวกับแอพจริง) — เพิ่ม print_bluetooth_thermal, adapter 2 โหมด classic/ble, รายการ paired devices ขึ้นอัตโนมัติ, bump v1.1.2+4 | `apps/mobile/lib/core/printer/flash_label_a318_adapter.dart`, `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`, `apps/mobile/pubspec.yaml` |
| 2026-07-15 | **Fix:** สแกนหาเครื่องพิมพ์ BT แล้ว crash (ไม่มี BLUETOOTH permission) — เพิ่ม manifest permissions + runtime request, bump v1.1.1+3 | `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`, `apps/mobile/pubspec.yaml` |
| 2026-07-15 | เพิ่มระบบแจ้งเตือน FCM (ใกล้หมดอายุ + สรุปรายวัน) ทั้ง backend + mobile scaffold, ยังต้องเสียบ Firebase project จริง | `apps/api/src/modules/notifications/*`, `apps/api/prisma/schema.prisma`, `apps/mobile/lib/core/notifications/fcm_service.dart`, `apps/mobile/lib/main.dart`, `apps/mobile/lib/core/auth/auth_controller.dart` |
