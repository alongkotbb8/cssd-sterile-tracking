import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// สไตล์การแสดงผลของแต่ละสถานะงานพิมพ์ (label + สี + ไอคอน)
/// ตรงกับ PrintJobStatus enum ฝั่ง backend — label มาจาก i18n (ส่ง l10n เข้ามา)
class PrintJobStatusStyle {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;

  const PrintJobStatusStyle(this.label, this.color, this.bg, this.icon);

  static PrintJobStatusStyle of(AppLocalizations l10n, String status) {
    switch (status) {
      case 'QUEUED':
        return PrintJobStatusStyle(l10n.pjStatusQueued,
            SterelisColors.textMuted, SterelisColors.surface2, Icons.schedule);
      case 'CLAIMED':
        return PrintJobStatusStyle(l10n.pjStatusClaimed,
            SterelisColors.blue600, SterelisColors.blue50, Icons.assignment_turned_in_outlined);
      case 'PRINTING':
        return PrintJobStatusStyle(l10n.pjStatusPrinting,
            SterelisColors.blue600, SterelisColors.blue50, Icons.print_outlined);
      case 'SENT':
        return PrintJobStatusStyle(l10n.pjStatusSent,
            SterelisColors.teal500, SterelisColors.teal100, Icons.outbox_outlined);
      case 'PRINTED':
        return PrintJobStatusStyle(l10n.pjStatusPrinted,
            SterelisColors.success, SterelisColors.successBg, Icons.check_circle);
      case 'SIMULATED':
        return PrintJobStatusStyle(l10n.pjStatusSimulated,
            SterelisColors.warning, SterelisColors.warningBg, Icons.science_outlined);
      case 'FAILED':
        return PrintJobStatusStyle(l10n.pjStatusFailed,
            SterelisColors.danger, SterelisColors.dangerBg, Icons.error_outline);
      case 'RETRYING':
        return PrintJobStatusStyle(l10n.pjStatusRetrying,
            SterelisColors.warning, SterelisColors.warningBg, Icons.refresh);
      case 'DEAD_LETTER':
        return PrintJobStatusStyle(l10n.pjStatusDeadLetter,
            SterelisColors.danger, SterelisColors.dangerBg, Icons.report_gmailerrorred_outlined);
      case 'ACK_UNKNOWN':
        return PrintJobStatusStyle(l10n.pjStatusAckUnknown,
            SterelisColors.warning, SterelisColors.warningBg, Icons.help_outline);
      case 'RESOLVED_PRINTED':
        return PrintJobStatusStyle(l10n.pjStatusResolvedPrinted,
            SterelisColors.success, SterelisColors.successBg, Icons.verified_outlined);
      case 'RESOLVED_REQUEUED':
        return PrintJobStatusStyle(l10n.pjStatusResolvedRequeued,
            SterelisColors.blue600, SterelisColors.blue50, Icons.replay);
      case 'CANCELLED':
        return PrintJobStatusStyle(l10n.pjStatusCancelled,
            SterelisColors.textFaint, SterelisColors.surface2, Icons.cancel_outlined);
      default:
        return PrintJobStatusStyle(status, SterelisColors.textMuted,
            SterelisColors.surface2, Icons.help_outline);
    }
  }
}

/// ลำดับความคืบหน้าปกติ (happy path) — ใช้วาด timeline (label มาจาก i18n)
List<(String, String)> printProgressSteps(AppLocalizations l10n) => [
      ('QUEUED', l10n.pjStepQueued),
      ('CLAIMED', l10n.pjStepClaimed),
      ('PRINTING', l10n.pjStepPrinting),
      ('SENT', l10n.pjStepSent),
      ('PRINTED', l10n.pjStepPrinted),
    ];

/// index ของสถานะปัจจุบันบน happy path (-1 = ไม่อยู่บนเส้นปกติ เช่น FAILED/ACK_UNKNOWN)
int printProgressIndex(String status) {
  switch (status) {
    case 'QUEUED':
      return 0;
    case 'CLAIMED':
    case 'RETRYING':
      return 1;
    case 'PRINTING':
      return 2;
    case 'SENT':
      return 3;
    case 'PRINTED':
    case 'SIMULATED':
    case 'RESOLVED_PRINTED':
      return 4;
    default:
      return -1;
  }
}
