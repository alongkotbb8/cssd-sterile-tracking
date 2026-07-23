import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../../../l10n/app_localizations.dart';

/// ตรวจรูปแบบเลขห่อ (running number) — ใช้ร่วมกันทั้งการสแกน QR และพิมพ์เลขเอง
///
/// QR ของระบบเก็บแค่ `package_id` เท่านั้น (CLAUDE.md ข้อ 3) รูปแบบเลขรันคือ
/// `{SET_CODE}-{YYYYMMDD}-{SEQ4}` (เช่น `DELIV-20260630-0007`) — อักขระที่เป็นไปได้
/// คือ ตัวอักษร/ตัวเลข/ขีด (-) เท่านั้น การตรวจนี้กันสแกน QR อื่น (ลิงก์/นามบัตร)
/// หรือกรอกอักขระแปลกปลอมแล้วยิง lookup ไป backend โดยเปล่าประโยชน์ (2.4)
/// แยกเป็น pure function เพื่อ unit-test ได้ (ดู package_id_validation_test.dart)
bool isValidPackageId(String id) {
  if (id.isEmpty || id.length > 60) return false;
  return RegExp(r'^[A-Za-z0-9-]+$').hasMatch(id);
}

enum ScanMode { scanIn, scanOut, scanReturn, scanReprocess }

/// ป้ายชื่อโหมด (i18n) — "เข้ารอบนึ่ง" ห่อจะเข้าคลัง (STERILE) อัตโนมัติเมื่อ
/// SUPERVISOR/ADMIN บันทึกผล CI/BI ว่าผ่าน (ลำดับถูกหลัก traceability)
String scanModeTitle(AppLocalizations l10n, ScanMode m) => switch (m) {
      ScanMode.scanIn => l10n.scanModeIn,
      ScanMode.scanOut => l10n.scanModeOut,
      ScanMode.scanReturn => l10n.scanModeReturn,
      ScanMode.scanReprocess => l10n.scanModeReprocess,
    };

extension on ScanMode {
  /// สถานะห่อที่ mode นี้รับได้
  /// - เบิกออก: STERILE (ปกติ) และ PACKED (ส่งออกโดยยังไม่ฆ่าเชื้อ เช่น ส่ง รพ.อื่น)
  /// - ส่งคืน: ISSUED (ปกติ → รอ reprocess) และ PACKED_OUT (คืนแล้วกลับเป็น PACKED)
  /// - reprocess: RETURNED (ส่งคืนแล้ว) → PACKED เพื่อเข้ารอบนึ่งใหม่
  Set<String> get allowedStatuses => switch (this) {
        ScanMode.scanIn => const {'PACKED'},
        ScanMode.scanOut => const {'STERILE', 'PACKED'},
        ScanMode.scanReturn => const {'ISSUED', 'PACKED_OUT'},
        ScanMode.scanReprocess => const {'RETURNED'},
      };
}

/// รายการที่สแกนแล้ว + ผล lookup
class _ScannedItem {
  final String id;
  final bool isManual; // true = พิมพ์เลขเอง (กล้องใช้ไม่ได้) — ต้อง audit แยก
  String? name;
  String? status;
  int? daysLeft;
  bool isExpired = false;
  bool loading = true;
  String? blockReason; // null = ผ่าน
  String? warning; // เตือนแต่ไม่บล็อก (เช่น เบิกออกของที่ยังไม่ฆ่าเชื้อ)
  String? serverError; // error จากตอนยืนยัน

  _ScannedItem(this.id, {this.isManual = false});
  bool get eligible => !loading && blockReason == null;
}

/// ผลลัพธ์ 1 ห่อหลังกดยืนยัน — ใช้แสดงในหน้าสรุปผล (แทนการบอกผ่าน SnackBar อย่างเดียว)
typedef _AttemptResult = ({String id, String? name, bool success, String? error});

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
  // facing: back = กล้องหลังเป็นค่าเริ่มต้น (สแกน QR บนห่อ) — สลับได้ด้วยปุ่มบน AppBar
  late final MobileScannerController _cam =
      MobileScannerController(autoStart: false, facing: CameraFacing.back);
  StreamSubscription<BarcodeCapture>? _detectSub;

  /// null = ยังไม่ตรวจ, true = อนุญาตแล้ว, false = ถูกปฏิเสธ
  bool? _cameraGranted;
  bool _permanentlyDenied = false;
  // กัน race: การขอ permission จะ pause→resume แอป ทำให้ lifecycle handler
  // เรียก init/start ซ้อนกับรอบแรก → mobile_scanner โยน genericError
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectSub = _cam.barcodes.listen(_onDetect);
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_busy) return; // มี init/start ค้างอยู่ อย่าเริ่มซ้ำ (กัน genericError)
    _busy = true;
    try {
      if (kIsWeb) {
        // เว็บ/PWA: permission_handler รองรับกล้องไม่ครบ — ปล่อยให้เบราว์เซอร์
        // prompt เอง (getUserMedia) ตอน start() ต้องรันผ่าน HTTPS (secure context)
        // ถ้าถูกปฏิเสธ/ไม่ใช่ https → start() จะ error แล้วไปโผล่ที่ errorBuilder
        if (mounted) {
          setState(() {
            _cameraGranted = true;
            _permanentlyDenied = false;
          });
        }
        await _cam.start();
        return;
      }
      final status = await Permission.camera.request();
      if (!mounted) return;
      setState(() {
        _cameraGranted = status.isGranted;
        _permanentlyDenied = status.isPermanentlyDenied;
      });
      if (status.isGranted) {
        await _cam.start();
      }
    } catch (_) {
      // MobileScanner จะแสดง error ผ่าน errorBuilder ให้กด "ลองใหม่" ได้
    } finally {
      _busy = false;
    }
  }

  /// start กล้องแบบกัน start ซ้อน (ใช้ตอน resume)
  Future<void> _safeStart() async {
    if (_busy) return;
    _busy = true;
    try {
      await _cam.start();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _cameraGranted = null;
      _permanentlyDenied = false;
    });
    await _initCamera();
  }

  /// สลับกล้องหน้า/หลัง — บนเว็บที่มีกล้องเดียวอาจสลับไม่ได้ (จับ error ไว้เงียบ ๆ)
  Future<void> _switchCamera() async {
    try {
      await _cam.switchCamera();
      if (_torchOn && mounted) setState(() => _torchOn = false); // ไฟฉายรีเซ็ตเมื่อสลับกล้อง
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).scanSwitchCameraFailed),
        ));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraGranted != true) {
      // ผู้ใช้อาจเพิ่งไปกดอนุญาตสิทธิ์ใน "ตั้งค่าเครื่อง" แล้วกลับมาแอป —
      // ตรวจสิทธิ์ใหม่ตอน resume ถ้ายังไม่มี init ค้างอยู่ (กัน start ซ้อน)
      if (state == AppLifecycleState.resumed && !_busy) _initCamera();
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _detectSub ??= _cam.barcodes.listen(_onDetect);
        unawaited(_safeStart());
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
      _addItem(raw); // debounce ของเดิมในรายการ ทำอยู่แล้วใน _addItem
    }
  }

  // กัน SnackBar เตือน QR ผิดรูปแบบเด้งรัวๆ ระหว่างกล้องอ่าน frame เดิมซ้ำ
  DateTime _lastInvalidScanNotice = DateTime.fromMillisecondsSinceEpoch(0);

  /// เพิ่มห่อเข้ารายการสแกน — ใช้ร่วมกันทั้งจากกล้องและกรอกเลขเอง (manual entry)
  /// กัน id ซ้ำที่มีอยู่แล้วในรายการ (debounce การสแกนเดิมซ้ำ)
  void _addItem(String id, {bool isManual = false}) {
    // 2.4 — ตรวจรูปแบบเลขห่อก่อนเสมอ (ทั้ง QR และพิมพ์เอง) กันยิง lookup ด้วยค่าขยะ
    // ฝั่งพิมพ์เอง form validator กันไว้แล้วชั้นหนึ่ง — ตรงนี้กัน QR ที่ไม่ใช่เลขห่อ
    if (!isValidPackageId(id)) {
      if (!isManual) _notifyInvalidScan();
      return;
    }
    if (_items.any((i) => i.id == id)) return;
    final item = _ScannedItem(id, isManual: isManual);
    setState(() => _items.insert(0, item));
    HapticFeedback.mediumImpact();
    _lookup(item);
  }

  /// เตือนเมื่อสแกนโดน QR ที่ไม่ใช่เลขห่อของระบบ (throttle 2 วินาที)
  void _notifyInvalidScan() {
    final now = DateTime.now();
    if (now.difference(_lastInvalidScanNotice) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalidScanNotice = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).scanInvalidQr),
      duration: const Duration(seconds: 1),
    ));
  }

  /// Fallback เมื่อกล้องใช้ไม่ได้ (per AI_DEVELOPMENT_GUARDRAILS.md ข้อ 7) —
  /// พิมพ์เลขห่อเอง ระบบจะ validate รูปแบบเบื้องต้น + backend lookup จริงอีกชั้น
  /// และ audit ทุกรายการที่มาจากทางนี้ด้วย flag `manualEntry` แยกจากการสแกน
  Future<void> _showManualEntryDialog() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final id = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.scanManualTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: l10n.scanManualHint,
              helperText: l10n.scanManualHelper,
              helperMaxLines: 2,
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return l10n.scanManualEmpty;
              if (s.length > 60) return l10n.scanManualTooLong;
              // ใช้กติกาเดียวกับตอนสแกน QR (isValidPackageId) — charset เดียวกัน
              if (!isValidPackageId(s)) {
                return l10n.scanManualCharset;
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: Text(l10n.actionCancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dctx).pop(ctrl.text.trim().toUpperCase());
              }
            },
            child: Text(l10n.commonAdd),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;
    _addItem(id, isManual: true);
  }

  Future<void> _lookup(_ScannedItem item) async {
    final l10n = AppLocalizations.of(context);
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
        ..blockReason = apiErrorMessage(l10n, e);
    }
    if (mounted) setState(() {});
  }

  /// กติกาบล็อกฝั่ง client (server ตรวจซ้ำอีกชั้น)
  String? _blockReason(LookupResult r) {
    final l10n = AppLocalizations.of(context);
    if (_mode == ScanMode.scanOut && r.isExpired) {
      return l10n.scanBlockExpired;
    }
    final st = r.package.status;
    if (!_mode.allowedStatuses.contains(st)) {
      final label = packageStatusStyle(l10n, st).label;
      return l10n.scanBlockStatus(label, scanModeTitle(l10n, _mode));
    }
    return null;
  }

  /// เตือนแต่ไม่บล็อก — เบิกออกของที่แพ็กแล้วแต่ยังไม่ผ่านการฆ่าเชื้อ
  String? _warning(LookupResult r) {
    if (_mode == ScanMode.scanOut && r.package.status == 'PACKED') {
      return AppLocalizations.of(context).scanWarnUnsterile;
    }
    return null;
  }

  bool get _readyToSubmit {
    if (_submitting) return false;
    if (_items.where((i) => i.eligible).isEmpty) return false;
    return switch (_mode) {
      ScanMode.scanIn => _batch != null,
      ScanMode.scanOut || ScanMode.scanReturn => _department != null,
      ScanMode.scanReprocess => true, // ไม่ต้องเลือกปลายทาง
    };
  }

  Future<void> _confirm() async {
    final eligible = _items.where((i) => i.eligible).toList();
    if (eligible.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    final modeTitle = scanModeTitle(l10n, _mode);
    final receiver = _receiverCtrl.text.trim();
    // pop-up ยืนยันก่อนบันทึกจริง
    final destination = switch (_mode) {
      ScanMode.scanIn => l10n.scanDestBatch(
          '${_batch?.roundNo ?? '-'}', _batch?.sterilizerName ?? ''),
      ScanMode.scanOut => l10n.scanDestDept(_department?.name ?? '') +
          (receiver.isNotEmpty ? l10n.scanReceiverSuffix(receiver) : ''),
      ScanMode.scanReturn => l10n.scanDestDept(_department?.name ?? ''),
      ScanMode.scanReprocess => l10n.scanDestReprocess,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.scanConfirmTitle(modeTitle)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.scanConfirmCount(modeTitle, eligible.length),
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
              child: Text(l10n.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);

    try {
      final repo = ref.read(scanRepositoryProvider);
      // แยกยิงเป็น 2 ชุดถ้ามีทั้งสแกนและกรอกเอง — ต้องติด flag manualEntry
      // ให้ตรงความจริงต่อห่อ (audit log แยกที่มาได้ชัดเจน)
      final manualIds =
          eligible.where((i) => i.isManual).map((i) => i.id).toList();
      final scannedIds =
          eligible.where((i) => !i.isManual).map((i) => i.id).toList();

      Future<List<ScanResultItem>> submit(List<String> ids, bool manual) {
        if (ids.isEmpty) return Future.value(const []);
        return switch (_mode) {
          ScanMode.scanIn =>
            repo.scanIn(ids, _batch!.id, manualEntry: manual),
          ScanMode.scanOut => repo.scanOut(ids, _department!.id,
              receiverName: _receiverCtrl.text.trim(), manualEntry: manual),
          ScanMode.scanReturn =>
            repo.scanReturn(ids, _department!.id, manualEntry: manual),
          ScanMode.scanReprocess =>
            repo.scanReprocess(ids, manualEntry: manual),
        };
      }

      final results = [
        ...await submit(scannedIds, false),
        ...await submit(manualIds, true),
      ];

      final byId = {for (final r in results) r.packageId: r};
      final okCount = results.where((r) => r.success).length;
      final failCount = results.length - okCount;

      // เก็บรายละเอียดผลลัพธ์ไว้ก่อนแก้ _items — ใช้แสดงในหน้าสรุปผล
      final attempted = eligible
          .map((i) => (
                id: i.id,
                name: i.name,
                success: byId[i.id]?.success ?? false,
                error: byId[i.id]?.error,
              ))
          .toList();

      setState(() {
        // ลบตัวที่สำเร็จออก คงตัวที่พลาดไว้พร้อมเหตุผล (กด "ยืนยัน" ซ้ำ = ลองใหม่เฉพาะที่ค้าง)
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
      // เสียง/แรงสั่นต่างกันระหว่างสำเร็จทั้งหมดกับมีรายการไม่ผ่าน ให้รู้สึกต่างชัดเจน
      if (failCount == 0) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.heavyImpact();
      }
      await _showResultDialog(attempted, okCount, failCount);
    } catch (e) {
      setState(() => _submitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  /// หน้าสรุปผลหลังยืนยัน — แสดงรายการทุกห่อพร้อมสำเร็จ/ไม่ผ่านเป็นรายตัว
  /// (เดิมแจ้งผ่าน SnackBar อย่างเดียว มองไม่เห็นว่าห่อไหนพลาดเพราะอะไร)
  Future<void> _showResultDialog(
      List<_AttemptResult> attempted, int okCount, int failCount) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(failCount == 0
            ? l10n.scanResultOkTitle(scanModeTitle(l10n, _mode), okCount)
            : l10n.scanResultMixedTitle(okCount, failCount)),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: attempted.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final a = attempted[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    a.success ? Icons.check_circle : Icons.error_outline,
                    color: a.success
                        ? SterelisColors.success
                        : SterelisColors.danger,
                  ),
                  title: Text(a.id,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.5)),
                  subtitle: a.success
                      ? (a.name != null ? Text(a.name!) : null)
                      : Text(a.error ?? l10n.scanUnknownReason,
                          style:
                              const TextStyle(color: SterelisColors.danger)),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(l10n.commonClose),
          ),
          if (failCount > 0)
            FilledButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                // รายการที่เหลือใน _items คือชุดที่ไม่ผ่านพอดี (สำเร็จถูกลบไปแล้ว)
                _confirm();
              },
              child: Text(l10n.scanRetryFailed),
            ),
        ],
      ),
    );
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

  /// ยืนยันก่อนล้างรายการที่สแกนไว้ — กันกดโดนพลาดแล้วต้องสแกนใหม่ทั้งหมด
  Future<void> _confirmClear() async {
    if (_items.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.scanClearTitle),
        content: Text(l10n.scanClearBody(_items.length)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: Text(l10n.actionCancel)),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: SterelisColors.danger),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.scanClearAction),
          ),
        ],
      ),
    );
    if (ok == true) setState(_items.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_alt_outlined),
            tooltip: l10n.scanManualTooltip,
            onPressed: _showManualEntryDialog,
          ),
          if (_cameraGranted == true) ...[
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: l10n.scanSwitchCameraTooltip,
              onPressed: _switchCamera,
            ),
            IconButton(
              icon: Icon(_torchOn
                  ? Icons.flashlight_off_outlined
                  : Icons.flashlight_on_outlined),
              tooltip: l10n.scanTorchTooltip,
              onPressed: () {
                setState(() => _torchOn = !_torchOn);
                _cam.toggleTorch();
              },
            ),
          ],
        ],
      ),
      body: Column(children: [
        Container(
          color: SterelisColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SegmentedButton<ScanMode>(
            // ซ่อนไอคอนติ๊ก + label กระชับ เพื่อให้ 4 โหมดพอดีจอแคบ (ไม่ overflow)
            showSelectedIcon: false,
            segments: ScanMode.values
                .map((m) => ButtonSegment(
                    value: m,
                    label: Text(scanModeTitle(l10n, m),
                        style: const TextStyle(fontSize: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            selected: {_mode},
            onSelectionChanged: (s) => _switchMode(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6)),
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
            onClear: _confirmClear,
            onRemove: (item) => setState(() => _items.remove(item)),
          ),
        ),
      ]),
    );
  }

  Widget _buildCameraArea() {
    final l10n = AppLocalizations.of(context);
    // ยังไม่ตรวจสิทธิ์ → กำลังโหลด
    if (_cameraGranted == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    // ถูกปฏิเสธ → แสดงเหตุผล + ปุ่มดำเนินการ (ไม่ปล่อยให้จอดำเฉย ๆ)
    // เว็บ/PWA เปิดสิทธิ์ต่างจากมือถือ (ที่ไอคอนแม่กุญแจบนแถบที่อยู่ ไม่ใช่ตั้งค่าเครื่อง)
    if (_cameraGranted == false) {
      return _CameraMessage(
        icon: Icons.no_photography_outlined,
        message: kIsWeb
            ? l10n.scanCameraWebBlocked
            : _permanentlyDenied
                ? l10n.scanCameraDenied
                : l10n.scanCameraNeed,
        actionLabel:
            (!kIsWeb && _permanentlyDenied) ? l10n.scanOpenSettings : l10n.commonRetry,
        onAction: (!kIsWeb && _permanentlyDenied) ? openAppSettings : _retry,
      );
    }
    // ได้สิทธิ์แล้ว → แสดงกล้อง พร้อม errorBuilder ให้ลองใหม่ถ้ากล้องเปิดไม่ได้
    return MobileScanner(
      controller: _cam,
      errorBuilder: (context, error, child) => _CameraMessage(
        icon: Icons.no_photography_outlined,
        message: kIsWeb
            ? l10n.scanCameraWebError
            : l10n.scanCameraError(error.errorCode.name),
        actionLabel: l10n.commonRetry,
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
    final l10n = AppLocalizations.of(context);
    if (mode == ScanMode.scanIn) {
      // เฉพาะรอบ PENDING เท่านั้น — เพิ่มห่อเข้ารอบที่บันทึกผลแล้วไม่ได้ (traceability)
      final batches = ref.watch(batchesProvider('PENDING'));
      final role = ref.watch(authControllerProvider).user?.role;
      final canRecordResult = role == 'SUPERVISOR' || role == 'ADMIN';
      return Container(
        color: SterelisColors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: batches.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text(l10n.batchLoadError(apiErrorMessage(l10n, e)),
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
                    labelText:
                        list.isEmpty ? l10n.batchNonePending : l10n.batchSelectLabel,
                    prefixIcon:
                        const Icon(Icons.local_fire_department_outlined),
                    isDense: true,
                  ),
                  items: list
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              l10n.batchRoundLabel(
                                    '${b.roundNo ?? '-'}',
                                    b.sterilizerName ?? b.id,
                                  ) +
                                  (b.packageCount != null
                                      ? l10n.batchPkgCountSuffix(b.packageCount!)
                                      : ''),
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
                    ref.invalidate(batchesProvider('PENDING'));
                    onBatch(created);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.batchNewButton),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: SterelisColors.blue50,
                    foregroundColor: SterelisColors.blue600),
              ),
            ]),
            if (canRecordResult && list.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final recorded = await showRecordResultSheet(context, ref);
                    if (recorded == true) {
                      ref.invalidate(batchesProvider('PENDING'));
                      onBatch(null);
                    }
                  },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(l10n.batchRecordResultButton),
                ),
              ),
          ]),
        ),
      );
    }

    // Reprocess ไม่ต้องเลือกปลายทาง — สแกนห่อที่ส่งคืน (RETURNED) แล้วยืนยันได้เลย
    if (mode == ScanMode.scanReprocess) {
      return Container(
        color: SterelisColors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          const Icon(Icons.recycling_outlined,
              size: 18, color: SterelisColors.teal500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.scanReprocessHint,
              style: const TextStyle(
                  fontSize: 12.5, color: SterelisColors.textMuted),
            ),
          ),
        ]),
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
        error: (e, _) => Text(l10n.deptLoadError(apiErrorMessage(l10n, e)),
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
                      ? l10n.deptDestRequired
                      : l10n.deptReturnRequired,
                  prefixIcon: const Icon(Icons.apartment_outlined),
                ),
                items: list
                    .map((d) => DropdownMenuItem(
                        value: d, child: Text(d.displayName(l10n))))
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
                label: Text(l10n.deptAddPlace),
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
              decoration: InputDecoration(
                labelText: l10n.deptReceiverOptional,
                prefixIcon: const Icon(Icons.person_outline),
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
    final l10n = AppLocalizations.of(context);
    final okCount = items.where((i) => i.eligible).length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Text(l10n.scanCountLabel(items.length),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SterelisColors.textStrong)),
          if (okCount != items.length) ...[
            const SizedBox(width: 6),
            Text(l10n.scanEligibleSuffix(okCount),
                style: const TextStyle(
                    fontSize: 12, color: SterelisColors.textMuted)),
          ],
          const Spacer(),
          if (items.isNotEmpty)
            TextButton(onPressed: onClear, child: Text(l10n.commonClear)),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? Center(
                child: Text(l10n.scanEmptyHint,
                    style: const TextStyle(color: SterelisColors.textFaint)))
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
              ? l10n.scanSaving
              : l10n.scanConfirmTitle(scanModeTitle(l10n, mode)) +
                  (okCount == 0 ? '' : ' ($okCount)')),
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
    final l10n = AppLocalizations.of(context);
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
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          Text(l10n.deptAddTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(l10n.deptAddSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          TextField(
            controller: _codeCtrl,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.deptCodeLabel,
              hintText: l10n.deptCodeHint,
              prefixIcon: const Icon(Icons.tag),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: l10n.deptNameLabel,
              hintText: l10n.deptNameHint,
              prefixIcon: const Icon(Icons.apartment_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.deptExternalTitle,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(l10n.deptExternalSubtitle,
                style: const TextStyle(
                    fontSize: 12, color: SterelisColors.textMuted)),
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
            label: Text(AppLocalizations.of(context).deptSaveButton),
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
  bool _saving = false;

  Future<void> _submit() async {
    final st = _sterilizer;
    if (st == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      // เปิดรอบเป็น PENDING เท่านั้น — ผล CI/BI บันทึกทีหลังโดย SUPERVISOR/ADMIN
      final batch = await ref.read(batchRepositoryProvider).create(
            sterilizerId: st.id,
            roundNo: _roundNo,
          );
      if (!mounted) return;
      Navigator.of(context).pop(batch);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          Text(l10n.batchOpenTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(l10n.batchOpenSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          Text(l10n.batchSterilizerLabel,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          sterilizers.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(apiErrorMessage(l10n, e),
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
            Text(l10n.batchRoundNo,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
            label: Text(l10n.batchOpenButton),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

/// Sheet บันทึกผล CI/BI ของรอบ PENDING — SUPERVISOR/ADMIN เท่านั้น
/// (backend บังคับ role ซ้ำอีกชั้น) คืน true เมื่อบันทึกสำเร็จ
Future<bool?> showRecordResultSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _RecordResultSheet(),
  );
}

class _RecordResultSheet extends ConsumerStatefulWidget {
  const _RecordResultSheet();

  @override
  ConsumerState<_RecordResultSheet> createState() => _RecordResultSheetState();
}

class _RecordResultSheetState extends ConsumerState<_RecordResultSheet> {
  SterilizationBatch? _batch;
  bool _ciPassed = true;
  bool _biPassed = true;
  bool _saving = false;

  Future<void> _submit() async {
    final b = _batch;
    if (b == null) return;

    final l10n = AppLocalizations.of(context);
    final willPass = _ciPassed && _biPassed;
    // ยืนยันซ้ำ — การบันทึกผลตัดสินสถานะห่อทั้งรอบ ย้อนกลับไม่ได้
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
            willPass ? l10n.batchConfirmPassTitle : l10n.batchConfirmFailTitle),
        content: Text(willPass
            ? l10n.batchConfirmPassBody(
                '${b.roundNo ?? '-'}', '${b.packageCount ?? '-'}')
            : l10n.batchConfirmFailBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: Text(l10n.actionCancel)),
          FilledButton(
            style: willPass
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: SterelisColors.danger),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(batchRepositoryProvider).recordResult(
            b.id,
            ciResult: _ciPassed,
            biResult: _biPassed,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            willPass ? l10n.batchRecordedPass : l10n.batchRecordedFail),
        backgroundColor:
            willPass ? SterelisColors.success : SterelisColors.warning,
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final batches = ref.watch(batchesProvider('PENDING'));
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
          Text(l10n.batchRecordTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(l10n.batchRecordSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          batches.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(apiErrorMessage(l10n, e),
                style: const TextStyle(color: SterelisColors.danger)),
            data: (list) => DropdownButtonFormField<SterilizationBatch>(
              initialValue: list.any((b) => b.id == _batch?.id) ? _batch : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.batchSelectToRecord,
                prefixIcon: const Icon(Icons.local_fire_department_outlined),
              ),
              items: list
                  .map((b) => DropdownMenuItem(
                        value: b,
                        child: Text(
                          l10n.batchRoundLabel(
                                '${b.roundNo ?? '-'}',
                                b.sterilizerName ?? b.id,
                              ) +
                              (b.packageCount != null
                                  ? l10n.batchPkgCountSuffix(b.packageCount!)
                                  : ''),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _saving ? null : (b) => setState(() => _batch = b),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.batchCiPass,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            value: _ciPassed,
            activeThumbColor: SterelisColors.success,
            onChanged: _saving ? null : (v) => setState(() => _ciPassed = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.batchBiPass,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            value: _biPassed,
            activeThumbColor: SterelisColors.success,
            onChanged: _saving ? null : (v) => setState(() => _biPassed = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _batch == null || _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.fact_check_outlined),
            label: Text(l10n.batchRecordButton),
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
    final l10n = AppLocalizations.of(context);
    // ของหมดอายุ (เบิกออก) → การ์ดแดง "ห้ามใช้" เด่นชัดตาม design system
    if (item.isExpired && item.blockReason != null) {
      return Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(item),
        child: BlockedCard(
          title: l10n.scanBlockExpired,
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
              Row(children: [
                Text(item.id,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                if (item.isManual) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: SterelisColors.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(l10n.scanManualBadge,
                        style: const TextStyle(
                            fontSize: 10, color: SterelisColors.textMuted)),
                  ),
                ],
              ]),
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
            Text(l10n.scanDaysLeft(item.daysLeft!),
                style: const TextStyle(
                    fontSize: 11, color: SterelisColors.textMuted)),
        ]),
      ),
    );
  }
}
