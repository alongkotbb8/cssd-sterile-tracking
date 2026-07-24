import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'label_renderer.dart';
import 'printer_adapter.dart';

/// ⚠️ LEGACY / DEPRECATED — Bluetooth direct-print fallback เท่านั้น (ไม่ใช่ทางหลัก)
///
/// ทางพิมพ์อย่างเป็นทางการของระบบตอนนี้ = **Print Job Queue → Print Gateway → Xprinter
/// XP-420B (usb_spool)** ซึ่ง PWA/มือถือ **ไม่พิมพ์ตรงและไม่ตั้งสถานะ PRINTED เอง**
/// (ดู features/print_jobs/) adapter นี้ไม่ได้ผูกกับปุ่มพิมพ์ใน UI แล้ว คงไว้เป็น
/// fallback ฉุกเฉินระดับโค้ด — ถอดได้เมื่อยืนยันยกเลิก BT fallback
///
/// FlashLabel A318BT adapter — TSPL over Bluetooth
///
/// FlashLabel A318BT specs:
///   Resolution: 203 DPI
///   Protocol:   TSPL
///   Label size: 60 × 40 mm (default; configurable)
///   Connectivity: Bluetooth Classic SPP + USB
///
/// การเชื่อมต่อมี 2 ทาง (เหมือนแอพเครื่องพิมพ์ label ทั่วไป):
///   1. **Classic SPP** (ทางหลัก) — จับคู่เครื่องพิมพ์ใน Settings ของเครื่องก่อน
///      แล้วเปิด RFCOMM socket ผ่าน print_bluetooth_thermal (A318BT เป็น BT Classic)
///   2. **BLE GATT** (ทางสำรอง) — สำหรับเครื่องพิมพ์รุ่น dual-mode ที่โฆษณาเป็น BLE
///
/// label ทุกใบ render เป็นภาพ bitmap ก่อนส่ง (ดู [LabelRenderer]) เพื่อให้พิมพ์
/// ภาษาไทยได้ถูกต้อง — ฟอนต์ในตัวเครื่องพิมพ์ TSPL ไม่มีอักษรไทย
enum _Transport { classicSpp, ble }

class FlashLabelA318Adapter extends PrinterAdapter {
  FlashLabelA318Adapter.classic({
    required String name,
    required String mac,
    this.labelWidthMm = 60,
    this.labelHeightMm = 40,
  })  : _transport = _Transport.classicSpp,
        _name = name,
        _mac = mac,
        device = null;

  FlashLabelA318Adapter.ble({
    required BluetoothDevice this.device,
    this.labelWidthMm = 60,
    this.labelHeightMm = 40,
  })  : _transport = _Transport.ble,
        _name = device.platformName,
        _mac = device.remoteId.str;

  final _Transport _transport;
  final String _name;
  final String _mac;
  final BluetoothDevice? device;
  final int labelWidthMm;
  final int labelHeightMm;

  BluetoothCharacteristic? _txChar;
  bool _connected = false;

  static const _writeCharUuid = '0000ff02-0000-1000-8000-00805f9b34fb';

  @override
  String get displayName =>
      'FlashLabel A318BT ($_name${_transport == _Transport.ble ? ' · BLE' : ''})';

  @override
  bool get isConnected => _connected;

  /// print_bluetooth_thermal โค้ด native จะ **ค้าง (ไม่ยิง result กลับ)** ถ้า
  /// BLUETOOTH_CONNECT ยังไม่ได้รับอนุญาตบน Android 12+ → ต้องเช็คสิทธิ์ก่อน
  /// เรียก method ใด ๆ ของมันเสมอ ไม่งั้น Future จะค้างตลอดไป
  Future<void> _ensureConnectPermission() async {
    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      throw const PrinterException(
          'ต้องอนุญาตสิทธิ์ Bluetooth ก่อนเชื่อมต่อเครื่องพิมพ์ '
          '(ตั้งค่าเครื่อง > แอป > CSSD > สิทธิ์)');
    }
  }

  @override
  Future<void> connect() async {
    switch (_transport) {
      case _Transport.classicSpp:
        await _connectClassic();
      case _Transport.ble:
        await _connectBle();
    }
    _connected = true;
  }

  Future<void> _connectClassic() async {
    await _ensureConnectPermission();

    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw const PrinterException('กรุณาเปิด Bluetooth ก่อนเชื่อมต่อเครื่องพิมพ์');
    }

    // ตัด connection ค้าง (เช่นเครื่องพิมพ์ถูกปิด-เปิดใหม่) เพื่อเริ่ม socket ที่สะอาด
    if (await PrintBluetoothThermal.connectionStatus) {
      await PrintBluetoothThermal.disconnect;
    }

    // native connect ไม่มี timeout — ถ้าเครื่องพิมพ์ปิด/อยู่นอกระยะจะบล็อกนาน
    // ครอบ timeout ไว้ให้ผู้ใช้ได้ error ที่อ่านรู้เรื่องแทนการค้าง
    bool ok;
    try {
      ok = await PrintBluetoothThermal.connect(macPrinterAddress: _mac)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const PrinterException(
          'เชื่อมต่อเครื่องพิมพ์ไม่สำเร็จ (หมดเวลา) — ตรวจว่าเครื่องพิมพ์เปิดอยู่และอยู่ในระยะ');
    }
    if (!ok) {
      throw const PrinterException(
          'เชื่อมต่อเครื่องพิมพ์ไม่สำเร็จ — ตรวจว่าเครื่องพิมพ์เปิดอยู่ '
          'และจับคู่ (pair) ไว้ในตั้งค่า Bluetooth ของเครื่องแล้ว');
    }
  }

  Future<void> _connectBle() async {
    await _ensureConnectPermission();
    final dev = device!;
    await dev.connect(timeout: const Duration(seconds: 12));
    final services = await dev.discoverServices();

    BluetoothCharacteristic? found;
    for (final svc in services) {
      for (final char in svc.characteristics) {
        final props = char.properties;
        if (props.write || props.writeWithoutResponse) {
          found ??= char;
          if (char.uuid.toString().toLowerCase() == _writeCharUuid) {
            found = char;
            break;
          }
        }
      }
    }

    if (found == null) {
      await dev.disconnect();
      throw const PrinterException(
          'ไม่พบช่องทางเขียนข้อมูลแบบ BLE — เครื่องพิมพ์รุ่นนี้น่าจะเป็น '
          'Bluetooth Classic: จับคู่ในตั้งค่า Bluetooth ของเครื่องก่อน '
          'แล้วเลือกจากรายการ "จับคู่ไว้แล้ว" แทน');
    }
    _txChar = found;
  }

  @override
  Future<void> disconnect() async {
    switch (_transport) {
      case _Transport.classicSpp:
        try {
          await PrintBluetoothThermal.disconnect;
        } catch (_) {/* ปล่อยผ่าน — ตั้งใจจะตัดการเชื่อมต่ออยู่แล้ว */}
      case _Transport.ble:
        try {
          await device!.disconnect();
        } catch (_) {/* ignore */}
        _txChar = null;
    }
    _connected = false;
  }

  @override
  Future<void> printLabel(LabelData data) async {
    if (!_connected) throw const PrinterException('ยังไม่ได้เชื่อมต่อเครื่องพิมพ์');

    final bytes = await LabelRenderer.buildTsplBitmap(
      data,
      widthMm: labelWidthMm,
      heightMm: labelHeightMm,
    );
    await _send(bytes);
  }

  Future<void> _send(List<int> bytes) async {
    switch (_transport) {
      case _Transport.classicSpp:
        // เช็คว่า socket ยังอยู่ก่อนเขียน (เครื่องพิมพ์อาจถูกปิดระหว่างทาง)
        if (!await PrintBluetoothThermal.connectionStatus) {
          _connected = false;
          throw const PrinterException(
              'การเชื่อมต่อหลุด — กรุณาเชื่อมต่อเครื่องพิมพ์ใหม่อีกครั้ง');
        }
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        if (!ok) {
          _connected = false;
          throw const PrinterException('ส่งข้อมูลไปเครื่องพิมพ์ไม่สำเร็จ');
        }
      case _Transport.ble:
        // BLE: ส่งเป็น chunk ตาม MTU
        const chunkSize = 512;
        final data = Uint8List.fromList(bytes);
        for (var i = 0; i < data.length; i += chunkSize) {
          final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
          await _txChar!.write(
            data.sublist(i, end),
            withoutResponse: _txChar!.properties.writeWithoutResponse,
          );
          await Future.delayed(const Duration(milliseconds: 20)); // let printer buffer
        }
    }
  }
}
