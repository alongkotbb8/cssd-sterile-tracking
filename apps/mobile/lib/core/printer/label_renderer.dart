import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'printer_adapter.dart';

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

    // วันที่
    final fmt = DateFormat('dd/MM/yyyy');
    drawText('นึ่ง: ${fmt.format(d.sterilizeDate)}', 12, 258, fontSize: 20);
    drawText('หมดอายุ: ${fmt.format(d.expiryDate)}', 12, 286, fontSize: 20);

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
