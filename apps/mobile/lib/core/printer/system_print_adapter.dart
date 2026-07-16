import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'label_renderer.dart';
import 'printer_adapter.dart';

/// พิมพ์ผ่าน **ระบบพิมพ์ของเครื่อง/เบราว์เซอร์** (Android print framework / browser print)
///
/// ทำงานได้ทุกแพลตฟอร์มรวมถึงเว็บ โดยไม่ต้องต่อ Bluetooth ตรง:
/// - บนมือถือ: เปิดหน้าต่างพิมพ์ของ Android → ผู้ใช้เลือกเครื่องพิมพ์ผ่าน
///   print service ใดก็ได้ที่ติดตั้งไว้ **รวมถึงแอปของผู้ผลิตเครื่องพิมพ์เอง**
///   (เช่นแอป FlashLabel / Mopria / print plugin ที่ลงไว้)
/// - บนเว็บ: เปิดหน้าต่างพิมพ์ของเบราว์เซอร์ (หรือดาวน์โหลด PDF)
///
/// label ถูก render เป็นภาพ (รองรับภาษาไทย) แล้วฝังลง PDF ขนาด 60×40mm
class SystemPrintAdapter extends PrinterAdapter {
  final int labelWidthMm;
  final int labelHeightMm;

  SystemPrintAdapter({this.labelWidthMm = 60, this.labelHeightMm = 40});

  @override
  String get displayName => 'ระบบพิมพ์ของเครื่อง / เบราว์เซอร์';

  // ไม่มี socket ให้เชื่อม — เปิด dialog ทุกครั้งที่พิมพ์
  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> printLabel(LabelData data) async {
    final png = await LabelRenderer.renderPng(
      data,
      widthMm: labelWidthMm,
      heightMm: labelHeightMm,
    );
    final image = pw.MemoryImage(png);

    final format = PdfPageFormat(
      labelWidthMm * PdfPageFormat.mm,
      labelHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );

    try {
      await Printing.layoutPdf(
        name: 'label-${data.packageId}',
        format: format,
        onLayout: (fmt) async {
          final doc = pw.Document();
          doc.addPage(pw.Page(
            pageFormat: fmt,
            build: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(image, fit: pw.BoxFit.fill),
            ),
          ));
          return doc.save();
        },
      );
    } catch (e) {
      throw PrinterException('เปิดหน้าต่างพิมพ์ไม่สำเร็จ: $e');
    }
  }
}
