import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/app_localizations.dart';

/// ประเภท error ของกล้อง QR — แยกให้ครบตาม master directive §4B.1.4 เพื่อแสดง
/// ข้อความที่ผู้ใช้เข้าใจและกู้คืนได้ถูกทาง โดยเฉพาะ Safari/iOS WebKit ที่ `getUserMedia`
/// คืน `DOMException` ชื่อต่างกัน (NotAllowedError / NotFoundError / NotReadableError ฯลฯ)
enum ScannerErrorKind {
  permissionDenied,
  permissionRevoked,
  insecureContext,
  noCamera,
  cameraInUse,
  unsupportedConstraint,
  generic,
}

/// สถานะ UI ของกล้องที่ผู้ใช้เห็น (§4B.1.6) — ห้ามปล่อยจอดำโดยไม่มีคำอธิบาย/ปุ่มลองใหม่
enum ScannerUiState { initializing, ready, denied, unavailable, interrupted, retrying }

/// จำแนก error ของกล้องเป็น [ScannerErrorKind] — **pure function** (unit-test ได้)
///
/// รองรับทั้ง native ([MobileScannerException.errorCode]) และ web/WebKit ที่ error
/// ถูกห่อมาพร้อม `DOMException` name/message ใน `errorDetails` หรือใน `toString()`
/// [wasGranted] = เคยได้สิทธิ์กล้องมาก่อนหรือไม่ (แยก "ถูกเพิกถอน" ออกจาก "ถูกปฏิเสธ")
ScannerErrorKind classifyScannerError(Object error, {bool wasGranted = false}) {
  MobileScannerErrorCode? code;
  String haystack;
  if (error is MobileScannerException) {
    code = error.errorCode;
    haystack =
        '${error.errorDetails?.code ?? ''} ${error.errorDetails?.message ?? ''}'
            .toLowerCase();
  } else {
    haystack = error.toString().toLowerCase();
  }
  bool has(String s) => haystack.contains(s);

  // 1) secure context / HTTPS — getUserMedia ทำงานเฉพาะ secure context
  if (has('securityerror') ||
      has('secure context') ||
      has('insecure') ||
      has('https')) {
    return ScannerErrorKind.insecureContext;
  }
  // 2) permission — NotAllowedError (deny/revoke) หรือ code permissionDenied
  if (code == MobileScannerErrorCode.permissionDenied ||
      has('notallowederror') ||
      has('permissiondenied') ||
      has('permission denied') ||
      has('permission dismissed')) {
    return wasGranted
        ? ScannerErrorKind.permissionRevoked
        : ScannerErrorKind.permissionDenied;
  }
  // 3) กล้องถูกยึด/เปิดไม่ได้ — NotReadableError / TrackStartError / in use
  if (has('notreadableerror') ||
      has('trackstarterror') ||
      has('could not start video source') ||
      has('in use') ||
      has('already in use') ||
      has('aborterror')) {
    return ScannerErrorKind.cameraInUse;
  }
  // 4) constraint ที่อุปกรณ์ไม่รองรับ — OverconstrainedError
  if (has('overconstrained') ||
      has('constraintnotsatisfied') ||
      has('unsupportedconstraint')) {
    return ScannerErrorKind.unsupportedConstraint;
  }
  // 5) ไม่มีกล้อง / อุปกรณ์ไม่รองรับการสแกน
  if (code == MobileScannerErrorCode.unsupported ||
      has('notfounderror') ||
      has('devicesnotfounderror') ||
      has('no camera') ||
      has('notfound')) {
    return ScannerErrorKind.noCamera;
  }
  // 6) อื่น ๆ (รวม genericError / controller ยังไม่พร้อม)
  return ScannerErrorKind.generic;
}

/// ข้อความ error ของกล้อง (i18n) — ทุกภาษาอยู่ใน ARB ตาม §4B.1.13
String scannerErrorMessage(AppLocalizations l10n, ScannerErrorKind kind) {
  switch (kind) {
    case ScannerErrorKind.permissionDenied:
      return l10n.scanErrPermissionDenied;
    case ScannerErrorKind.permissionRevoked:
      return l10n.scanErrPermissionRevoked;
    case ScannerErrorKind.insecureContext:
      return l10n.scanErrInsecureContext;
    case ScannerErrorKind.noCamera:
      return l10n.scanErrNoCamera;
    case ScannerErrorKind.cameraInUse:
      return l10n.scanErrCameraInUse;
    case ScannerErrorKind.unsupportedConstraint:
      return l10n.scanErrUnsupportedConstraint;
    case ScannerErrorKind.generic:
      return l10n.scanErrGeneric;
  }
}

/// true = error นี้ต้องให้ผู้ใช้ไปเปิดสิทธิ์เอง (แสดงปุ่ม "เปิดการตั้งค่า" บน native)
/// — retry เฉย ๆ แก้ไม่ได้ถ้าสิทธิ์ถูกปฏิเสธถาวร
bool scannerNeedsPermissionAction(ScannerErrorKind kind) =>
    kind == ScannerErrorKind.permissionDenied ||
    kind == ScannerErrorKind.permissionRevoked;

/// กัน frame QR เดิมถูกอ่านซ้ำแล้วยิง lookup/mutation ซ้ำ (§4B.1.11) — cooldown ต่อ id
/// แยกเป็นคลาสเล็ก ๆ ที่รับ `now` เข้ามา เพื่อ unit-test ได้โดยไม่พึ่งนาฬิกาจริง
class ScanCooldown {
  ScanCooldown({this.window = const Duration(seconds: 3)});
  final Duration window;
  final Map<String, DateTime> _last = {};

  /// true = ควรประมวลผล id นี้ (ไม่ใช่การอ่าน frame เดิมซ้ำภายในช่วง cooldown)
  bool shouldProcess(String id, DateTime now) {
    final prev = _last[id];
    if (prev != null && now.difference(prev) < window) return false;
    _last[id] = now;
    return true;
  }

  void reset() => _last.clear();
}
