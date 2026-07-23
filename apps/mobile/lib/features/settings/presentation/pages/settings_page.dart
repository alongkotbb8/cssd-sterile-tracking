import 'dart:async';
// dart:io Platform ต้องเช็ค kIsWeb ก่อนใช้เสมอ — บนเว็บ getter ทุกตัวของ Platform
// (isAndroid, isIOS, ...) throw UnsupportedError ทันที ไม่ใช่แค่คืนค่า false
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/printer/printer_provider.dart';
import '../../../../core/printer/system_print_adapter.dart';
import '../../../../core/theme/app_theme.dart';

/// ตรวจ server URL — คืน `null` ถ้าใช้ได้ หรือข้อความ error (ไทย) ถ้าไม่ผ่าน
///
/// กติกา (ให้ตรง FIX-06 ฝั่ง Gateway): **release/production = https:// เท่านั้น**
/// (แม้ localhost/LAN ก็ไม่ยอม http — กัน JWT/ข้อมูลรั่ว) ; **debug/dev = http:// ได้
/// เฉพาะ localhost/LAN** (ทดสอบในตึก) ปลายทางสาธารณะต้อง https เสมอ
/// แยกเป็น pure function เพื่อ unit-test ได้ (ดู settings_url_validation_test.dart)
String? serverUrlValidationError(String url, {required bool isRelease}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return 'รูปแบบ URL ไม่ถูกต้อง (ต้องขึ้นต้นด้วย http:// หรือ https://)';
  }
  if (uri.isScheme('https')) return null;
  // ถึงตรงนี้ = http://
  if (isRelease) {
    return 'production ต้องใช้ https:// เท่านั้น (http:// ใช้ไม่ได้แม้เป็น LAN)';
  }
  if (!_isPrivateHost(uri.host)) {
    return 'server ภายนอกต้องใช้ https:// (http:// ใช้ได้เฉพาะ localhost/LAN ตอน dev)';
  }
  return null;
}

/// host ที่ถือว่าเป็นเครือข่ายภายใน — อนุญาต http:// ได้เฉพาะ debug/dev เท่านั้น
bool _isPrivateHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2') {
    return true; // 10.0.2.2 = host loopback ของ Android emulator
  }
  final octets = host.split('.').map(int.tryParse).toList();
  if (octets.length == 4 && octets.every((o) => o != null && o >= 0 && o <= 255)) {
    final a = octets[0]!, b = octets[1]!;
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  }
  return false;
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    final printer = ref.watch(printerAdapterProvider);
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: ListView(children: [
        if (user != null) ...[
          const _SectionHeader('บัญชีผู้ใช้'),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: SterelisColors.blue50,
              child: Icon(Icons.person_outline,
                  color: SterelisColors.blue600),
            ),
            title: Text(user.name),
            subtitle: Text('${user.employeeCode} · ${user.role}',
                style: const TextStyle(color: SterelisColors.textMuted)),
          ),
          const Divider(),
        ],
        const _SectionHeader('เครื่องพิมพ์'),
        ListTile(
          leading:
              const Icon(Icons.print_outlined, color: SterelisColors.blue500),
          title: const Text('เครื่องพิมพ์ที่ใช้'),
          subtitle: Text(printer.displayName,
              style: const TextStyle(color: SterelisColors.textMuted)),
          trailing:
              const Icon(Icons.chevron_right, color: SterelisColors.textFaint),
          onTap: () => _choosePrinter(context, ref),
        ),
        const ListTile(
          leading: Icon(Icons.receipt_long_outlined,
              color: SterelisColors.blue500),
          title: Text('ขนาดฉลาก'),
          subtitle: Text('60 × 40 mm · TSPL · 203 DPI',
              style: TextStyle(color: SterelisColors.textMuted)),
        ),
        const Divider(),
        const _SectionHeader('ระบบ'),
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined,
              color: SterelisColors.teal500),
          title: const Text('ที่อยู่ Server API'),
          subtitle: Text(serverUrl,
              style: const TextStyle(
                  color: SterelisColors.textMuted, fontFamily: 'monospace')),
          trailing:
              const Icon(Icons.chevron_right, color: SterelisColors.textFaint),
          onTap: () => _editServerUrl(context, ref, serverUrl),
        ),
        ListTile(
          leading:
              const Icon(Icons.logout_outlined, color: SterelisColors.danger),
          title: const Text('ออกจากระบบ',
              style: TextStyle(color: SterelisColors.danger)),
          onTap: () => _confirmLogout(context, ref),
        ),
      ]),
    );
  }

  Future<void> _editServerUrl(
      BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ที่อยู่ Server API'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.10:3000',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final url = result.trim();
    final err = serverUrlValidationError(url, isRelease: kReleaseMode);
    if (err != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: SterelisColors.danger),
        );
      }
      return;
    }
    await ref.read(serverUrlProvider.notifier).set(url);
  }

  Future<void> _choosePrinter(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: SterelisColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _PrinterSheet(),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ออกจากระบบ?'),
        content: const Text('ต้องเข้าสู่ระบบใหม่ในการใช้งานครั้งถัดไป'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('ยกเลิก')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: SterelisColors.danger),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

/// ⚠️ LEGACY — Sheet เลือกเครื่องพิมพ์สำหรับ **direct-print fallback** เท่านั้น
/// (ทางหลัก = Print Gateway + XP-420B ผ่าน Print Job Queue ไม่ผ่าน sheet นี้)
/// Sheet เลือกเครื่องพิมพ์: Mock (dev) หรือสแกนหา FlashLabel A318BT ผ่าน Bluetooth
class _PrinterSheet extends ConsumerStatefulWidget {
  const _PrinterSheet();

  @override
  ConsumerState<_PrinterSheet> createState() => _PrinterSheetState();
}

class _PrinterSheetState extends ConsumerState<_PrinterSheet> {
  bool _scanning = false;
  List<ScanResult> _found = [];
  // อุปกรณ์ Bluetooth Classic ที่จับคู่ไว้ในตั้งค่าเครื่องแล้ว — ทางหลักของ
  // A318BT (เหมือนแอพเครื่องพิมพ์ทั่วไป: pair ในระบบก่อน แล้วเลือกจากรายการนี้)
  List<BluetoothInfo> _paired = [];
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  void initState() {
    super.initState();
    // โหลดรายการที่จับคู่ไว้ทันทีที่เปิด sheet — ไม่ต้องรอผู้ใช้กดค้นหา
    _loadPaired();
  }

  Future<void> _loadPaired() async {
    if (kIsWeb || !Platform.isAndroid) return;
    // Android 12+ ต้องได้ BLUETOOTH_CONNECT ก่อนถึงจะอ่านรายการ paired ได้
    if (!await Permission.bluetoothConnect.request().isGranted) return;
    try {
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) setState(() => _paired = paired);
    } catch (_) {
      // อ่านไม่ได้ → ปล่อยรายการว่าง ผู้ใช้ยังสแกน BLE ได้
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  /// ขอ permission Bluetooth ตอนรันไทม์ — คืน null เมื่อได้ครบ,
  /// คืนข้อความ error เมื่อถูกปฏิเสธ
  ///
  /// Android 12+ ต้องขอ BLUETOOTH_SCAN/CONNECT ตอนรัน ;
  /// Android 6–11 ต้องได้ Location ไม่งั้นระบบไม่คืนผลสแกน BLE ให้เลย
  Future<String?> _requestBluetoothPermissions() async {
    if (kIsWeb) return null; // เว็บไม่รองรับ Bluetooth printer อยู่แล้ว (เช็คแยกที่ปุ่ม)
    if (!Platform.isAndroid) return null; // iOS ระบบถามเองตอนเริ่มใช้ Bluetooth
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final denied =
        statuses.entries.where((e) => !e.value.isGranted).toList();
    if (denied.isEmpty) return null;
    if (denied.any((e) => e.value.isPermanentlyDenied)) {
      return 'สิทธิ์ Bluetooth/ตำแหน่งถูกปิดไว้ — เปิดที่ ตั้งค่าเครื่อง > แอป > CSSD > สิทธิ์';
    }
    return 'ต้องอนุญาตสิทธิ์ Bluetooth และตำแหน่งก่อน จึงจะค้นหาเครื่องพิมพ์ได้';
  }

  void _showError(String message, {bool openSettings = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: SterelisColors.danger,
      action: openSettings
          ? const SnackBarAction(
              label: 'เปิดตั้งค่า',
              textColor: Colors.white,
              onPressed: openAppSettings,
            )
          : null,
    ));
  }

  Future<void> _scan() async {
    // 1) permission ต้องมาก่อน startScan — ไม่งั้น Android โยน SecurityException
    final permError = await _requestBluetoothPermissions();
    if (permError != null) {
      _showError(permError, openSettings: permError.contains('ตั้งค่าเครื่อง'));
      return;
    }

    // 2) Bluetooth ต้องเปิดอยู่ (Android ขอเปิดให้อัตโนมัติได้)
    if (await FlutterBluePlus.adapterState.first !=
        BluetoothAdapterState.on) {
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
          await FlutterBluePlus.adapterState
              .where((s) => s == BluetoothAdapterState.on)
              .first
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          _showError('กรุณาเปิด Bluetooth ก่อนค้นหาเครื่องพิมพ์');
          return;
        }
      } else {
        _showError('กรุณาเปิด Bluetooth ก่อนค้นหาเครื่องพิมพ์');
        return;
      }
    }

    setState(() {
      _scanning = true;
      _found = [];
    });
    try {
      // 3) รีเฟรชรายการที่จับคู่ไว้ (Classic) แล้วสแกน BLE ควบคู่กัน
      await _loadPaired();

      _sub?.cancel();
      _sub = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() => _found = results
            .where((r) => r.device.platformName.isNotEmpty)
            .toList());
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      _showError('สแกน Bluetooth ไม่ได้: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(printerAdapterProvider);
    final isSystem = current is SystemPrintAdapter;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('เลือกเครื่องพิมพ์',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: RadioListTile<bool>(
              value: true,
              // ignore: deprecated_member_use
              groupValue: isSystem,
              // ignore: deprecated_member_use
              onChanged: (_) {
                ref.read(printerAdapterProvider.notifier).selectSystem();
                Navigator.of(context).pop();
              },
              title: const Text('ระบบพิมพ์ของเครื่อง / เบราว์เซอร์ (แนะนำ)'),
              subtitle: const Text(
                  'เปิดหน้าต่างพิมพ์ → เลือกเครื่องพิมพ์ผ่านแอปของเครื่องพิมพ์เอง '
                  'หรือ print service ที่ติดตั้งไว้ (ใช้ได้ทั้งมือถือและเว็บ)',
                  style: TextStyle(
                      fontSize: 12, color: SterelisColors.textMuted)),
            ),
          ),
          const SizedBox(height: 14),
          if (kIsWeb)
            // Bluetooth Classic SPP (ทางหลักของ A318BT) ไม่มีในเบราว์เซอร์เลย
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'เชื่อมต่อ FlashLabel A318BT ผ่าน Bluetooth ตรง ใช้ได้เฉพาะแอปมือถือ '
                '(Android/iOS) — เวอร์ชันเว็บให้ใช้ "ระบบพิมพ์" ด้านบน',
                style: TextStyle(fontSize: 12.5, color: SterelisColors.textFaint),
              ),
            )
          else ...[
            Row(children: [
              const Expanded(
                child: Text('FlashLabel A318BT (Bluetooth ต่อตรง)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching, size: 18),
                label: Text(_scanning ? 'กำลังค้นหา...' : 'ค้นหา'),
              ),
            ]),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _buildDeviceList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    // จับคู่ไว้แล้ว (Classic — ทางหลัก) มาก่อน แล้วตามด้วยผลสแกน BLE (ตัดตัวซ้ำ)
    final pairedMacs =
        _paired.map((p) => p.macAdress.toUpperCase()).toSet();
    final scanned = _found
        .map((r) => r.device)
        .where((d) => !pairedMacs.contains(d.remoteId.str.toUpperCase()))
        .toList();

    if (_paired.isEmpty && scanned.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _scanning
              ? 'กำลังค้นหาอุปกรณ์...'
              : 'วิธีที่แนะนำ: จับคู่ (pair) เครื่องพิมพ์ในตั้งค่า Bluetooth '
                  'ของเครื่องก่อน แล้วกลับมาที่หน้านี้ — เครื่องจะขึ้นในรายการทันที\n'
                  'หรือกด "ค้นหา" เพื่อสแกนหาแบบ BLE',
          textAlign: TextAlign.center,
          style: const TextStyle(color: SterelisColors.textFaint),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        if (_paired.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('จับคู่ไว้แล้วในเครื่อง (แนะนำ)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SterelisColors.textMuted)),
          ),
          ..._paired.map(_pairedTile),
        ],
        if (scanned.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('พบจากการค้นหา (BLE)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SterelisColors.textMuted)),
          ),
          ...scanned.map(_scannedTile),
        ],
      ],
    );
  }

  /// อุปกรณ์จับคู่แล้ว → เชื่อมต่อแบบ Bluetooth Classic SPP (ทางหลักของ A318BT)
  Widget _pairedTile(BluetoothInfo p) {
    return ListTile(
      leading:
          const Icon(Icons.bluetooth_connected, color: SterelisColors.blue500),
      title: Text(p.name.isEmpty ? '(ไม่มีชื่อ)' : p.name),
      subtitle: Text(p.macAdress,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      onTap: () async {
        // หยุดสแกน BLE ก่อน — RFCOMM (Classic) กับ BLE scan ทำงานพร้อมกัน
        // ทำให้ BT stack บางเครื่องรวน เชื่อมต่อไม่ติด
        await FlutterBluePlus.stopScan();
        ref.read(printerAdapterProvider.notifier)
            .selectClassic(name: p.name, mac: p.macAdress);
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  /// อุปกรณ์จากผลสแกน BLE → ใช้ได้กับเครื่องพิมพ์รุ่น dual-mode เท่านั้น
  Widget _scannedTile(BluetoothDevice d) {
    return ListTile(
      leading: const Icon(Icons.print, color: SterelisColors.blue500),
      title: Text(d.platformName.isEmpty ? '(ไม่มีชื่อ)' : d.platformName),
      subtitle: Text(d.remoteId.str,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      onTap: () async {
        await FlutterBluePlus.stopScan();
        ref.read(printerAdapterProvider.notifier).selectBle(d);
        if (mounted) Navigator.of(context).pop();
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SterelisColors.textMuted,
              letterSpacing: .5)),
    );
  }
}
