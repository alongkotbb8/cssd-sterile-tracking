import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';
import '../widgets/create_package_sheet.dart';

final _statusFilterProvider = StateProvider<String?>((ref) => null);
final _searchProvider = StateProvider<String>((ref) => '');

class PackagesPage extends ConsumerWidget {
  const PackagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_statusFilterProvider);
    final packages = ref.watch(packagesProvider(filter));

    return Scaffold(
      appBar: AppBar(title: const Text('รายการห่อ')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreatePackageSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('สร้างห่อใหม่'),
        backgroundColor: SterelisColors.blue500,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        const _SearchBar(),
        const _StatusFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(packagesProvider(filter).future),
            child: packages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [
                const SizedBox(height: 100),
                Center(
                  child: Text(apiErrorMessage(e),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SterelisColors.textMuted)),
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton(
                    onPressed: () => ref.invalidate(packagesProvider(filter)),
                    child: const Text('ลองใหม่'),
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

class _SearchBar extends ConsumerWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextField(
        onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
        decoration: InputDecoration(
          hintText: 'ค้นหาเลขรัน / ชื่อชุด',
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

  static const _filters = [
    (null, 'ทั้งหมด'),
    ('PACKED', 'แพ็กแล้ว'),
    ('STERILE', 'ปลอดเชื้อ'),
    ('ISSUED', 'เบิกออก'),
    ('RETURNED', 'รอ Reprocess'),
    ('EXPIRED', 'หมดอายุ'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_statusFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: _filters.map((f) {
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

class _PackageList extends ConsumerWidget {
  const _PackageList({required this.packages});
  final List<PackageModel> packages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(_searchProvider).trim().toLowerCase();
    final list = q.isEmpty
        ? packages
        : packages
            .where((p) =>
                p.id.toLowerCase().contains(q) ||
                p.templateName.toLowerCase().contains(q))
            .toList();

    if (list.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Icon(Icons.inventory_2_outlined,
            size: 44, color: SterelisColors.textFaint),
        SizedBox(height: 12),
        Center(
            child: Text('ไม่พบห่อในเงื่อนไขนี้',
                style: TextStyle(color: SterelisColors.textFaint))),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PackageCard(pkg: list[i]),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.pkg});
  final PackageModel pkg;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    final danger = pkg.isExpired || pkg.status == 'EXPIRED';

    return InkWell(
      onTap: () => context.push('/packages/${Uri.encodeComponent(pkg.id)}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SterelisColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: danger ? const Color(0xFFF4BFC1) : SterelisColors.border),
        ),
        child: Row(children: [
          ExpiryRing(pkg: pkg, size: 50),
          const SizedBox(width: 12),
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
                Text('หมดอายุ ${fmt.format(pkg.expiryDate!)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: danger
                            ? SterelisColors.danger
                            : SterelisColors.textMuted,
                        fontWeight:
                            danger ? FontWeight.w700 : FontWeight.w400)),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right, color: SterelisColors.textFaint),
        ]),
      ),
    );
  }
}
