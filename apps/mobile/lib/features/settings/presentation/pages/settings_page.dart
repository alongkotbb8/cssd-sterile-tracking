import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/printer/flash_label_a318_adapter.dart';
import '../../../../core/printer/mock_printer_adapter.dart';
import '../../../../core/printer/printer_provider.dart';
import '../../../../core/theme/app_theme.dart';

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
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('รูปแบบ URL ไม่ถูกต้อง (ต้องขึ้นต้นด้วย http:// หรือ https://)'),
          backgroundColor: SterelisColors.danger,
        ));
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

/// Sheet เลือกเครื่องพิมพ์: Mock (dev) หรือสแกนหา FlashLabel A318BT ผ่าน Bluetooth
class _PrinterSheet extends ConsumerStatefulWidget {
  const _PrinterSheet();

  @override
  ConsumerState<_PrinterSheet> createState() => _PrinterSheetState();
}

class _PrinterSheetState extends ConsumerState<_PrinterSheet> {
  bool _scanning = false;
  List<ScanResult> _found = [];
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _found = [];
    });
    try {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('สแกน Bluetooth ไม่ได้: $e'),
          backgroundColor: SterelisColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(printerAdapterProvider);
    final isMock = current is MockPrinterAdapter;

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
              groupValue: isMock,
              // ignore: deprecated_member_use
              onChanged: (_) {
                ref.read(printerAdapterProvider.notifier).state =
                    MockPrinterAdapter();
                Navigator.of(context).pop();
              },
              title: const Text('Mock Printer (สำหรับพัฒนา)'),
              subtitle: const Text('พิมพ์คำสั่ง TSPL ลง console',
                  style: TextStyle(
                      fontSize: 12, color: SterelisColors.textMuted)),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Text('FlashLabel A318BT (Bluetooth)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
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
            constraints: const BoxConstraints(maxHeight: 220),
            child: _found.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _scanning
                          ? 'กำลังค้นหาอุปกรณ์...'
                          : 'กด "ค้นหา" เพื่อสแกนหาเครื่องพิมพ์',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: SterelisColors.textFaint),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _found.length,
                    itemBuilder: (_, i) {
                      final d = _found[i].device;
                      return ListTile(
                        leading: const Icon(Icons.print,
                            color: SterelisColors.blue500),
                        title: Text(d.platformName),
                        subtitle: Text(d.remoteId.str,
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace')),
                        onTap: () {
                          ref.read(printerAdapterProvider.notifier).state =
                              FlashLabelA318Adapter(device: d);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
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
