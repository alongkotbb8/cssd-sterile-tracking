import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/config/feature_flags.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../browser_print/presentation/widgets/browser_print_history_card.dart';
import '../print_job_status_style.dart';

/// รายการงานพิมพ์ — CSSD เห็นของตัวเอง, SUPERVISOR/ADMIN เห็นทั้งหมด (backend filter)
/// งานที่ต้องดูแล (ACK_UNKNOWN/DEAD_LETTER) ถูกเน้นและดันขึ้นบน
/// เมื่อเปิด flag browser print มี segment สลับดูคำขอพิมพ์ผ่านเบราว์เซอร์ (ของฉัน)
class PrintJobsPage extends ConsumerStatefulWidget {
  const PrintJobsPage({super.key});

  @override
  ConsumerState<PrintJobsPage> createState() => _PrintJobsPageState();
}

class _PrintJobsPageState extends ConsumerState<PrintJobsPage> {
  bool _showBrowser = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final browserPrint = ref.watch(browserPrintEnabledProvider);
    final showBrowser = browserPrint && _showBrowser;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pjPageTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(printJobsProvider);
              if (browserPrint) ref.invalidate(browserPrintRequestsProvider);
            },
          ),
        ],
      ),
      body: Column(children: [
        if (browserPrint)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.bpSegGateway)),
                ButtonSegment(value: true, label: Text(l10n.bpSegBrowser)),
              ],
              selected: {_showBrowser},
              onSelectionChanged: (s) =>
                  setState(() => _showBrowser = s.first),
            ),
          ),
        Expanded(
            child: showBrowser ? _browserBody(l10n) : _gatewayBody(l10n)),
      ]),
    );
  }

  /// รายการคำขอ browser print (ของฉัน — backend บังคับ scope ให้เอง)
  Widget _browserBody(AppLocalizations l10n) {
    final async = ref.watch(browserPrintRequestsProvider(null));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(apiErrorMessage(l10n, e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: SterelisColors.danger)),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(l10n.bpHistoryNone,
                style: const TextStyle(color: SterelisColors.textMuted)),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(browserPrintRequestsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final r in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: SterelisColors.border),
                  ),
                  color: SterelisColors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(r.packageId,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: SterelisColors.textStrong)),
                          BrowserPrintHistoryRow(request: r),
                        ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _gatewayBody(AppLocalizations l10n) {
    final async = ref.watch(printJobsProvider(null));
    final role = ref.watch(authControllerProvider).user?.role;
    final scope = (role == 'SUPERVISOR' || role == 'ADMIN')
        ? l10n.pjScopeAll
        : l10n.pjScopeMine;

    return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(apiErrorMessage(l10n, e),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SterelisColors.danger)),
          ),
        ),
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Text(l10n.pjNone,
                  style: const TextStyle(color: SterelisColors.textMuted)),
            );
          }
          // ดันงานที่ต้องดูแลขึ้นบนสุด
          final sorted = [...jobs]..sort((a, b) {
              final pa = _attentionRank(a), pb = _attentionRank(b);
              if (pa != pb) return pa.compareTo(pb);
              return b.createdAt.compareTo(a.createdAt);
            });
          final needAttention =
              jobs.where((j) => j.needsSupervisor || j.status == 'DEAD_LETTER').length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(printJobsProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  // Expanded + ellipsis — จอแคบ (320px) ข้อความ scope ยาวกว่าพื้นที่
                  // เมื่อมี badge "ต้องดูแล" ด้านขวา (Gate 1 layout test จับ overflow)
                  Expanded(
                    child: Text(l10n.pjScopeLine(scope),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: SterelisColors.textMuted)),
                  ),
                  if (needAttention > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: SterelisColors.warningBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(l10n.pjNeedAttention(needAttention),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: SterelisColors.warning)),
                    ),
                ]),
                const SizedBox(height: 12),
                ...sorted.map((j) => _JobCard(job: j)),
              ],
            ),
          );
        },
      );
  }

  int _attentionRank(PrintJob j) {
    if (j.needsSupervisor) return 0;
    if (j.status == 'DEAD_LETTER') return 1;
    if (!j.isTerminal) return 2;
    return 3;
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final PrintJob job;

  @override
  Widget build(BuildContext context) {
    final style = PrintJobStatusStyle.of(AppLocalizations.of(context), job.status);
    final highlight = job.needsSupervisor || job.status == 'DEAD_LETTER';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: highlight ? style.color : SterelisColors.border),
      ),
      color: SterelisColors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/print-jobs/${job.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
              child: Icon(style.icon, color: style.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.packageId,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: SterelisColors.textStrong)),
                const SizedBox(height: 2),
                Text(style.label,
                    style: TextStyle(fontSize: 12.5, color: style.color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(DateFormat('dd/MM HH:mm').format(job.createdAt),
                    style: const TextStyle(fontSize: 11, color: SterelisColors.textFaint)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: SterelisColors.textFaint),
          ]),
        ),
      ),
    );
  }
}
