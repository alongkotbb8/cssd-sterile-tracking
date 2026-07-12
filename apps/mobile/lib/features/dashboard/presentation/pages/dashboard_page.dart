import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('แดชบอร์ด'),
            if (user != null)
              Text('สวัสดี ${user.name}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: SterelisColors.textMuted,
                      fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'รายงานสรุป / พิมพ์',
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
            message: apiErrorMessage(e),
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              _SummaryCards(data: d),
              const SizedBox(height: 8),
              _DonutCard(
                title: 'คงเหลือปลอดเชื้อ (แยกตามชุด)',
                slices: d.sterileStock,
                total: d.sterileTotal,
                centerLabel: 'ห่อพร้อมใช้',
              ),
              const SizedBox(height: 8),
              _DonutCard(
                title: 'เบิกแยกตามแผนก (30 วัน)',
                slices: d.issuedByDept,
                total: d.issuedTotal,
                centerLabel: 'ครั้งที่เบิก',
              ),
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
            label: const Text('ลองใหม่'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _SummaryCard('ใกล้หมดอายุ', data.expiringSoon, SterelisColors.warning,
            SterelisColors.warningBg, Icons.timer_outlined),
        const SizedBox(width: 8),
        _SummaryCard('หมดอายุ', data.expired, SterelisColors.danger,
            SterelisColors.dangerBg, Icons.dangerous_outlined),
        const SizedBox(width: 8),
        _SummaryCard('รอ Reprocess', data.awaitingReprocess,
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('ยังไม่มีข้อมูล',
                    style: TextStyle(color: SterelisColors.textFaint)),
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
