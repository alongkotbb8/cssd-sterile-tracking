import 'dart:developer' as dev;
import 'package:intl/intl.dart';
import 'printer_adapter.dart';

/// MockPrinterAdapter — พิมพ์ลง debug console แทนฮาร์ดแวร์จริง
/// ใช้ระหว่างพัฒนา / สภาพแวดล้อมที่ไม่มีเครื่องพิมพ์
class MockPrinterAdapter extends PrinterAdapter {
  @override
  String get displayName => 'Mock Printer (Console)';

  bool _connected = false;
  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _connected = true;
    dev.log('[MockPrinter] Connected', name: 'Printer');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    dev.log('[MockPrinter] Disconnected', name: 'Printer');
  }

  @override
  Future<void> printLabel(LabelData data) async {
    if (!_connected) throw const PrinterException('ยังไม่ได้เชื่อมต่อเครื่องพิมพ์');
    await Future.delayed(const Duration(milliseconds: 300));

    final fmt = DateFormat('dd/MM/yyyy');
    final tspl = _buildTspl(data, fmt);
    dev.log('[MockPrinter] --- TSPL Command ---\n$tspl', name: 'Printer');
  }

  String _buildTspl(LabelData d, DateFormat fmt) {
    // Simulates TSPL commands that would be sent to FlashLabel A318BT
    return '''
SIZE 60 mm, 40 mm
GAP 3 mm, 0
DIRECTION 1
CLS
TEXT 20,10,"3",0,1,1,"${d.setName}"
TEXT 20,32,"2",0,1,1,"${d.wrapType}"
BARCODE 20,55,"QRCODE",3,A,0,"${d.packageId}"
TEXT 190,55,"2",0,1,1,"${d.packageId}"
TEXT 20,145,"2",0,1,1,"นึ่ง: ${fmt.format(d.sterilizeDate)}"
TEXT 20,165,"2",0,1,1,"หมดอายุ: ${fmt.format(d.expiryDate)}"
PRINT 1,1
''';
  }
}
