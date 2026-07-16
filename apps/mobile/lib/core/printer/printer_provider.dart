import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'flash_label_a318_adapter.dart';
import 'printer_adapter.dart';
import 'system_print_adapter.dart';

const _kPrefPrinterSelection = 'printer_selection';

/// Printer ที่เลือกไว้ — **ต้องจำข้าม session** ไม่งั้นทุกครั้งที่เปิดแอปใหม่
/// จะเด้งกลับไป default ทั้งที่ผู้ใช้เพิ่งจับคู่เครื่องพิมพ์จริงไป
///
/// ค่าเริ่มต้น = ระบบพิมพ์ของเครื่อง/เบราว์เซอร์ (SystemPrintAdapter) ซึ่งพิมพ์ได้จริง
/// ทุกแพลตฟอร์ม (ไม่ใช่ Mock ที่แค่ log) — ลดความสับสนว่าพิมพ์แล้วไม่ออก
final printerAdapterProvider =
    NotifierProvider<PrinterAdapterNotifier, PrinterAdapter>(
        PrinterAdapterNotifier.new);

class PrinterAdapterNotifier extends Notifier<PrinterAdapter> {
  @override
  PrinterAdapter build() {
    final saved =
        ref.read(sharedPreferencesProvider).getString(_kPrefPrinterSelection);
    if (saved == null) return SystemPrintAdapter();

    try {
      final map = jsonDecode(saved) as Map<String, dynamic>;
      switch (map['transport']) {
        case 'system':
          return SystemPrintAdapter();
        case 'classic':
          return FlashLabelA318Adapter.classic(
            name: map['name'] as String,
            mac: map['mac'] as String,
          );
        case 'ble':
          return FlashLabelA318Adapter.ble(
            device: BluetoothDevice.fromId(map['mac'] as String),
          );
      }
    } catch (_) {
      // ข้อมูลที่บันทึกไว้อ่านไม่ได้ (รูปแบบเปลี่ยนตอนอัปเดต) → กลับไป System Print
    }
    return SystemPrintAdapter();
  }

  void _persist(Map<String, dynamic> data) {
    ref
        .read(sharedPreferencesProvider)
        .setString(_kPrefPrinterSelection, jsonEncode(data));
  }

  void selectSystem() {
    state = SystemPrintAdapter();
    _persist({'transport': 'system'});
  }

  void selectClassic({required String name, required String mac}) {
    state = FlashLabelA318Adapter.classic(name: name, mac: mac);
    _persist({'transport': 'classic', 'name': name, 'mac': mac});
  }

  void selectBle(BluetoothDevice device) {
    state = FlashLabelA318Adapter.ble(device: device);
    _persist({
      'transport': 'ble',
      'name': device.platformName,
      'mac': device.remoteId.str,
    });
  }
}
