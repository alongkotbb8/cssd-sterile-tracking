import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ยกเลิกงานพิมพ์?'),
        content: const Text('ยกเลิกได้เฉพาะงานที่ยังไม่ถูกเครื่องพิมพ์รับไป'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ไม่')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('ยกเลิกงาน')),
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
    final title = decision == 'CONFIRM_PRINTED'
        ? 'ยืนยันว่าพิมพ์จริงแล้ว'
        : 'เปิดงานพิมพ์ใหม่ (ไม่ยืนยันว่าพิมพ์)';
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
          decoration: const InputDecoration(
            labelText: 'หมายเหตุการตัดสินใจ (บังคับ)',
            hintText: 'เช่น ตรวจกับเครื่องพิมพ์แล้วพบว่า...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('บันทึก')),
        ],
      ),
    );
    if (ok != true) return;
    final note = noteCtrl.text.trim();
    if (note.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ต้องระบุหมายเหตุการตัดสินใจ'),
            backgroundColor: SterelisColors.danger));
      }
      return;
    }
    try {
      await ref.read(printJobRepositoryProvider).resolve(widget.id, decision, note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('บันทึกการตัดสินใจแล้ว'), backgroundColor: SterelisColors.success));
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

    return Scaffold(
      appBar: AppBar(title: const Text('สถานะงานพิมพ์')),
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
          final style = PrintJobStatusStyle.of(job.status);
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
                      SterelisColors.warningBg,
                      'โหมดทดสอบ (SIMULATED) — ไม่ใช่การพิมพ์จริง ไม่นับเป็นประวัติการพิมพ์'),
                ],
                if (job.needsSupervisor) ...[
                  const SizedBox(height: 16),
                  if (isSupervisor)
                    _resolveActions()
                  else
                    _banner(Icons.help_outline, SterelisColors.warning,
                        SterelisColors.warningBg,
                        'ไม่แน่ใจว่าพิมพ์จริงหรือไม่ — กรุณาติดต่อหัวหน้า (SUPERVISOR/ADMIN) เพื่อตรวจสอบและตัดสิน'),
                ],
                if (job.status == 'DEAD_LETTER') ...[
                  const SizedBox(height: 16),
                  _banner(Icons.report_gmailerrorred_outlined, SterelisColors.danger,
                      SterelisColors.dangerBg,
                      'พิมพ์ล้มเหลวครบจำนวนครั้งแล้ว — ต้องตรวจสอบเครื่องพิมพ์แล้วสั่งพิมพ์ใหม่'),
                ],
                if (job.canCancel) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('ยกเลิกงานพิมพ์'),
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
              Text('ห่อ ${job.packageId}',
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < kPrintProgressSteps.length; i++) ...[
            Expanded(
              child: Column(children: [
                Icon(
                  i <= idx ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: i <= idx ? SterelisColors.success : SterelisColors.textFaint,
                ),
                const SizedBox(height: 4),
                Text(kPrintProgressSteps[i].$2,
                    style: TextStyle(
                        fontSize: 11,
                        color: i <= idx ? SterelisColors.text : SterelisColors.textFaint)),
              ]),
            ),
            if (i < kPrintProgressSteps.length - 1)
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
    final rows = <(String, String)>[
      ('สร้างเมื่อ', _fmt(job.createdAt)),
      if (job.printerId != null) ('เครื่องพิมพ์', job.printerId!),
      if (job.attemptCount > 0) ('จำนวนครั้งที่พยายาม', '${job.attemptCount}'),
      if (job.isReprint) ('พิมพ์ซ้ำ', 'ใช่'),
      if (job.reprintReason != null) ('เหตุผลพิมพ์ซ้ำ', job.reprintReason!),
      if (job.errorCode != null) ('รหัสข้อผิดพลาด', job.errorCode!),
      if (job.sentAt != null) ('ส่งถึงเครื่องเมื่อ', _fmt(job.sentAt!)),
      if (job.printedAt != null) ('พิมพ์เสร็จเมื่อ', _fmt(job.printedAt!)),
      if (job.resolvedAt != null) ('หัวหน้าตัดสินเมื่อ', _fmt(job.resolvedAt!)),
      if (job.resolutionNote != null) ('หมายเหตุการตัดสิน', job.resolutionNote!),
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

  Widget _resolveActions() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SterelisColors.warningBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('ตัดสินใจ (หัวหน้า)',
              style: TextStyle(fontWeight: FontWeight.w800, color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          const Text(
              'งานนี้ส่งถึงเครื่องพิมพ์แล้วแต่ยืนยันผลไม่ได้ — ตรวจกับเครื่องพิมพ์จริงก่อนตัดสิน',
              style: TextStyle(fontSize: 13, color: SterelisColors.text)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _resolve('CONFIRM_PRINTED'),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: const Text('ยืนยันว่าพิมพ์แล้ว'),
            style: FilledButton.styleFrom(backgroundColor: SterelisColors.success),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _resolve('REQUEUE'),
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('ไม่ยืนยัน — เปิดงานพิมพ์ใหม่'),
          ),
        ]),
      );

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
