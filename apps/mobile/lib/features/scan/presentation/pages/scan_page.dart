import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';

enum ScanMode { scanIn, scanOut, scanReturn }

extension on ScanMode {
  String get title => switch (this) {
        ScanMode.scanIn => 'นำเข้าคลัง',
        ScanMode.scanOut => 'เบิกออก',
        ScanMode.scanReturn => 'ส่งคืน',
      };

  /// สถานะห่อที่ mode นี้รับได้
  /// - เบิกออก: STERILE (ปกติ) และ PACKED (ส่งออกโดยยังไม่ฆ่าเชื้อ เช่น ส่ง รพ.อื่น)
  /// - ส่งคืน: ISSUED (ปกติ → รอ reprocess) และ PACKED_OUT (คืนแล้วกลับเป็น PACKED)
  Set<String> get allowedStatuses => switch (this) {
        ScanMode.scanIn => const {'PACKED'},
        ScanMode.scanOut => const {'STERILE', 'PACKED'},
        ScanMode.scanReturn => const {'ISSUED', 'PACKED_OUT'},
      };
}

/// รายการที่สแกนแล้ว + ผล lookup
class _ScannedItem {
  final String id;
  String? name;
  String? status;
  int? daysLeft;
  bool isExpired = false;
  bool loading = true;
  String? blockReason; // null = ผ่าน
  String? warning; // เตือนแต่ไม่บล็อก (เช่น เบิกออกของที่ยังไม่ฆ่าเชื้อ)
  String? serverError; // error จากตอนยืนยัน

  _ScannedItem(this.id);
  bool get eligible => !loading && blockReason == null;
}

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> with WidgetsBindingObserver {
  ScanMode _mode = ScanMode.scanOut;
  final List<_ScannedItem> _items = [];
  bool _torchOn = false;
  bool _submitting = false;

  Department? _department;
  SterilizationBatch? _batch;
  final _receiverCtrl = TextEditingController();

  // จัดการ lifecycle ของกล้องเอง เพราะเราส่ง controller ของตัวเองให้ MobileScanner
  // (widget จะไม่ start/stop ให้อัตโนมัติเมื่อสลับแอป/แท็บ) และตั้ง autoStart=false
  // เพื่อสั่ง start เองหลังได้สิทธิ์กล้องแล้ว — กันเคส start ก่อน permission → ค้างที่ error
  late final MobileScannerController _cam =
      MobileScannerController(autoStart: false);
  StreamSubscription<BarcodeCapture>? _detectSub;

  /// null = ยังไม่ตรวจ, true = อนุญาตแล้ว, false = ถูกปฏิเสธ
  bool? _cameraGranted;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectSub = _cam.barcodes.listen(_onDetect);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _cameraGranted = status.isGranted;
      _permanentlyDenied = status.isPermanentlyDenied;
    });
    if (status.isGranted) {
      try {
        await _cam.start();
      } catch (_) {
        // MobileScanner จะแสดง error ผ่าน errorBuilder ให้กด "ลองใหม่" ได้
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _cameraGranted = null;
      _permanentlyDenied = false;
    });
    await _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraGranted != true) {
      // ผู้ใช้อาจเพิ่งไปกดอนุญาตสิทธิ์ใน "ตั้งค่าเครื่อง" แล้วกลับมาแอป —
      // ตรวจสิทธิ์ใหม่ตอน resume ไม่งั้นจะค้างที่หน้า "ถูกปฏิเสธ" ตลอดไป
      // แม้ผู้ใช้จะอนุญาตแล้วก็ตาม (ต้องปิด-เปิดหน้าใหม่ถึงจะเช็คซ้ำ)
      if (state == AppLifecycleState.resumed) _initCamera();
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _detectSub ??= _cam.barcodes.listen(_onDetect);
        unawaited(_cam.start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_cam.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectSub?.cancel();
    _cam.dispose();
    _receiverCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      if (_items.any((i) => i.id == raw)) continue;

      final item = _ScannedItem(raw);
      setState(() => _items.insert(0, item));
      HapticFeedback.mediumImpact();
      _lookup(item);
    }
  }

  Future<void> _lookup(_ScannedItem item) async {
    try {
      final r = await ref.read(scanRepositoryProvider).lookup(item.id);
      item
        ..name = r.package.templateName
        ..status = r.package.status
        ..daysLeft = r.daysLeft
        ..isExpired = r.isExpired
        ..loading = false
        ..blockReason = _blockReason(r)
        ..warning = _warning(r);
    } catch (e) {
      item
        ..loading = false
        ..blockReason = apiErrorMessage(e);
    }
    if (mounted) setState(() {});
  }

  /// กติกาบล็อกฝั่ง client (server ตรวจซ้ำอีกชั้น)
  String? _blockReason(LookupResult r) {
    if (_mode == ScanMode.scanOut && r.isExpired) {
      return 'ห้ามใช้ — ห่อหมดอายุแล้ว';
    }
    final st = r.package.status;
    if (!_mode.allowedStatuses.contains(st)) {
      final label = packageStatusStyle(st).label;
      return 'สถานะปัจจุบัน: $label — ${_mode.title}ไม่ได้';
    }
    return null;
  }

  /// เตือนแต่ไม่บล็อก — เบิกออกของที่แพ็กแล้วแต่ยังไม่ผ่านการฆ่าเชื้อ
  String? _warning(LookupResult r) {
    if (_mode == ScanMode.scanOut && r.package.status == 'PACKED') {
      return '⚠ ยังไม่ฆ่าเชื้อ — จะบันทึกเป็น "ส่งออก (ยังไม่ฆ่าเชื้อ)"';
    }
    return null;
  }

  bool get _readyToSubmit {
    if (_submitting) return false;
    if (_items.where((i) => i.eligible).isEmpty) return false;
    return switch (_mode) {
      ScanMode.scanIn => _batch != null,
      ScanMode.scanOut || ScanMode.scanReturn => _department != null,
    };
  }

  Future<void> _confirm() async {
    final eligible = _items.where((i) => i.eligible).toList();
    if (eligible.isEmpty) return;

    // pop-up ยืนยันก่อนบันทึกจริง
    final destination = switch (_mode) {
      ScanMode.scanIn =>
        'รอบ ${_batch?.roundNo ?? '-'} · ${_batch?.sterilizerName ?? ''}',
      ScanMode.scanOut => 'แผนก ${_department?.name ?? ''}'
          '${_receiverCtrl.text.trim().isNotEmpty ? ' · ผู้รับ ${_receiverCtrl.text.trim()}' : ''}',
      ScanMode.scanReturn => 'แผนก ${_department?.name ?? ''}',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('ยืนยัน${_mode.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_mode.title} ${eligible.length} ห่อ',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(destination,
                style: const TextStyle(
                    fontSize: 13.5, color: SterelisColors.textMuted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);

    try {
      final ids = eligible.map((i) => i.id).toList();
      final repo = ref.read(scanRepositoryProvider);
      final results = switch (_mode) {
        ScanMode.scanIn => await repo.scanIn(ids, _batch!.id),
        ScanMode.scanOut => await repo.scanOut(ids, _department!.id,
            receiverName: _receiverCtrl.text.trim()),
        ScanMode.scanReturn => await repo.scanReturn(ids, _department!.id),
      };

      final byId = {for (final r in results) r.packageId: r};
      final okCount = results.where((r) => r.success).length;
      final failCount = results.length - okCount;

      setState(() {
        // ลบตัวที่สำเร็จออก คงตัวที่พลาดไว้พร้อมเหตุผล
        _items.removeWhere((i) => byId[i.id]?.success == true);
        for (final i in _items) {
          final r = byId[i.id];
          if (r != null && !r.success) i.serverError = r.error;
        }
        _submitting = false;
      });

      ref.invalidate(packagesProvider);
      ref.invalidate(dashboardProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failCount == 0
            ? 'บันทึก${_mode.title}สำเร็จ $okCount ห่อ'
            : 'สำเร็จ $okCount ห่อ · ไม่ผ่าน $failCount ห่อ (ดูเหตุผลในรายการ)'),
        backgroundColor:
            failCount == 0 ? SterelisColors.success : SterelisColors.warning,
      ));
    } catch (e) {
      setState(() => _submitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  void _switchMode(ScanMode m) {
    setState(() {
      _mode = m;
      _items.clear();
      _department = null;
      _batch = null;
      _receiverCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกน QR'),
        actions: [
          IconButton(
            icon: Icon(_torchOn
                ? Icons.flashlight_off_outlined
                : Icons.flashlight_on_outlined),
            onPressed: () {
              setState(() => _torchOn = !_torchOn);
              _cam.toggleTorch();
            },
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: SterelisColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SegmentedButton<ScanMode>(
            segments: ScanMode.values
                .map((m) => ButtonSegment(value: m, label: Text(m.title)))
                .toList(),
            selected: {_mode},
            onSelectionChanged: (s) => _switchMode(s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? SterelisColors.blue500
                      : null),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? Colors.white
                      : SterelisColors.textMuted),
            ),
          ),
        ),
        _TargetSelector(
          mode: _mode,
          department: _department,
          batch: _batch,
          receiverCtrl: _receiverCtrl,
          onDepartment: (d) => setState(() => _department = d),
          onBatch: (b) => setState(() => _batch = b),
        ),
        Expanded(
          flex: 4,
          child: Container(
            color: SterelisColors.ink900,
            child: _buildCameraArea(),
          ),
        ),
        Expanded(
          flex: 4,
          child: _ScannedPanel(
            items: _items,
            mode: _mode,
            submitting: _submitting,
            canSubmit: _readyToSubmit,
            onConfirm: _confirm,
            onClear: () => setState(_items.clear),
            onRemove: (item) => setState(() => _items.remove(item)),
          ),
        ),
      ]),
    );
  }

  Widget _buildCameraArea() {
    // ยังไม่ตรวจสิทธิ์ → กำลังโหลด
    if (_cameraGranted == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    // ถูกปฏิเสธ → แสดงเหตุผล + ปุ่มดำเนินการ (ไม่ปล่อยให้จอดำเฉย ๆ)
    if (_cameraGranted == false) {
      return _CameraMessage(
        icon: Icons.no_photography_outlined,
        message: _permanentlyDenied
            ? 'ปิดสิทธิ์กล้องไว้ — เปิดที่ ตั้งค่าเครื่อง > แอป > CSSD > สิทธิ์'
            : 'ต้องอนุญาตสิทธิ์กล้องเพื่อสแกน QR',
        actionLabel: _permanentlyDenied ? 'เปิดตั้งค่า' : 'อนุญาตกล้อง',
        onAction: _permanentlyDenied ? openAppSettings : _retry,
      );
    }
    // ได้สิทธิ์แล้ว → แสดงกล้อง พร้อม errorBuilder ให้ลองใหม่ถ้ากล้องเปิดไม่ได้
    return MobileScanner(
      controller: _cam,
      errorBuilder: (context, error, child) => _CameraMessage(
        icon: Icons.error_outline,
        message: 'เปิดกล้องไม่ได้: ${error.errorCode.name}',
        actionLabel: 'ลองใหม่',
        onAction: _retry,
      ),
    );
  }
}

/// ข้อความ + ปุ่มบนพื้นที่กล้อง (สิทธิ์ถูกปฏิเสธ / กล้อง error)
class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 44),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// แถบเลือกปลายทาง: แผนก (out/return) หรือรอบนึ่ง (in) + ชื่อผู้รับ (out)
class _TargetSelector extends ConsumerWidget {
  const _TargetSelector({
    required this.mode,
    required this.department,
    required this.batch,
    required this.receiverCtrl,
    required this.onDepartment,
    required this.onBatch,
  });

  final ScanMode mode;
  final Department? department;
  final SterilizationBatch? batch;
  final TextEditingController receiverCtrl;
  final ValueChanged<Department?> onDepartment;
  final ValueChanged<SterilizationBatch?> onBatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode == ScanMode.scanIn) {
      final batches = ref.watch(batchesProvider('PASSED'));
      return Container(
        color: SterelisColors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: batches.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text('โหลดรอบนึ่งไม่ได้: ${apiErrorMessage(e)}',
              style:
                  const TextStyle(color: SterelisColors.danger, fontSize: 12)),
          data: (list) => Column(children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<SterilizationBatch>(
                  initialValue:
                      list.any((b) => b.id == batch?.id) ? batch : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: list.isEmpty
                        ? 'ยังไม่มีรอบนึ่ง — กด "รอบใหม่"'
                        : 'รอบนึ่ง (เฉพาะรอบที่ผ่านการตรวจ)',
                    prefixIcon:
                        const Icon(Icons.local_fire_department_outlined),
                    isDense: true,
                  ),
                  items: list
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              'รอบ ${b.roundNo ?? '-'} · ${b.sterilizerName ?? b.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: onBatch,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final created = await showCreateBatchSheet(context, ref);
                  if (created != null) {
                    ref.invalidate(batchesProvider('PASSED'));
                    onBatch(created);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('รอบใหม่'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: SterelisColors.blue50,
                    foregroundColor: SterelisColors.blue600),
              ),
            ]),
          ]),
        ),
      );
    }

    final departments = ref.watch(departmentsProvider);
    // เพิ่มสถานที่ใหม่ได้เฉพาะ SUPERVISOR/ADMIN (ตรงกับ guard ฝั่ง server)
    final role = ref.watch(authControllerProvider).user?.role;
    final canAddPlace = role == 'SUPERVISOR' || role == 'ADMIN';

    return Container(
      color: SterelisColors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: departments.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (e, _) => Text('โหลดแผนกไม่ได้: ${apiErrorMessage(e)}',
            style: const TextStyle(color: SterelisColors.danger, fontSize: 12)),
        data: (list) => Column(children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<Department>(
                initialValue:
                    list.any((d) => d.id == department?.id) ? department : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: mode == ScanMode.scanOut
                      ? 'แผนกปลายทาง (บังคับ)'
                      : 'แผนกที่ส่งของคืน (บังคับ)',
                  prefixIcon: const Icon(Icons.apartment_outlined),
                ),
                items: list
                    .map((d) => DropdownMenuItem(
                        value: d, child: Text(d.displayName)))
                    .toList(),
                onChanged: onDepartment,
              ),
            ),
            if (canAddPlace) ...[
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final created = await showCreateDepartmentSheet(context);
                  if (created != null) {
                    ref.invalidate(departmentsProvider);
                    onDepartment(created);
                  }
                },
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('เพิ่มสถานที่'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: SterelisColors.blue50,
                    foregroundColor: SterelisColors.blue600),
              ),
            ],
          ]),
          if (mode == ScanMode.scanOut) ...[
            const SizedBox(height: 8),
            TextField(
              controller: receiverCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อผู้รับ (ไม่บังคับ)',
                prefixIcon: Icon(Icons.person_outline),
                isDense: true,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ScannedPanel extends StatelessWidget {
  const _ScannedPanel({
    required this.items,
    required this.mode,
    required this.submitting,
    required this.canSubmit,
    required this.onConfirm,
    required this.onClear,
    required this.onRemove,
  });

  final List<_ScannedItem> items;
  final ScanMode mode;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onConfirm, onClear;
  final ValueChanged<_ScannedItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final okCount = items.where((i) => i.eligible).length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Text('สแกนแล้ว ${items.length} ห่อ',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SterelisColors.textStrong)),
          if (okCount != items.length) ...[
            const SizedBox(width: 6),
            Text('(ผ่าน $okCount)',
                style: const TextStyle(
                    fontSize: 12, color: SterelisColors.textMuted)),
          ],
          const Spacer(),
          if (items.isNotEmpty)
            TextButton(onPressed: onClear, child: const Text('ล้าง')),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? const Center(
                child: Text('ชี้กล้องไปที่ QR code ของห่อ',
                    style: TextStyle(color: SterelisColors.textFaint)))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) =>
                    _ScannedTile(item: items[i], onRemove: onRemove),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: canSubmit ? onConfirm : null,
          icon: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: Text(submitting
              ? 'กำลังบันทึก...'
              : 'ยืนยัน${mode.title}${okCount == 0 ? '' : ' ($okCount)'}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ),
    ]);
  }
}

/// เปิด sheet เปิดรอบนึ่งใหม่ (บันทึกผล CI/BI ผ่านให้เลย) — คืน batch ที่พร้อมใช้
/// เปิด sheet เพิ่มแผนก/สถานที่ปลายทางใหม่ — คืน Department ที่สร้างเมื่อสำเร็จ
Future<Department?> showCreateDepartmentSheet(BuildContext context) {
  return showModalBottomSheet<Department>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _CreateDepartmentSheet(),
  );
}

class _CreateDepartmentSheet extends ConsumerStatefulWidget {
  const _CreateDepartmentSheet();

  @override
  ConsumerState<_CreateDepartmentSheet> createState() =>
      _CreateDepartmentSheetState();
}

class _CreateDepartmentSheetState
    extends ConsumerState<_CreateDepartmentSheet> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isExternal = true; // เคสหลักของฟีเจอร์นี้คือส่งออกนอกโรงพยาบาล
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _codeCtrl.text.trim().length >= 2 && _nameCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final created = await ref.read(departmentRepositoryProvider).create(
            code: _codeCtrl.text.trim().toUpperCase(),
            name: _nameCtrl.text.trim(),
            type: _isExternal ? 'external' : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: SterelisColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('เพิ่มสถานที่ปลายทาง',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          const Text('เช่น โรงพยาบาลอื่นที่ส่งชุดอุปกรณ์ไปให้',
              style: TextStyle(fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          TextField(
            controller: _codeCtrl,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'รหัส (ห้ามซ้ำ)',
              hintText: 'เช่น EXT-PYT',
              prefixIcon: Icon(Icons.tag),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'ชื่อสถานที่',
              hintText: 'เช่น รพ.พญาไท',
              prefixIcon: Icon(Icons.apartment_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('สถานที่ภายนอกโรงพยาบาล',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('แสดงป้าย "(ภายนอก)" ต่อท้ายชื่อ',
                style: TextStyle(fontSize: 12, color: SterelisColors.textMuted)),
            value: _isExternal,
            activeThumbColor: SterelisColors.blue500,
            onChanged: _saving ? null : (v) => setState(() => _isExternal = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !_valid || _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('บันทึกสถานที่'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

Future<SterilizationBatch?> showCreateBatchSheet(
    BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<SterilizationBatch>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _CreateBatchSheet(),
  );
}

class _CreateBatchSheet extends ConsumerStatefulWidget {
  const _CreateBatchSheet();

  @override
  ConsumerState<_CreateBatchSheet> createState() => _CreateBatchSheetState();
}

class _CreateBatchSheetState extends ConsumerState<_CreateBatchSheet> {
  Sterilizer? _sterilizer;
  int _roundNo = 1;
  bool _biPassed = true;
  bool _saving = false;

  Future<void> _submit() async {
    final st = _sterilizer;
    if (st == null) return;
    setState(() => _saving = true);
    try {
      final batch = await ref.read(batchRepositoryProvider).createPassed(
            sterilizerId: st.id,
            roundNo: _roundNo,
            biResult: _biPassed,
          );
      if (!mounted) return;
      Navigator.of(context).pop(batch);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sterilizers = ref.watch(sterilizersProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: SterelisColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('เปิดรอบนึ่งใหม่',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          const Text('บันทึกเป็นรอบที่ผ่านการตรวจ CI/BI แล้ว พร้อมนำเข้าคลัง',
              style: TextStyle(fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          const Text('เครื่องนึ่ง',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          sterilizers.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(apiErrorMessage(e),
                style: const TextStyle(color: SterelisColors.danger)),
            data: (list) => DropdownButtonFormField<Sterilizer>(
              initialValue: _sterilizer,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.local_fire_department_outlined),
              ),
              items: list
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s.name)))
                  .toList(),
              onChanged: _saving ? null : (s) => setState(() => _sterilizer = s),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Text('รอบที่',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            IconButton.filledTonal(
              onPressed: _roundNo > 1 && !_saving
                  ? () => setState(() => _roundNo--)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 52,
              child: Text('$_roundNo',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: SterelisColors.textStrong)),
            ),
            IconButton.filledTonal(
              onPressed:
                  _saving ? null : () => setState(() => _roundNo++),
              icon: const Icon(Icons.add),
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ผลตรวจ BI ผ่าน',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('CI ถือว่าผ่านโดยอัตโนมัติ',
                style: TextStyle(fontSize: 12, color: SterelisColors.textMuted)),
            value: _biPassed,
            activeThumbColor: SterelisColors.success,
            onChanged: _saving ? null : (v) => setState(() => _biPassed = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sterilizer == null || _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('เปิดรอบ + บันทึกผลผ่าน'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _ScannedTile extends StatelessWidget {
  const _ScannedTile({required this.item, required this.onRemove});
  final _ScannedItem item;
  final ValueChanged<_ScannedItem> onRemove;

  @override
  Widget build(BuildContext context) {
    // ของหมดอายุ (เบิกออก) → การ์ดแดง "ห้ามใช้" เด่นชัดตาม design system
    if (item.isExpired && item.blockReason != null) {
      return Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(item),
        child: BlockedCard(
          title: 'ห้ามใช้ — หมดอายุแล้ว',
          detail: '${item.id}${item.name != null ? ' · ${item.name}' : ''}',
        ),
      );
    }

    final blocked = item.blockReason != null || item.serverError != null;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: SterelisColors.dangerBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: SterelisColors.danger),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SterelisColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: blocked
                  ? const Color(0xFFF4BFC1)
                  : SterelisColors.border),
        ),
        child: Row(children: [
          if (item.loading)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(
              blocked ? Icons.error_outline : Icons.check_circle,
              color:
                  blocked ? SterelisColors.danger : SterelisColors.success,
              size: 20,
            ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.id,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              if (item.name != null && item.name!.isNotEmpty)
                Text(item.name!,
                    style: const TextStyle(
                        fontSize: 12, color: SterelisColors.textMuted)),
              if (item.blockReason != null)
                Text(item.blockReason!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: SterelisColors.danger,
                        fontWeight: FontWeight.w600))
              else if (item.serverError != null)
                Text(item.serverError!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: SterelisColors.danger,
                        fontWeight: FontWeight.w600))
              else if (item.warning != null)
                Text(item.warning!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: SterelisColors.warning,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
          if (!item.loading &&
              item.daysLeft != null &&
              item.blockReason == null)
            Text('เหลือ ${item.daysLeft} วัน',
                style: const TextStyle(
                    fontSize: 11, color: SterelisColors.textMuted)),
        ]),
      ),
    );
  }
}
