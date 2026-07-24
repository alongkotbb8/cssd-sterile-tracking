import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feature flags ของแอป — คุมการมองเห็นเส้นทาง legacy ใน Pilot/production
///
/// **legacy direct print** (Bluetooth FlashLabel A318BT / System·Browser print):
/// เส้นทางพิมพ์หลักของ Pilot คือ **Print Gateway → Linux/CUPS → XP-420B** เท่านั้น
/// (สร้าง Print Job แล้ว Gateway พิมพ์/ACK — บันทึกประวัติ + ยืนยันพิมพ์จริงได้)
/// direct-print เดิมไม่บันทึกประวัติและยืนยันไม่ได้ จึง **ซ่อนจากผู้ใช้ทั่วไปใน Pilot**
///
/// ค่าเริ่มต้น: **ปิดใน release/Pilot** (patient safety — กันผู้ใช้เข้าใจผิดว่าพิมพ์ผ่าน
/// Gateway), เปิดใน debug (สะดวกพัฒนา) ; override ตอน build ด้วย
/// `--dart-define=CSSD_ENABLE_LEGACY_PRINT=true` (เก็บโค้ด legacy ไว้ ไม่ได้ลบ —
/// ยังไม่ลบจนกว่า XP-420B/Linux จะผ่าน Hardware Gate)
const bool _legacyPrintOptIn =
    bool.fromEnvironment('CSSD_ENABLE_LEGACY_PRINT', defaultValue: false);

/// ตรรกะบริสุทธิ์ (unit-test ได้): legacy เปิดเมื่อ **ไม่ใช่ release** หรือ opt-in ชัดเจน
/// → release/Pilot (releaseMode=true, optIn=false) = **ปิด** เสมอ
bool computeLegacyDirectPrintEnabled(
        {required bool releaseMode, bool optIn = _legacyPrintOptIn}) =>
    optIn || !releaseMode;

/// true = แสดง UI legacy direct-print ให้ผู้ใช้ (debug หรือ opt-in ชัดเจน)
final bool kLegacyDirectPrintEnabled =
    computeLegacyDirectPrintEnabled(releaseMode: kReleaseMode);

/// provider ครอบ [kLegacyDirectPrintEnabled] เพื่อ override ได้ในเทส
/// (feature-flag test ยืนยันว่า Pilot production build ไม่โชว์ตัวเลือกเครื่องพิมพ์ legacy)
final legacyDirectPrintEnabledProvider =
    Provider<bool>((ref) => kLegacyDirectPrintEnabled);

/// **Browser print (`BROWSER_DIALOG`)** — MACOS_BROWSER_PRINT_DIRECTIVE.md §4
///
/// เปิด UI พิมพ์ผ่าน macOS system print dialog (Mac ที่เสียบ XP-420B และเปิด PWA
/// เครื่องเดียวกัน) — default **ปิด** เสมอ (production ห้ามเปิดโดยไม่ตั้งใจ);
/// เปิดตอน build ด้วย `--dart-define=CSSD_BROWSER_PRINT_ENABLED=true`
/// backend ตรวจ flag ฝั่งตัวเองซ้ำทุก endpoint — การซ่อนปุ่มนี้ไม่ใช่การป้องกันหลัก
const bool kBrowserPrintEnabled =
    bool.fromEnvironment('CSSD_BROWSER_PRINT_ENABLED', defaultValue: false);

/// provider ครอบ [kBrowserPrintEnabled] เพื่อ override ได้ในเทส
/// (flag ปิด = ไม่มีปุ่ม/ประวัติ browser print ปรากฏใน UI เลย)
final browserPrintEnabledProvider = Provider<bool>((ref) => kBrowserPrintEnabled);

/// ขนาด label จริง (มม.) — MACOS_BROWSER_PRINT_DIRECTIVE.md §11: เริ่มต้น 60×40
/// และปรับได้ผ่าน configuration (dart-define) ใช้ทั้ง preview bitmap และ
/// ขนาดหน้ากระดาษ PDF ตอนเปิด print dialog (1 หน้า = 1 label ขนาดจริง)
const int kLabelWidthMm =
    int.fromEnvironment('CSSD_LABEL_WIDTH_MM', defaultValue: 60);
const int kLabelHeightMm =
    int.fromEnvironment('CSSD_LABEL_HEIGHT_MM', defaultValue: 40);
