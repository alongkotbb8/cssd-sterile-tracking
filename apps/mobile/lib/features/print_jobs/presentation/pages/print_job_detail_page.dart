import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../print_job_status_style.dart';

/// หน้าติดตามสถานะงานพิมพ์ — poll ทุก 2.5 วิ จนกว่างานจะจบ (terminal)
/// รองรับ: ยกเลิก (เฉพาะ QUEUED), หัวหน้าตัดสิน ACK_UNKNOWN
class PrintJobDetailPage extends ConsumerStatefulWidget {
  const PrintJobDetailPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<PrintJobDetailPage> createState() => _PrintJobDetailPageState();
}

class _PrintJobDetailPageState extends ConsumerState<PrintJobDetailPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // poll สถานะเป็นระยะ — PWA ไม่รู้เองว่าพิมพ์เสร็จ ต้องถาม backend เรื่อยๆ
    _poll = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      ref.invalidate(printJobDetailProvider(widget.id));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _stopPollingIfTerminal(PrintJob job) {
    if (job.isTerminal && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.pjCancelTitle),
        content: Text(l10n.pjCancelBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l10n.pjCancelNo)),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(l10n.pjCancelYes)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(printJobRepositoryProvider).cancel(widget.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(apiErrorMessage(e)), backgroundColor: SterelisColors.danger));
      }
    }
  }

  Future<void> _resolve(String decision) async {
    final l10n = AppLocalizations.of(context);
    final title = decision == 'CONFIRM_PRINTED'
        ? l10n.pjResolveConfirm
        : l10n.pjResolveRequeue;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: noteCtrl,
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.pjResolveNote,
            hintText: l10n.pjResolveNoteHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l10n.actionCancel)),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(l10n.actionSave)),
        ],
      ),
    );
    if (ok != true) return;
    final note = noteCtrl.text.trim();
    if (note.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.pjResolveNoteRequired),
            backgroundColor: SterelisColors.danger));
      }
      return;
    }
    try {
      await ref.read(printJobRepositoryProvider).resolve(widget.id, decision, note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.pjResolveDone), backgroundColor: SterelisColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(apiErrorMessage(e)), backgroundColor: SterelisColors.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(printJobDetailProvider(widget.id));
    final role = ref.watch(authControllerProvider).user?.role;
    final isSupervisor = role == 'SUPERVISOR' || role == 'ADMIN';
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pjDetailTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(apiErrorMessage(e),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SterelisColors.danger)),
          ),
        ),
        data: (job) {
          _stopPollingIfTerminal(job);
          final style = PrintJobStatusStyle.of(l10n, job.status);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(printJobDetailProvider(widget.id)),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _statusCard(job, style),
                const SizedBox(height: 16),
                _timeline(job),
                const SizedBox(height: 16),
                _details(job),
                if (job.isSimulated) ...[
                  const SizedBox(height: 16),
                  _banner(Icons.science_outlined, SterelisColors.warning,
                      SterelisColors.warningBg, l10n.pjSimulatedBanner),
                ],
                if (job.needsSupervisor) ...[
                  const SizedBox(height: 16),
                  if (isSupervisor)
                    _resolveActions()
                  else
                    _banner(Icons.help_outline, SterelisColors.warning,
                        SterelisColors.warningBg, l10n.pjAckBanner),
                ],
                if (job.status == 'DEAD_LETTER') ...[
                  const SizedBox(height: 16),
                  _banner(Icons.report_gmailerrorred_outlined, SterelisColors.danger,
                      SterelisColors.dangerBg, l10n.pjDeadBanner),
                ],
                if (job.canCancel) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(l10n.pjCancelButton),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: SterelisColors.danger,
                      side: const BorderSide(color: SterelisColors.danger),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusCard(PrintJob job, PrintJobStatusStyle style) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Icon(style.icon, color: style.color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(style.label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16, color: style.color)),
              const SizedBox(height: 2),
              Text(AppLocalizations.of(context).pjPackageTitle(job.packageId),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13, color: SterelisColors.textMuted)),
            ]),
          ),
          if (!job.isTerminal)
            const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      );

  Widget _timeline(PrintJob job) {
    final idx = printProgressIndex(job.status);
    if (idx < 0) return const SizedBox.shrink(); // ไม่อยู่บน happy path (FAILED/ACK_UNKNOWN ฯลฯ)
    final steps = printProgressSteps(AppLocalizations.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(children: [
                Icon(
                  i <= idx ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: i <= idx ? SterelisColors.success : SterelisColors.textFaint,
                ),
                const SizedBox(height: 4),
                Text(steps[i].$2,
                    style: TextStyle(
                        fontSize: 11,
                        color: i <= idx ? SterelisColors.text : SterelisColors.textFaint)),
              ]),
            ),
            if (i < steps.length - 1)
              Container(
                width: 16,
                height: 2,
                color: i < idx ? SterelisColors.success : SterelisColors.border,
              ),
          ],
        ],
      ),
    );
  }

  Widget _details(PrintJob job) {
    final l10n = AppLocalizations.of(context);
    final rows = <(String, String)>[
      (l10n.pjFieldCreated, _fmt(job.createdAt)),
      if (job.printerId != null) (l10n.pjFieldPrinter, job.printerId!),
      if (job.attemptCount > 0) (l10n.pjFieldAttempts, '${job.attemptCount}'),
      if (job.isReprint) (l10n.pjFieldReprint, l10n.commonYes),
      if (job.reprintReason != null) (l10n.pjFieldReprintReason, job.reprintReason!),
      if (job.errorCode != null) (l10n.pjFieldErrorCode, job.errorCode!),
      if (job.sentAt != null) (l10n.pjFieldSentAt, _fmt(job.sentAt!)),
      if (job.printedAt != null) (l10n.pjFieldPrintedAt, _fmt(job.printedAt!)),
      if (job.resolvedAt != null) (l10n.pjFieldResolvedAt, _fmt(job.resolvedAt!)),
      if (job.resolutionNote != null) (l10n.pjFieldResolutionNote, job.resolutionNote!),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 130,
                    child: Text(r.$1,
                        style: const TextStyle(
                            fontSize: 13, color: SterelisColors.textMuted))),
                Expanded(
                    child: Text(r.$2,
                        style: const TextStyle(
                            fontSize: 13,
                            color: SterelisColors.text,
                            fontWeight: FontWeight.w600))),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _resolveActions() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SterelisColors.warningBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.pjResolveSectionTitle,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: SterelisColors.textStrong)),
        const SizedBox(height: 4),
        Text(l10n.pjResolveSectionHint,
            style: const TextStyle(fontSize: 13, color: SterelisColors.text)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _resolve('CONFIRM_PRINTED'),
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: Text(l10n.pjResolveConfirmBtn),
          style: FilledButton.styleFrom(backgroundColor: SterelisColors.success),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _resolve('REQUEUE'),
          icon: const Icon(Icons.replay, size: 18),
          label: Text(l10n.pjResolveRequeueBtn),
        ),
      ]),
    );
  }

  Widget _banner(IconData icon, Color color, Color bg, String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13, color: SterelisColors.text))),
        ]),
      );

  String _fmt(DateTime d) => DateFormat('dd/MM/yyyy HH:mm:ss').format(d);
}
