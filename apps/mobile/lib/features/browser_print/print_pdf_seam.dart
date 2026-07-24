import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/printer/label_renderer.dart';
import '../../core/printer/printer_adapter.dart';

/// Seam สำหรับการเปิด print dialog ของระบบ (Printing.layoutPdf) — แยกเป็น
/// provider เพื่อให้เทส override ได้ (ตรวจ **ลำดับ**: create → dialog-opened →
/// จึงเรียก seam และห้าม auto-confirm จากผลลัพธ์ของ seam)
///
/// กติกาสำคัญ (MACOS_BROWSER_PRINT_DIRECTIVE.md §3/§10):
/// - การ return จาก dialog **ไม่ใช่** หลักฐานว่าพิมพ์จริง — caller ต้องเพิกเฉย
///   ผลลัพธ์ทั้งหมด (สำเร็จ/พัง/timeout) แล้วให้ผู้ใช้เลือกผลเอง
/// - ห้ามตั้ง printedAt หรือสถานะ PRINTED จากเส้นทางนี้เด็ดขาด
typedef PrintPdfFn = Future<void> Function(Uint8List bytes, String name);

final printPdfProvider = Provider<PrintPdfFn>((ref) => _printingLayoutPdf);

Future<void> _printingLayoutPdf(Uint8List bytes, String name) async {
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
}

/// Seam ของการ render label bitmap (default = LabelRenderer.renderPng ตัวจริง)
/// — เทส override เพื่อจับ [LabelData] ที่ถูกส่งเข้า renderer (ยืนยันว่า preview
/// สร้างจาก payload label ของ backend เท่านั้น: วันที่/QR = packageId passthrough)
typedef RenderLabelPngFn = Future<Uint8List> Function(
  LabelData data, {
  int widthMm,
  int heightMm,
});

final renderLabelPngProvider =
    Provider<RenderLabelPngFn>((ref) => LabelRenderer.renderPng);
