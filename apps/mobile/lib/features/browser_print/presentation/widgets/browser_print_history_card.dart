import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// สไตล์การแสดงผลสถานะ Browser Print Request (label + สี + ไอคอน)
/// ตรงกับ BrowserPrintStatus enum ฝั่ง backend — label มาจาก i18n ตาม
/// directive §12 (ห้ามสื่อว่า USER_CONFIRMED = เครื่องพิมพ์ยืนยัน; เป็นการ
/// ยืนยันโดย **ผู้ใช้** เท่านั้น)
class BrowserPrintStatusStyle {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;

  const BrowserPrintStatusStyle(this.label, this.color, this.bg, this.icon);

  static BrowserPrintStatusStyle of(AppLocalizations l10n, String status) {
    switch (status) {
      case 'CREATED':
        return BrowserPrintStatusStyle(l10n.bpStatusCreated,
            SterelisColors.textMuted, SterelisColors.surface2, Icons.schedule);
      case 'DIALOG_OPENED':
        return BrowserPrintStatusStyle(
            l10n.bpStatusDialogOpened,
            SterelisColors.warning,
            SterelisColors.warningBg,
            Icons.open_in_browser);
      case 'USER_CONFIRMED':
        // ไอคอน "คนยืนยัน" — เน้นว่าเป็นผู้ใช้ยืนยันเอง ไม่ใช่ hardware ACK
        return BrowserPrintStatusStyle(l10n.bpStatusUserConfirmed,
            SterelisColors.success, SterelisColors.successBg, Icons.how_to_reg);
      case 'CANCELLED':
        return BrowserPrintStatusStyle(
            l10n.bpStatusCancelled,
            SterelisColors.textFaint,
            SterelisColors.surface2,
            Icons.cancel_outlined);
      default:
        return BrowserPrintStatusStyle(status, SterelisColors.textMuted,
            SterelisColors.surface2, Icons.help_outline);
    }
  }
}

/// การ์ดประวัติพิมพ์ผ่านเบราว์เซอร์ของห่อ (directive §12) — แสดง เวลา, ผู้สั่ง,
/// mode, จำนวนสำเนา, template version, สถานะ, เหตุผล reprint, เลขคำขอ (ย่อ)
class BrowserPrintHistoryCard extends ConsumerWidget {
  const BrowserPrintHistoryCard({super.key, required this.packageId});
  final String packageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(browserPrintRequestsProvider(packageId));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.bpHistoryTitle,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text(apiErrorMessage(l10n, e),
              style:
                  const TextStyle(fontSize: 13, color: SterelisColors.danger)),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l10n.bpHistoryNone,
                      style: const TextStyle(
                          fontSize: 13, color: SterelisColors.textFaint)),
                )
              : Column(children: [
                  for (final r in items) BrowserPrintHistoryRow(request: r),
                ]),
        ),
      ]),
    );
  }
}

/// แถวรายการเดียวของประวัติ browser print (ใช้ทั้งในการ์ดนี้และหน้ารวมงานพิมพ์)
class BrowserPrintHistoryRow extends StatelessWidget {
  const BrowserPrintHistoryRow({super.key, required this.request});
  final BrowserPrintRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = BrowserPrintStatusStyle.of(l10n, request.status);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final shortId = request.id.length > 8
        ? request.id.substring(0, 8)
        : request.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(style.icon, color: style.color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(style.label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: style.color)),
            Text(
              [
                l10n.bpHistoryBy(request.requestedByName),
                l10n.bpHistoryMeta(
                    request.mode, request.copies, request.templateVersion),
              ].join(' · '),
              style: const TextStyle(
                  fontSize: 12, color: SterelisColors.textMuted),
            ),
            if (request.reprintReason != null &&
                request.reprintReason!.isNotEmpty)
              Text(l10n.bpHistoryReason(request.reprintReason!),
                  style: const TextStyle(
                      fontSize: 12, color: SterelisColors.textMuted)),
            Text(l10n.bpHistoryRequestId(shortId),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: SterelisColors.textFaint)),
          ]),
        ),
        if (request.requestedAt != null)
          Text(fmt.format(request.requestedAt!),
              style: const TextStyle(
                  fontSize: 11, color: SterelisColors.textFaint)),
      ]),
    );
  }
}
