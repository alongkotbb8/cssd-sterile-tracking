import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';
import '../widgets/create_package_sheet.dart';

class PackageDetailPage extends ConsumerWidget {
  const PackageDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(packageDetailProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: Text(id,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
        actions: [
          detail.maybeWhen(
            data: (pkg) => IconButton(
              tooltip: 'พิมพ์ label ซ้ำ',
              icon: const Icon(Icons.print_outlined),
              onPressed: () => printPackageLabel(context, ref, pkg),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(apiErrorMessage(e),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SterelisColors.textMuted)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(packageDetailProvider(id)),
                child: const Text('ลองใหม่'),
              ),
            ]),
          ),
        ),
        data: (pkg) => RefreshIndicator(
          onRefresh: () => ref.refresh(packageDetailProvider(id).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pkg.isExpired || pkg.status == 'EXPIRED') ...[
                const BlockedCard(
                    title: 'ห้ามใช้ — ห่อหมดอายุแล้ว',
                    detail: 'นำกลับไป reprocess ที่หน่วยจ่ายกลางเท่านั้น'),
                const SizedBox(height: 12),
              ],
              _HeaderCard(pkg: pkg),
              const SizedBox(height: 12),
              PackageQrCard(packageId: pkg.id),
              const SizedBox(height: 12),
              _LifecycleCard(
                  status: pkg.status,
                  locationName: pkg.currentLocationName),
              const SizedBox(height: 12),
              _InfoCard(pkg: pkg),
              const SizedBox(height: 12),
              _HistoryCard(movements: pkg.movements),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.pkg});
  final PackageModel pkg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pkg.templateName,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SterelisColors.textStrong)),
            const SizedBox(height: 4),
            Text(pkg.id,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: SterelisColors.textMuted)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusBadge(pkg.isExpired && pkg.status == 'STERILE'
                  ? 'EXPIRED'
                  : pkg.status),
              WrapBadge(pkg.wrapType),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        ExpiryRing(pkg: pkg, size: 66),
      ]),
    );
  }
}

class _LifecycleCard extends StatelessWidget {
  const _LifecycleCard({required this.status, this.locationName});
  final String status;
  final String? locationName;

  static const _steps = [
    ('PACKED', 'แพ็ก'),
    ('STERILE', 'ปลอดเชื้อ'),
    ('ISSUED', 'เบิกออก'),
    ('RETURNED', 'ส่งคืน'),
  ];

  @override
  Widget build(BuildContext context) {
    // PACKED_OUT อยู่นอกวงจรหลัก (แพ็ก→ปลอดเชื้อ→เบิก→คืน) — แสดงการ์ดสถานะแยก
    if (status == 'PACKED_OUT') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EEFE), // โทนม่วงอ่อน เข้าชุดกับ StatusBadge
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD9CCFA)),
        ),
        child: Row(children: [
          const Icon(Icons.local_shipping_outlined,
              color: Color(0xFF8B5CF6), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ส่งออกโดยยังไม่ฆ่าเชื้อ',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF6D28D9))),
                  const SizedBox(height: 4),
                  Text(
                    locationName != null
                        ? 'อยู่ที่ $locationName · ยังไม่คืนคลัง'
                        : 'ยังไม่คืนคลัง',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF7C5CC4)),
                  ),
                  const SizedBox(height: 2),
                  const Text('เมื่อสแกนรับคืน สถานะจะกลับเป็น "แพ็กแล้ว" พร้อมเข้ารอบนึ่งต่อ',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF9B87CE))),
                ]),
          ),
        ]),
      );
    }

    final currentIdx = _steps.indexWhere((s) => s.$1 == status);
    final isTerminal = status == 'EXPIRED' || status == 'DISCARDED';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('วงจรชีวิต',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 16),
        Row(children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: !isTerminal && currentIdx >= i
                        ? SterelisColors.success
                        : SterelisColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            _LifecycleNode(
              label: _steps[i].$2,
              state: isTerminal
                  ? _NodeState.idle
                  : currentIdx > i
                      ? _NodeState.done
                      : currentIdx == i
                          ? _NodeState.active
                          : _NodeState.idle,
            ),
          ],
        ]),
        if (isTerminal) ...[
          const SizedBox(height: 12),
          Text(
            status == 'EXPIRED'
                ? 'สถานะปัจจุบัน: หมดอายุ — ห้ามใช้'
                : 'สถานะปัจจุบัน: ทิ้ง/ชำรุด',
            style: const TextStyle(
                color: SterelisColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
        ],
      ]),
    );
  }
}

enum _NodeState { idle, active, done }

class _LifecycleNode extends StatelessWidget {
  const _LifecycleNode({required this.label, required this.state});
  final String label;
  final _NodeState state;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (state) {
      _NodeState.done => (
          SterelisColors.success,
          SterelisColors.success,
          Colors.white
        ),
      _NodeState.active => (
          SterelisColors.blue500,
          SterelisColors.blue500,
          Colors.white
        ),
      _NodeState.idle => (
          SterelisColors.white,
          SterelisColors.border,
          SterelisColors.textFaint
        ),
    };

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2),
          boxShadow: state == _NodeState.active
              ? const [BoxShadow(color: Color(0xFFDCE8FD), spreadRadius: 4)]
              : null,
        ),
        child: Icon(
          state == _NodeState.done ? Icons.check : Icons.circle,
          size: state == _NodeState.done ? 18 : 8,
          color: fg,
        ),
      ),
      const SizedBox(height: 6),
      Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: state == _NodeState.idle
                  ? SterelisColors.textFaint
                  : SterelisColors.text)),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.pkg});
  final PackageModel pkg;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final dfmt = DateFormat('dd/MM/yyyy');
    final rows = <(String, String, bool)>[
      if (pkg.sterilizeDate != null)
        ('วันที่นึ่ง', fmt.format(pkg.sterilizeDate!), false),
      if (pkg.expiryDate != null)
        ('วันหมดอายุ', dfmt.format(pkg.expiryDate!), pkg.isExpired),
      if (pkg.daysLeft != null && !pkg.isExpired)
        ('เหลืออีก', '${pkg.daysLeft} วัน', false),
      if (pkg.batchId != null) ('รอบนึ่ง', pkg.batchId!, false),
      if (pkg.notes != null && pkg.notes!.isNotEmpty)
        ('หมายเหตุ', pkg.notes!, false),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ข้อมูลห่อ',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 100,
                child: Text(r.$1,
                    style: const TextStyle(
                        fontSize: 13, color: SterelisColors.textMuted)),
              ),
              Expanded(
                child: Text(r.$2,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: r.$3
                          ? SterelisColors.danger
                          : SterelisColors.textStrong,
                    )),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.movements});
  final List<Movement> movements;

  static ({IconData icon, Color color, String label}) _style(String type) {
    switch (type) {
      case 'IN':
        return (
          icon: Icons.login,
          color: SterelisColors.success,
          label: 'สแกนเข้าคลังปลอดเชื้อ'
        );
      case 'OUT':
        return (
          icon: Icons.logout,
          color: SterelisColors.blue500,
          label: 'เบิกออก'
        );
      case 'RETURN':
        return (
          icon: Icons.keyboard_return,
          color: SterelisColors.warning,
          label: 'ส่งคืน'
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
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final sorted = [...movements]..sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ประวัติการเคลื่อนไหว',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('ยังไม่มีการเคลื่อนไหว',
                style: TextStyle(color: SterelisColors.textFaint, fontSize: 13)),
          )
        else
          for (final m in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Builder(builder: (_) {
                  final s = _style(m.type);
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
                        Text(_style(m.type).label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: SterelisColors.textStrong)),
                        Text(
                          [
                            if (m.departmentName != null)
                              'แผนก: ${m.departmentName}',
                            if (m.receiverName != null &&
                                m.receiverName!.isNotEmpty)
                              'ผู้รับ: ${m.receiverName}',
                            if (m.performedByName != null)
                              'โดย: ${m.performedByName}',
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 12, color: SterelisColors.textMuted),
                        ),
                      ]),
                ),
                if (m.createdAt != null)
                  Text(fmt.format(m.createdAt!),
                      style: const TextStyle(
                          fontSize: 11, color: SterelisColors.textFaint)),
              ]),
            ),
      ]),
    );
  }
}
