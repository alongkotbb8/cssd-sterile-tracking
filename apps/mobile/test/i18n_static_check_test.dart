import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Gate 1 §1B — Static check: ห้ามมี user-facing Thai hard-coded นอก ARB
//
// สแกน string literal ทุกตัวใน lib/**.dart หาอักษรไทย (U+0E00–U+0E7F)
// ที่อยู่นอกไฟล์ l10n — ทุกรายการที่พบต้องอยู่ใน allowlist ด้านล่างซึ่งระบุ
// file + pattern + เหตุผล + owner ตาม directive (§1B: "Allowlist ต้องระบุ
// file, line/pattern, เหตุผล และ owner")

/// allowlist: file (relative จาก lib/) → รายการ (pattern อธิบาย, เหตุผล, owner)
/// การเพิ่มรายการใหม่ต้องผ่าน QA (§9: ห้ามเพิ่ม allowlist เพื่อหลบ i18n โดยไม่มี QA อนุมัติ)
const Map<String, ({String pattern, String reason, String owner})>
    kThaiAllowlist = {
  'core/printer/label_renderer.dart': (
    pattern: 'ข้อความบน label ที่พิมพ์จริงทั้งไฟล์',
    reason: 'เนื้อหา label เป็นภาษาไทยตาม SOP ของ CSSD — แยกจาก UI localization '
        'โดยเจตนา (directive §1A.5: label จริงอาจเป็นภาษาไทยตาม SOP ได้)',
    owner: 'Dev (mobile)',
  ),
  'features/settings/presentation/pages/settings_page.dart': (
    pattern: '_PrinterSheet (legacy direct-print chooser) เท่านั้น',
    reason: 'UI legacy อยู่หลัง feature flag CSSD_ENABLE_LEGACY_PRINT (default '
        'off ใน release) — ผู้ใช้ Pilot เข้าไม่ถึง และมีแผนลบหลัง Hardware Gate',
    owner: 'Dev (mobile)',
  ),
  'core/printer/flash_label_a318_adapter.dart': (
    pattern: 'error message ของ Bluetooth legacy adapter ทั้งไฟล์',
    reason: 'เส้นทาง legacy direct-print (FlashLabel A318BT) เข้าถึงได้เฉพาะหลัง '
        'flag CSSD_ENABLE_LEGACY_PRINT (ปิดใน Pilot/release ตาม directive §1.2) '
        '— ไม่ i18n เพิ่มเพราะมีแผนลบ/แยกออกหลัง Hardware Gate',
    owner: 'Dev (mobile)',
  ),
  'core/printer/system_print_adapter.dart': (
    pattern: 'ชื่อ/error ของ System-Browser print legacy adapter',
    reason: 'เส้นทาง legacy fallback หลัง flag เดียวกัน (ปิดใน Pilot/release) — '
        'แผนเดียวกับ A318 adapter',
    owner: 'Dev (mobile)',
  ),
};

final _thai = RegExp(r'[฀-๿]');

/// ดึง string literal ทั้งหมดจากซอร์ส 1 บรรทัด (ตัด comment ออกก่อนเรียก)
final _stringLiteral = RegExp("r?'''.*?'''|r?\"\"\".*?\"\"\"|r?'[^']*'|r?\"[^\"]*\"");

/// ตัด comment (// และ /* */) ออกจากซอร์สทั้งไฟล์ — คงจำนวนบรรทัดไว้ให้รายงาน
/// เลขบรรทัดตรง (แทนที่ด้วยช่องว่าง)
String _stripComments(String src) {
  final buf = StringBuffer();
  var i = 0;
  var inLineComment = false;
  var inBlockComment = false;
  String? stringQuote; // ใน string literal ห้ามตัด // (เช่น URL ใน string)
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (inLineComment) {
      if (c == '\n') {
        inLineComment = false;
        buf.write(c);
      } else {
        buf.write(' ');
      }
    } else if (inBlockComment) {
      if (c == '*' && next == '/') {
        inBlockComment = false;
        buf.write('  ');
        i++;
      } else {
        buf.write(c == '\n' ? '\n' : ' ');
      }
    } else if (stringQuote != null) {
      buf.write(c);
      if (c == r'\') {
        // ข้าม escape ตัวถัดไป
        if (next.isNotEmpty) {
          buf.write(next);
          i++;
        }
      } else if (c == stringQuote) {
        stringQuote = null;
      }
    } else {
      if (c == '/' && next == '/') {
        inLineComment = true;
        buf.write('  ');
        i++;
      } else if (c == '/' && next == '*') {
        inBlockComment = true;
        buf.write('  ');
        i++;
      } else {
        if (c == "'" || c == '"') stringQuote = c;
        buf.write(c);
      }
    }
    i++;
  }
  return buf.toString();
}

void main() {
  test('ไม่มี Thai hard-coded ใน string literal นอก l10n/allowlist (Gate 1 §1B)',
      () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'ต้องรันจาก apps/mobile (flutter test)');

    final violations = <String>[];
    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        // ไฟล์ l10n ทั้งโฟลเดอร์ = แหล่ง ARB/generated — ไม่ใช่ hard-code
        .where((f) => !f.path.contains('lib/l10n/'));

    for (final f in files) {
      final rel = f.path.replaceFirst(RegExp(r'^lib/'), '');
      if (kThaiAllowlist.containsKey(rel)) continue;
      final src = _stripComments(f.readAsStringSync());
      final lines = src.split('\n');
      for (var n = 0; n < lines.length; n++) {
        for (final m in _stringLiteral.allMatches(lines[n])) {
          final lit = m.group(0)!;
          if (_thai.hasMatch(lit)) {
            violations.add('$rel:${n + 1} → $lit');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'พบ Thai hard-coded นอก ARB/allowlist — ย้ายเข้า lib/l10n/*.arb '
          'หรือขอ QA อนุมัติเพิ่ม allowlist (ระบุ pattern/เหตุผล/owner):\n'
          '${violations.join('\n')}',
    );
  });

  test('allowlist ทุกรายการชี้ไฟล์ที่ยังมีอยู่จริง (กัน allowlist ค้าง)', () {
    for (final rel in kThaiAllowlist.keys) {
      expect(File('lib/$rel').existsSync(), isTrue,
          reason: 'allowlist ชี้ไฟล์ที่ไม่มีแล้ว: lib/$rel — ลบรายการออก');
    }
  });
}
