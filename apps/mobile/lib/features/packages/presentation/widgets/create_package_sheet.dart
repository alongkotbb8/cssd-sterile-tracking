import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/models/models.dart';
import '../../../../core/printer/printer_adapter.dart';
import '../../../../core/printer/printer_provider.dart';
import '../../../../core/theme/app_theme.dart';

/// เปิด sheet สร้างห่อ — เมื่อสร้างสำเร็จ แสดง dialog เลขรัน + ปุ่มพิมพ์ label
Future<void> showCreatePackageSheet(BuildContext context, WidgetRef ref) async {
  final pkg = await showModalBottomSheet<PackageModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _CreatePackageSheet(),
  );
  if (pkg == null || !context.mounted) return;

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
        const Text('สร้างห่อสำเร็จ', style: TextStyle(fontSize: 18)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(pkg.templateName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: SterelisColors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(pkg.id,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('ปิด'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dctx).pop(true),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('พิมพ์ label'),
        ),
      ],
    ),
  );

  if (shouldPrint == true && context.mounted) {
    await printPackageLabel(context, ref, pkg);
  }
}

/// พิมพ์ label ของห่อผ่าน adapter ที่เลือกไว้ (ใช้ซ้ำได้จากหน้ารายละเอียด)
Future<void> printPackageLabel(
    BuildContext context, WidgetRef ref, PackageModel pkg) async {
  final messenger = ScaffoldMessenger.of(context);
  final printer = ref.read(printerAdapterProvider);
  // ห่อที่ยังไม่นึ่งจะยังไม่มีวันหมดอายุจริง (backend คำนวณตอนสแกนเข้าคลัง)
  // ใช้วันโดยประมาณ = แพ็กวันนี้ + อายุตามชนิดห่อ
  final sterilize = pkg.sterilizeDate ?? DateTime.now();
  final expiry =
      pkg.expiryDate ?? sterilize.add(Duration(days: pkg.shelfLifeDays));
  try {
    if (!printer.isConnected) await printer.connect();
    await printer.printLabel(LabelData(
      packageId: pkg.id,
      setName: pkg.templateName,
      wrapType: pkg.wrapType == 'SEAL' ? 'ห่อซีล' : 'ห่อผ้า',
      sterilizeDate: sterilize,
      expiryDate: expiry,
    ));
    messenger.showSnackBar(SnackBar(
      content: Text('ส่งพิมพ์ไปยัง ${printer.displayName} แล้ว'),
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
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final template = _template;
    if (template == null) return;
    setState(() => _saving = true);
    try {
      final pkg = await ref.read(packageRepositoryProvider).create(
            setTemplateId: template.id,
            wrapType: _wrapType,
            notes: _notesCtrl.text.trim(),
          );
      ref.invalidate(packagesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(pkg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(apiErrorMessage(e)),
            backgroundColor: SterelisColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider);
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
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: list.map((t) {
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
                        color:
                            sel ? SterelisColors.blue600 : SterelisColors.text,
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
                  }).toList(),
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
          TextField(
            controller: _notesCtrl,
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
            label: const Text('บันทึก + ออกเลขรัน'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
