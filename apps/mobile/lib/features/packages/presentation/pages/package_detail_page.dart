import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/config/feature_flags.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../browser_print/presentation/widgets/browser_print_history_card.dart';
import '../../../browser_print/presentation/widgets/browser_print_sheet.dart';
import '../../../print_jobs/presentation/widgets/submit_print_job_sheet.dart';

class PackageDetailPage extends ConsumerWidget {
  const PackageDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(packageDetailProvider(id));
    final l10n = AppLocalizations.of(context);
    // Browser print (BROWSER_DIALOG) — ปุ่ม/ประวัติแสดงเฉพาะเมื่อเปิด feature flag
    // (backend ตรวจ flag ซ้ำทุก endpoint — การซ่อน UI ไม่ใช่การป้องกันหลัก)
    final browserPrint = ref.watch(browserPrintEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(id,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
        actions: [
          if (browserPrint)
            detail.maybeWhen(
              data: (pkg) => IconButton(
                tooltip: l10n.bpPrintViaThisDevice,
                icon: const Icon(Icons.open_in_browser),
                onPressed: () => showBrowserPrintSheet(context, ref,
                    pkgs: [pkg], createdFrom: 'PACKAGE_DETAIL'),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          detail.maybeWhen(
            data: (pkg) => IconButton(
              tooltip: l10n.pdReprintTooltip,
              icon: const Icon(Icons.print_outlined),
              onPressed: () => submitPrintJobs(context, ref, [pkg]),
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
              Text(apiErrorMessage(l10n, e),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SterelisColors.textMuted)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(packageDetailProvider(id)),
                child: Text(l10n.commonRetry),
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
                BlockedCard(
                    title: l10n.scanBlockExpired,
                    detail: l10n.pdExpiredDetail),
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
              _TagsCard(pkg: pkg),
              const SizedBox(height: 12),
              if (browserPrint) ...[
                BrowserPrintHistoryCard(packageId: pkg.id),
                const SizedBox(height: 12),
              ],
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = [
      ('PACKED', l10n.pdStepPacked),
      ('STERILE', l10n.pdStepSterile),
      ('ISSUED', l10n.pdStepIssued),
      ('RETURNED', l10n.pdStepReturned),
    ];
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
                  Text(l10n.pdPackedOutTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF6D28D9))),
                  const SizedBox(height: 4),
                  Text(
                    locationName != null
                        ? l10n.pdLocationNotReturned(locationName!)
                        : l10n.pdNotReturned,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF7C5CC4)),
                  ),
                  const SizedBox(height: 2),
                  Text(l10n.pdPackedOutHint,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9B87CE))),
                ]),
          ),
        ]),
      );
    }

    final currentIdx = steps.indexWhere((s) => s.$1 == status);
    final isTerminal = status == 'EXPIRED' || status == 'DISCARDED';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.pdLifecycleTitle,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 16),
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
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
              label: steps[i].$2,
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
                ? l10n.pdTerminalExpired
                : l10n.pdTerminalDiscarded,
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
      // จำกัดความกว้าง + ellipsis — 4 node บนจอ 320px ที่ text scale 1.3
      // label กว้างเกินจน Row วงจรชีวิตล้น (Gate 1 layout test)
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 64),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: state == _NodeState.idle
                    ? SterelisColors.textFaint
                    : SterelisColors.text)),
      ),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.pkg});
  final PackageModel pkg;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final dfmt = DateFormat('dd/MM/yyyy');
    final rows = <(String, String, bool)>[
      if (pkg.sterilizeDate != null)
        (l10n.pdFieldSterilizeDate, fmt.format(pkg.sterilizeDate!), false),
      if (pkg.expiryDate != null)
        (l10n.pdFieldExpiryDate, dfmt.format(pkg.expiryDate!), pkg.isExpired),
      if (pkg.daysLeft != null && !pkg.isExpired)
        (l10n.pdFieldDaysLeft, l10n.pdDaysValue(pkg.daysLeft!), false),
      if (pkg.batchId != null) (l10n.pdFieldBatch, pkg.batchId!, false),
      if (pkg.printedAt != null)
        (
          l10n.pjPrintLabel,
          '${fmt.format(pkg.printedAt!)}'
              '${pkg.reprintCount > 0 ? l10n.pdReprintSuffix(pkg.reprintCount) : ''}',
          false
        ),
      if (pkg.notes != null && pkg.notes!.isNotEmpty)
        (l10n.pdFieldNotes, pkg.notes!, false),
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
        Text(l10n.pdInfoTitle,
            style: const TextStyle(
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

/// การ์ดจัดการ tag ของห่อ — แสดง tag ปัจจุบัน + ปุ่มแก้ไข (ติด/ถอด)
class _TagsCard extends ConsumerWidget {
  const _TagsCard({required this.pkg});
  final PackageModel pkg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(l10n.pdTagsTitle,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: SterelisColors.textStrong)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _editTags(context, ref),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(l10n.commonEdit),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        ]),
        const SizedBox(height: 4),
        if (pkg.tags.isEmpty)
          Text(l10n.pdNoTags,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textFaint))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pkg.tags.map((t) => _TagPill(tag: t)).toList(),
          ),
      ]),
    );
  }

  Future<void> _editTags(BuildContext context, WidgetRef ref) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SterelisColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _EditTagsSheet(pkg: pkg),
    );
    if (changed == true) {
      ref.invalidate(packageDetailProvider(pkg.id));
    }
  }
}

/// ป้าย tag แบบอ่านอย่างเดียว (มีจุดสีตาม colorHex)
class _TagPill extends StatelessWidget {
  const _TagPill({required this.tag});
  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final c = tag.colorValue != null
        ? Color(tag.colorValue!)
        : SterelisColors.blue500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(backgroundColor: c, radius: 5),
        const SizedBox(width: 6),
        Text(tag.name,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SterelisColors.textStrong)),
      ]),
    );
  }
}

/// Sheet ติด/ถอด tag — toggle chips จากรายการ tag ทั้งหมด แล้วบันทึกทีเดียว
class _EditTagsSheet extends ConsumerStatefulWidget {
  const _EditTagsSheet({required this.pkg});
  final PackageModel pkg;

  @override
  ConsumerState<_EditTagsSheet> createState() => _EditTagsSheetState();
}

class _EditTagsSheetState extends ConsumerState<_EditTagsSheet> {
  late final Set<String> _selected =
      widget.pkg.tags.map((t) => t.id).toSet();
  bool _saving = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(packageRepositoryProvider)
          .setTags(widget.pkg.id, _selected.toList());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tagsAsync = ref.watch(tagsProvider);
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
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.pdEditTagsTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(l10n.pdEditTagsSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: SterelisColors.textMuted)),
          const SizedBox(height: 16),
          tagsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(apiErrorMessage(l10n, e),
                style: const TextStyle(color: SterelisColors.danger)),
            data: (tags) => tags.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(l10n.pdNoTagsInSystem,
                        style:
                            const TextStyle(color: SterelisColors.textFaint)),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tags.map((t) {
                      final sel = _selected.contains(t.id);
                      final c = t.colorValue != null
                          ? Color(t.colorValue!)
                          : SterelisColors.blue500;
                      return FilterChip(
                        avatar: CircleAvatar(backgroundColor: c, radius: 6),
                        label: Text(t.name),
                        selected: sel,
                        showCheckmark: false,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                  if (!_selected.add(t.id)) {
                                    _selected.remove(t.id);
                                  }
                                }),
                        selectedColor: c.withValues(alpha: 0.16),
                        side: BorderSide(color: sel ? c : SterelisColors.border),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(l10n.pdSaveTags),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.movements});
  final List<Movement> movements;

  static ({IconData icon, Color color, String label}) _style(
      AppLocalizations l10n, String type) {
    switch (type) {
      case 'IN':
        return (
          icon: Icons.login,
          color: SterelisColors.success,
          label: l10n.pdMoveIn
        );
      case 'OUT':
        return (
          icon: Icons.logout,
          color: SterelisColors.blue500,
          label: l10n.moveOut
        );
      case 'RETURN':
        return (
          icon: Icons.keyboard_return,
          color: SterelisColors.warning,
          label: l10n.moveReturn
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
        Text(l10n.pdHistoryTitle,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l10n.pdNoHistory,
                style: const TextStyle(
                    color: SterelisColors.textFaint, fontSize: 13)),
          )
        else
          for (final m in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                        Text(_style(l10n, m.type).label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: SterelisColors.textStrong)),
                        Text(
                          [
                            if (m.departmentName != null)
                              l10n.pdMoveDept(m.departmentName!),
                            if (m.receiverName != null &&
                                m.receiverName!.isNotEmpty)
                              l10n.pdMoveReceiver(m.receiverName!),
                            if (m.performedByName != null)
                              l10n.pdMoveBy(m.performedByName!),
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
