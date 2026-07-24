// Regression: the printed/browser-print label bitmap must render Thai glyphs,
// not tofu (□). Root cause of the original bug: the label's TextPainter ran
// outside the widget tree with no fontFamily, so on web (CanvasKit) it fell
// back to Roboto — which has no Thai glyphs. The renderer now (a) binds text
// to the bundled 'Sarabun' family and (b) self-loads Sarabun before rasterizing.
//
// This test decodes the rendered PNG with pure dart:ui (no extra deps) and
// asserts the Thai regions actually contain drawn ink. If fontFamily is dropped
// again or the font fails to load, the glyphs vanish and these assertions fail.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cssd_mobile/core/printer/label_renderer.dart';
import 'package:cssd_mobile/core/printer/printer_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// จำนวนพิกเซล "ดำ" (lum<128, opaque) ในกรอบ [l,t,r,b] ของภาพ RGBA
int _blackInRect(Uint8List rgba, int w, int l, int t, int r, int b) {
  var n = 0;
  for (var y = t; y < b; y++) {
    for (var x = l; x < r; x++) {
      final o = (y * w + x) * 4;
      final lum = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
      if (rgba[o + 3] > 128 && lum < 128) n++;
    }
  }
  return n;
}

/// จำนวนพิกเซล "ขาว" (lum>200) ในกรอบเดียวกัน
int _whiteInRect(Uint8List rgba, int w, int l, int t, int r, int b) {
  var n = 0;
  for (var y = t; y < b; y++) {
    for (var x = l; x < r; x++) {
      final o = (y * w + x) * 4;
      final lum = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
      if (lum > 200) n++;
    }
  }
  return n;
}

Future<Uint8List> _decodeRgba(Uint8List png, int w, int h) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  // 480×320 dots = 60×40mm @203DPI (พิกัด layout ตายตัวใน LabelRenderer)
  const w = 480, h = 320;

  testWidgets('unsterilized label renders Thai name + black warning banner',
      (tester) async {
    await tester.runAsync(() async {
      final png = await LabelRenderer.renderPng(const LabelData(
        packageId: 'DELIV-20260711-0001',
        setName: 'ชุดถอนฟัน',
        wrapType: 'ห่อซีล',
      ));
      final rgba = await _decodeRgba(png, w, h);

      // (1) ชื่อชุดไทย (ดำบนขาว) ที่มุมบนซ้าย — ต้องมี ink จริง ไม่ใช่ว่างเปล่า
      final nameInk = _blackInRect(rgba, w, 12, 8, 260, 46);
      expect(nameInk, greaterThan(150),
          reason: 'ชื่อชุดภาษาไทยต้องถูกวาด (ไม่ใช่ว่าง/tofu ที่หายไป)');

      // (2) แถบเตือน y∈[254,314]: พื้นดำ + ตัวอักษรไทยสีขาว "ยังไม่ผ่านการฆ่าเชื้อ"
      final bannerBlack = _blackInRect(rgba, w, 12, 254, 468, 314);
      final bannerWhiteText = _whiteInRect(rgba, w, 12, 254, 468, 314);
      expect(bannerBlack, greaterThan(3000),
          reason: 'แถบเตือนต้องมีพื้นหลังดำ');
      expect(bannerWhiteText, greaterThan(150),
          reason: 'ข้อความไทยสีขาวบนแถบดำต้องถูกวาด (ถ้า tofu หาย = ดำล้วน)');
    });
  });

  testWidgets('sterilized label renders Thai wrap type + dates (no banner)',
      (tester) async {
    await tester.runAsync(() async {
      final png = await LabelRenderer.renderPng(LabelData(
        packageId: 'DELIV-20260711-0002',
        setName: 'ชุดทำแผลใหญ่',
        wrapType: 'ห่อผ้า',
        sterilizeDate: DateTime(2026, 7, 20),
        expiryDate: DateTime(2027, 1, 16),
      ));
      final rgba = await _decodeRgba(png, w, h);

      // ชื่อชุดไทย + บรรทัดวันที่ (นึ่ง/หมดอายุ) ล่างซ้าย — ทั้งคู่ต้องมี ink
      expect(_blackInRect(rgba, w, 12, 8, 300, 46), greaterThan(150),
          reason: 'ชื่อชุดภาษาไทยต้องถูกวาด');
      expect(_blackInRect(rgba, w, 12, 250, 300, 314), greaterThan(150),
          reason: 'บรรทัดวันที่ (นึ่ง/หมดอายุ) ต้องถูกวาด');

      // ไม่มีแถบเตือนดำเต็มความกว้างเมื่อ sterile แล้ว
      expect(_blackInRect(rgba, w, 12, 254, 468, 314), lessThan(3000),
          reason: 'ห่อ sterile ต้องไม่มีแถบดำ "ยังไม่ผ่านการฆ่าเชื้อ"');
    });
  });
}
