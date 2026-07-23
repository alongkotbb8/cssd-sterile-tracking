import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Master directive A2.2/A2.3 — cross-language contract:
// ทุก "client" error code ในทะเบียนกลาง (packages/shared/error-codes.json)
// ต้องถูก map โดย serverErrorFromCode ทั้ง th และ en และ en ต้องไม่มีอักษรไทย
// (ฝั่ง backend มี jest ตรวจกลับว่า code ที่ throw ทุกตัวอยู่ในทะเบียน)
//
// จับเคส: backend เพิ่ม client code ใหม่ → เทสนี้ FAIL จนกว่า client จะ map
final _thai = RegExp(r'[฀-๿]');

void main() {
  late AppLocalizations th;
  late AppLocalizations en;
  late List<String> clientCodes;

  setUpAll(() async {
    th = await AppLocalizations.delegate.load(const Locale('th'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
    // อ่านทะเบียนกลางจาก repo (SSOT เดียวกับ backend) — path จาก apps/mobile
    final f = File('../../packages/shared/error-codes.json');
    expect(f.existsSync(), isTrue,
        reason: 'ไม่พบ packages/shared/error-codes.json (รันจาก apps/mobile)');
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    clientCodes = (json['client'] as List).cast<String>();
  });

  test('มี client code ในทะเบียนพอสมควร (sanity)', () {
    expect(clientCodes.length, greaterThan(10));
  });

  test('ทุก client code map ได้ทั้ง th + en (กัน backend เพิ่ม code ที่ client ไม่รู้จัก)',
      () {
    final missingTh = <String>[];
    final missingEn = <String>[];
    for (final code in clientCodes) {
      if (serverErrorFromCode(th, code) == null) missingTh.add(code);
      if (serverErrorFromCode(en, code) == null) missingEn.add(code);
    }
    expect(missingTh, isEmpty, reason: 'th ยังไม่ map: $missingTh');
    expect(missingEn, isEmpty, reason: 'en ยังไม่ map: $missingEn');
  });

  test('ข้อความ en ของทุก client code ต้องไม่มีอักษรไทย (A2.3)', () {
    final leaked = <String>[];
    for (final code in clientCodes) {
      final msg = serverErrorFromCode(en, code)!;
      if (_thai.hasMatch(msg)) leaked.add('$code → "$msg"');
    }
    expect(leaked, isEmpty, reason: 'en มีอักษรไทย: $leaked');
  });

  test('unknown code → null (fallback ไป generic ของ caller)', () {
    expect(serverErrorFromCode(en, 'NO_SUCH_CODE_XYZ'), isNull);
    expect(serverErrorFromCode(th, null), isNull);
  });
}
