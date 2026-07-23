import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/features/settings/presentation/pages/settings_page.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// #3 — PWA production HTTPS enforcement (ให้ตรง FIX-06 ฝั่ง Gateway)
// 2.3 — production API URL pin/allowlist  (ข้อความ error ผ่าน gen-l10n)
void main() {
  const allow = {'api.example.com', 'cssd-api.onrender.com'};
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('th'));
  });

  // wrapper ใส่ l10n ให้อัตโนมัติ
  String? err(String url, {required bool release, Set<String>? hosts}) =>
      serverUrlValidationError(url,
          isRelease: release, l10n: l10n, allowedHosts: hosts);

  group('serverUrlValidationError', () {
    test('https ผ่านเสมอบน dev (ไม่บังคับ allowlist)', () {
      expect(err('https://api.example.com', release: false), isNull);
      expect(err('https://any-host.example.org', release: false), isNull);
    });

    test('https บน release ผ่านเฉพาะ host ใน allowlist', () {
      expect(err('https://api.example.com', release: true, hosts: allow), isNull);
    });

    test('รูปแบบผิด → error', () {
      expect(err('ftp://x', release: false), isNotNull);
      expect(err('not a url', release: false), isNotNull);
    });

    group('release (production)', () {
      test('http localhost → error (https-only)', () {
        expect(err('http://localhost:3000', release: true), isNotNull);
      });
      test('http private LAN → error (Private IP ไม่ยกเว้น)', () {
        expect(err('http://192.168.1.10:3000', release: true), isNotNull);
        expect(err('http://10.0.0.5', release: true), isNotNull);
      });
      test('http public → error', () {
        expect(err('http://api.example.com', release: true), isNotNull);
      });
    });

    // 2.3 — pin/allowlist: release ต้องชี้ไปเฉพาะโฮสต์ที่อนุมัติ (แม้เป็น https)
    group('release allowlist (pin)', () {
      test('https host นอก allowlist → error (กัน harvest JWT/ข้อมูล)', () {
        expect(err('https://evil.attacker.com', release: true, hosts: allow),
            isNotNull);
      });
      test('https host ใน allowlist → ok (ตัวพิมพ์ใหญ่/เล็กไม่สำคัญ)', () {
        expect(err('https://API.Example.com', release: true, hosts: allow), isNull);
        expect(err('https://cssd-api.onrender.com', release: true, hosts: allow),
            isNull);
      });
      test('ค่า default allowlist = host ของ kDefaultServerUrl', () {
        final hosts = productionAllowedHosts();
        expect(hosts, contains('cssd-api.onrender.com'));
        expect(err('https://cssd-api.onrender.com', release: true), isNull);
        expect(err('https://somewhere-else.example.com', release: true), isNotNull);
      });
    });

    group('debug/dev', () {
      test('http localhost/emulator → ok', () {
        expect(err('http://localhost:3000', release: false), isNull);
        expect(err('http://127.0.0.1:3000', release: false), isNull);
        expect(err('http://10.0.2.2:3000', release: false), isNull);
      });
      test('http private LAN → ok (ทดสอบในตึก)', () {
        expect(err('http://192.168.1.10:3000', release: false), isNull);
        expect(err('http://172.16.5.5', release: false), isNull);
      });
      test('http public → error (ปลายทางสาธารณะต้อง https)', () {
        expect(err('http://api.example.com', release: false), isNotNull);
      });
    });
  });
}
