import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'printer_adapter.dart';

/// ข้อความชนิดห่อ **บน label ที่พิมพ์จริง** — ภาษาไทยตาม SOP ของ CSSD
/// (i18n-allowlist: เนื้อหา label แยกจาก UI localization ตาม directive §1A.5
/// — ห้ามใช้ค่านี้แสดงบน UI; UI ใช้ l10n.dmWrapSeal/dmWrapCloth)
String wrapTypeLabelText(String wrapType) =>
    wrapType == 'SEAL' ? 'ห่อซีล' : 'ห่อผ้า';

/// สร้างคำสั่ง TSPL สำหรับพิมพ์ label โดย **render ทั้งใบเป็นภาพ bitmap ก่อน**
/// แล้วส่งผ่านคำสั่ง `BITMAP`
///
/// ทำไมต้อง bitmap: คำสั่ง TSPL `TEXT ...,"font",...` ใช้ฟอนต์ในตัวเครื่องพิมพ์
/// (font "1"–"5") ซึ่งเป็น ASCII/ละติน ไม่มีสระ/พยัญชนะไทย + การส่ง UTF-8 ให้
/// เครื่องตีความตาม code page ของมันเอง → ตัวอักษรไทยกลายเป็นขยะ
/// การ render เป็นภาพด้วย Flutter (ใช้ฟอนต์ในเครื่องที่รองรับไทยอยู่แล้ว)
/// แล้วส่งเป็น bitmap จึงเป็นวิธีมาตรฐานที่แอพเครื่องพิมพ์จริงใช้กับภาษาที่ไม่ใช่ละติน
class LabelRenderer {
  /// 203 DPI ≈ 8 dots/mm
  static const int dotsPerMm = 8;

  /// ฟอนต์ที่ฝังมากับแอป (assets/fonts/Sarabun-*.ttf) — **ต้องระบุชัดเจน**
  /// เพราะ [TextPainter] ที่วาดลง [Canvas] นอก widget tree ไม่สืบทอด fontFamily
  /// จาก ThemeData; ถ้าไม่ระบุ เอนจินจะใช้ฟอนต์ดีฟอลต์ (บนเว็บ/CanvasKit = Roboto)
  /// ซึ่ง **ไม่มี glyph ภาษาไทย** → ตัวอักษรไทยกลายเป็นกล่องว่าง (tofu)
  static const String _fontFamily = 'Sarabun';

  /// โหลด glyph ของ Sarabun เข้าเอนจิน **ครั้งเดียว** ก่อน rasterize —
  /// กันเคส cold-start บนเว็บที่ยังไม่เคยวาดข้อความ Sarabun (ฟอนต์ยังไม่ถูก
  /// ดาวน์โหลด) แล้ว [Canvas]→[toImage] ไปหยิบฟอนต์ fallback ที่ไม่มีสระ/
  /// พยัญชนะไทย → label เป็นกล่องว่าง. ทำให้ renderer เป็น self-contained
  /// (ไม่พึ่งว่า theme ต้องเคยวาดข้อความ Sarabun มาก่อน) และทดสอบ headless ได้
  static Future<void>? _fontReady;
  static Future<void> _ensureFont() {
    return _fontReady ??= () async {
      final loader = FontLoader(_fontFamily);
      for (final asset in const [
        'assets/fonts/Sarabun-Regular.ttf',
        'assets/fonts/Sarabun-Bold.ttf',
      ]) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }();
  }

  /// คืน bytes ของคำสั่ง TSPL ทั้งชุด (header + BITMAP data + PRINT)
  static Future<List<int>> buildTsplBitmap(
    LabelData data, {
    int widthMm = 60,
    int heightMm = 40,
  }) async {
    final widthDots = widthMm * dotsPerMm; // 480
    final heightDots = heightMm * dotsPerMm; // 320

    final image = await _renderImage(data, widthDots, heightDots);
    final mono = await _toMonochrome(image, widthDots, heightDots);
    image.dispose();

    final widthBytes = widthDots ~/ 8; // 60

    // header/footer เป็น ASCII ล้วน จึงส่งเป็น latin1/utf8 ได้เท่ากัน
    final header = ascii.encode(
      'SIZE $widthMm mm, $heightMm mm\r\n'
      'GAP 3 mm, 0\r\n'
      'DIRECTION 1\r\n'
      'REFERENCE 0,0\r\n'
      'CLS\r\n'
      'BITMAP 0,0,$widthBytes,$heightDots,0,',
    );
    final footer = ascii.encode('\r\nPRINT 1,1\r\n');

    return <int>[...header, ...mono, ...footer];
  }

  /// คืนภาพ label เป็น PNG — ใช้กับการพิมพ์ผ่านระบบพิมพ์ของเครื่อง/เบราว์เซอร์
  /// (System Print) ที่ต้องฝังรูปลง PDF แทนการส่ง TSPL ตรง
  /// ใช้ความละเอียดเดียวกับ TSPL (480×320 @203DPI) เพราะพิกัด layout ตายตัว
  /// PDF จะขยายภาพเต็มหน้ากระดาษ 60×40mm ให้เอง
  static Future<Uint8List> renderPng(
    LabelData data, {
    int widthMm = 60,
    int heightMm = 40,
  }) async {
    final image =
        await _renderImage(data, widthMm * dotsPerMm, heightMm * dotsPerMm);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }

  static Future<ui.Image> _renderImage(
      LabelData d, int widthDots, int heightDots) async {
    await _ensureFont(); // มี glyph ไทยแน่นอนก่อนวาด (กัน tofu บนเว็บ)
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // พื้นหลังขาว
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      Paint()..color = Colors.white,
    );

    void drawText(
      String text,
      double x,
      double y, {
      double fontSize = 20,
      FontWeight weight = FontWeight.w600,
      double? maxWidth,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontFamily: _fontFamily,
            fontSize: fontSize,
            fontWeight: weight,
            height: 1.0,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth ?? (widthDots - x));
      tp.paint(canvas, Offset(x, y));
    }

    // ชื่อชุด (ตัวใหญ่)
    drawText(d.setName, 12, 8, fontSize: 30, weight: FontWeight.w800);
    // ชนิดห่อ
    drawText(d.wrapType, 12, 46, fontSize: 22);

    // QR code — เนื้อหา = packageId เท่านั้น (ตามกฎโดเมน)
    const qrSize = 150.0;
    final qrPainter = QrPainter(
      data: d.packageId,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
      eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
    );
    canvas.save();
    canvas.translate(12, 92);
    qrPainter.paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();

    // เลขรันข้าง QR (ASCII — ตัวเลข/ขีด)
    drawText(d.packageId, 175, 150,
        fontSize: 22, weight: FontWeight.w700, maxWidth: widthDots - 175 - 8);

    if (d.isSterilized) {
      // วันที่จริงจาก backend (หลังผ่านรอบนึ่งแล้วเท่านั้น)
      final fmt = DateFormat('dd/MM/yyyy');
      drawText('นึ่ง: ${fmt.format(d.sterilizeDate!)}', 12, 258, fontSize: 20);
      drawText('หมดอายุ: ${fmt.format(d.expiryDate!)}', 12, 286, fontSize: 20);
    } else {
      // ห่อยังไม่ผ่านการนึ่ง — ห้ามพิมพ์วันที่โดยประมาณ (ความปลอดภัยผู้ป่วย)
      // พิมพ์แถบดำตัวหนังสือขาวให้เห็นชัดว่าห่อนี้ยังใช้กับผู้ป่วยไม่ได้
      canvas.drawRect(
        Rect.fromLTWH(12, 254, widthDots - 24, 60),
        Paint()..color = Colors.black,
      );
      final tp = TextPainter(
        text: const TextSpan(
          text: 'ยังไม่ผ่านการฆ่าเชื้อ',
          style: TextStyle(
            color: Colors.white,
            fontFamily: _fontFamily,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: widthDots - 24);
      tp.paint(
        canvas,
        Offset(12 + (widthDots - 24 - tp.width) / 2, 254 + (60 - tp.height) / 2),
      );
    }

    final picture = recorder.endRecording();
    return picture.toImage(widthDots, heightDots);
  }

  /// แปลงภาพ RGBA → 1 บิตต่อพิกเซล ตามรูปแบบ TSPL BITMAP
  /// TSPL BITMAP: bit 0 = จุดดำ (พิมพ์), bit 1 = ขาว (ไม่พิมพ์)
  static Future<Uint8List> _toMonochrome(
      ui.Image image, int widthDots, int heightDots) async {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = byteData!.buffer.asUint8List();

    final widthBytes = widthDots ~/ 8;
    final mono = Uint8List(widthBytes * heightDots);
    // เริ่มต้นเป็นขาวทั้งหมด (ทุกบิต = 1)
    for (var i = 0; i < mono.length; i++) {
      mono[i] = 0xFF;
    }

    for (var y = 0; y < heightDots; y++) {
      for (var x = 0; x < widthDots; x++) {
        final o = (y * widthDots + x) * 4;
        final r = rgba[o];
        final g = rgba[o + 1];
        final b = rgba[o + 2];
        final a = rgba[o + 3];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final isBlack = a > 128 && lum < 128;
        if (isBlack) {
          final byteIndex = y * widthBytes + (x >> 3);
          final bit = 7 - (x & 7);
          mono[byteIndex] &= ~(1 << bit); // เคลียร์บิต → 0 → ดำ
        }
      }
    }
    return mono;
  }
}
