import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/features/settings/presentation/pages/settings_page.dart';

// #3 — PWA production HTTPS enforcement (ให้ตรง FIX-06 ฝั่ง Gateway)
// 2.3 — production API URL pin/allowlist
void main() {
  const allow = {'api.example.com', 'cssd-api.onrender.com'};

  group('serverUrlValidationError', () {
    test('https ผ่านเสมอบน dev (ไม่บังคับ allowlist)', () {
      expect(serverUrlValidationError('https://api.example.com', isRelease: false), isNull);
      expect(serverUrlValidationError('https://any-host.example.org', isRelease: false), isNull);
    });

    test('https บน release ผ่านเฉพาะ host ใน allowlist', () {
      expect(
          serverUrlValidationError('https://api.example.com',
              isRelease: true, allowedHosts: allow),
          isNull);
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

    // 2.3 — pin/allowlist: release ต้องชี้ไปเฉพาะโฮสต์ที่อนุมัติ (แม้เป็น https)
    group('release allowlist (pin)', () {
      test('https host นอก allowlist → error (กัน harvest JWT/ข้อมูล)', () {
        expect(
            serverUrlValidationError('https://evil.attacker.com',
                isRelease: true, allowedHosts: allow),
            isNotNull);
      });
      test('https host ใน allowlist → ok (ตัวพิมพ์ใหญ่/เล็กไม่สำคัญ)', () {
        expect(
            serverUrlValidationError('https://API.Example.com',
                isRelease: true, allowedHosts: allow),
            isNull);
        expect(
            serverUrlValidationError('https://cssd-api.onrender.com',
                isRelease: true, allowedHosts: allow),
            isNull);
      });
      test('ค่า default allowlist = host ของ kDefaultServerUrl', () {
        // ไม่ส่ง allowedHosts → ใช้ productionAllowedHosts() (ค่า default)
        final hosts = productionAllowedHosts();
        expect(hosts, contains('cssd-api.onrender.com'));
        expect(
            serverUrlValidationError('https://cssd-api.onrender.com', isRelease: true),
            isNull);
        expect(
            serverUrlValidationError('https://somewhere-else.example.com', isRelease: true),
            isNotNull);
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
