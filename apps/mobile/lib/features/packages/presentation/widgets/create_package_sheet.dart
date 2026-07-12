import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/printer/printer_adapter.dart';
import '../../../../core/printer/printer_provider.dart';
import '../../../../core/theme/app_theme.dart';

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
                ? 'สร้างห่อสำเร็จ'
                : 'สร้าง ${created.length} ห่อสำเร็จ',
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
          child: const Text('ปิด'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dctx).pop(true),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: Text(created.length == 1
              ? 'พิมพ์ label'
              : 'พิมพ์ทั้งหมด (${created.length})'),
        ),
      ],
    ),
  );

  if (shouldPrint == true && context.mounted) {
    await printPackageLabels(context, ref, created);
  }
}

/// พิมพ์ label ของห่อเดียว (ใช้จากหน้ารายละเอียด)
Future<void> printPackageLabel(
        BuildContext context, WidgetRef ref, PackageModel pkg) =>
    printPackageLabels(context, ref, [pkg]);

/// พิมพ์ label หลายห่อ — เชื่อมต่อเครื่องพิมพ์ครั้งเดียว แล้วส่งทีละใบ
Future<void> printPackageLabels(
    BuildContext context, WidgetRef ref, List<PackageModel> pkgs) async {
  if (pkgs.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final printer = ref.read(printerAdapterProvider);
  try {
    if (!printer.isConnected) await printer.connect();
    var ok = 0;
    for (final pkg in pkgs) {
      // ห่อที่ยังไม่นึ่งยังไม่มีวันหมดอายุจริง (backend คำนวณตอนสแกนเข้าคลัง)
      // ใช้วันโดยประมาณ = แพ็กวันนี้ + อายุตามชนิดห่อ
      final sterilize = pkg.sterilizeDate ?? DateTime.now();
      final expiry =
          pkg.expiryDate ?? sterilize.add(Duration(days: pkg.shelfLifeDays));
      await printer.printLabel(LabelData(
        packageId: pkg.id,
        setName: pkg.templateName,
        wrapType: pkg.wrapType == 'SEAL' ? 'ห่อซีล' : 'ห่อผ้า',
        sterilizeDate: sterilize,
        expiryDate: expiry,
      ));
      ok++;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(pkgs.length == 1
          ? 'ส่งพิมพ์ไปยัง ${printer.displayName} แล้ว'
          : 'ส่งพิมพ์ $ok label ไปยัง ${printer.displayName} แล้ว'),
      backgroundColor: SterelisColors.success,
    ));
  } on PrinterException catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e.message), backgroundColor: SterelisColors.danger));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('พิมพ์ไม่สำเร็จ ตรวจสอบเครื่องพิมพ์'),
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
          const Text('สร้างห่อใหม่',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          const Text('ระบบจะออกเลขรันให้อัตโนมัติเมื่อบันทึก',
              style: TextStyle(fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 18),
          const Text('ชุดอุปกรณ์',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                        label: const Text('ชุดใหม่'),
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
          const Text('ชนิดห่อ',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'SEAL', label: Text('ห่อซีล · 180 วัน')),
              ButtonSegment(value: 'CLOTH', label: Text('ห่อผ้า · 7 วัน')),
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
            const Text('จำนวน',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
          const Text('สร้างได้สูงสุด 50 ห่อต่อครั้ง',
              style: TextStyle(fontSize: 12, color: SterelisColors.textFaint)),
          const SizedBox(height: 18),
          TextField(
            controller: _notesCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'หมายเหตุ (ไม่บังคับ)'),
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
                ? 'กำลังสร้าง $_savedCount/$_quantity...'
                : _quantity == 1
                    ? 'บันทึก + ออกเลขรัน'
                    : 'บันทึก $_quantity ห่อ + ออกเลขรัน'),
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
      setState(() => _error = 'กรอกรหัส ชื่อชุด และรายการอุปกรณ์อย่างน้อย 1 รายการ');
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
          const Text('สร้างชุดอุปกรณ์ใหม่',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          const Text('ระบุว่าในอุปกรณ์ 1 ชุดมีอะไรบ้าง',
              style: TextStyle(fontSize: 13, color: SterelisColors.textMuted)),
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
                    decoration: const InputDecoration(
                      labelText: 'รหัสชุด (ใช้ขึ้นต้นเลขรัน)',
                      hintText: 'เช่น DELIV',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อชุดอุปกรณ์',
                      hintText: 'เช่น ชุดทำคลอด',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('ชนิดห่อเริ่มต้น',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'SEAL', label: Text('ห่อซีล · 180 วัน')),
                      ButtonSegment(
                          value: 'CLOTH', label: Text('ห่อผ้า · 7 วัน')),
                    ],
                    selected: {_wrapType},
                    onSelectionChanged: _saving
                        ? null
                        : (s) => setState(() => _wrapType = s.first),
                  ),
                  const SizedBox(height: 18),
                  const Text('รายการอุปกรณ์ในชุด',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                              labelText: 'อุปกรณ์ชิ้นที่ ${i + 1}',
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
                    label: const Text('เพิ่มรายการอุปกรณ์'),
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
            label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึกชุดอุปกรณ์'),
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
