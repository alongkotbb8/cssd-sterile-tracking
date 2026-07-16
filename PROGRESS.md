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
