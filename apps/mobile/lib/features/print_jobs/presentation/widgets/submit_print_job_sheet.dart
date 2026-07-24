import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// สร้างงานพิมพ์ผ่าน Print Job Queue (แทนการพิมพ์ตรง) — เลือก gateway + เหตุผล
/// พิมพ์ซ้ำ (ถ้าเคยพิมพ์แล้ว) → สร้าง PrintJob 1 งานต่อ 1 ห่อ แล้วพาไปดูสถานะ
///
/// PWA ไม่ตั้งสถานะ PRINTED เอง — หลังสร้างงานแล้วต้อง poll สถานะจนกว่า Gateway
/// จะ claim/พิมพ์/ACK (ดู PrintJobDetailPage)
Future<void> submitPrintJobs(
  BuildContext context,
  WidgetRef ref,
  List<PackageModel> pkgs,
) async {
  if (pkgs.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _SubmitPrintJobSheet(pkgs: pkgs),
  );
}

class _SubmitPrintJobSheet extends ConsumerStatefulWidget {
  const _SubmitPrintJobSheet({required this.pkgs});
  final List<PackageModel> pkgs;

  @override
  ConsumerState<_SubmitPrintJobSheet> createState() => _SubmitPrintJobSheetState();
}

class _SubmitPrintJobSheetState extends ConsumerState<_SubmitPrintJobSheet> {
  String? _gatewayId; // null = เครื่องไหนก็ได้ (auto)
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  int _done = 0;

  // Idempotency-Key คงที่ต่อ 1 ห่อ ต่อการเปิด sheet นี้ — ใช้ซ้ำทุกครั้งที่กดลองใหม่
  // (ถ้า response แรกหายแล้วผู้ใช้กดซ้ำ backend จะ replay งานเดิม ไม่สร้าง print job ซ้ำ)
  late final Map<String, String> _idemKeys = {
    for (final p in widget.pkgs) p.id: newIdempotencyKey(),
  };

  bool get _hasReprint => widget.pkgs.any((p) => p.printedAt != null);

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (_hasReprint && _reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.pjReprintReasonRequired),
        backgroundColor: SterelisColors.danger,
      ));
      return;
    }
    setState(() {
      _submitting = true;
      _done = 0;
    });
    final repo = ref.read(printJobRepositoryProvider);
    final reason = _reasonCtrl.text.trim();
    final created = <PrintJob>[];
    try {
      for (final pkg in widget.pkgs) {
        final job = await repo.create(
          pkg.id,
          requestedPrinterId: _gatewayId,
          reprintReason: reason.isEmpty ? null : reason,
          idempotencyKey: _idemKeys[pkg.id], // คงเดิมเมื่อกดลองใหม่ → ไม่พิมพ์ซ้ำ
        );
        created.add(job);
        if (mounted) setState(() => _done = created.length);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: Text(created.length == 1
            ? l10n.pjCreatedOne
            : l10n.pjCreatedMany(created.length)),
        backgroundColor: SterelisColors.success,
      ));
      // งานเดียว → ไปหน้าสถานะเลย; หลายงาน → ไปหน้ารายการงานพิมพ์
      if (created.length == 1) {
        context.push('/print-jobs/${created.first.id}');
      } else {
        context.push('/print-jobs');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
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
    final gateways = ref.watch(gatewaysProvider);

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
          Text(
            widget.pkgs.length == 1
                ? l10n.pjPrintLabel
                : l10n.pjPrintLabelCount(widget.pkgs.length),
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: SterelisColors.textStrong),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.pjSubmitDesc,
            style: const TextStyle(fontSize: 13, color: SterelisColors.textMuted),
          ),
          const SizedBox(height: 18),
          Text(l10n.pjTargetPrinter,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          // ตัวเลือก gateway — CSSD อาจโหลดรายการไม่ได้ (สิทธิ์เฉพาะ SUPERVISOR/ADMIN)
          // จึง fallback เป็น "อัตโนมัติ" อย่างเดียวเมื่อโหลดไม่ได้/ว่าง
          gateways.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => _autoOnlyHint(),
            data: (list) {
              final online = list.where((g) => g.isActive && g.revokedAt == null).toList();
              if (online.isEmpty) return _autoOnlyHint();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _gatewayChip(null, l10n.pjAutoAnyPrinter, true),
                  ...online.map((g) => _gatewayChip(
                        g.id,
                        '${g.name}${g.isOnline ? '' : l10n.pjOfflineSuffix}',
                        g.isOnline,
                      )),
                ],
              );
            },
          ),
          if (_hasReprint) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SterelisColors.warningBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: SterelisColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.pjReprintReasonRequired,
                      style: const TextStyle(fontSize: 13, color: SterelisColors.text)),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonCtrl,
              enabled: !_submitting,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: l10n.pjReprintReasonLabel,
                hintText: l10n.pjReprintReasonHint,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined),
            label: Text(_submitting
                ? l10n.pjCreatingProgress(_done, widget.pkgs.length)
                : widget.pkgs.length == 1
                    ? l10n.pjCreateButton
                    : l10n.pjCreateButtonCount(widget.pkgs.length)),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }

  Widget _autoOnlyHint() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SterelisColors.blue50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.print_outlined, color: SterelisColors.blue600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppLocalizations.of(context).pjAutoHint,
                style: const TextStyle(fontSize: 13, color: SterelisColors.text)),
          ),
        ]),
      );

  Widget _gatewayChip(String? id, String label, bool enabled) {
    final sel = _gatewayId == id;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      showCheckmark: false,
      onSelected: (_submitting || !enabled) ? null : (_) => setState(() => _gatewayId = id),
      backgroundColor: SterelisColors.white,
      selectedColor: SterelisColors.blue50,
      labelStyle: TextStyle(
        color: sel ? SterelisColors.blue600 : SterelisColors.text,
        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: sel ? SterelisColors.blue500 : SterelisColors.border,
          width: sel ? 1.5 : 1,
        ),
      ),
    );
  }
}
