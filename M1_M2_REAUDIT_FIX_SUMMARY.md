# M1/M2 Re-audit — เอกสารสรุปหลังแก้ไข

วันที่: 22 กรกฎาคม 2026
ตอบสนอง: `M1_M2_REAUDIT_FIX_DIRECTIVE.md` (อ้างอิง `AGENTS.md`, `AI_DEVELOPMENT_GUARDRAILS.md`, `M1_M2_REQUIRED_FIXES.md`)
สถานะรวม: **FIX-01 ถึง FIX-07 เสร็จ + ทดสอบผ่าน** · **FIX-08 (hardware) รอทีมรันกับเครื่องจริง** · **ยังไม่ deploy**

> **แก้รอบสอง (หลัง review):** ผู้ตรวจพบ 2 จุดที่เดิมประเมินเกินไปว่า "ผ่าน" — แก้แล้ว:
> - **FIX-02:** cleanup เดิมลบ `PENDING` ที่หมดอายุได้ (ขัดกฎ "ห้ามลบ PENDING โดยไม่ตรวจ domain result") → จำกัดให้ลบเฉพาะ `DONE` เท่านั้น + เพิ่ม test ยืนยันว่า PENDING ที่หมดอายุถูกคงไว้
> - **FIX-05:** เดิมตรวจแค่ `canConfirmRealPrint` ตัวเดียว จึงตั้ง `CONSOLE + canConfirmRealPrint=true` แล้วดัน Package เป็น PRINTED ได้ → เพิ่ม invariant validation (register + update) + **re-check ครบทั้ง 3 ค่าตอน ACK** (Console/Dev/Test → SIMULATED เสมอ)

---

## 1. สรุปผลระดับสูง

| FIX | เรื่อง | สถานะ | ทดสอบ |
|---|---|---|---|
| 01 | Migration `expiresAt` backfill-safe | ✅ เสร็จ | Postgres จริง 3 สถานการณ์ |
| 02 | Idempotency crash recovery (single transaction) | ✅ เสร็จ | unit + integration |
| 03 | ACK_UNKNOWN resolve ได้ครั้งเดียว | ✅ เสร็จ | unit + integration |
| 04 | Transport typed result NOT_SENT/MAYBE_SENT/SENT | ✅ เสร็จ | unit (gateway) |
| 05 | Backend ตัดสิน Simulation mode | ✅ เสร็จ | unit + integration |
| 06 | Production HTTPS เข้มขึ้น | ✅ เสร็จ | config test ครบเคส |
| 07 | PostgreSQL integration/concurrency tests | ✅ เสร็จ | 11 เคสกับ Postgres จริง |
| 08 | Hardware verification (A318BT) | ⚠️ **AI ทำไม่ได้** | เอกสาร + แบบฟอร์มให้ทีมรัน |

**ผลทดสอบรวม (หลังแก้รอบสอง):** API unit **94/94** · Gateway unit **25/25** · Integration (Postgres จริง) **12/12** · `tsc --noEmit` สะอาดทั้งสอง workspace · `prisma migrate status` = up to date (ไม่ drift, 9 migrations)

**การตัดสินใจที่ขอผู้ใช้ก่อน:** FIX-02 เป็น fork สถาปัตยกรรม → ผู้ใช้เลือก **แนวทาง A (single transaction)**

---

## 2. รายละเอียดต่อ FIX (ตามรูปแบบ directive ข้อ 14)

### FIX-01 — Migration `expiresAt` backfill-safe

- **ปัญหาเดิม:** migration `20260722072226` เพิ่มคอลัมน์ `expiresAt TIMESTAMP NOT NULL` โดยไม่มี default → ล้มเหลวทันทีถ้า `idempotent_requests` มีข้อมูล
- **แนวทาง:** แก้ SQL เป็น 3 ขั้น — `ADD COLUMN` (nullable) → `UPDATE` backfill (DONE = createdAt+24h, อื่น = createdAt+5min) → `ALTER COLUMN ... SET NOT NULL` → สร้าง index
- **เหตุผลความปลอดภัย:** production deploy ห้ามพังกลางคันบนตารางที่มีข้อมูล (ห้ามใช้ destructive reset)
- **ไฟล์ที่เปลี่ยน:** `apps/api/prisma/migrations/20260722072226_m1_m2_audit_fixes/migration.sql`
- **ทดสอบ:** (ก) DB ว่าง → `prisma migrate deploy` ทั้งชุดผ่าน (ข) DB มี PENDING+DONE (isolated SQL) → 5→5 แถว, 0 แถวขาด expiresAt (ค) DB มีข้อมูลผ่าน Prisma จริง → 4→4 แถว, `migrate status` = up to date ไม่ drift
- **Migration impact:** แก้ไฟล์ migration ที่ยังไม่ปล่อย (unreleased) — end schema เท่าเดิม
- **Rollback/forward-fix:** ถ้าต้องถอย ลบ index + column ได้ตรงๆ (คอลัมน์ nullable ก่อน set not null จึงถอยง่าย)

### FIX-02 — Idempotency crash recovery (แนวทาง A: single transaction)

- **ปัญหาเดิม:** โค้ดเดิม reclaim แถว `PENDING` ที่หมด TTL แล้ว **rerun mutation** — ถ้า process ตายหลัง mutation สำเร็จแต่ก่อนบันทึก DONE จะเกิด package/print job/batch/movement ซ้ำ, เลขรันกระโดด (กฎห้ามละเมิดสั่งห้ามชัดเจน)
- **แนวทาง (A):** reservation (`idempotent_requests`) + domain mutation + AuditLog + response อยู่ใน `$transaction` เดียวกัน — `idem.run` เปิด transaction แล้วส่ง `tx` ให้ service ทุกตัวใช้ร่วม; crash = rollback ทั้งก้อน จึงเป็นไปไม่ได้ที่จะมี PENDING commit เดี่ยวคู่กับ mutation ครึ่งทาง — **ตัด logic rerun ทิ้งทั้งหมด** ถ้าเจอ PENDING ที่ commit แล้ว → ตอบ 409 ไม่ rerun เด็ดขาด
- **⭐ แก้รอบสอง (review):** cron `cleanupExpired` เดิมลบทุกแถวที่ `expiresAt` หมด (รวม `PENDING`) → **จำกัดให้ลบเฉพาะ `status=DONE`** เท่านั้น; แถว `PENDING` ที่หมดอายุ (แถวเก่าจากก่อน FIX-02 / ความผิดปกติ) **ห้ามลบโดยดูแค่เวลา** ต้องคงไว้ให้คน reconcile — ตรงกฎ "ห้ามลบ PENDING โดยไม่ตรวจ domain result"
- **เหตุผลความปลอดภัย:** ไม่มีทางสร้างข้อมูลซ้ำจาก retry, ไม่ตัดสิน/ไม่ลบ mutation จากเวลาอย่างเดียว; unique constraint บน `key` = compare-and-swap จริง (request ซ้ำถูก Postgres serialize)
- **ไฟล์ที่เปลี่ยน:** `common/idempotency/idempotency.service.ts`, `modules/scan/scan.service.ts` (+controller), `modules/packages/packages.service.ts` + `running-number.service.ts` (+controller), `modules/batches/batches.service.ts` (+controller, recall เข้า tx เดียวกัน), `modules/print-jobs/print-jobs.service.ts` (createJob) + controller
- **ทดสอบ:** unit 11 เคส (CAS, replay, 409, no-rerun-on-PENDING, crash rollback, **cleanup ลบ DONE เท่านั้น—คง PENDING**) + integration 4 เคส (ดู FIX-07)
- **Migration impact:** ไม่มี (ใช้ schema เดิม)

### FIX-03 — ACK_UNKNOWN resolve ได้ครั้งเดียว

- **ปัญหาเดิม:** CAS เช็คแค่ `status = ACK_UNKNOWN`; การ REQUEUE คงสถานะเดิมไว้ → เรียกซ้ำสร้างงานพิมพ์ใหม่ได้หลายงาน
- **แนวทาง:** เพิ่มสถานะ terminal `RESOLVED_PRINTED` / `RESOLVED_REQUEUED`; CAS เพิ่มเงื่อนไข `resolvedAt IS NULL`; งานใหม่ลิงก์กลับผ่าน `requeuedFromJobId` (`@unique` กันสร้างซ้ำแม้แข่งกัน); resolve + สร้างงานใหม่อยู่ใน transaction เดียว; บันทึก resolver/note/decision/เวลา + AuditLog 1 ชุดต่อ resolution
- **เหตุผลความปลอดภัย:** ป้องกัน reprintCount เพิ่มซ้ำ / งานพิมพ์ซ้ำจากการกดตัดสินใจซ้ำหรือพร้อมกัน
- **ไฟล์ที่เปลี่ยน:** `prisma/schema.prisma` (enum + `requeuedFromJobId` self relation), `print-jobs.service.ts` (`resolveAckUnknown`)
- **ทดสอบ:** unit 6 เคส (CONFIRM/REQUEUE, resolve ซ้ำ→reject, concurrent→1 สำเร็จ, no note) + integration (concurrent resolve, REQUEUE ซ้ำ)
- **Migration impact:** `20260722140000_fix03_ackunknown_resolution` (additive — enum values + nullable column + unique + self-FK)

### FIX-04 — Transport typed result NOT_SENT / MAYBE_SENT / SENT

- **ปัญหาเดิม:** `write()` callback/drain error ถูกตีความเป็น "ส่งไม่สำเร็จ" แล้ว retry อัตโนมัติ ทั้งที่อาจมี byte ออกไปเครื่องพิมพ์แล้วบางส่วน → พิมพ์ซ้ำ
- **แนวทาง:** `TransportSendError(outcome)` — SerialTransport จัดประเภท (เปิด port ไม่ได้=NOT_SENT, write/drain error=MAYBE_SENT); poll-loop map: NOT_SENT→`fail()` (retry ปลอดภัย), MAYBE_SENT→`reportMaybeSent()`→ACK_UNKNOWN (ห้าม retry), **error ที่ไม่ระบุชนิด→ถือเป็น MAYBE_SENT เสมอ**; เพิ่ม endpoint `POST /print-gateway/jobs/:id/maybe-sent` + service `reportIndeterminate` (CAS CLAIMED/PRINTING→ACK_UNKNOWN)
- **เหตุผลความปลอดภัย:** "ห้ามถือว่า write() error แปลว่าไม่มี byte ใดถูกส่ง" — default ปลอดภัยสุดคือให้คนตรวจ
- **ไฟล์ที่เปลี่ยน:** `apps/print-gateway/src/transports/{transport,serial-transport,console-transport}.ts`, `poll-loop.ts`, `api-client.ts`; `apps/api/.../print-gateway.controller.ts`, `print-jobs.service.ts`
- **ทดสอบ:** gateway unit (NOT_SENT→fail, MAYBE_SENT→reportMaybeSent, unknown→MAYBE_SENT, SENT-แล้วห้าม fail) + API unit `reportIndeterminate` 4 เคส
- **หมายเหตุ semantics:** `drain()` สำเร็จ = OS/driver รับข้อมูล ไม่ยืนยันกระดาษออกจริง → นิยาม `PRINTED` = "ส่งข้อมูลสำเร็จตามหลักฐานที่อุปกรณ์รองรับ" (ระบุใน `HARDWARE_VERIFICATION.md`)

### FIX-05 — Backend ตัดสิน Simulation mode

- **ปัญหาเดิม:** ACK รับ `simulated` จาก gateway request → gateway ที่ผิดพลาด/ถูกยึดส่ง `simulated=false` เพื่อดันให้ Package เป็น PRINTED ได้
- **แนวทาง:** ลบ flag ออกจาก request เด็ดขาด; เพิ่ม `environment` / `transportMode` / `canConfirmRealPrint` ใน `PrinterDevice` (backend เป็นเจ้าของ); เปลี่ยน capability ได้เฉพาะ ADMIN (`POST /print-jobs/gateways/:id/capability`) + AuditLog `GATEWAY_CAPABILITY_CHANGE`; gateway ที่ถูก revoke → auth ไม่ผ่าน (guard เดิม) → ACK ไม่ได้
- **⭐ แก้รอบสอง (review):** เดิมตัดสินจาก `canConfirmRealPrint` ตัวเดียว จึงตั้งชุดขัดแย้ง `environment=DEVELOPMENT, transportMode=CONSOLE, canConfirmRealPrint=true` แล้วดัน Package เป็น PRINTED ได้ → เพิ่ม 2 ชั้น:
  1. **Invariant validation** ตอน register/update — `canConfirmRealPrint=true` อนุญาตเฉพาะเมื่อ `environment=PRODUCTION` **และ** `transportMode != CONSOLE` เท่านั้น (ไม่งั้น 400)
  2. **Re-check ครบทั้ง 3 ค่าตอน ACK** (`canReallyConfirm` = canConfirmRealPrint && PRODUCTION && ไม่ใช่ CONSOLE) — ต่อให้มีแถวค่าขัดแย้งหลุดเข้ามาในฐานข้อมูล (bypass service) ตอน ACK ก็ยังเป็น SIMULATED เสมอ
- **เหตุผลความปลอดภัย:** Console/Test/Development Gateway → SIMULATED เท่านั้น (ตรงตัว directive) ทั้งชั้น input validation และชั้นตัดสินใจจริง
- **ไฟล์ที่เปลี่ยน:** `prisma/schema.prisma` (2 enum + 3 fields), `print-jobs.service.ts` (`canReallyConfirm`/`assertCapabilityConsistent`/`ack`/`registerGateway`/`updateGatewayCapability`/`listGateways`), controllers, DTOs
- **ทดสอบ:** unit — PRINTED เฉพาะ PRODUCTION+SERIAL+canConfirm, SIMULATED เมื่อ canConfirm=false / non-PRODUCTION / CONSOLE-แม้ canConfirm=true, register/update reject ชุดขัดแย้ง; integration — CONSOLE gateway (persist canConfirm=true ตรงๆ) → ACK ได้แค่ SIMULATED ไม่แตะ Package (พิสูจน์ re-check บน Postgres จริง)
- **Migration impact:** `20260722150000_fix05_gateway_capability` (additive — enums + 3 columns `NOT NULL DEFAULT` = backfill ปลอดภัยบนตารางที่มีข้อมูล)

### FIX-06 — Production HTTPS

- **ปัญหาเดิม:** ยอม http ใน private LAN เสมอ → `X-Gateway-Key` เดินทาง plaintext ใน LAN
- **แนวทาง:** production = https เท่านั้น (แม้ localhost/private IP ก็ไม่ยอม http); development/test = http เฉพาะ localhost/127.0.0.1/::1
- **ไฟล์ที่เปลี่ยน:** `apps/print-gateway/src/config.ts`
- **ทดสอบ:** config test 10 เคส (prod+http localhost/private/public → reject, prod+https → ok, dev+localhost → ok, dev+LAN/public → reject, prod+console → reject)

### FIX-07 — PostgreSQL integration/concurrency tests

- **แนวทาง:** เพิ่ม suite แยก `npm run test:integration` (jest config + global setup/teardown สร้าง/ลบ DB `cssd_inttest` จริง + `prisma migrate deploy`) — แยกจาก `npm test` เพื่อไม่บังคับให้ทุกคน/CI ต้องมี Postgres
- **เคสที่ทดสอบกับ Postgres จริง (11):**
  - Idempotency: 10-concurrent-same-key (→ 1 package, ทุก request replay response เดียวกัน, เลขรัน seq=1 ไม่กระโดด — **พิสูจน์ row-lock + replay จริงที่ fake client ทำไม่ได้**), key+payload ต่าง→409, crash-rollback, committed-PENDING no-rerun
  - Print Job: dual-claim (`FOR UPDATE SKIP LOCKED` → 1 ผู้ชนะ), concurrent-ACK (reprintCount +1 ครั้งเดียว), cancel-vs-claim (ไม่เกิดทั้งคู่), concurrent-resolve (1 สำเร็จ), REQUEUE พร้อมกัน/ซ้ำ (งานใหม่ 1 งาน), lease recovery PRINTING→ACK_UNKNOWN
- **ไฟล์:** `apps/api/test/integration/{config,global-setup,global-teardown,harness,jest.config,idempotency.int-spec,print-jobs.int-spec}`
- **ผล:** **12/12 ผ่าน** (เพิ่ม 1 เคส console-can't-PRINTED จากการแก้ FIX-05)
- **⚠️ เงื่อนไข reproducibility:** suite นี้ต้องมี **PostgreSQL จริงที่เข้าถึงได้ตาม `DATABASE_URL`** (dev นี้ใช้ PostgreSQL 16.14 Homebrew ที่ `localhost:5432`) — ถ้า Postgres ไม่พร้อม (เช่น ในสภาพแวดล้อมตรวจที่ไม่มี DB) suite จะรันไม่ได้ ต้องถือว่า "ยังยืนยันซ้ำไม่ได้ในรอบนั้น" ไม่ใช่ "ผ่าน" — วิธี reproduce: สตาร์ท Postgres ตาม `apps/api/.env` แล้ว `cd apps/api && npm run test:integration` (suite สร้าง/ลบ DB `cssd_inttest` เอง). รอบจัดทำเอกสารนี้รันแล้วได้ 12/12 บนเครื่อง dev

### FIX-08 — Hardware verification (A318BT)

- **สถานะ:** **AI ทำแทนไม่ได้** — ไม่มีเครื่องพิมพ์จริงในสภาพแวดล้อมพัฒนา
- **สิ่งที่ส่งมอบ:** `HARDWARE_VERIFICATION.md` — checklist 14 ข้อ (รวมถอดสายก่อน/ระหว่าง/หลัง write เพื่อพิสูจน์ NOT_SENT vs MAYBE_SENT บนเครื่องจริง), เกณฑ์ผ่าน (QR ≥99.5%, ไทยไม่ tofu, ไม่มี label ซ้ำจาก auto-retry), แบบฟอร์มเก็บหลักฐาน + Golden Label Sample
- **ต้องมีคนรัน** ก่อนเปิด Pilot

---

## 3. พฤติกรรมที่เปลี่ยน (ต้องรับรู้)

- **Scan เป็น all-or-nothing ต่อ request แล้ว**: เดิมแต่ละห่อ commit แยกทรานแซกชัน (บางห่อสำเร็จ บางห่อพลาดได้) → ตอนนี้ทั้ง request อยู่ทรานแซกชันเดียว
  - "ไม่ผ่าน" แบบปกติ (ไม่พบห่อ/สถานะผิด/หมดอายุ/CAS ชน) ยังรายงานรายห่อได้เหมือนเดิม (ไม่ throw ทรานแซกชันไม่ล้ม)
  - แต่ถ้าเกิด **DB error จริง** กลางคัน ทั้ง request จะ rollback แล้ว retry ด้วย idempotency-key เดิมได้สะอาด
- **ACK ไม่รับ `simulated` จาก request อีกต่อไป** (backend ตัดสินเอง) — client เดิมที่ส่ง field นี้จะถูกเพิกเฉย
- **`cancel` เหลือเฉพาะ QUEUED** (จาก audit รอบก่อน — ยังคงไว้)

---

## 4. Migrations ที่เพิ่ม/แก้ (รอบนี้)

| migration | ชนิด | ปลอดภัยบน DB ที่มีข้อมูล? |
|---|---|---|
| `20260722072226_m1_m2_audit_fixes` (แก้) | expiresAt 3-step backfill | ✅ พิสูจน์แล้ว |
| `20260722140000_fix03_ackunknown_resolution` | enum values + nullable col + unique + self-FK | ✅ additive |
| `20260722150000_fix05_gateway_capability` | 2 enums + 3 col (NOT NULL DEFAULT) | ✅ default = backfill |

ทั้งหมด apply กับ dev DB จริงสำเร็จ, `prisma migrate status` = up to date

---

## 5. Pilot Gate (directive ข้อ 15) — สถานะ

| เงื่อนไข | สถานะ |
|---|---|
| FIX-01 ถึง FIX-07 ผ่านทั้งหมด | ✅ |
| FIX-08 มีผลทดสอบเครื่องจริง | ❌ รอทีมรัน |
| Critical defect = 0 | ✅ (จากขอบเขต FIX-01–07) |
| High defect = 0 | ✅ (จากขอบเขต FIX-01–07) |
| Migration dry run ผ่าน | ✅ |
| PostgreSQL concurrency tests ผ่าน | ✅ 11/11 |
| Gateway Production ใช้ HTTPS | ✅ บังคับใน config |
| Console Gateway ทำ Package เป็น PRINTED ไม่ได้ | ✅ (canConfirmRealPrint) |
| ACK_UNKNOWN resolve ได้ครั้งเดียว | ✅ |
| MAYBE_SENT ไม่ auto-retry | ✅ |
| UAT อนุมัติ | ❌ ยัง |

**สรุป: ยังไม่พร้อมเปิด Pilot** — ติด FIX-08 (hardware) + UAT + PWA Print Job integration

---

## 6. สิ่งที่ยังเหลือ / ยังไม่ได้ทดสอบ

1. **FIX-08 hardware** — ต้องรันกับ A318BT จริงตาม `HARDWARE_VERIFICATION.md`
2. **Integration suite ยังไม่ผูกเข้า CI** — ต้องเพิ่ม Postgres service ใน pipeline ก่อน (ตอนนี้รันด้วยมือ `npm run test:integration`)
3. **PWA Print Job integration** (directive ข้อ 11) — directive ห้ามเริ่มก่อน FIX-01–07 ผ่าน (ตอนนี้ผ่านแล้ว) แต่เป็นงานใหญ่: PrintJob model/repo, printer selection, สร้าง job + Idempotency-Key, poll สถานะ, แสดง QUEUED/CLAIMED/PRINTING/SENT/PRINTED, SIMULATED เฉพาะ dev, ACK_UNKNOWN + คำแนะนำติดต่อ supervisor, dead-letter UI, cancel เฉพาะ QUEUED, reprint reason dialog, supervisor resolution UI, เลิกใช้ `recordPrint()` จาก PWA
4. **CSP/HSTS กับ Swagger UI จริง** (ยกมาจากรอบก่อน) ยังไม่ได้ทดสอบ

---

## 7. ยังไม่ deploy / ไม่ commit

ตามคำสั่งเดิม — โค้ดทั้งหมดอยู่ใน working tree เท่านั้น รออนุมัติก่อน commit/deploy
