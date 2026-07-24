import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
import '../../../../l10n/app_localizations.dart';

enum ReportPeriod { today, week, month }

/// ป้ายชื่อช่วงเวลา (i18n)
String reportPeriodLabel(AppLocalizations l10n, ReportPeriod p) => switch (p) {
      ReportPeriod.today => l10n.reportPeriodToday,
      ReportPeriod.week => l10n.reportPeriodWeek,
      ReportPeriod.month => l10n.reportPeriodMonth,
    };

extension on ReportPeriod {
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reportTitle),
        actions: [
          report.maybeWhen(
            data: (r) => IconButton(
              tooltip: l10n.reportPrintTooltip,
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
                  label: Text(reportPeriodLabel(l10n, p)),
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
                  Text(apiErrorMessage(l10n, e),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: SterelisColors.textMuted)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(weeklyReportProvider(range)),
                    child: Text(l10n.commonRetry),
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
    final l10n = AppLocalizations.of(context);
    try {
      // ฟอนต์ bundle ในแอป (ไม่โหลดจากเน็ต) — สร้างรายงานได้แม้ offline
      final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/Sarabun-Regular.ttf'));
      final fontBold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Sarabun-Bold.ttf'));
      final dfmt = DateFormat('dd/MM/yyyy');
      final tfmt = DateFormat('dd/MM/yyyy HH:mm');
      final (from, to) = period.range;

      String typeLabel(String t) => switch (t) {
            'IN' => l10n.moveIn,
            'OUT' => l10n.moveOut,
            'RETURN' => l10n.moveReturn,
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
                  pw.Text(l10n.pdfReportTitle,
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      l10n.pdfDateRange(dfmt.format(from), dfmt.format(to),
                          tfmt.format(DateTime.now())),
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ]),
          ),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            _pdfStat(l10n.moveIn, r.inCount, font, fontBold),
            pw.SizedBox(width: 10),
            _pdfStat(l10n.moveOut, r.outCount, font, fontBold),
            pw.SizedBox(width: 10),
            _pdfStat(l10n.moveReturn, r.returnCount, font, fontBold),
            pw.SizedBox(width: 10),
            _pdfStat(l10n.reportTotal, r.movements.length, font, fontBold),
          ]),
          pw.SizedBox(height: 14),
          if (r.movements.isEmpty)
            pw.Text(l10n.pdfNoMovements,
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
              headers: [
                l10n.pdfColDatetime,
                l10n.pdfColType,
                l10n.pdfColPackage,
                l10n.pdfColSet,
                l10n.pdfColDept,
                l10n.pdfColUser
              ],
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
              pw.Text(l10n.pdfInspector,
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
        content: Text(l10n.pdfError('$e')),
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

    final l10n = AppLocalizations.of(context);
    return Row(children: [
      card(l10n.moveIn, report.inCount, SterelisColors.success,
          SterelisColors.successBg, Icons.login),
      const SizedBox(width: 8),
      card(l10n.moveOut, report.outCount, SterelisColors.blue500,
          SterelisColors.blue50, Icons.logout),
      const SizedBox(width: 8),
      card(l10n.moveReturn, report.returnCount, SterelisColors.warning,
          SterelisColors.warningBg, Icons.keyboard_return),
    ]);
  }
}

class _MovementsCard extends StatelessWidget {
  const _MovementsCard({required this.movements});
  final List<ReportMovement> movements;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tfmt = DateFormat('dd/MM HH:mm');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.reportMovementsTitle(movements.length),
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 6),
        if (movements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(l10n.reportNoMovements,
                style: const TextStyle(
                    color: SterelisColors.textFaint, fontSize: 13)),
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
                              l10n.reportDeptLine(m.departmentName!),
                            if (m.performedByName != null)
                              l10n.reportByLine(m.performedByName!),
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
    final l10n = AppLocalizations.of(context);
    final (from, _) = widget.period.range;
    final before = from;
    final dfmt = DateFormat('dd/MM/yyyy');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.cleanupConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cleanupConfirmBody(dfmt.format(before))),
            const SizedBox(height: 10),
            Text(l10n.cleanupKeep,
                style: const TextStyle(
                    fontSize: 12.5, color: SterelisColors.success)),
            const SizedBox(height: 4),
            Text(l10n.cleanupIrreversible,
                style: const TextStyle(
                    fontSize: 12.5, color: SterelisColors.danger)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: Text(l10n.actionCancel)),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: SterelisColors.danger),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.cleanupConfirmAction),
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
      final m = (result['deletedMovements'] ?? 0) as int;
      final p = (result['deletedPackages'] ?? 0) as int;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).cleanupDone(m, p)),
        backgroundColor: SterelisColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF4D9A8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cleaning_services_outlined,
              color: SterelisColors.warning, size: 20),
          const SizedBox(width: 8),
          Text(l10n.cleanupTitle,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: SterelisColors.textStrong)),
        ]),
        const SizedBox(height: 6),
        Text(
          l10n.cleanupDesc,
          style: const TextStyle(
              fontSize: 12.5, color: SterelisColors.textMuted),
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
          label: Text(l10n.cleanupButton),
          style: OutlinedButton.styleFrom(
            foregroundColor: SterelisColors.danger,
            side: const BorderSide(color: SterelisColors.danger),
          ),
        ),
      ]),
    );
  }
}
