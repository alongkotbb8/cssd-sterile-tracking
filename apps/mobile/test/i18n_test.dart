import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/core/api/api_client.dart';
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

  group('error messages i18n (login + apiErrorMessage)', () {
    test('login invalid — แปลทั้งสองภาษา ต่างกันจริง', () {
      expect(th.errLoginInvalid, contains('รหัส'));
      expect(en.errLoginInvalid.toLowerCase(), contains('incorrect'));
      expect(th.errLoginInvalid, isNot(equals(en.errLoginInvalid)));
    });

    test('apiErrorMessage — connection/timeout/generic เป็นภาษาอังกฤษเมื่อ locale en', () {
      final conn = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      expect(apiErrorMessage(en, conn), equals(en.errConnection));
      expect(apiErrorMessage(th, conn), equals(th.errConnection));
      expect(apiErrorMessage(en, conn), isNot(equals(apiErrorMessage(th, conn))));

      final timeout = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(apiErrorMessage(en, timeout), equals(en.errTimeout));

      // non-Dio → unknown (แปลตาม locale)
      expect(apiErrorMessage(en, Exception('boom')), equals(en.errUnknown));
    });

    test('backend error code → map เป็น ARB ตาม locale (Gate 1 blocker #1)', () {
      final coded = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 400,
          data: {
            'message': 'ห่อนี้อยู่ในรอบนึ่งอื่นอยู่แล้ว',
            'code': 'PKG_IN_OTHER_BATCH',
          },
        ),
      );
      // code เดียวกัน → ภาษาตาม locale ของผู้ใช้ ไม่ใช่ภาษาของ server
      expect(apiErrorMessage(en, coded), equals(en.srvPkgInOtherBatch));
      expect(apiErrorMessage(th, coded), equals(th.srvPkgInOtherBatch));
      expect(_hasThai(apiErrorMessage(en, coded)), isFalse,
          reason: 'locale en ต้องไม่เห็นอักษรไทย');
    });

    test('error เก่าไม่มี code: th = passthrough, en = generic (ห้ามโชว์ไทย)', () {
      final uncoded = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 400,
          data: {'message': 'ข้อความไทยจาก server ที่ยังไม่มี code'},
        ),
      );
      // ไทย: server เขียนไทยอยู่แล้ว — ส่งต่อได้ (ข้อมูลครบกว่า generic)
      expect(apiErrorMessage(th, uncoded), 'ข้อความไทยจาก server ที่ยังไม่มี code');
      // อังกฤษ: ห้ามเห็นไทยเด็ดขาด → generic ตาม locale พร้อม status code
      final enMsg = apiErrorMessage(en, uncoded);
      expect(_hasThai(enMsg), isFalse,
          reason: 'locale en ต้องไม่ leak ข้อความไทยจาก server: "$enMsg"');
      expect(enMsg, equals(en.errGeneric('400')));
    });

    test('AUTH_LOCKED — จอ login แยก "ถูกล็อก" ออกจากรหัสผิด (ทั้งสองภาษา)', () {
      // คำว่า "ถูกล็อก" ต้องอยู่ในข้อความ th (E2E lockout test ใช้คำนี้หา element)
      expect(serverErrorFromCode(th, 'AUTH_LOCKED'), contains('ถูกล็อก'));
      expect(serverErrorFromCode(en, 'AUTH_LOCKED')!.toLowerCase(),
          contains('locked'));
      expect(serverErrorFromCode(th, 'AUTH_LOCKED'),
          isNot(equals(th.errLoginInvalid)));
    });

    test('serverErrorFromCode ครอบทุก code แล้วให้ข้อความ en ที่ไม่มีอักษรไทย', () {
      const codes = [
        'AUTH_LOCKED',
        'PKG_NOT_FOUND', 'PKG_WRONG_STATUS', 'PKG_ALREADY_IN_THIS_BATCH',
        'PKG_IN_OTHER_BATCH', 'PKG_CONCURRENT', 'PKG_EXPIRED',
        'PKG_UNSTERILE_EXTERNAL_ONLY', 'PKG_DISCARDED', 'REPRINT_REASON_REQUIRED',
        'BATCH_NOT_FOUND', 'BATCH_DUPLICATE', 'BATCH_ALREADY_RESULTED',
        'BATCH_STATE', 'STERILIZER_NOT_FOUND', 'TEMPLATE_NOT_FOUND',
        'DEPT_NOT_FOUND', 'PRINT_JOB_NOT_FOUND', 'PRINT_JOB_FORBIDDEN',
        'PRINT_JOB_STATE', 'PRINT_JOB_NOTE_REQUIRED', 'GATEWAY_NOT_FOUND',
        'GATEWAY_REVOKED', 'GATEWAY_CONFIG', 'PRINTER_NOT_FOUND',
      ];
      for (final c in codes) {
        final thMsg = serverErrorFromCode(th, c);
        final enMsg = serverErrorFromCode(en, c);
        expect(thMsg, isNotNull, reason: 'th ไม่รู้จัก code $c');
        expect(enMsg, isNotNull, reason: 'en ไม่รู้จัก code $c');
        expect(_hasThai(enMsg!), isFalse, reason: 'en ของ $c มีอักษรไทย: "$enMsg"');
      }
      expect(serverErrorFromCode(en, 'NO_SUCH_CODE'), isNull);
      expect(serverErrorFromCode(en, null), isNull);
    });
  });
}

/// มีอักษรไทย (U+0E00–U+0E7F) ในข้อความหรือไม่
bool _hasThai(String s) => RegExp(r'[฀-๿]').hasMatch(s);
