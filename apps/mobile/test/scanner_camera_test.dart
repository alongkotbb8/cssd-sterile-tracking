import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:cssd_mobile/features/scan/presentation/scanner_camera.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Gate 4 §4B.1 — Safari/iOS QR scanner: จำแนก error ของกล้อง + cooldown กัน frame ซ้ำ
// (logic บริสุทธิ์ unit-test ได้; camera hardware จริงตรวจใน Gate 4 บนอุปกรณ์)
MobileScannerException _ex(MobileScannerErrorCode code, {String? message}) =>
    MobileScannerException(
      errorCode: code,
      errorDetails:
          message == null ? null : MobileScannerErrorDetails(message: message),
    );

void main() {
  group('classifyScannerError — native error codes', () {
    test('permissionDenied → denied (ยังไม่เคยได้สิทธิ์)', () {
      expect(classifyScannerError(_ex(MobileScannerErrorCode.permissionDenied)),
          ScannerErrorKind.permissionDenied);
    });

    test('permissionDenied + wasGranted → revoked (ถูกเพิกถอนระหว่างใช้งาน)', () {
      expect(
        classifyScannerError(_ex(MobileScannerErrorCode.permissionDenied),
            wasGranted: true),
        ScannerErrorKind.permissionRevoked,
      );
    });

    test('unsupported code → noCamera (อุปกรณ์สแกนไม่ได้)', () {
      expect(classifyScannerError(_ex(MobileScannerErrorCode.unsupported)),
          ScannerErrorKind.noCamera);
    });

    test('genericError ไม่มี detail → generic', () {
      expect(classifyScannerError(_ex(MobileScannerErrorCode.genericError)),
          ScannerErrorKind.generic);
    });
  });

  group('classifyScannerError — web/Safari WebKit DOMException', () {
    test('NotAllowedError → denied; + wasGranted → revoked', () {
      final e = _ex(MobileScannerErrorCode.genericError,
          message: 'NotAllowedError: Permission denied by user');
      expect(classifyScannerError(e), ScannerErrorKind.permissionDenied);
      expect(classifyScannerError(e, wasGranted: true),
          ScannerErrorKind.permissionRevoked);
    });

    test('SecurityError / secure context → insecureContext', () {
      expect(
        classifyScannerError('NotSupportedError: only secure context (https)'),
        ScannerErrorKind.insecureContext,
      );
      expect(
        classifyScannerError(
            _ex(MobileScannerErrorCode.genericError, message: 'SecurityError')),
        ScannerErrorKind.insecureContext,
      );
    });

    test('NotFoundError → noCamera', () {
      expect(
        classifyScannerError(
            _ex(MobileScannerErrorCode.genericError, message: 'NotFoundError')),
        ScannerErrorKind.noCamera,
      );
    });

    test('NotReadableError / TrackStartError → cameraInUse', () {
      expect(
        classifyScannerError(_ex(MobileScannerErrorCode.genericError,
            message: 'NotReadableError: Could not start video source')),
        ScannerErrorKind.cameraInUse,
      );
      expect(
        classifyScannerError('TrackStartError'),
        ScannerErrorKind.cameraInUse,
      );
    });

    test('OverconstrainedError → unsupportedConstraint', () {
      expect(
        classifyScannerError(_ex(MobileScannerErrorCode.genericError,
            message: 'OverconstrainedError: facingMode')),
        ScannerErrorKind.unsupportedConstraint,
      );
    });

    test('ข้อความแปลก ๆ → generic', () {
      expect(classifyScannerError('boom something odd'),
          ScannerErrorKind.generic);
    });
  });

  group('scannerNeedsPermissionAction', () {
    test('เฉพาะ denied/revoked ต้องให้ผู้ใช้ไปเปิดสิทธิ์', () {
      expect(scannerNeedsPermissionAction(ScannerErrorKind.permissionDenied),
          isTrue);
      expect(scannerNeedsPermissionAction(ScannerErrorKind.permissionRevoked),
          isTrue);
      expect(
          scannerNeedsPermissionAction(ScannerErrorKind.noCamera), isFalse);
      expect(scannerNeedsPermissionAction(ScannerErrorKind.cameraInUse),
          isFalse);
    });
  });

  group('scannerErrorMessage i18n', () {
    late AppLocalizations th;
    late AppLocalizations en;
    setUpAll(() async {
      th = await AppLocalizations.delegate.load(const Locale('th'));
      en = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('ทุกชนิดมีข้อความไม่ว่างทั้งสองภาษา และต่างภาษากันจริง', () {
      for (final kind in ScannerErrorKind.values) {
        final tMsg = scannerErrorMessage(th, kind);
        final eMsg = scannerErrorMessage(en, kind);
        expect(tMsg.isNotEmpty, isTrue, reason: 'th $kind');
        expect(eMsg.isNotEmpty, isTrue, reason: 'en $kind');
        expect(tMsg, isNot(equals(eMsg)), reason: 'th≠en $kind');
      }
    });

    test('denied ภาษาอังกฤษพูดถึง permission; insecure พูดถึง https', () {
      expect(scannerErrorMessage(en, ScannerErrorKind.permissionDenied)
          .toLowerCase(), contains('permission'));
      expect(scannerErrorMessage(en, ScannerErrorKind.insecureContext)
          .toLowerCase(), contains('https'));
    });
  });

  group('ScanCooldown — กัน frame QR เดิมยิงซ้ำ (§4B.1.11)', () {
    final t0 = DateTime(2026, 7, 23, 10, 0, 0);

    test('frame เดิมภายในหน้าต่าง cooldown ถูกกัน แต่ผ่านเมื่อพ้นเวลา', () {
      final c = ScanCooldown(window: const Duration(seconds: 3));
      expect(c.shouldProcess('PKG-1', t0), isTrue);
      expect(c.shouldProcess('PKG-1', t0.add(const Duration(seconds: 1))), isFalse);
      expect(c.shouldProcess('PKG-1', t0.add(const Duration(seconds: 2))), isFalse);
      expect(c.shouldProcess('PKG-1', t0.add(const Duration(seconds: 4))), isTrue);
    });

    test('id ต่างกันไม่กันกัน', () {
      final c = ScanCooldown();
      expect(c.shouldProcess('PKG-1', t0), isTrue);
      expect(c.shouldProcess('PKG-2', t0), isTrue);
    });

    test('reset แล้วสแกน id เดิมได้ทันที (หลังล้างรายการ/สลับโหมด)', () {
      final c = ScanCooldown();
      expect(c.shouldProcess('PKG-1', t0), isTrue);
      expect(c.shouldProcess('PKG-1', t0.add(const Duration(seconds: 1))), isFalse);
      c.reset();
      expect(c.shouldProcess('PKG-1', t0.add(const Duration(seconds: 1))), isTrue);
    });
  });
}
