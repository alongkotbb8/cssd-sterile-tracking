# CSSD MASTER EXECUTION DIRECTIVE

## คำสั่งพัฒนาระบบฉบับหลัก — Online-only Chrome PWA + QR Camera + Xprinter XP-420B Print Gateway

**สถานะ:** REQUIRED / BLOCKING / SINGLE SOURCE OF TRUTH  
**ใช้กับ:** Developer, AI Developer, QA, Cybersecurity, DevOps และผู้อนุมัติ UAT  
**วันที่ฐานตรวจ:** 23 กรกฎาคม 2026  
**ระบบ:** CSSD Sterile Supply Tracking  
**ลำดับเอกสาร:** เอกสารนี้มีอำนาจเหนือแผนพัฒนาและเอกสารเก่าที่ขัดแย้งกัน  

> เป้าหมายของเอกสารนี้คือหยุดการตีความเอง หยุดการประกาศงานเสร็จโดยไม่มีหลักฐาน
> และทำให้ทุก Requirement เชื่อมกับ Code, Test, CI, Hardware Verification และ UAT

---

# 0. คำสั่งสูงสุด

1. ห้ามข้าม Gate
2. ห้ามประกาศ Gate ผ่านด้วยคำอธิบายของ Developer เพียงอย่างเดียว
3. Gate ผ่านได้เมื่อ QA ตรวจหลักฐานจริงและลงผล `PASS`
4. คำว่า “เขียนโค้ดแล้ว”, “test ในเครื่องผ่าน” หรือ “commit แล้ว” หมายถึง `IMPLEMENTED` เท่านั้น
5. ห้ามใช้คำว่า `DEPLOY READY`, `UAT READY` หรือ `PILOT READY` จนกว่าจะผ่าน Gate ที่กำหนด
6. ห้ามเปลี่ยน Requirement, Domain Rule, Workflow, Security Control หรือ Hardware Path ด้วยการคาดเดา
7. หาก Requirement ไม่ชัด ให้หยุดเฉพาะจุดนั้น บันทึกคำถาม และทำงานส่วนอื่นที่ไม่ขึ้นต่อกันต่อได้
8. ห้ามลบ ลด หรือ skip test เพื่อทำให้ Gate ผ่าน
9. ห้ามแก้ข้อมูลย้อนหลังเพื่อตกแต่งผลทดสอบ
10. ทุกหลักฐานต้องอ้างอิง commit SHA เดียวกับโค้ดที่ตรวจ

---

# 1. Baseline ที่ล็อกแล้ว

## 1.1 รูปแบบระบบ

ระบบเป้าหมายต้องเป็น:

- Chrome PWA
- Safari บน iPhone/iPad สำหรับสแกน QR และ workflow หลัก
- Online-only
- Backend NestJS + Prisma + PostgreSQL
- Frontend Flutter Web/PWA
- กล้องของ Chrome สำหรับสแกน QR
- Manual entry เป็น fallback
- Print Gateway แยกจาก Browser
- Xprinter XP-420B แบบ USB
- Print Gateway ส่งงานผ่าน Linux/CUPS แบบ raw
- Backend เป็นแหล่งความจริงเพียงแห่งเดียว

## 1.2 สิ่งที่ยกเลิก

ยกเลิกจาก Production/Pilot scope ทั้งหมด:

- Offline mutation
- Offline queue
- Offline running-number generation
- Offline PDF/report generation
- Offline master-data cache ที่ใช้แทน backend
- Mobile application เป็นช่องทางหลัก
- Bluetooth direct print เป็นช่องทาง Pilot
- FlashLabel A318BT เป็นเครื่องพิมพ์ Pilot
- Zebra เป็นเครื่องพิมพ์เป้าหมาย
- Browser สั่ง USB printer โดยตรง
- Browser ตั้ง Print Job เป็น `PRINTED`

Legacy code อาจเก็บไว้ชั่วคราวได้เฉพาะเมื่อ:

1. ไม่ถูกเรียกจาก Production/Pilot UI
2. feature flag ปิดเป็นค่าเริ่มต้นใน release
3. ไม่มี secret หรือ permission ที่เพิ่ม attack surface โดยไม่จำเป็น
4. มี test ยืนยันว่าผู้ใช้ทั่วไปเข้าไม่ถึง
5. มีแผนลบหรือแยกออกหลัง Hardware Gate

## 1.3 เอกสารเก่าที่ขัดแย้ง

ก่อนปิด Gate 1 ต้องปรับเอกสารต่อไปนี้ให้ไม่สั่งงานขัดกับเอกสารนี้:

- `AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `AI_DEVELOPMENT_GUARDRAILS.md`
- เอกสารที่ยังระบุ Offline-first, Bluetooth, Zebra หรือ Mobile-first

ห้ามลบประวัติเอกสาร ให้ใช้ข้อความ `SUPERSEDED` หรือแก้หัวข้อที่ขัดแย้งพร้อมอ้างอิงเอกสารนี้

---

# 2. กฎโดเมนที่ห้ามเปลี่ยน

1. `SEAL` หมดอายุหลังวันนึ่ง 180 วัน
2. `CLOTH` หมดอายุหลังวันนึ่ง 7 วัน
3. Backend คำนวณ `expiry_date`; client ห้ามกำหนดเอง
4. Running number สร้างโดย Backend เท่านั้น
5. QR มีเฉพาะ `package_id`
6. เบิกใช้ FEFO
7. ห่อหมดอายุต้องถูกบล็อกแบบ fail-closed
8. Scan Out ต้องมี Department
9. Receiver name เป็น nullable
10. Return ต้องบันทึก Department ต้นทาง
11. `PACKED_OUT` ใช้กับ Department ชนิด external เท่านั้น
12. State transition ต้องผ่าน state-machine guard
13. Recall ต้องใช้ประวัติ `PackageBatchAttempt` ไม่ใช้เพียง `Package.batchId` ปัจจุบัน
14. ห้ามลบหรือ rewrite AuditLog, Movement และ PackageBatchAttempt
15. การตัดสิน recall/reprocess ต้องรักษา package-level traceability

State machine:

```text
PACKED → STERILE → ISSUED → RETURNED → PACKED
PACKED → PACKED_OUT → PACKED
ทุกสถานะ → DISCARDED
STERILE → EXPIRED เมื่อหมดอายุขณะอยู่ในคลัง
```

Transition อื่นต้องถูกปฏิเสธทั้งที่ UI และ Backend โดย Backend เป็นตัวบังคับสุดท้าย

---

# 3. นิยามสถานะงาน

ใช้สถานะต่อไปนี้เท่านั้น:

| สถานะ | ความหมาย |
|---|---|
| `NOT_STARTED` | ยังไม่เริ่ม |
| `IMPLEMENTED` | เขียนโค้ดแล้ว แต่ยังไม่มีหลักฐานครบ |
| `LOCAL_VERIFIED` | test/build ที่กำหนดผ่านในเครื่อง |
| `CI_VERIFIED` | remote CI ผ่านที่ commit SHA เดียวกัน |
| `QA_PASSED` | QA ตรวจ requirement และ negative cases แล้ว |
| `HARDWARE_PASSED` | ทดสอบ XP-420B จริงแล้ว |
| `UAT_PASSED` | ผู้ใช้หน้างานลงนามแล้ว |
| `PILOT_APPROVED` | ได้รับอนุมัติให้ใช้งานแบบจำกัด |
| `BLOCKED` | มี blocker พร้อม owner และหลักฐาน |

ห้ามเปลี่ยนจาก `IMPLEMENTED` เป็น `QA_PASSED` โดยข้าม `LOCAL_VERIFIED` และ `CI_VERIFIED`

---

# 4. Baseline จากการตรวจครั้งล่าสุด

หลักฐานที่เคยผ่านในเครื่อง:

- `flutter analyze`: 0 issues
- `flutter test`: 45/45 tests passed
- `flutter build web --release`: สำเร็จ
- Legacy printer UI มี feature flag
- Print Gateway / XP-420B ถูกวางเป็นเส้นทางหลัก

ผลดังกล่าวเป็นเพียง baseline และใช้แทนผลของ commit ใหม่ไม่ได้

จุดที่ตรวจพบและต้อง re-audit ก่อนลงนาม Gate 1:

- Navigation labels ใน `app_router.dart`
- `(ภายนอก)` ใน model/display mapping
- Login error ใน auth controller
- Generic API error ใน API client
- Server URL validation errors
- FCM notification channel name/description
- User-facing string ทุกชนิดที่อยู่นอก ARB
- Test ภาษาอังกฤษและ release feature-flag behavior

หากทีมแก้แล้ว ต้องแนบ diff และผลทดสอบใหม่ ห้ามตอบเพียง “แก้แล้ว”

---

# GATE 1 — Source of Truth, i18n และ Legacy Printer Isolation

## 1A. งานบังคับ

1. ย้ายข้อความ user-facing ทุกจุดเข้า ARB:
   - page title
   - navigation label
   - button
   - tooltip
   - field label/helper
   - validation
   - API/login/network error ที่แสดงต่อผู้ใช้
   - dialog
   - SnackBar
   - empty/loading/error state
   - accessibility/semantics
   - notification channel ที่ระบบปฏิบัติการแสดง
2. รองรับ `th` และ `en`
3. ภาษาไทยเป็นค่าเริ่มต้น
4. ห้ามต่อข้อความที่มีค่าตัวแปรด้วย string concatenation; ใช้ ARB placeholder
5. ข้อความบน label จริงอาจเป็นภาษาไทยตาม SOP แต่ต้องแยกจาก UI localization
6. ซ่อน legacy printer UI จาก role ปกติใน Pilot release
7. `CSSD_ENABLE_LEGACY_PRINT` ต้องเป็น `false` ใน Pilot/Production
8. หน้า Settings ต้องแสดง Print Gateway และ XP-420B เป็นเส้นทางหลัก
9. ปรับเอกสารเก่าที่ขัดกับ Online-only/Xprinter

## 1B. Automated checks ที่ต้องเพิ่ม

- Static check ตรวจ hard-coded user-facing Thai/English
- Allowlist ต้องระบุ file, line/pattern, เหตุผล และ owner
- Widget tests locale `th`
- Widget tests locale `en`
- Tests สำหรับ domain-critical errors
- Test release/default flag ซ่อน legacy printer
- Test role ปกติไม่เห็น legacy controls
- Layout test ที่ 320 px, Pixel 7 และ Desktop Chrome
- Text scale 1.0 และ 1.3

## 1C. คำสั่งตรวจ

```bash
cd apps/mobile
flutter gen-l10n
flutter analyze
flutter test
flutter build web --release
```

## 1D. เกณฑ์ผ่าน

- ทุกคำสั่ง exit code 0
- ไม่มี hard-coded user-facing string นอก allowlist
- ไม่มี overflow ภาษาไทยและอังกฤษ
- Pilot release ไม่แสดง Bluetooth/A318BT/System direct print แก่ผู้ใช้ทั่วไป
- เอกสารหลักไม่มีข้อสั่งงาน Offline/Bluetooth/Zebra ที่ยังมีสถานะ active
- QA ลงผล `GATE 1: PASS`

---

# GATE 2 — Deterministic Full-stack E2E

ห้ามเริ่ม Gate 2 จน Gate 1 ผ่าน

## 2A. Stack ที่ต้องยกขึ้นอัตโนมัติ

1. PostgreSQL
2. Prisma migration
3. Seed สำหรับ E2E เท่านั้น
4. NestJS API
5. Flutter release web build
6. Static web server
7. Test Print Gateway/Simulator
8. Playwright

Script ต้อง:

- ใช้ lockfile
- ใช้ `npm ci`
- รอ health check แบบมี timeout
- exit non-zero เมื่อ service ใดไม่พร้อม
- cleanup ทุก process/container แม้ test fail
- ห้ามใช้ production database, credential หรือ URL

## 2B. Playwright workflows บังคับ

### Authentication

- Login สำเร็จ
- Login ผิด
- Account lockout
- RBAC ปฏิเสธ CSSD ที่เรียก Supervisor/Admin endpoint
- Logout current device
- Logout all devices
- Token เก่าถูกปฏิเสธ
- 401 clear session โดยไม่เกิด request loop

### Package lifecycle

- สร้าง Package
- running number มาจาก Backend
- QR/package ID validation
- Scan In
- Batch CI/BI workflow
- Batch pass
- Batch fail และ recall ผ่าน attempt history
- Expired package ถูกบล็อก
- Scan Out ต้องเลือก Department
- `PACKED_OUT` เฉพาะ external Department
- Return พร้อม Department ต้นทาง
- Reprocess `RETURNED → PACKED`
- Tag attach/detach/filter
- รายงาน recall ยังเห็น package หลัง current `batchId` เปลี่ยน

### Print lifecycle

- สร้าง Print Job จาก Package UI
- Idempotency-Key เดิมไม่สร้างงานซ้ำ
- `QUEUED → CLAIMED/PRINTING → PRINTED`
- Browser ไม่สามารถ ACK งานเอง
- `MAYBE_SENT → ACK_UNKNOWN`
- `ACK_UNKNOWN` ไม่ auto-retry
- Supervisor resolve `ACK_UNKNOWN`
- ผู้ใช้ทั่วไปไม่มีสิทธิ์ resolve
- งานของผู้ใช้อื่นไม่รั่วไหล

### Chrome/PWA

- Desktop Chrome
- Pixel 7 Chrome profile
- Playwright WebKit สำหรับตรวจ compatibility ของ Safari
- Manifest
- Service worker โดยไม่สร้าง offline mutation behavior
- Camera permission denied
- Manual entry fallback
- Invalid QR ถูกปฏิเสธ
- Network interruption ไม่สร้าง mutation ซ้ำ
- Refresh/reload รักษาสถานะที่ถูกต้อง

### Safari/iOS WebKit

- เปิดระบบผ่าน Safari บน iPhone/iPad ได้
- ติดตั้งผ่าน Safari `Add to Home Screen` ได้
- ขอสิทธิ์กล้องจาก user gesture และแสดงคำแนะนำเมื่อถูกปฏิเสธ
- ใช้กล้องหลังเป็นค่าเริ่มต้นเมื่ออุปกรณ์อนุญาต
- สแกน QR ที่มีเฉพาะ `package_id`
- ป้องกันการอ่าน QR เดิมซ้ำหลายครั้งจากหลาย frame
- สลับ Safari ไป background แล้วกลับมา กล้องต้องเริ่มใหม่ได้โดยไม่ค้าง
- เมื่อกล้องถูกระบบปฏิบัติการยึดหรือหยุด ต้องแสดง error และปุ่มลองใหม่
- เมื่อ Safari ไม่รองรับ torch ต้องซ่อนหรือ disable ปุ่ม ห้าม throw/crash
- เมื่อสลับกล้องไม่ได้ ต้องแจ้งอย่างปลอดภัยและใช้กล้องเดิมต่อ
- เมื่อสิทธิ์ถูก deny/revoke ต้องแสดงวิธีเปิดสิทธิ์สำหรับ Safari/iOS
- Manual entry ต้องพร้อมใช้เสมอและถูก audit ว่าเป็น manual entry
- การสแกนต้องทำงานผ่าน HTTPS เท่านั้น; environment ที่ไม่ใช่ secure context
  ต้อง fail closed พร้อมข้อความที่เข้าใจได้
- การ refresh, lock screen, rotate screen และกลับจาก Home Screen ต้องไม่สร้าง
  mutation ซ้ำหรือยืนยันรายการโดยอัตโนมัติ

## 2C. ข้อห้าม

- ห้าม `test.skip`
- ห้าม `test.fixme`
- ห้าม placeholder test
- ห้าม assertion ว่าง
- ห้ามเปิด flow ด้วย environment flag ที่ CI ไม่ได้ตั้ง
- ห้าม mock ทุก layer จนไม่ผ่าน API/PostgreSQL จริง

## 2D. เกณฑ์ผ่าน

- E2E ทุก flow ผ่าน 3 รอบติดกัน
- Playwright ต้องมี project `webkit` และ required CI job สำหรับ WebKit
- ไม่มี skip/fixme
- Fail แล้วมี trace, screenshot, video หรือ report
- DB/API/UI assertions สอดคล้องกัน
- QA ลงผล `GATE 2: PASS`

---

# GATE 3 — Remote CI และ Security Gate

Gate นี้ต้องมีการ push branch และเปิด Pull Request จริง

## 3A. ก่อน push

- Working tree ไม่มี secret
- Review diff ทั้งหมด
- Commit แยกตามหัวข้อ
- ระบุ commit SHA
- ห้ามรวมไฟล์ส่วนตัวหรือ local environment
- ต้องได้รับอนุญาตจากเจ้าของระบบก่อน push/open PR

## 3B. Required CI jobs

- API build
- API unit tests
- API integration tests with PostgreSQL
- Prisma migration บน DB ว่าง
- Migration/backfill บน DB ที่มีข้อมูลจำลองเดิม
- Print Gateway build
- Print Gateway unit tests
- Flutter analyze
- Flutter tests
- Flutter release web build
- Playwright Desktop Chrome
- Playwright Mobile Chrome
- Playwright WebKit
- Secret scan แบบ full Git history
- Dependency vulnerability scan
- SBOM สำหรับ API และ Print Gateway

## 3C. Security rules

- High/Critical vulnerability ต้อง block
- ห้าม `|| true` ใน required security job
- False positive ต้องมีเหตุผล, owner, expiry และผู้อนุมัติ
- ห้ามใช้ floating dependency ใน CI ส่วนสำคัญโดยไม่มีเหตุผล
- ห้าม Deploy จาก commit ที่ไม่ตรงกับ CI evidence
- ตั้ง branch protection ให้ required jobs ผ่านก่อน merge

## 3D. หลักฐาน

- Repository/PR URL
- Commit SHA
- CI run URL/ID
- Job summary
- Test artifact
- Security scan artifact
- รายการ exception ที่อนุมัติ

## 3E. เกณฑ์ผ่าน

- Required checks ผ่านทั้งหมดบน remote CI
- ไม่มี unresolved secret
- ไม่มี unapproved High/Critical vulnerability
- QA/Security ลงผล `GATE 3: PASS`

หากยังไม่ได้ push หรือไม่มี CI URL ให้รายงาน `LOCAL_VERIFIED` เท่านั้น ห้ามรายงาน Gate 3 ผ่าน

---

# GATE 4 — Chrome, Safari และ Device Verification

## 4A. Test matrix ขั้นต่ำ

- Desktop Chrome รุ่น production ปัจจุบัน
- Android Chrome อย่างน้อย 2 รุ่นอุปกรณ์
- iPhone Safari อย่างน้อย 2 รุ่น iOS ที่ยังได้รับ security update
- iPad Safari อย่างน้อย 1 รุ่น หากหน้างานจะใช้ iPad
- ความกว้าง 320 px
- Pixel 7 viewport
- Desktop 1366×768
- Wi-Fi โรงพยาบาลจริงหรือเครือข่าย Pilot ที่เทียบเท่า
- กล้อง permission: allow, deny, revoke
- แสงสว่างดี, แสงน้อย, QR เอียง, QR ยับ/เล็ก

Safari/iOS ต้องทดสอบบนอุปกรณ์ Apple จริง ห้ามใช้ Playwright WebKit หรือ simulator
เป็นหลักฐานแทนกล้องจริง เพราะ browser automation ไม่พิสูจน์ permission, camera
driver, lifecycle และพฤติกรรม Add to Home Screen ของอุปกรณ์จริง

## 4B. สิ่งที่ต้องทดสอบ

- ติดตั้ง PWA
- เปิดจาก Home Screen
- Login/logout
- Session expiry
- QR scan ต่อเนื่อง
- ป้องกัน scan ซ้ำ
- Safari เปิดจาก browser tab
- Safari เปิดจาก Add to Home Screen
- Safari allow/deny/revoke camera permission
- Safari background/foreground
- Safari lock/unlock screen ระหว่างเปิดกล้อง
- Safari rotate portrait/landscape
- Safari ปิด tab/PWA แล้วเปิดใหม่
- Safari กล้องถูกใช้งานโดยแอปอื่น
- Safari ไม่มี torch หรือสลับกล้องไม่ได้แล้วระบบต้องไม่ crash
- Manual entry
- Error visibility
- Loading feedback
- ปุ่มไม่ถูกกดซ้ำระหว่าง mutation
- Network หลุดก่อน request
- Network หลุดหลังส่ง request
- Refresh ระหว่าง workflow
- ภาษาไทย/อังกฤษ
- Accessibility เบื้องต้น

## 4B.1 คำสั่งพัฒนา Safari QR Scanner

Developer ต้องดำเนินการครบทุกข้อ:

1. ตรวจสอบ `mobile_scanner` เวอร์ชันที่ใช้อยู่กับ Safari/iOS WebKit และ Flutter Web
   จากเอกสารทางการ/Changelog ของเวอร์ชันที่ติดตั้งจริง
2. ห้าม upgrade package แบบ major โดยไม่อ่าน breaking changes และรัน regression
   tests ทั้ง Chrome และ Safari
3. ปรับ camera initialization ให้:
   - เริ่มจาก user gesture เมื่อ Safari/WebKit ต้องการ
   - กัน `start()` ซ้อน
   - กัน lifecycle resume ซ้อน
   - stop stream เมื่อ inactive/background
   - start stream ใหม่เมื่อ resumed โดยไม่สร้าง subscription ซ้ำ
4. จัดการ error แยกอย่างน้อย:
   - permission denied
   - permission revoked
   - insecure context / ไม่ใช่ HTTPS
   - no camera
   - camera already in use
   - unsupported constraint
   - generic camera error
5. ห้ามถือว่า Web browser ได้สิทธิ์กล้องเพียงเพราะ `kIsWeb == true`
6. UI ต้องสะท้อนสถานะจริง: `initializing`, `ready`, `denied`, `unavailable`,
   `interrupted` และ `retrying`
7. ใช้ capability detection สำหรับ torch/switch camera ห้ามตัดสินจาก user-agent
   เพียงอย่างเดียว
8. `toggleTorch()` และ `switchCamera()` ต้องถูก await/catch; Safari ไม่รองรับแล้ว
   ต้องไม่เกิด unhandled exception
9. ปุ่ม Manual entry ต้องมองเห็นและใช้งานได้แม้กล้องกำลังโหลดหรือ error
10. QR validation ต้องเกิดก่อนเรียก API และ QR ต้องยอมรับเฉพาะ `package_id`
11. เพิ่ม debounce/cooldown ป้องกัน frame เดิมสร้าง lookup/mutation ซ้ำ
12. ห้าม auto-submit mutation ทันทีเมื่ออ่าน QR; ต้องคง workflow ตรวจสอบ/ยืนยันเดิม
13. ข้อความ permission/error/retry ทั้งไทยและอังกฤษต้องอยู่ใน ARB
14. เพิ่ม automated tests:
    - camera denied
    - camera unavailable
    - retry
    - manual fallback
    - invalid QR
    - duplicate QR frame
    - lifecycle resume
    - unsupported torch/switch camera
15. เพิ่ม Playwright project:

```ts
{ name: 'webkit', use: { ...devices['Desktop Safari'] } }
```

16. ติดตั้ง browser engine ใน development/CI ด้วย lockfile เดิม:

```bash
cd e2e
npm ci
npx playwright install --with-deps chromium webkit
npm test
```

17. Automated WebKit test ต้องตรวจ UI/error/fallback แต่ห้ามอ้างว่าเป็น hardware
   camera verification
18. ทดสอบกล้องจริงบน Safari ตาม 4A/4B และบันทึก:
    - iPhone/iPad model
    - iOS version
    - Safari version
    - browser tab หรือ Add to Home Screen
    - permission state
    - QR sample ID
    - pass/fail
    - screenshot/video
19. ห้ามประกาศ “Safari รองรับแล้ว” จน Automated WebKit และอุปกรณ์จริงผ่านทั้งคู่

## 4C. เกณฑ์ผ่าน

- ไม่มี P0/P1
- ไม่มี workflow ที่ทำให้สถานะ package ผิด
- Network interruption ไม่สร้างข้อมูลซ้ำ
- ผู้ใช้เข้าใจว่า scan สำเร็จ/ล้มเหลว
- Safari สแกน QR ได้จริงบน iPhone ตาม test matrix
- Safari lifecycle/permission failure ไม่ทำให้หน้าจอดำถาวร
- มีภาพหรือวิดีโอและ test record ต่อ device
- QA ลงผล `GATE 4: PASS`

---

# GATE 5 — XP-420B Hardware Verification

Gate นี้ห้ามใช้ ConsoleTransport/Mock เป็นหลักฐานผ่าน

## 5A. Hardware ที่ต้องล็อก

- Xprinter XP-420B เครื่องจริง
- USB cable จริง
- Label size/ชนิดกระดาษจริง
- Raspberry Pi/Linux host หรือ Linux host ที่ได้รับอนุมัติ
- CUPS queue ที่ชื่อแน่นอน
- Print Gateway build ที่ตรงกับ commit SHA

หาก Production host ไม่ใช่ Raspberry Pi/Linux ต้องหยุด Gate นี้และขออนุมัติสถาปัตยกรรมใหม่

## 5B. Test บังคับ

- CUPS detect printer
- `lpstat` แสดง queue
- Raw test print
- ภาษาไทย
- QR scan คืนค่า `package_id` ตรง
- ขนาด label
- ความคมชัด
- ระยะขอบ
- พิมพ์ 1 งาน
- พิมพ์ต่อเนื่องอย่างน้อย 50 งาน
- Duplicate submission
- Gateway restart ก่อน claim
- Gateway restart หลัง claim
- USB disconnect ก่อนส่ง
- USB disconnect ระหว่าง/หลังส่ง
- Printer offline
- Paper out
- CUPS error
- API unavailable
- `ACK_UNKNOWN` และ manual resolution
- Gateway key revoke/rotate

## 5C. Patient-safety acceptance

- QR ทุกใบตรงกับ package จริง
- ไม่มี label สลับ package
- ไม่มี duplicate print ที่ระบบรายงานเป็นงานใหม่โดยไม่เตือน
- งานคลุมเครือไม่ auto-retry
- Audit trail ครบ
- ผู้ปฏิบัติงานเห็นคำเตือนก่อนสั่งซ้ำ

## 5D. หลักฐาน

- รุ่น/serial/firmware ของเครื่องพิมพ์
- Linux/CUPS version
- CUPS queue config
- Gateway config แบบปกปิด secret
- ตัวอย่าง label
- ภาพ QR scan
- test log
- รายการ failure/recovery
- ผู้ทดสอบและวันเวลา

## 5E. เกณฑ์ผ่าน

- ทุก critical case ผ่าน
- ไม่มี P0/P1
- มีผู้รับผิดชอบ CSSD และ IT ลงนาม
- QA ลงผล `GATE 5: HARDWARE_PASSED`

---

# GATE 6 — Operational Readiness และ Security Assessment

## 6A. Backup/restore

- Automated PostgreSQL backup
- Encryption at rest/in transit ตาม infrastructure
- Retention policy
- Restore drill ลง environment แยก
- วัด RPO/RTO จริง
- Backup failure alert

## 6B. Monitoring

- API health
- Database health
- Gateway heartbeat
- Printer queue
- Print failure rate
- `ACK_UNKNOWN` count
- Authentication failure/lockout
- Error rate/latency
- Disk/certificate expiry
- Alert owner และ escalation path

## 6C. SOP

- เริ่ม/หยุด Gateway
- เปลี่ยนกระดาษ
- Printer offline/paper out
- ตรวจ label ก่อนใช้
- แก้ `ACK_UNKNOWN`
- Rotate/revoke Gateway key
- Incident response
- Recall procedure
- Backup/restore
- Deploy/rollback

## 6D. Security assessment

- Authentication/session
- RBAC/IDOR
- Injection
- XSS/CSRF/CORS/CSP
- Rate limiting/lockout
- Secret management
- Gateway authentication
- Audit integrity
- Dependency/container risks
- PWA storage/session exposure
- TLS configuration
- Log privacy

## 6E. เกณฑ์ผ่าน

- Restore drill ผ่าน
- Alert ส่งถึงผู้รับผิดชอบจริง
- SOP ผ่าน tabletop exercise
- ไม่มี unresolved P0/P1
- High finding ต้องแก้หรือมี risk acceptance ที่ลงนาม
- Security/Operations ลงผล `GATE 6: PASS`

---

# GATE 7 — UAT และ Limited Pilot

## 7A. UAT roles

- เจ้าหน้าที่ CSSD
- Supervisor
- Admin/IT
- ผู้รับผิดชอบ Print Gateway
- ผู้อนุมัติ Patient Safety/หน่วยงาน

## 7B. UAT scenarios

- Login ตาม role
- สร้างและพิมพ์ label
- Scan In/Out/Return/Reprocess
- Batch pass/fail
- Recall
- Expired package block
- Department/external workflow
- Tag
- Report
- Print failure
- `ACK_UNKNOWN`
- Gateway offline
- Logout all devices

## 7C. Pilot constraints

- เริ่มหนึ่งจุดพิมพ์
- XP-420B หนึ่งเครื่อง
- Gateway หนึ่งตัว
- กลุ่มผู้ใช้จำกัด
- ระยะเวลา Pilot ระบุชัด
- มี rollback และ manual continuity plan
- มี on-call owner
- ห้ามขยาย Pilot จน review ผลรอบแรก

## 7D. Stop conditions

หยุด Pilot ทันทีเมื่อ:

- Package/label mismatch
- Recall false-negative
- Expired package ถูกเบิกได้
- Unauthorized access
- Audit trail หาย
- Duplicate/ambiguous print ถูก retry โดยไม่มีคำเตือน
- Data corruption
- Restore ไม่ได้

## 7E. เกณฑ์ผ่าน

- UAT scenarios ผ่าน
- ผู้ใช้หน้างานลงนาม
- ไม่มี P0/P1
- P2 มี owner/deadline
- Pilot owner อนุมัติ
- สถานะสุดท้าย `PILOT_APPROVED`

---

# 5. Requirement-to-Evidence Matrix

Developer ต้องส่งตารางนี้ทุก Gate:

| Requirement ID | Code/File | Automated Test | Manual Test | Evidence | Commit SHA | Status |
|---|---|---|---|---|---|---|
| ตัวอย่าง G1-I18N-01 | path:line | test name | device/page | artifact URL | SHA | PASS/FAIL |

ห้ามเว้นช่อง `Code/File`, `Test` หรือ `Evidence` สำหรับ Requirement ที่ประกาศผ่าน

---

# 6. รูปแบบรายงานส่ง QA

ใช้รูปแบบนี้เท่านั้น:

```markdown
# GATE N SUBMISSION

Commit SHA:
Branch:
Scope:

## Requirements completed
- [ID] รายละเอียด

## Files changed
- path — เหตุผล

## Tests executed
- command
- exit code
- passed/failed count

## Negative cases
- case — result

## Evidence
- CI URL
- artifact
- screenshot/video/log

## Known limitations
- limitation
- severity
- owner
- deadline

## Declaration
สถานะที่ขอ: LOCAL_VERIFIED / CI_VERIFIED / QA_PASSED
```

คำว่า “ทั้งหมดผ่าน” โดยไม่มี command, count, SHA และ evidence ถือว่าไม่ส่งงาน

---

# 7. Severity และการตัดสิน

## P0 — ห้าม Deploy/Pilot

- Patient safety
- Recall false-negative
- Package/label mismatch
- Data loss/corruption
- Authentication bypass
- Secret exposure
- Audit trail ถูกลบหรือขาด

## P1 — ห้ามผ่าน Gate

- Workflow หลักใช้ไม่ได้
- Expired package หลุด
- RBAC/IDOR
- Duplicate mutation/print
- `ACK_UNKNOWN` ถูก retry อัตโนมัติ
- Migration/restore ล้มเหลว

## P2 — ผ่านได้เฉพาะมีแผนอนุมัติ

- UX ที่มี workaround ปลอดภัย
- Report/display defect ที่ไม่เปลี่ยนข้อมูล
- Performance issue ที่ไม่กระทบ safety

## P3

- Cosmetic
- Documentation typo ที่ไม่ทำให้ตีความ Requirement ผิด

---

# 8. คำสั่งทำงานถัดไปสำหรับ Developer

ให้ดำเนินการตามลำดับนี้โดยเด็ดขาด:

1. ตรวจ `git status` และรักษางานที่มีอยู่
2. ทำ Gate 1 residual re-audit จากรายการในหัวข้อ 4
3. ปรับเอกสาร active ที่ยังขัดกับ Online-only/Xprinter
4. รันคำสั่ง Gate 1 ใหม่ทั้งหมด
5. ส่ง `GATE 1 SUBMISSION` ให้ QA
6. หยุดรอผล QA Gate 1
7. เมื่อ QA ระบุ `GATE 1: PASS` จึงทำ Gate 2
8. สร้าง deterministic E2E stack และ full Playwright workflows
9. รัน E2E 3 รอบติดกัน
10. ส่ง `GATE 2 SUBMISSION`
11. เมื่อ QA ระบุ `GATE 2: PASS` ให้เตรียม Gate 3
12. ขออนุญาตเจ้าของระบบก่อน push/open PR
13. Push commit SHA ที่ตรวจแล้วและเปิด PR
14. รอ remote CI/Security จริง
15. ส่ง URL/Run ID/Artifacts ให้ QA
16. หลัง Gate 3 ผ่าน จึงทำ Browser/Device Gate
17. ทดสอบ Safari/iOS QR Camera บนอุปกรณ์จริงและแนบหลักฐานใน Gate 4
18. หลัง Gate 4 ผ่าน จึงทำ XP-420B Hardware Gate
19. หลัง Gate 5 ผ่าน จึงทำ Operational/Security Gate
20. หลัง Gate 6 ผ่าน จึงทำ UAT
21. เริ่ม Pilot จำกัดหนึ่งจุดพิมพ์เมื่อได้รับ `PILOT_APPROVED` เท่านั้น

---

# 9. สิ่งที่ Developer ห้ามทำ

- ห้ามแก้ Requirement ให้เข้ากับโค้ด
- ห้ามอ้าง test เก่ากับ commit ใหม่
- ห้ามอ้าง local test เป็น remote CI
- ห้ามอ้าง mock print เป็น hardware verification
- ห้ามอ้าง build สำเร็จว่า UX ผ่าน
- ห้ามอ้างจำนวน test โดยไม่ระบุ test ที่ครอบคลุม Requirement
- ห้ามซ่อนข้อค้างไว้ใน comment
- ห้ามเพิ่ม allowlist เพื่อหลบ i18n โดยไม่มี QA อนุมัติ
- ห้ามเปิด legacy printer flag ใน Pilot
- ห้ามนำ Offline behavior กลับมา
- ห้ามให้ Browser/PWA เข้าถึง USB printer โดยตรง
- ห้าม retry งานพิมพ์ที่ไม่ทราบว่าส่งออกแล้วหรือยัง
- ห้าม push, deploy, migrate Production หรือ rotate secret โดยไม่มีอำนาจ
- ห้ามประกาศ Gate ผ่านแทน QA

---

# 10. ข้อกำหนดที่ต้องยืนยันก่อน Hardware/Production

รายการต่อไปนี้ไม่ขวาง Gate 1–3 แต่ต้องยืนยันก่อน Gate 5:

1. Production Gateway host เป็น Raspberry Pi/Linux รุ่นใด
2. Linux distribution/version
3. CUPS queue name
4. Label width/height และ gap
5. XP-420B DPI/firmware/driver mode
6. จำนวน label ต่อวันและ peak rate
7. Pilot site/network/VLAN
8. Production hostname/HTTPS certificate owner
9. Backup retention, RPO และ RTO
10. ผู้มีอำนาจ resolve `ACK_UNKNOWN`

ห้าม Developer เดาค่าเหล่านี้แล้วฝังลง Production code ให้ใช้ configuration และ fail-fast validation

---

# 11. Definition of Done ของระบบ

ระบบจะถือว่า “พร้อมให้คนทดสอบ Pilot” เมื่อ:

- Gate 1–6 ผ่าน
- Remote CI ผ่านที่ commit SHA ที่จะ Deploy
- Chrome/PWA device matrix ผ่าน
- XP-420B เครื่องจริงผ่าน
- Backup restore ผ่าน
- Monitoring/alert ผ่าน
- SOP พร้อม
- Security assessment ไม่มี P0/P1
- UAT plan และ stop conditions พร้อม

ระบบจะถือว่า “พร้อมใช้งาน Production” ได้หลัง Limited Pilot สำเร็จและมีการอนุมัติแยกต่างหากเท่านั้น

---

# 12. QA Sign-off

| Gate | ผล | Commit SHA | หลักฐาน | ผู้ตรวจ | วันที่ |
|---|---|---|---|---|---|
| Gate 1 | NOT APPROVED | | | | |
| Gate 2 | NOT STARTED | | | | |
| Gate 3 | NOT STARTED | | | | |
| Gate 4 | NOT STARTED | | | | |
| Gate 5 | NOT STARTED | | | | |
| Gate 6 | NOT STARTED | | | | |
| Gate 7/UAT | NOT STARTED | | | | |

จนกว่าตารางนี้จะมีหลักฐานและผู้ตรวจลงผล ห้ามเปลี่ยนสถานะเอง

---

# 13. Addendum: Browser Print Mode (2026-07-24)

เอกสาร [`MACOS_BROWSER_PRINT_DIRECTIVE.md`](MACOS_BROWSER_PRINT_DIRECTIVE.md)
(REQUIRED / BLOCKING / LOCKED) เป็น **ส่วนขยายอย่างเป็นทางการของ directive ฉบับนี้**
ว่าด้วยโหมดพิมพ์ `BROWSER_DIALOG`:

- เพิ่มโหมดพิมพ์ `BROWSER_DIALOG` (macOS system print dialog บน Mac ที่เสียบ XP-420B
  และเปิด PWA เครื่องเดียวกัน) โดย **คง `PRINT_GATEWAY` เดิมไว้ครบถ้วน** — ห้ามลบ
  ลดความปลอดภัย หรือเปลี่ยนความหมายของ Print Gateway
- Browser พิสูจน์ผล hardware ไม่ได้ → สถานะจำกัดที่
  `CREATED → DIALOG_OPENED → USER_CONFIRMED | CANCELLED` (ผู้ใช้ยืนยันเอง)
  และ**ห้ามแตะ** `printedAt`/`reprintCount`/สถานะ Gateway ใด ๆ
- เปิดใช้หลัง feature flag `CSSD_BROWSER_PRINT_ENABLED` (default ปิดทั้ง backend + PWA)
- ข้อกำหนดโดยละเอียด (data model, API, audit, reprint, UX, label, security, tests,
  hardware acceptance บน Mac + XP-420B, รูปแบบรายงาน) ให้ยึดตามเอกสาร addendum ฉบับเต็ม
- เมื่อขัดแย้งกับข้อความเดิมในเอกสารนี้ที่ระบุว่า Print Gateway เป็น "ทางเดียว/เท่านั้น"
  ให้ตีความว่า: Print Gateway เป็นเส้นทางเดียวที่ **hardware-confirm ผลพิมพ์ได้**
  ส่วน `BROWSER_DIALOG` เป็นโหมดเสริมที่บันทึกผลแบบ user-confirmed เท่านั้น
