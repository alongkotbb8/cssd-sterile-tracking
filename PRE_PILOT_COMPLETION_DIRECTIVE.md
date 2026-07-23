# PRE-PILOT COMPLETION DIRECTIVE

## คำสั่งบังคับสำหรับทีมพัฒนา — CSSD Online-only PWA + Xprinter XP-420B

**สถานะเอกสาร:** Required / Blocking  
**ขอบเขต:** งานที่ต้องปิดหลัง M1/M2 ก่อนอนุญาตให้ Push, Deploy, UAT หรือ Pilot  
**ระบบเป้าหมาย:** Chrome PWA แบบ online-only + QR Camera Scan + Print Gateway บน Raspberry Pi/Linux + CUPS + Xprinter XP-420B USB  
**หลักความปลอดภัย:** Patient safety, package-level traceability, fail closed, no duplicate print, least privilege, auditability

> เอกสารนี้เป็นคำสั่งดำเนินงาน ไม่ใช่รายการแนะนำ  
> ห้ามประกาศว่า “เสร็จ”, “พร้อม Deploy”, “พร้อม UAT” หรือ “พร้อม Pilot” จนกว่าจะส่งหลักฐานครบทุก Gate ที่กำหนด

---

## 1. กฎบังคับก่อนเริ่มงาน

1. อ่าน `AGENTS.md`, `AI_DEVELOPMENT_GUARDRAILS.md`, `ONLINE_ONLY_XPRINTER_REMAINING_WORK.md`, `OPERATIONAL_READINESS.md` และ `HARDWARE_VERIFICATION.md` ให้ครบก่อนแก้ไข
2. ห้ามเปลี่ยน Tech Stack, state machine, expiry rule, QR payload, Print Job semantics หรือ early-release CI/BI policy โดยไม่ได้รับอนุมัติเป็นลายลักษณ์อักษร
3. ระบบนี้เป็น **online-only**:
   - ห้ามสร้าง offline mutation queue
   - ห้ามสร้างเลขห่อบน client
   - ห้ามใช้ข้อมูล cache เป็นแหล่งความจริงแทน backend
4. QR ต้องมีเฉพาะ `package_id`
5. ห้ามให้ PWA ตั้งสถานะ Print Job เป็น `PRINTED` เอง
6. กรณีพิมพ์คลุมเครือหลังเริ่มส่งข้อมูลต้องเป็น `ACK_UNKNOWN` และห้าม auto-retry
7. ทุก mutation สำคัญต้องมี authorization, validation, idempotency ตามความเหมาะสม และ AuditLog ใน transaction เดียวกัน
8. ห้ามลบหรือ rewrite AuditLog, Movement หรือ PackageBatchAttempt
9. ห้ามลด test coverage หรือลบ test เพื่อให้ CI ผ่าน
10. ห้าม commit secret, production credential, database dump, FCM key, JWT secret หรือ Gateway API key
11. แก้ทีละหัวข้อและ commit แยกเป็นก้อนเล็กที่ตรวจสอบย้อนหลังได้
12. ก่อนเริ่มต้องตรวจ `git status`; ห้ามทับการเปลี่ยนแปลงที่ไม่เกี่ยวข้อง

---

# GATE 1 — ปิด i18n และตัด UX เครื่องพิมพ์ Legacy ออกจาก Pilot

## 1.1 เป้าหมาย

- UI หลักต้องใช้ `gen-l10n` ครบทั้งภาษาไทยและอังกฤษ
- ภาษาไทยเป็นค่าเริ่มต้น
- ห้ามมีข้อความภาษาไทย hard-coded ใน widget user-facing
- Pilot UI ต้องสื่อชัดว่าเส้นทางพิมพ์หลักคือ **Print Gateway → Linux/CUPS → XP-420B**
- ห้ามให้ผู้ใช้ทั่วไปเลือกเส้นทาง legacy แล้วเข้าใจผิดว่าเป็น Gateway

## 1.2 ไฟล์ที่ต้องตรวจและแก้เป็นอย่างน้อย

- `apps/mobile/lib/features/auth/presentation/pages/login_page.dart`
- `apps/mobile/lib/features/dashboard/presentation/pages/dashboard_page.dart`
- `apps/mobile/lib/features/packages/presentation/widgets/create_package_sheet.dart`
- `apps/mobile/lib/features/packages/presentation/pages/package_detail_page.dart`
- `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`
- `apps/mobile/lib/core/widgets/domain_widgets.dart`
- `apps/mobile/lib/core/printer/label_renderer.dart`
- `apps/mobile/lib/l10n/app_th.arb`
- `apps/mobile/lib/l10n/app_en.arb`

## 1.3 คำสั่งดำเนินงาน

1. ย้ายข้อความ user-facing ทั้งหมดเข้า ARB:
   - page title
   - button/tooltip
   - form label/helper/validation
   - empty/error/loading state
   - status label
   - confirmation dialog
   - SnackBar
   - accessibility/semantics label
2. ข้อความที่มีค่าตัวแปรต้องใช้ ARB placeholder ห้ามต่อ string เอง
3. ข้อความ domain-critical ต้องแปลโดยรักษาความหมาย:
   - “ห้ามใช้”
   - “หมดอายุ”
   - “ยังไม่ผ่านการฆ่าเชื้อ”
   - “Recall”
   - `ACK_UNKNOWN`
   - “อาจพิมพ์ออกแล้ว ห้ามพิมพ์ซ้ำโดยไม่ตรวจ”
4. ตรวจ layout ภาษาอังกฤษที่ยาวกว่า:
   - 320 px viewport
   - Pixel 7 viewport
   - Desktop Chrome
   - text scale 1.0 และ 1.3
5. Label ที่พิมพ์จริงอาจคงภาษาไทยตาม SOP ได้ แต่ต้องแยกจาก UI i18n และเขียนเหตุผลไว้ใน code comment/เอกสาร
6. สำหรับ Pilot build:
   - ซ่อน FlashLabel A318BT/Bluetooth direct print จากผู้ใช้ทั่วไป
   - ซ่อนหรือย้าย System/Browser Print ไปส่วน “Legacy/Admin fallback”
   - แสดง XP-420B ผ่าน Print Gateway เป็นเส้นทางหลัก
   - แสดง Gateway online/offline, queue และคำเตือนเมื่อ Gateway ไม่พร้อม
7. ถ้าจำเป็นต้องเก็บ legacy code ให้ใช้ feature flag ที่ default เป็น `false` ใน production/Pilot
8. ห้ามลบ legacy transport จนกว่า XP-420B/Linux จะผ่าน Hardware Gate

## 1.4 Acceptance Criteria

- `flutter gen-l10n` ผ่าน
- `flutter analyze` ผ่านโดยไม่มี issue
- `flutter test` ผ่านทั้งหมด
- ไม่มี user-facing Thai hard-coded ที่หลุดจาก allowlist ที่มีคำอธิบาย
- ภาษาไทยและอังกฤษเปิดทุกหน้าหลักได้โดยไม่มี overflow
- Pilot UI ไม่มีตัวเลือก A318BT/Bluetooth สำหรับ role ปกติ
- Print Gateway ถูกแสดงเป็นเส้นทางหลักอย่างไม่กำกวม

## 1.5 Test ที่ต้องเพิ่ม

- Widget test สำหรับ locale `th`
- Widget test สำหรับ locale `en`
- Test domain-critical messages ทั้งสองภาษา
- Golden/widget test สำหรับหน้าสร้างห่อ, รายละเอียดห่อ, scan, print status และ settings
- Test feature flag ว่า legacy printer UI ไม่ปรากฏใน Pilot production build

---

# GATE 2 — ทำ Playwright Full Workflow ให้เป็น E2E จริง

## 2.1 เป้าหมาย

Playwright ต้องทดสอบระบบจริงตั้งแต่ browser → API → PostgreSQL และตรวจผลใน UI/DB/API ห้ามมีเพียง smoke test

## 2.2 ข้อบังคับด้าน Test Stack

1. Stack ต้องยกขึ้นแบบ deterministic:
   - PostgreSQL
   - Migration
   - Seed
   - NestJS API
   - Flutter release web build
   - Static web server
2. เพิ่ม health check ที่ fail จริงเมื่อ service ไม่พร้อม
3. Script ต้อง exit non-zero เมื่อ:
   - PostgreSQL ไม่พร้อม
   - migration/seed ล้มเหลว
   - API ไม่ตอบ health check
   - PWA ไม่ตอบ HTTP 200
4. ต้อง cleanup process/container เสมอแม้ test fail โดยใช้ `trap`
5. ต้องมี `e2e/package-lock.json`
6. ใช้ `npm ci` ห้ามใช้ `npm install` ใน CI
7. Pin static server เป็น dependency ห้ามใช้ `npx --yes` ดาวน์โหลดแบบไม่ล็อกเวอร์ชันระหว่าง CI
8. ห้ามใช้ production credential หรือ production URL

## 2.3 ห้าม Skip

ต้องนำเงื่อนไขต่อไปนี้ออกก่อนปิด Gate:

- `test.skip(!E2E_FLOW, ...)`
- `test.fixme(...)`
- placeholder comment ที่ไม่มี assertion
- test ที่คลิกแล้วไม่ตรวจผลลัพธ์

ถ้ายังจำเป็นต้อง skip ต้องมี ticket, owner, deadline และ Gate นี้ยังถือว่า **ไม่ผ่าน**

## 2.4 Full Workflow ที่ต้องครอบคลุม

### Auth/Security

1. Login สำเร็จ
2. Login ผิดและ lockout ตาม policy
3. Role CSSD ถูกปฏิเสธ endpoint Supervisor/Admin
4. Logout เครื่องปัจจุบัน
5. Logout all devices แล้ว token เก่าถูกปฏิเสธ
6. 401 ทำให้ clear local session โดยไม่เกิด request loop

### Package/Batch

1. สร้าง Package และเลขรันจาก backend
2. QR/package ID มีรูปแบบถูกต้อง
3. Scan In เข้ารอบนึ่ง
4. CI ผ่าน + BI pending ตาม approved early-release policy
5. BI ผ่าน → Batch `PASSED`
6. BI ไม่ผ่าน → Recall ผ่าน attempt history
7. ห่อหมดอายุถูกบล็อกตอนเบิก
8. Scan Out ต้องมี Department
9. `PACKED_OUT` ใช้ได้เฉพาะ external Department
10. Return บันทึก Department ต้นทาง
11. Reprocess `RETURNED → PACKED`
12. Tag attach/detach/filter
13. รายงาน Recall ยังเห็นห่อที่ `batchId` ปัจจุบันเปลี่ยนแล้ว

### Print Job

1. สร้าง Print Job จากหน้า Package
2. Idempotency-Key เดิมไม่สร้างงานซ้ำ
3. ผู้ใช้เห็น `QUEUED`
4. จำลอง Gateway claim/printing/sent/ack ผ่าน test gateway
5. ผู้ใช้เห็น `PRINTED` หรือ `SIMULATED` ตาม capability
6. กรณี `MAYBE_SENT` ต้องเป็น `ACK_UNKNOWN`
7. ห้าม auto-retry งาน `ACK_UNKNOWN`
8. Supervisor resolve `ACK_UNKNOWN`
9. User ปกติมองไม่เห็น/แก้ Print Job ของผู้อื่น

### Browser/PWA

1. Desktop Chrome
2. Mobile Chrome profile อย่างน้อย Pixel 7
3. Manifest และ service worker
4. Camera permission denied
5. Manual entry fallback
6. Invalid QR ถูกปฏิเสธก่อนยิง API
7. Network interruption แสดง error และไม่สร้าง mutation ซ้ำ
8. Refresh/reload แล้ว session และหน้าสถานะไม่ผิด

## 2.5 Acceptance Criteria

- E2E ทุก flow ผ่านโดยไม่ตั้ง `E2E_FLOW`
- ไม่มี `skip`, `fixme`, placeholder หรือ assertion ที่ว่าง
- รันซ้ำอย่างน้อย 3 รอบได้ผลเหมือนกัน
- CI เก็บ trace, screenshot และ report เมื่อ fail
- Test data แยกจาก production และ cleanup ได้

---

# GATE 3 — บังคับ CI ให้เป็น Release Gate

## 3.1 Jobs ที่ต้องมีและต้องผ่าน

1. API build
2. API unit tests
3. Print Gateway build
4. Print Gateway unit tests
5. Flutter analyze
6. Flutter tests
7. Flutter release web build
8. Prisma migration บนฐานข้อมูลว่าง
9. Migration/backfill test บนฐานข้อมูลจำลองที่มีข้อมูลเดิม
10. PostgreSQL integration tests
11. Playwright Desktop Chrome
12. Playwright Mobile Chrome
13. Secret scan
14. Dependency vulnerability scan

## 3.2 CI Rules

- ห้ามใช้ `|| true` กับ security gate ที่บังคับ
- ห้ามปล่อย wait loop จบด้วย exit 0 ถ้า service ไม่พร้อม
- ทุก dependency ต้องใช้ lockfile
- ห้ามใช้ floating container/action version สำหรับส่วน sensitive โดยไม่มีเหตุผล
- เก็บ test evidence/artifacts เมื่อ fail
- ตั้ง branch protection ให้ merge ได้เฉพาะเมื่อ required checks ผ่าน
- ห้าม Deploy จาก branch ที่ไม่ผ่าน checks

## 3.3 Security Scan

- `gitleaks` ต้องตรวจ full Git history
- `npm audit` ระดับ high/critical ต้อง block
- ตรวจ dependency ฝั่ง Flutter ด้วยเครื่องมือที่รายงาน advisory/CVE ได้จริง ไม่ใช่เพียง `pub outdated`
- สร้าง SBOM อย่างน้อยสำหรับ API และ Print Gateway
- ตรวจ container image ของ PostgreSQL/API/Gateway หากใช้ container deploy
- บันทึก false positive พร้อมเหตุผลและผู้อนุมัติ ห้าม ignore แบบเงียบ

## 3.4 Acceptance Criteria

- Push branch และเปิด PR
- Required checks ผ่านทั้งหมดบน remote CI
- แนบ URL/run ID/commit SHA ของ CI
- ไม่มี secret finding ที่ยังไม่ resolve
- ไม่มี high/critical vulnerability ที่ยังไม่อนุมัติ exception

---

# GATE 4 — Chrome Browser และ Device Verification

## 4.1 อุปกรณ์ขั้นต่ำ

- Android Chrome อย่างน้อย 2 รุ่น/2 ระดับเครื่อง
- Desktop Chrome บน OS ที่ใช้งานจริง
- กล้องหลังความละเอียดต่างกันอย่างน้อย 2 เครื่อง
- ทดสอบผ่าน HTTPS production-like environment

## 4.2 Test Matrix

- ติดตั้ง PWA
- เปิดจาก standalone mode
- Login/logout/logout-all
- Camera allow/deny/permanently deny
- สลับกล้องและเปิดไฟฉาย
- Scan QR ปกติ/ซ้ำ/เสีย/ไม่ใช่ QR ระบบ
- Manual entry
- Network ช้า/หลุด/กลับมา
- กด submit ซ้ำ
- ปิดแท็บ/เปิดใหม่
- Session revoked ระหว่างใช้งาน
- ภาษาไทย/อังกฤษ
- viewport และ text scaling
- Print Job status polling
- Gateway offline
- ACK_UNKNOWN resolution

## 4.3 หลักฐาน

- รุ่นเครื่อง/OS/Chrome version
- วันที่และผู้ทดสอบ
- ผลแต่ละเคส
- screenshot/video ของ failure และ critical workflow
- defect ID และ retest result

---

# GATE 5 — XP-420B Hardware Verification

## 5.1 Configuration บังคับ

- Host: Raspberry Pi/Linux
- Transport: `usb_spool`
- CUPS raw queue
- Command: `lp -d <queue> -o raw`
- Printer: Xprinter XP-420B USB
- Label: 60 × 40 mm
- Resolution: 203 DPI
- Renderer: TSPL bitmap + Sarabun

## 5.2 ต้องทำตาม `HARDWARE_VERIFICATION.md` ครบ

อย่างน้อยต้องผ่าน:

1. Golden Label
2. ภาษาไทยถูกต้อง
3. QR scan success ≥ 99.5%
4. วันที่นึ่ง/หมดอายุตรง backend
5. ห่อก่อนนึ่งไม่มีวันที่ปลอม
6. Soak test 100–500 ใบ
7. ไม่มี duplicate จาก automatic retry
8. USB หลุดก่อนส่ง → `NOT_SENT`
9. USB หลุดระหว่างส่ง → `MAYBE_SENT/ACK_UNKNOWN`
10. Network หลุดหลังส่ง → `ACK_UNKNOWN`
11. Gateway restart ระหว่างงาน
12. กระดาษหมด/ฝาเปิด/queue ค้าง
13. Operator ตรวจ label จริงได้ตาม SOP

## 5.3 ห้ามทำ

- ห้ามนับ `lp exit 0` ว่ากระดาษออกจริง
- ห้ามเปิด Windows `lpr` สำหรับ Pilot
- ห้ามตั้ง `PRINTER_ALLOW_UNVERIFIED_WINDOWS_SPOOL=true` ใน production
- ห้ามใช้ ConsoleTransport ใน production

## 5.4 Acceptance Criteria

- Checklist ผ่านทุกข้อ
- แนบ Golden Label
- แนบ Gateway log ที่ลบ secret แล้ว
- ระบุ printer serial, Pi model, OS, CUPS version และ queue config
- เจ้าหน้าที่หน้างานลงชื่อรับรองความอ่านง่ายของ label/QR

---

# GATE 6 — Backup, Monitoring, SOP และ Security Assessment

## 6.1 Backup/Restore

- เปิด automated PostgreSQL backup
- ระบุ RPO/RTO
- ซ้อม `pg_dump` และ restore ไปฐานข้อมูลใหม่
- ตรวจ row count และ traceability หลัง restore
- รัน migration บนฐานข้อมูลที่ restore แล้ว
- ตรวจข้อมูล FAILED Batch เก่าก่อน `PackageBatchAttempt` backfill
- บันทึกเวลาที่ใช้และผลการซ้อม

## 6.2 Monitoring/Alert

ต้องมี alert อย่างน้อยสำหรับ:

- API unavailable
- Database unavailable/high connection usage
- Gateway heartbeat หาย
- Print queue ค้าง
- `ACK_UNKNOWN`
- `DEAD_LETTER`
- login failure/lockout ผิดปกติ
- backup ล้มเหลว
- disk/storage ใกล้เต็ม

ทุก alert ต้องมี owner และ escalation path

## 6.3 SOP

ต้องมีคู่มือภาษาไทยสำหรับ:

- Login และสิทธิ์แต่ละ role
- Scan In/Out/Return/Reprocess
- ของหมดอายุ
- Batch failed/Recall
- Gateway offline
- กระดาษหมด/เปลี่ยนม้วน/calibrate
- `ACK_UNKNOWN`
- Reprint
- `DEAD_LETTER`
- Network outage ในระบบ online-only
- Lost/stolen device
- Logout all devices
- Backup/restore และ incident response

## 6.4 Security Assessment

- ทดสอบ OWASP API/Web risks ที่เกี่ยวข้อง
- ตรวจ RBAC/IDOR ทุก sensitive endpoint
- ตรวจ JWT revocation
- ตรวจ CORS/CSP/HSTS/TLS
- ตรวจ brute-force/rate limiting
- ตรวจ input validation/file/report export
- ตรวจ secret/key rotation
- ตรวจ dependency/container vulnerabilities
- ทำ penetration test ก่อน Pilot หรือบันทึก risk acceptance ที่ผู้มีอำนาจอนุมัติ
- ตัดสินใจ global rate limit และ topology; ห้ามปล่อยเป็น “ค่อยพิจารณา” ก่อน Pilot

---

# GATE 7 — UAT

## 7.1 ผู้เข้าร่วม

- เจ้าหน้าที่ CSSD ผู้ใช้งานจริง
- Supervisor
- Admin/IT
- ผู้รับผิดชอบด้านคุณภาพ/ความปลอดภัยผู้ป่วย
- ทีมพัฒนา/ผู้รับ defect

## 7.2 UAT Workflow บังคับ

1. Login ตาม role
2. Master data
3. สร้าง Package และพิมพ์ label
4. Scan เข้ารอบ
5. บันทึก CI/BI
6. คลังปลอดเชื้อ/FEFO
7. เบิกออกและเลือก Department
8. บล็อกของหมดอายุ
9. ส่งคืน
10. Reprocess
11. Failed Batch และ Recall
12. Tagging
13. Reports/PDF/Excel
14. Gateway offline/recovery
15. ACK_UNKNOWN/reprint
16. Logout all devices
17. Network outage

## 7.3 UAT Acceptance

- P0/P1 defect = 0
- P2 ต้องมี owner, workaround, deadline และอนุมัติรับความเสี่ยง
- ผู้ใช้งานทำ critical workflow ได้โดยไม่ต้องให้ developer ช่วย
- SOP ตรงกับพฤติกรรมระบบจริง
- มีลายเซ็น/ชื่อผู้อนุมัติและวันที่

---

# GATE 8 — Limited Pilot

## 8.1 เงื่อนไขก่อนเริ่ม

ต้องผ่าน Gate 1–7 ทั้งหมด และมี Go/No-Go sign-off

## 8.2 ขอบเขต Pilot

- โรงพยาบาล/หน่วยงานเดียว
- จุดพิมพ์เดียว
- XP-420B หนึ่งเครื่อง
- Raspberry Pi/Linux Gateway หนึ่งเครื่อง
- กลุ่มผู้ใช้จำกัด
- มี fallback SOP ที่ไม่ทำลาย traceability
- มีทีม support และช่องทาง incident ชัดเจน

## 8.3 Monitoring ระหว่าง Pilot

- ตรวจ Gateway heartbeat
- ตรวจ Print Job queue
- ตรวจ ACK_UNKNOWN/DEAD_LETTER
- ตรวจ scan blocked/expired
- ตรวจ failed batch/recall
- ตรวจ error rate และ user-reported defect ทุกวัน
- ห้ามขยาย Pilot หากมี P0/P1 ที่ยังไม่ปิด

---

# Definition of Done

งานจะถือว่าเสร็จต่อเมื่อมีครบ:

1. Code review ผ่าน
2. Unit/integration/widget/E2E tests ผ่าน
3. Build ผ่าน
4. Remote CI ผ่าน
5. Security scan ผ่าน
6. Browser/device evidence ผ่าน
7. XP-420B hardware evidence ผ่าน
8. Backup/restore drill ผ่าน
9. Monitoring/alerts เปิดใช้งาน
10. SOP อนุมัติ
11. UAT sign-off
12. Pilot Go/No-Go sign-off

คำว่า “มีโค้ดแล้ว”, “มี test file แล้ว”, “build ผ่านในเครื่อง” หรือ “มี checklist แล้ว” **ไม่เท่ากับเสร็จ**

---

# รูปแบบรายงานที่ Dev ต้องส่งกลับ

```md
# PRE-PILOT IMPLEMENTATION RESULT

Commit SHA:
Branch:
Remote PR:
Deployment environment:

## Gate 1 — i18n / Printer UX
- Files changed:
- Tests:
- Evidence:
- Remaining:

## Gate 2 — Playwright Full E2E
- Flows completed:
- Skipped/fixme count:
- Desktop Chrome result:
- Mobile Chrome result:
- Artifacts:

## Gate 3 — CI / Security
- CI URL:
- Integration:
- E2E:
- Secret scan:
- Dependency scan:

## Gate 4 — Browser/Device
- Devices:
- Chrome versions:
- Result:

## Gate 5 — XP-420B
- Hardware:
- Queue:
- Golden label:
- Soak result:
- Failure tests:

## Gate 6 — Operations/Security
- Backup/restore:
- Monitoring:
- SOP:
- Security assessment:

## Gate 7 — UAT
- Participants:
- Result:
- Defects:
- Sign-off:

## Gate 8 — Pilot
- Go/No-Go:
- Scope:
- Owner:

## Automated Test Summary
- API unit:
- API integration:
- Gateway:
- Flutter analyze:
- Flutter tests:
- Flutter web build:
- Playwright:

## Known Limitations

## Explicit statement
ไม่มี P0/P1 ที่ยังเปิดอยู่: YES/NO
พร้อม Deploy: YES/NO
พร้อม UAT: YES/NO
พร้อม Pilot: YES/NO
```

---

## คำสั่งสุดท้าย

ให้ทีมพัฒนาดำเนินงานตาม Gate ตามลำดับ ห้ามข้าม Gate และห้ามลดเกณฑ์เพื่อให้สถานะดูเสร็จเร็วขึ้น  
หากพบข้อขัดแย้งกับ SOP โรงพยาบาลหรือกฎ patient safety ให้หยุดงานส่วนนั้นและขอคำยืนยันเป็นลายลักษณ์อักษร  
หลังแก้แต่ละ Gate ให้ส่ง commit SHA, diff summary, test output และหลักฐานจริงกลับมาตรวจแบบ read-only ก่อนดำเนิน Gate ถัดไป
