import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/features/settings/presentation/pages/settings_page.dart';

// #3 — PWA production HTTPS enforcement (ให้ตรง FIX-06 ฝั่ง Gateway)
void main() {
  group('serverUrlValidationError', () {
    test('https ผ่านเสมอ (ทั้ง release และ dev)', () {
      expect(serverUrlValidationError('https://api.example.com', isRelease: true), isNull);
      expect(serverUrlValidationError('https://api.example.com', isRelease: false), isNull);
    });

    test('รูปแบบผิด → error', () {
      expect(serverUrlValidationError('ftp://x', isRelease: false), isNotNull);
      expect(serverUrlValidationError('not a url', isRelease: false), isNotNull);
    });

    group('release (production)', () {
      test('http localhost → error (https-only)', () {
        expect(serverUrlValidationError('http://localhost:3000', isRelease: true), isNotNull);
      });
      test('http private LAN → error (Private IP ไม่ยกเว้น)', () {
        expect(serverUrlValidationError('http://192.168.1.10:3000', isRelease: true), isNotNull);
        expect(serverUrlValidationError('http://10.0.0.5', isRelease: true), isNotNull);
      });
      test('http public → error', () {
        expect(serverUrlValidationError('http://api.example.com', isRelease: true), isNotNull);
      });
    });

    group('debug/dev', () {
      test('http localhost/emulator → ok', () {
        expect(serverUrlValidationError('http://localhost:3000', isRelease: false), isNull);
        expect(serverUrlValidationError('http://127.0.0.1:3000', isRelease: false), isNull);
        expect(serverUrlValidationError('http://10.0.2.2:3000', isRelease: false), isNull);
      });
      test('http private LAN → ok (ทดสอบในตึก)', () {
        expect(serverUrlValidationError('http://192.168.1.10:3000', isRelease: false), isNull);
        expect(serverUrlValidationError('http://172.16.5.5', isRelease: false), isNull);
      });
      test('http public → error (ปลายทางสาธารณะต้อง https)', () {
        expect(serverUrlValidationError('http://api.example.com', isRelease: false), isNotNull);
      });
    });
  });
}
