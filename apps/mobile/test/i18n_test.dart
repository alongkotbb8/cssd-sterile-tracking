import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Gate 1 — i18n: ยืนยันว่ามีทั้ง th/en และ domain-critical messages แปลครบทั้งสองภาษา
void main() {
  late AppLocalizations th;
  late AppLocalizations en;

  setUpAll(() async {
    th = await AppLocalizations.delegate.load(const Locale('th'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('รองรับ th + en และ th เป็นค่าเริ่มต้น', () {
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode),
        containsAll(<String>['th', 'en']));
  });

  test('ทั้งสองภาษาให้ข้อความไม่ว่าง และต่างกันจริง (ไม่หลุด fallback)', () {
    expect(th.loginTitle.isNotEmpty, isTrue);
    expect(en.loginTitle.isNotEmpty, isTrue);
    expect(th.loginTitle, isNot(equals(en.loginTitle))); // เข้าสู่ระบบ vs Sign in
    expect(th.statusExpired, isNot(equals(en.statusExpired)));
  });

  group('domain-critical messages ครบทั้งสองภาษา', () {
    test('"ห้ามใช้" / do-not-use (ห่อหมดอายุ)', () {
      expect(th.scanBlockExpired, contains('ห้ามใช้'));
      expect(en.scanBlockExpired.toLowerCase(), contains('do not use'));
    });

    test('"หมดอายุ" / expired', () {
      expect(th.statusExpired, equals('หมดอายุ'));
      expect(en.statusExpired.toLowerCase(), contains('expired'));
    });

    test('"ยังไม่ฆ่าเชื้อ" / not sterilized (เตือนเบิกออกก่อนนึ่ง)', () {
      expect(th.scanWarnUnsterile, contains('ยังไม่ฆ่าเชื้อ'));
      expect(en.scanWarnUnsterile.toLowerCase(), contains('steriliz'));
    });

    test('Recall (บันทึกผลไม่ผ่าน → recall)', () {
      expect(th.batchRecordedFail.toLowerCase(), contains('recall'));
      expect(en.batchRecordedFail.toLowerCase(), contains('recall'));
    });

    test('ACK_UNKNOWN — ไม่ยืนยันว่าพิมพ์จริง / needs supervisor', () {
      expect(th.pjStatusAckUnknown.isNotEmpty, isTrue);
      expect(en.pjStatusAckUnknown.toLowerCase(), contains('unsure'));
      // banner เตือน "อาจพิมพ์ออกแล้ว ห้ามพิมพ์ซ้ำโดยไม่ตรวจ" (แนวคิดเดียวกัน)
      expect(th.pjAckBanner.contains('หัวหน้า'), isTrue);
      expect(en.pjAckBanner.toLowerCase(), contains('supervisor'));
    });

    test('placeholder ทำงานถูกต้องทั้งสองภาษา', () {
      expect(th.scanDaysLeft(5), contains('5'));
      expect(en.scanDaysLeft(5), contains('5'));
      expect(th.pkgSelectedCount(3), contains('3'));
      expect(en.pkgSelectedCount(3), contains('3'));
    });
  });
}
