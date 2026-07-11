import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'printer_adapter.dart';

/// FlashLabel A318BT adapter — TSPL over Bluetooth Classic (SPP)
///
/// FlashLabel A318BT specs:
///   Resolution: 203 DPI
///   Protocol:   TSPL (primary) / CPCL (fallback)
///   Label size: 60 × 40 mm (default; configurable)
///   Connectivity: Bluetooth Classic SPP + USB
///
/// Wiring:
///   1. Scan BT devices → find one whose name contains "A318" or user selects
///   2. Connect to SPP service (UUID: 00001101-0000-1000-8000-00805f9b34fb)
///   3. Write TSPL commands as UTF-8 bytes to the characteristic/channel
class FlashLabelA318Adapter extends PrinterAdapter {
  FlashLabelA318Adapter({required this.device, this.labelWidthMm = 60, this.labelHeightMm = 40});

  final BluetoothDevice device;
  final int labelWidthMm;
  final int labelHeightMm;

  BluetoothCharacteristic? _txChar;
  bool _connected = false;

  // SPP service UUID (standard Bluetooth Serial Port Profile)
  // Fallback: many BLE-SPP bridges use this write characteristic
  static const _writeCharUuid   = '0000ff02-0000-1000-8000-00805f9b34fb';

  @override
  String get displayName => 'FlashLabel A318BT (${device.platformName})';

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    await device.connect(timeout: const Duration(seconds: 10));
    final services = await device.discoverServices();

    BluetoothCharacteristic? found;
    for (final svc in services) {
      for (final char in svc.characteristics) {
        final props = char.properties;
        if (props.write || props.writeWithoutResponse) {
          found ??= char;
          // Prefer the known write char UUID
          if (char.uuid.toString().toLowerCase() == _writeCharUuid) {
            found = char;
            break;
          }
        }
      }
    }

    if (found == null) throw const PrinterException('ไม่พบ characteristic สำหรับเขียนข้อมูล');
    _txChar = found;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    await device.disconnect();
    _connected = false;
    _txChar = null;
  }

  @override
  Future<void> printLabel(LabelData data) async {
    if (!_connected || _txChar == null) throw const PrinterException('ยังไม่ได้เชื่อมต่อเครื่องพิมพ์');

    final tspl = _buildTspl(data);
    await _send(tspl);
  }

  Future<void> _send(String tspl) async {
    final bytes = utf8.encode(tspl);
    // MTU for BT Classic SPP: send in 512-byte chunks
    const chunkSize = 512;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      final chunk = Uint8List.fromList(bytes.sublist(i, end));
      await _txChar!.write(chunk, withoutResponse: _txChar!.properties.writeWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 20)); // let printer buffer
    }
  }

  String _buildTspl(LabelData d) {
    final fmt = DateFormat('dd/MM/yyyy');
    // Dots per mm at 203 DPI ≈ 8 dots/mm
    return '''
SIZE $labelWidthMm mm, $labelHeightMm mm
GAP 3 mm, 0
DIRECTION 1
REFERENCE 0,0
OFFSET 0 mm
SET PEEL OFF
SET CUTTER OFF
CLS

; Set name (large)
TEXT 20,8,"3",0,1,1,"${_esc(d.setName)}"

; Wrap type badge
TEXT 20,30,"2",0,1,1,"${_esc(d.wrapType)}"

; QR code — content = packageId only (per domain rule)
QRCODE 20,50,L,4,A,0,"${d.packageId}"

; Running number text beside QR
TEXT 185,50,"2",0,1,1,"${d.packageId}"

; Dates
TEXT 20,145,"2",0,1,1,"นึ่ง: ${fmt.format(d.sterilizeDate)}"
TEXT 20,163,"2",0,1,1,"หมดอายุ: ${fmt.format(d.expiryDate)}"

PRINT 1,1
''';
  }

  String _esc(String s) => s.replaceAll('"', '\\"');

  // ─── Bluetooth device discovery helpers ──────────────────────────────────

  /// Scan for nearby A318BT devices (call once from UI, then let user pick)
  static Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults.map(
      (results) => results.where((r) =>
        r.device.platformName.toUpperCase().contains('A318') ||
        r.device.platformName.toUpperCase().contains('FLASH')).toList(),
    );
  }
}
