import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'dart:async';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../print_jobs/presentation/widgets/submit_print_job_sheet.dart';
import '../widgets/create_package_sheet.dart';

final _statusFilterProvider = StateProvider<String?>((ref) => null);
final _tagFilterProvider = StateProvider<String?>((ref) => null); // 2.7 กรองตาม tag
// คำค้นที่ debounce แล้ว — ป้อนเข้า PackageQuery.search (ค้นที่ server: เลขห่อ /
// ชื่อชุด / อุปกรณ์ในชุด / คลังปัจจุบัน) แทนการกรองฝั่ง client อย่างเดียว
final _searchProvider = StateProvider<String>((ref) => '');

// โหมดเลือกหลายห่อเพื่อพิมพ์ label พร้อมกัน
final _selectModeProvider = StateProvider<bool>((ref) => false);
final _selectedIdsProvider = StateProvider<Set<String>>((ref) => {});

class PackagesPage extends ConsumerWidget {
  const PackagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_statusFilterProvider);
    final tagFilter = ref.watch(_tagFilterProvider);
    final search = ref.watch(_searchProvider).trim();
    final query = (
      status: filter,
      tagId: tagFilter,
      search: search.isEmpty ? null : search,
    );
    final packages = ref.watch(packagesProvider(query));
    final selectMode = ref.watch(_selectModeProvider);
    final selectedIds = ref.watch(_selectedIdsProvider);
    final l10n = AppLocalizations.of(context);

    void exitSelectMode() {
      ref.read(_selectModeProvider.notifier).state = false;
      ref.read(_selectedIdsProvider.notifier).state = {};
    }

    return Scaffold(
      appBar: AppBar(
        leading: selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: exitSelectMode,
              )
            : null,
        title: Text(selectMode
            ? l10n.pkgSelectedCount(selectedIds.length)
            : l10n.pkgListTitle),
        actions: [
          if (!selectMode)
            IconButton(
              tooltip: l10n.pkgSelectToPrintTooltip,
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () =>
                  ref.read(_selectModeProvider.notifier).state = true,
            ),
        ],
      ),
      floatingActionButton: selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showCreatePackageSheet(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.pkgCreateNew),
              backgroundColor: SterelisColors.blue500,
              foregroundColor: Colors.white,
            ),
      bottomNavigationBar:
          selectMode ? _SelectionBar(query: query) : null,
      body: Column(children: [
        const _SearchBar(),
        const _StatusFilterBar(),
        const _TagFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(packagesProvider(query).future),
            child: packages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [
                const SizedBox(height: 100),
                Center(
                  child: Text(apiErrorMessage(l10n, e),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SterelisColors.textMuted)),
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton(
                    onPressed: () => ref.invalidate(packagesProvider(query)),
                    child: Text(l10n.commonRetry),
                  ),
                ),
              ]),
              data: (list) => _PackageList(packages: list),
            ),
          ),
        ),
      ]),
    );
  }
}

/// แถบล่างตอนอยู่โหมดเลือก — ปุ่มพิมพ์ label ของห่อที่เลือกทั้งหมด
/// + ปุ่มลบถาวร (แสดงเฉพาะตัวกรอง PACKED และผู้ใช้ SUPERVISOR/ADMIN)
class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({required this.query});
  final PackageQuery query;

  /// ลบได้เฉพาะตัวกรองสถานะ = PACKED (ห่อที่ยังไม่มีประวัติ) และสิทธิ์สูงพอ
  /// (backend บังคับ RBAC + เงื่อนไข PACKED/ไม่มีประวัติซ้ำ — UI แค่ซ่อนปุ่ม)
  bool _canDelete(WidgetRef ref) {
    if (query.status != 'PACKED') return false;
    final role = ref.watch(authControllerProvider).user?.role;
    return role == 'SUPERVISOR' || role == 'ADMIN';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(_selectedIdsProvider);
    final packages = ref.watch(packagesProvider(query)).value ?? const [];
    final count = selectedIds.length;
    final l10n = AppLocalizations.of(context);
    final canDelete = _canDelete(ref);

    List<PackageModel> selectedPackages() =>
        packages.where((p) => selectedIds.contains(p.id)).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          if (canDelete) ...[
            OutlinedButton.icon(
              onPressed: count == 0
                  ? null
                  : () => _confirmDelete(context, ref, selectedIds.toList()),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.pkgDeleteSelected),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                foregroundColor: SterelisColors.danger,
                side: const BorderSide(color: SterelisColors.danger),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: count == 0
                  ? null
                  : () async {
                      final selected = selectedPackages();
                      await submitPrintJobs(context, ref, selected);
                      ref.read(_selectModeProvider.notifier).state = false;
                      ref.read(_selectedIdsProvider.notifier).state = {};
                    },
              icon: const Icon(Icons.print_outlined),
              label: Text(count == 0
                  ? l10n.pkgSelectToPrintHint
                  : l10n.pkgPrintSelected(count)),
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          ),
        ]),
      ),
    );
  }

  /// ยืนยันก่อนลบถาวร — ผู้ใช้ต้องกด "ลบถาวร" จึงจะเรียก repo.bulkDelete
  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, List<String> ids) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pkgDeleteConfirmTitle(ids.length)),
        content: Text(l10n.pkgDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.pkgDeleteConfirmCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: SterelisColors.danger),
            child: Text(l10n.pkgDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final results =
          await ref.read(packageRepositoryProvider).bulkDelete(ids);
      final okCount = results.where((r) => r.success).length;
      final failCount = results.length - okCount;
      // เคลียร์การเลือก + ออกจากโหมดเลือก (bulkDelete invalidate list/dashboard แล้ว)
      ref.read(_selectModeProvider.notifier).state = false;
      ref.read(_selectedIdsProvider.notifier).state = {};
      messenger.showSnackBar(SnackBar(
        content: Text(failCount == 0
            ? l10n.pkgDeleteDone(okCount)
            : '${l10n.pkgDeleteDone(okCount)}${l10n.pkgDeleteFailedSuffix(failCount)}'),
        backgroundColor:
            failCount == 0 ? SterelisColors.success : SterelisColors.warning,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }
}

/// ช่องค้นหา — debounce ~350ms ก่อนป้อนเข้า _searchProvider (ยิง GET /packages?search=)
/// กันยิง server ทุกตัวอักษรระหว่างพิมพ์
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(_searchProvider.notifier).state = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextField(
        onChanged: _onChanged,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).pkgSearchHint,
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

class _StatusFilterBar extends ConsumerWidget {
  const _StatusFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filters = <(String?, String)>[
      (null, l10n.filterAll),
      ('PACKED', l10n.statusPacked),
      ('PACKED_OUT', l10n.statusPackedOut),
      ('STERILE', l10n.statusSterile),
      ('ISSUED', l10n.statusIssued),
      ('RETURNED', l10n.statusReturned),
      ('EXPIRED', l10n.statusExpired),
    ];
    final selected = ref.watch(_statusFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: filters.map((f) {
          final isSel = selected == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f.$2),
              selected: isSel,
              showCheckmark: false,
              onSelected: (_) =>
                  ref.read(_statusFilterProvider.notifier).state = f.$1,
              backgroundColor: SterelisColors.white,
              selectedColor: SterelisColors.blue500,
              labelStyle: TextStyle(
                color: isSel ? Colors.white : SterelisColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
              side: BorderSide(
                  color:
                      isSel ? SterelisColors.blue500 : SterelisColors.border),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// แถบกรองตาม tag (2.7) — แสดงเมื่อมี tag อย่างน้อย 1 รายการเท่านั้น
/// ซ่อนเงียบ ๆ ถ้ายังไม่มี tag / โหลดไม่ได้ (ไม่รบกวนหน้าจอหลัก)
class _TagFilterBar extends ConsumerWidget {
  const _TagFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsProvider);
    final tags = tagsAsync.value ?? const <Tag>[];
    if (tags.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(_tagFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        _TagChip(
          label: AppLocalizations.of(context).pkgTagAll,
          selected: selected == null,
          color: SterelisColors.textMuted,
          onTap: () => ref.read(_tagFilterProvider.notifier).state = null,
        ),
        ...tags.map((t) {
          final c = t.colorValue != null
              ? Color(t.colorValue!)
              : SterelisColors.blue500;
          return _TagChip(
            label: t.name,
            selected: selected == t.id,
            color: c,
            onTap: () {
              // แตะซ้ำที่ tag เดิม = ยกเลิกตัวกรอง
              ref.read(_tagFilterProvider.notifier).state =
                  selected == t.id ? null : t.id;
            },
          );
        }),
      ]),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: CircleAvatar(backgroundColor: color, radius: 6),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        backgroundColor: SterelisColors.white,
        selectedColor: color.withValues(alpha: 0.16),
        labelStyle: TextStyle(
          color: selected ? SterelisColors.textStrong : SterelisColors.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: selected ? color : SterelisColors.border),
      ),
    );
  }
}

class _PackageList extends ConsumerWidget {
  const _PackageList({required this.packages});
  final List<PackageModel> packages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectMode = ref.watch(_selectModeProvider);
    final selectedIds = ref.watch(_selectedIdsProvider);
    // ค้นหาทำที่ server (PackageQuery.search) แล้ว — ที่นี่แสดงผลลัพธ์ตรง ๆ
    final list = packages;

    if (list.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        const Icon(Icons.inventory_2_outlined,
            size: 44, color: SterelisColors.textFaint),
        const SizedBox(height: 12),
        Center(
            child: Text(AppLocalizations.of(context).pkgNoneFound,
                style: const TextStyle(color: SterelisColors.textFaint))),
      ]);
    }

    return Column(children: [
      if (selectMode)
        _SelectAllRow(
          total: list.length,
          selectedCount: list.where((p) => selectedIds.contains(p.id)).length,
          onSelectAll: () => ref.read(_selectedIdsProvider.notifier).state =
              list.map((p) => p.id).toSet(),
          onClear: () => ref.read(_selectedIdsProvider.notifier).state = {},
        ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final pkg = list[i];
            return _PackageCard(
              pkg: pkg,
              selectMode: selectMode,
              selected: selectedIds.contains(pkg.id),
              onToggle: () {
                final next = {...selectedIds};
                if (!next.add(pkg.id)) next.remove(pkg.id);
                ref.read(_selectedIdsProvider.notifier).state = next;
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    required this.total,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onClear,
  });
  final int total;
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == total && total > 0;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(children: [
        Text(l10n.pkgSelectedOf(selectedCount, total),
            style: const TextStyle(
                fontSize: 13, color: SterelisColors.textMuted)),
        const Spacer(),
        TextButton(
          onPressed: allSelected ? onClear : onSelectAll,
          child: Text(allSelected ? l10n.commonClearAll : l10n.commonSelectAll),
        ),
      ]),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.pkg,
    this.selectMode = false,
    this.selected = false,
    this.onToggle,
  });
  final PackageModel pkg;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    final l10n = AppLocalizations.of(context);
    final danger = pkg.isExpired || pkg.status == 'EXPIRED';

    return InkWell(
      onTap: selectMode
          ? onToggle
          : () => context.push('/packages/${Uri.encodeComponent(pkg.id)}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? SterelisColors.blue50 : SterelisColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected
                  ? SterelisColors.blue500
                  : danger
                      ? const Color(0xFFF4BFC1)
                      : SterelisColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          if (selectMode) ...[
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: selected
                  ? SterelisColors.blue500
                  : SterelisColors.textFaint,
            ),
            const SizedBox(width: 12),
          ] else ...[
            ExpiryRing(pkg: pkg, size: 50),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pkg.templateName.isEmpty ? pkg.id : pkg.templateName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: SterelisColors.textStrong)),
              const SizedBox(height: 2),
              Text(pkg.id,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: SterelisColors.textMuted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusBadge(danger && pkg.status == 'STERILE'
                    ? 'EXPIRED'
                    : pkg.status),
                WrapBadge(pkg.wrapType),
              ]),
              if (pkg.expiryDate != null) ...[
                const SizedBox(height: 6),
                Text(l10n.pkgExpiryOn(fmt.format(pkg.expiryDate!)),
                    style: TextStyle(
                        fontSize: 12,
                        color: danger
                            ? SterelisColors.danger
                            : SterelisColors.textMuted,
                        fontWeight:
                            danger ? FontWeight.w700 : FontWeight.w400)),
              ],
              // ตำแหน่งปัจจุบัน — เฉพาะห่อที่ออกไปอยู่ข้างนอก (ISSUED/PACKED_OUT)
              if (pkg.currentLocationName != null) ...[
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.place_outlined,
                      size: 14, color: SterelisColors.blue600),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(l10n.pkgLocationAt(pkg.currentLocationName!),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: SterelisColors.blue600,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ],
            ]),
          ),
          if (!selectMode)
            const Icon(Icons.chevron_right, color: SterelisColors.textFaint),
        ]),
      ),
    );
  }
}
