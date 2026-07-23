import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/printer/printer_adapter.dart';
import '../../../../core/printer/printer_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../print_jobs/presentation/widgets/submit_print_job_sheet.dart';

/// เปิด sheet สร้างห่อ (สร้างได้ทีละหลายห่อ) — เมื่อสำเร็จแสดง dialog สรุป + ปุ่มพิมพ์ทั้งหมด
Future<void> showCreatePackageSheet(BuildContext context, WidgetRef ref) async {
  final created = await showModalBottomSheet<List<PackageModel>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _CreatePackageSheet(),
  );
  if (created == null || created.isEmpty || !context.mounted) return;

  final l10n = AppLocalizations.of(context);
  final shouldPrint = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
              color: SterelisColors.successBg, shape: BoxShape.circle),
          child:
              const Icon(Icons.check, color: SterelisColors.success, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            created.length == 1
                ? l10n.cpCreatedOne
                : l10n.cpCreatedMany(created.length),
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(created.first.templateName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            ...created.map((p) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: SterelisColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(p.id,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                )),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: Text(l10n.commonClose),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dctx).pop(true),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: Text(created.length == 1
              ? l10n.pjPrintLabel
              : l10n.cpPrintAll(created.length)),
        ),
      ],
    ),
  );

  if (shouldPrint == true && context.mounted) {
    // ใช้ Print Job Queue เป็นทางหลัก (สร้างงานผ่าน backend → Gateway พิมพ์/ACK)
    // ไม่พิมพ์ตรงจาก client อีกต่อไป — printedAt/reprintCount อัปเดตจาก Gateway ACK เท่านั้น
    await submitPrintJobs(context, ref, created);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ⚠️ Legacy direct-print (Bluetooth/System) — **ไม่ได้ผูกกับปุ่มพิมพ์ใน UI แล้ว**
// เก็บไว้เป็น fallback ฉุกเฉินระดับโค้ดเท่านั้น (เช่นกรณีไม่มี Gateway เลย) ห้ามใช้
// เป็นทางพิมพ์ปกติ เพราะไม่บันทึกประวัติ (printedAt/reprintCount) และไม่มีการยืนยัน
// ว่าพิมพ์จริงผ่าน Gateway ACK — ดู submitPrintJobs / Print Job Queue แทน
// ─────────────────────────────────────────────────────────────────────────

/// (legacy) พิมพ์ตรงห่อเดียว — ไม่ผูกกับ UI แล้ว ดู submitPrintJobs
Future<void> printPackageLabel(
        BuildContext context, WidgetRef ref, PackageModel pkg) =>
    printPackageLabels(context, ref, [pkg]);

/// (legacy) พิมพ์ตรงหลายห่อ — ไม่ผูกกับ UI แล้ว ดู submitPrintJobs
Future<void> printPackageLabels(
    BuildContext context, WidgetRef ref, List<PackageModel> pkgs) async {
  if (pkgs.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final printer = ref.read(printerAdapterProvider);
  try {
    if (!printer.isConnected) await printer.connect();
    var ok = 0;
    for (final pkg in pkgs) {
      // ใช้วันที่จริงจาก backend เท่านั้น — ห่อที่ยังไม่นึ่ง (null) label จะ
      // พิมพ์แถบ "ยังไม่ผ่านการฆ่าเชื้อ" แทนวันที่ ห้ามคำนวณวันโดยประมาณ
      // เด็ดขาด (ความปลอดภัยผู้ป่วย — ผล audit ระดับ Critical)
      await printer.printLabel(LabelData(
        packageId: pkg.id,
        setName: pkg.templateName,
        wrapType: pkg.wrapType == 'SEAL' ? 'ห่อซีล' : 'ห่อผ้า',
        sterilizeDate: pkg.sterilizeDate,
        expiryDate: pkg.expiryDate,
      ));
      ok++;
      // หมายเหตุ (AI_DEVELOPMENT_GUARDRAILS.md ข้อ 2): "ห้ามถือว่าเปิด Print
      // Dialog เท่ากับพิมพ์สำเร็จ" และ "ห้ามให้ PWA ตั้งสถานะ Print Job เป็น
      // PRINTED" — printer.printLabel() ที่สำเร็จแปลว่าส่งข้อมูลออกไปเท่านั้น
      // ไม่ใช่หลักฐานว่าเครื่องพิมพ์จริง เดิมโค้ดนี้เรียก
      // POST /packages/:id/printed ให้ตัวเองทันทีหลังบรรทัดนี้ ซึ่งเป็นการที่
      // client ยืนยันความสำเร็จเอง ตอนนี้ตัดออกแล้ว — printedAt/reprintCount
      // ที่เป็นทางการจะถูกอัปเดตเฉพาะผ่าน Print Job Queue + Gateway ACK
      // (ดู apps/api/src/modules/print-jobs) ซึ่งยังไม่ได้ผูกกับปุ่มพิมพ์นี้ในรอบนี้
    }
    messenger.showSnackBar(SnackBar(
      content: Text(pkgs.length == 1
          ? l10n.cpPrintSentOne(printer.displayName)
          : l10n.cpPrintSentMany(ok, printer.displayName)),
      backgroundColor: SterelisColors.success,
    ));
  } on PrinterException catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e.message), backgroundColor: SterelisColors.danger));
  } catch (_) {
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.cpPrintFailed),
        backgroundColor: SterelisColors.danger));
  }
}

class _CreatePackageSheet extends ConsumerStatefulWidget {
  const _CreatePackageSheet();

  @override
  ConsumerState<_CreatePackageSheet> createState() =>
      _CreatePackageSheetState();
}

class _CreatePackageSheetState extends ConsumerState<_CreatePackageSheet> {
  SetTemplate? _template;
  String _wrapType = 'SEAL';
  int _quantity = 1;
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  int _savedCount = 0;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final template = _template;
    if (template == null) return;
    setState(() {
      _saving = true;
      _savedCount = 0;
    });
    final repo = ref.read(packageRepositoryProvider);
    final notes = _notesCtrl.text.trim();
    final created = <PackageModel>[];
    try {
      // สร้างทีละห่อ backend ออกเลขรันเรียงกัน (กันเลขซ้ำฝั่ง server)
      for (var i = 0; i < _quantity; i++) {
        final pkg = await repo.create(
          setTemplateId: template.id,
          wrapType: _wrapType,
          notes: notes,
        );
        created.add(pkg);
        if (mounted) setState(() => _savedCount = created.length);
      }
      ref.invalidate(packagesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // ถ้าสร้างได้บางส่วนก่อน error → ปิด sheet คืนเท่าที่สำเร็จ ไม่ให้ห่อหาย
      if (created.isNotEmpty) {
        ref.invalidate(packagesProvider);
        Navigator.of(context).pop(created);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(apiErrorMessage(e)),
            backgroundColor: SterelisColors.danger),
      );
    }
  }

  Future<void> _createTemplate() async {
    final created = await showCreateTemplateSheet(context, ref);
    if (created != null && mounted) {
      setState(() {
        _template = created;
        _wrapType = created.defaultWrapType;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templates = ref.watch(templatesProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final role = ref.watch(authControllerProvider).user?.role;
    final canCreateTemplate = role == 'SUPERVISOR' || role == 'ADMIN';

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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.cpTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(l10n.cpSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          Text(l10n.cpSetLabel,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          templates.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(apiErrorMessage(e),
                style: const TextStyle(color: SterelisColors.danger)),
            data: (list) => ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...list.map((t) {
                      final sel = _template?.id == t.id;
                      return ChoiceChip(
                        label: Text(t.name),
                        selected: sel,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _template = t;
                          _wrapType = t.defaultWrapType;
                        }),
                        backgroundColor: SterelisColors.white,
                        selectedColor: SterelisColors.blue50,
                        labelStyle: TextStyle(
                          color: sel
                              ? SterelisColors.blue600
                              : SterelisColors.text,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: sel
                                  ? SterelisColors.blue500
                                  : SterelisColors.border,
                              width: sel ? 1.5 : 1),
                        ),
                      );
                    }),
                    if (canCreateTemplate)
                      ActionChip(
                        avatar: const Icon(Icons.add,
                            size: 16, color: SterelisColors.blue600),
                        label: Text(l10n.cpNewSet),
                        onPressed: _saving ? null : _createTemplate,
                        backgroundColor: SterelisColors.blue50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: SterelisColors.blue500),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(l10n.cpWrapType,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'SEAL', label: Text(l10n.dmWrapSeal)),
              ButtonSegment(value: 'CLOTH', label: Text(l10n.dmWrapCloth)),
            ],
            selected: {_wrapType},
            onSelectionChanged: (s) => setState(() => _wrapType = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? SterelisColors.blue500
                      : SterelisColors.white),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? Colors.white
                      : SterelisColors.textMuted),
            ),
          ),
          const SizedBox(height: 18),
          // จำนวนห่อที่จะสร้างพร้อมกัน
          Row(children: [
            Text(l10n.cpQuantity,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            _QtyButton(
              icon: Icons.remove,
              onTap: _quantity > 1 && !_saving
                  ? () => setState(() => _quantity--)
                  : null,
            ),
            SizedBox(
              width: 52,
              child: Text('$_quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: SterelisColors.textStrong)),
            ),
            _QtyButton(
              icon: Icons.add,
              onTap: _quantity < 50 && !_saving
                  ? () => setState(() => _quantity++)
                  : null,
            ),
          ]),
          const SizedBox(height: 6),
          Text(l10n.cpMaxQty,
              style: const TextStyle(fontSize: 12, color: SterelisColors.textFaint)),
          const SizedBox(height: 18),
          TextField(
            controller: _notesCtrl,
            enabled: !_saving,
            decoration: InputDecoration(labelText: l10n.cpNotes),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _template == null || _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.qr_code_2),
            label: Text(_saving
                ? l10n.cpSavingProgress(_savedCount, _quantity)
                : _quantity == 1
                    ? l10n.cpSaveOne
                    : l10n.cpSaveMany(_quantity)),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

/// เปิด sheet สร้างชุดอุปกรณ์ใหม่ (SUPERVISOR/ADMIN) — คืนค่า SetTemplate ที่สร้างสำเร็จ
Future<SetTemplate?> showCreateTemplateSheet(
    BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<SetTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _CreateTemplateSheet(),
  );
}

class _CreateTemplateSheet extends ConsumerStatefulWidget {
  const _CreateTemplateSheet();

  @override
  ConsumerState<_CreateTemplateSheet> createState() =>
      _CreateTemplateSheetState();
}

class _CreateTemplateSheetState extends ConsumerState<_CreateTemplateSheet> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _itemCtrls = <TextEditingController>[TextEditingController()];
  String _wrapType = 'SEAL';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    for (final c in _itemCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final items = _itemCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (code.isEmpty || name.isEmpty || items.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).ctValidationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref.read(templateRepositoryProvider).create(
            code: code,
            name: name,
            itemList: items,
            defaultWrapType: _wrapType,
          );
      ref.invalidate(templatesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = apiErrorMessage(e);
      });
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.ctTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(l10n.ctSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _codeCtrl,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: l10n.ctCode,
                      hintText: l10n.ctCodeHint,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: l10n.ctName,
                      hintText: l10n.ctNameHint,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.ctDefaultWrap,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'SEAL', label: Text(l10n.dmWrapSeal)),
                      ButtonSegment(
                          value: 'CLOTH', label: Text(l10n.dmWrapCloth)),
                    ],
                    selected: {_wrapType},
                    onSelectionChanged: _saving
                        ? null
                        : (s) => setState(() => _wrapType = s.first),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.ctItems,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _itemCtrls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _itemCtrls[i],
                            enabled: !_saving,
                            decoration: InputDecoration(
                              labelText: l10n.ctItemN(i + 1),
                            ),
                          ),
                        ),
                        if (_itemCtrls.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: SterelisColors.danger),
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _itemCtrls.removeAt(i).dispose();
                                    }),
                          ),
                      ]),
                    ),
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _itemCtrls.add(TextEditingController())),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.ctAddItem),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: SterelisColors.danger)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? l10n.scanSaving : l10n.ctSave),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? SterelisColors.blue50 : SterelisColors.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon,
              color: enabled
                  ? SterelisColors.blue600
                  : SterelisColors.textFaint),
        ),
      ),
    );
  }
}
