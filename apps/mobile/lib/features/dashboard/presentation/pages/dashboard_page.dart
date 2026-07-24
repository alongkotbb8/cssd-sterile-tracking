import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';
import '../../../../l10n/app_localizations.dart';

// คำค้นหน้าแดชบอร์ด (debounce แล้ว) — ป้อนเข้า packagesProvider(search:) เพื่อค้น
// ที่ server (ชื่อชุด / เลขห่อ / คลัง / อุปกรณ์ในชุด); ว่าง = ซ่อนผลลัพธ์
final _dashSearchProvider = StateProvider<String>((ref) => '');

const _palette = [
  SterelisColors.blue500,
  SterelisColors.teal500,
  SterelisColors.wrapCloth,
  SterelisColors.warning,
  SterelisColors.success,
  SterelisColors.blue300,
  SterelisColors.stDiscarded,
];

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final user = ref.watch(authControllerProvider).user;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dashTitle),
            if (user != null)
              Text(l10n.dashGreeting(user.name),
                  style: const TextStyle(
                      fontSize: 12,
                      color: SterelisColors.textMuted,
                      fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.dashReportTooltip,
            icon: const Icon(Icons.summarize_outlined),
            onPressed: () => context.push('/reports'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: dash.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: apiErrorMessage(l10n, e),
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              const _DashSearchBar(),
              // ระหว่างพิมพ์ค้นหา ซ่อนกราฟ/สรุป แล้วแสดงผลลัพธ์แทน (โฟกัสที่ผลค้นหา)
              const _DashSearchResults(),
              _SummaryCards(data: d),
              const SizedBox(height: 8),
              _DonutCard(
                title: l10n.dashSterileStockTitle,
                slices: d.sterileStock,
                total: d.sterileTotal,
                centerLabel: l10n.dashSterileStockCenter,
              ),
              const SizedBox(height: 8),
              _DonutCard(
                title: l10n.dashIssuedByDeptTitle,
                slices: d.issuedByDept,
                total: d.issuedTotal,
                centerLabel: l10n.dashIssuedCenter,
              ),
              const SizedBox(height: 8),
              _RecentMovementsCard(movements: d.recentMovements),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.cloud_off_outlined,
            size: 44, color: SterelisColors.textFaint),
        const SizedBox(height: 12),
        Center(
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: SterelisColors.textMuted))),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).commonRetry),
          ),
        ),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _SummaryCard(l10n.dashExpiringSoon, data.expiringSoon,
            SterelisColors.warning, SterelisColors.warningBg,
            Icons.timer_outlined),
        const SizedBox(width: 8),
        _SummaryCard(l10n.statusExpired, data.expired, SterelisColors.danger,
            SterelisColors.dangerBg, Icons.dangerous_outlined),
        const SizedBox(width: 8),
        _SummaryCard(l10n.statusReturned, data.awaitingReprocess,
            SterelisColors.stReturned, SterelisColors.stReturnedBg,
            Icons.autorenew),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.label, this.value, this.color, this.bg, this.icon);
  final String label;
  final int value;
  final Color color, bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SterelisColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SterelisColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text('$value',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong,
                  height: 1)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: SterelisColors.textMuted)),
        ]),
      ),
    );
  }
}

class _DonutCard extends StatelessWidget {
  const _DonutCard({
    required this.title,
    required this.slices,
    required this.total,
    required this.centerLabel,
  });
  final String title;
  final List<DashboardSlice> slices;
  final int total;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 16),
          if (slices.isEmpty || total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(AppLocalizations.of(context).dashNoData,
                    style: const TextStyle(color: SterelisColors.textFaint)),
              ),
            )
          else
            Row(children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  PieChart(PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 46,
                    startDegreeOffset: -90,
                    sections: [
                      for (var i = 0; i < slices.length; i++)
                        PieChartSectionData(
                          color: _palette[i % _palette.length],
                          value: slices[i].count.toDouble(),
                          radius: 26,
                          showTitle: false,
                        ),
                    ],
                  )),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$total',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: SterelisColors.textStrong,
                            height: 1)),
                    Text(centerLabel,
                        style: const TextStyle(
                            fontSize: 10, color: SterelisColors.textFaint)),
                  ]),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < slices.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _palette[i % _palette.length],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(slices[i].name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: SterelisColors.text)),
                          ),
                          Text('${slices[i].count}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: SterelisColors.textStrong)),
                        ]),
                      ),
                  ],
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}

/// ช่องค้นหาบนสุดของแดชบอร์ด — debounce ~350ms ก่อนยิง GET /packages?search=
class _DashSearchBar extends ConsumerStatefulWidget {
  const _DashSearchBar();

  @override
  ConsumerState<_DashSearchBar> createState() => _DashSearchBarState();
}

class _DashSearchBarState extends ConsumerState<_DashSearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(_dashSearchProvider.notifier).state = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        onChanged: _onChanged,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).dashSearchHint,
          hintStyle: const TextStyle(color: SterelisColors.textFaint),
          prefixIcon:
              const Icon(Icons.search, color: SterelisColors.textFaint),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: SterelisColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: SterelisColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide:
                const BorderSide(color: SterelisColors.blue500, width: 2),
          ),
        ),
      ),
    );
  }
}

/// ผลลัพธ์การค้นหา (inline) — ว่างเมื่อยังไม่พิมพ์อะไร; มีคำค้น → GET /packages?search=
class _DashSearchResults extends ConsumerWidget {
  const _DashSearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(_dashSearchProvider).trim();
    if (q.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final results = ref.watch(
        packagesProvider((status: null, tagId: null, search: q)));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: results.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(apiErrorMessage(l10n, e),
              style: const TextStyle(color: SterelisColors.textMuted)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(l10n.dashSearchNoResults,
                    style: const TextStyle(color: SterelisColors.textFaint)),
              ),
            );
          }
          return Column(
            children: [
              for (final pkg in list)
                _DashSearchRow(pkg: pkg),
            ],
          );
        },
      ),
    );
  }
}

class _DashSearchRow extends StatelessWidget {
  const _DashSearchRow({required this.pkg});
  final PackageModel pkg;

  @override
  Widget build(BuildContext context) {
    final loc = pkg.currentLocationName;
    return ListTile(
      onTap: () => context.push('/packages/${Uri.encodeComponent(pkg.id)}'),
      title: Text(pkg.templateName.isEmpty ? pkg.id : pkg.templateName,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: SterelisColors.textStrong)),
      subtitle: Text(pkg.id,
          style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: SterelisColors.textMuted)),
      trailing: SizedBox(
        width: 96,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusBadge(pkg.isExpired && pkg.status == 'STERILE'
                ? 'EXPIRED'
                : pkg.status),
            if (loc != null) ...[
              const SizedBox(height: 2),
              Text(loc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 11, color: SterelisColors.blue600)),
            ],
          ],
        ),
      ),
    );
  }
}

/// การ์ด "ชุดอะไรไปอยู่ที่ไหน (ล่าสุด)" — recentMovements จาก dashboard (~8)
class _RecentMovementsCard extends StatelessWidget {
  const _RecentMovementsCard({required this.movements});
  final List<RecentMovement> movements;

  static ({IconData icon, Color color, String label}) _style(
      AppLocalizations l10n, String type) {
    switch (type) {
      case 'IN':
        return (
          icon: Icons.login,
          color: SterelisColors.success,
          label: l10n.dashMoveIn
        );
      case 'OUT':
        return (
          icon: Icons.logout,
          color: SterelisColors.blue500,
          label: l10n.dashMoveOut
        );
      case 'RETURN':
        return (
          icon: Icons.keyboard_return,
          color: SterelisColors.warning,
          label: l10n.dashMoveReturn
        );
      default:
        return (
          icon: Icons.circle_outlined,
          color: SterelisColors.textMuted,
          label: type
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.dashRecentMovementsTitle,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 8),
          if (movements.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(l10n.dashNoMovements,
                    style: const TextStyle(color: SterelisColors.textFaint)),
              ),
            )
          else
            for (final m in movements)
              InkWell(
                onTap: () => context
                    .push('/packages/${Uri.encodeComponent(m.packageId)}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (_) {
                          final s = _style(l10n, m.type);
                          return Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: s.color.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(s.icon, color: s.color, size: 18),
                          );
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    m.setName.isEmpty
                                        ? m.packageId
                                        : m.setName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                        color: SterelisColors.textStrong)),
                                Text(m.packageId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: SterelisColors.textMuted)),
                                Text(
                                  [
                                    _style(l10n, m.type).label,
                                    if (m.departmentName != null)
                                      m.departmentName!,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: SterelisColors.textMuted),
                                ),
                              ]),
                        ),
                        if (m.at != null)
                          Text(fmt.format(m.at!),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: SterelisColors.textFaint)),
                      ]),
                ),
              ),
        ]),
      ),
    );
  }
}
