import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';

enum ReportPeriod { today, week, month }

extension on ReportPeriod {
  String get label => switch (this) {
        ReportPeriod.today => 'วันนี้',
        ReportPeriod.week => '7 วันล่าสุด',
        ReportPeriod.month => 'เดือนนี้',
      };

  /// ช่วงวันที่ (รวมปลายทั้งสองด้าน) ตามเวลาท้องถิ่น
  (DateTime, DateTime) get range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      ReportPeriod.today => (today, today),
      ReportPeriod.week => (today.subtract(const Duration(days: 6)), today),
      ReportPeriod.month => (DateTime(now.year, now.month, 1), today),
    };
  }
}

final _periodProvider =
    StateProvider.autoDispose<ReportPeriod>((ref) => ReportPeriod.today);

class ReportPage extends ConsumerWidget {
  const ReportPage({super.key});

  ReportRange _rangeOf(ReportPeriod p) {
    final fmt = DateFormat('yyyy-MM-dd');
    final (from, to) = p.range;
    return (from: fmt.format(from), to: fmt.format(to));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(_periodProvider);
    final range = _rangeOf(period);
    final report = ref.watch(weeklyReportProvider(range));
    final isAdmin =
        ref.watch(authControllerProvider).user?.role == 'ADMIN';

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายงานสรุป'),
        actions: [
          report.maybeWhen(
            data: (r) => IconButton(
              tooltip: 'พิมพ์รายงาน (PDF)',
              icon: const Icon(Icons.print_outlined),
              onPressed: () => _printReport(context, period, r),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(children: [
        // ตัวเลือกช่วงเวลา
        Container(
          color: SterelisColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: ReportPeriod.values.map((p) {
              final sel = p == period;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.label),
                  selected: sel,
                  showCheckmark: false,
                  onSelected: (_) =>
                      ref.read(_periodProvider.notifier).state = p,
                  backgroundColor: SterelisColors.white,
                  selectedColor: SterelisColors.blue500,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : SterelisColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  side: BorderSide(
                      color:
                          sel ? SterelisColors.blue500 : SterelisColors.border),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: report.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(apiErrorMessage(e),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: SterelisColors.textMuted)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(weeklyReportProvider(range)),
                    child: const Text('ลองใหม่'),
                  ),
                ]),
              ),
            ),
            data: (r) => RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(weeklyReportProvider(range).future),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryRow(report: r),
                  const SizedBox(height: 14),
                  _MovementsCard(movements: r.movements),
                  if (isAdmin) ...[
                    const SizedBox(height: 20),
                    _CleanupCard(period: period),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _printReport(
      BuildContext context, ReportPeriod period, WeeklyReport r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final font = await PdfGoogleFonts.sarabunRegular();
      final fontBold = await PdfGoogleFonts.sarabunBold();
      final dfmt = DateFormat('dd/MM/yyyy');
      final tfmt = DateFormat('dd/MM/yyyy HH:mm');
      final (from, to) = period.range;

      String typeLabel(String t) => switch (t) {
            'IN' => 'นำเข้าคลัง',
            'OUT' => 'เบิกออก',
            'RETURN' => 'ส่งคืน',
            _ => t,
          };

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('รายงานระบบตามรอยอุปกรณ์ปลอดเชื้อ (CSSD)',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      'ช่วงวันที่ ${dfmt.format(from)} – ${dfmt.format(to)}'
                      ' · พิมพ์เมื่อ ${tfmt.format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ]),
          ),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            _pdfStat('นำเข้าคลัง', r.inCount, font, fontBold),
            pw.SizedBox(width: 10),
            _pdfStat('เบิกออก', r.outCount, font, fontBold),
            pw.SizedBox(width: 10),
            _pdfStat('ส่งคืน', r.returnCount, font, fontBold),
            pw.SizedBox(width: 10),
            _pdfStat('รวม', r.movements.length, font, fontBold),
          ]),
          pw.SizedBox(height: 14),
          if (r.movements.isEmpty)
            pw.Text('— ไม่มีการเคลื่อนไหวในช่วงนี้ —',
                style:
                    const pw.TextStyle(fontSize: 11, color: PdfColors.grey))
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {0: pw.Alignment.centerLeft},
              headers: ['วัน-เวลา', 'ประเภท', 'เลขห่อ', 'ชุด', 'แผนก', 'ผู้ทำรายการ'],
              data: r.movements
                  .map((m) => [
                        m.createdAt != null ? tfmt.format(m.createdAt!) : '-',
                        typeLabel(m.type),
                        m.packageId,
                        m.templateName,
                        m.departmentName ?? '-',
                        m.performedByName ?? '-',
                      ])
                  .toList(),
            ),
          pw.SizedBox(height: 24),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Column(children: [
              pw.Container(width: 160, height: 0.8, color: PdfColors.grey),
              pw.SizedBox(height: 4),
              pw.Text('ผู้ตรวจสอบ / หัวหน้าหน่วยจ่ายกลาง',
                  style: const pw.TextStyle(fontSize: 9)),
            ]),
          ]),
        ],
      ));

      await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name:
            'cssd-report-${DateFormat('yyyyMMdd').format(from)}-${DateFormat('yyyyMMdd').format(to)}.pdf',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('สร้าง PDF ไม่สำเร็จ: $e'),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  pw.Widget _pdfStat(
      String label, int value, pw.Font font, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(children: [
          pw.Text('$value',
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    Widget card(String label, int value, Color color, Color bg,
        IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SterelisColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SterelisColors.border),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 8),
            Text('$value',
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: SterelisColors.textStrong,
                    height: 1)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: SterelisColors.textMuted)),
          ]),
        ),
      );
    }

    return Row(children: [
      card('นำเข้าคลัง', report.inCount, SterelisColors.success,
          SterelisColors.successBg, Icons.login),
      const SizedBox(width: 8),
      card('เบิกออก', report.outCount, SterelisColors.blue500,
          SterelisColors.blue50, Icons.logout),
      const SizedBox(width: 8),
      card('ส่งคืน', report.returnCount, SterelisColors.warning,
          SterelisColors.warningBg, Icons.keyboard_return),
    ]);
  }
}

class _MovementsCard extends StatelessWidget {
  const _MovementsCard({required this.movements});
  final List<ReportMovement> movements;

  @override
  Widget build(BuildContext context) {
    final tfmt = DateFormat('dd/MM HH:mm');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('รายการเคลื่อนไหว (${movements.length})',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 6),
        if (movements.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('ไม่มีการเคลื่อนไหวในช่วงนี้',
                style:
                    TextStyle(color: SterelisColors.textFaint, fontSize: 13)),
          )
        else
          for (final m in movements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                _TypeDot(type: m.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.packageId} · ${m.templateName}',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: SterelisColors.textStrong)),
                        Text(
                          [
                            if (m.departmentName != null)
                              'แผนก ${m.departmentName}',
                            if (m.performedByName != null)
                              'โดย ${m.performedByName}',
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: SterelisColors.textMuted),
                        ),
                      ]),
                ),
                if (m.createdAt != null)
                  Text(tfmt.format(m.createdAt!),
                      style: const TextStyle(
                          fontSize: 11, color: SterelisColors.textFaint)),
              ]),
            ),
      ]),
    );
  }
}

class _TypeDot extends StatelessWidget {
  const _TypeDot({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final (color, bg, icon) = switch (type) {
      'IN' => (
          SterelisColors.success,
          SterelisColors.successBg,
          Icons.login
        ),
      'OUT' => (SterelisColors.blue500, SterelisColors.blue50, Icons.logout),
      'RETURN' => (
          SterelisColors.warning,
          SterelisColors.warningBg,
          Icons.keyboard_return
        ),
      _ => (
          SterelisColors.textMuted,
          SterelisColors.surface2,
          Icons.circle_outlined
        ),
    };
    return Container(
      width: 30,
      height: 30,
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, color: color, size: 16),
    );
  }
}

/// การ์ดล้างข้อมูลเก่า (เฉพาะ ADMIN) — ลบประวัติก่อนช่วงที่พิมพ์ ไม่แตะคลังปัจจุบัน
class _CleanupCard extends ConsumerStatefulWidget {
  const _CleanupCard({required this.period});
  final ReportPeriod period;

  @override
  ConsumerState<_CleanupCard> createState() => _CleanupCardState();
}

class _CleanupCardState extends ConsumerState<_CleanupCard> {
  bool _busy = false;

  Future<void> _cleanup() async {
    // ลบเฉพาะประวัติที่เกิด "ก่อนวันเริ่มต้นของช่วงที่กำลังดู/พิมพ์"
    // เพื่อให้รายงานที่เพิ่งพิมพ์เก็บเข้าแฟ้มยังตรงกับข้อมูลในระบบ
    final (from, _) = widget.period.range;
    final before = from;
    final dfmt = DateFormat('dd/MM/yyyy');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ล้างข้อมูลเก่า?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('จะลบประวัติการเคลื่อนไหวและห่อที่ทิ้งแล้ว '
                'ที่เกิดก่อนวันที่ ${dfmt.format(before)} อย่างถาวร'),
            const SizedBox(height: 10),
            const Text('✓ ห่อที่ยังอยู่ในคลัง/วงจร (แพ็ก·ปลอดเชื้อ·เบิกออก·รอ reprocess) จะไม่ถูกลบ',
                style: TextStyle(
                    fontSize: 12.5, color: SterelisColors.success)),
            const SizedBox(height: 4),
            const Text('✗ ข้อมูลที่ลบแล้วกู้คืนไม่ได้ ควรพิมพ์รายงานเก็บเข้าแฟ้มก่อน',
                style:
                    TextStyle(fontSize: 12.5, color: SterelisColors.danger)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('ยกเลิก')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: SterelisColors.danger),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('ลบถาวร'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result =
          await ref.read(reportRepositoryProvider).cleanup(before);
      ref.invalidate(weeklyReportProvider);
      ref.invalidate(packagesProvider);
      ref.invalidate(dashboardProvider);
      if (!mounted) return;
      final m = result['deletedMovements'] ?? 0;
      final p = result['deletedPackages'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ล้างข้อมูลแล้ว: ประวัติ $m รายการ · ห่อที่ทิ้งแล้ว $p ห่อ'),
        backgroundColor: SterelisColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e)),
        backgroundColor: SterelisColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF4D9A8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.cleaning_services_outlined,
              color: SterelisColors.warning, size: 20),
          SizedBox(width: 8),
          Text('ล้างข้อมูลเก่า (ประหยัดพื้นที่)',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: SterelisColors.textStrong)),
        ]),
        const SizedBox(height: 6),
        const Text(
          'หลังพิมพ์รายงานเก็บเข้าแฟ้มแล้ว สามารถลบประวัติเก่าออกจากระบบได้ '
          'โดยห่อที่ยังอยู่ในคลังและอยู่ระหว่างใช้งานจะไม่ถูกลบ',
          style: TextStyle(fontSize: 12.5, color: SterelisColors.textMuted),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _cleanup,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('ลบประวัติก่อนช่วงนี้'),
          style: OutlinedButton.styleFrom(
            foregroundColor: SterelisColors.danger,
            side: const BorderSide(color: SterelisColors.danger),
          ),
        ),
      ]),
    );
  }
}
