import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// สไตล์การแสดงผลของแต่ละสถานะงานพิมพ์ (label ไทย + สี + ไอคอน)
/// ตรงกับ PrintJobStatus enum ฝั่ง backend
class PrintJobStatusStyle {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;

  const PrintJobStatusStyle(this.label, this.color, this.bg, this.icon);

  static PrintJobStatusStyle of(String status) {
    switch (status) {
      case 'QUEUED':
        return const PrintJobStatusStyle('รอเครื่องพิมพ์รับงาน',
            SterelisColors.textMuted, SterelisColors.surface2, Icons.schedule);
      case 'CLAIMED':
        return const PrintJobStatusStyle('เครื่องพิมพ์รับงานแล้ว',
            SterelisColors.blue600, SterelisColors.blue50, Icons.assignment_turned_in_outlined);
      case 'PRINTING':
        return const PrintJobStatusStyle('กำลังส่งไปเครื่องพิมพ์',
            SterelisColors.blue600, SterelisColors.blue50, Icons.print_outlined);
      case 'SENT':
        return const PrintJobStatusStyle('ส่งข้อมูลถึงเครื่องพิมพ์แล้ว',
            SterelisColors.teal500, SterelisColors.teal100, Icons.outbox_outlined);
      case 'PRINTED':
        return const PrintJobStatusStyle('พิมพ์สำเร็จ',
            SterelisColors.success, SterelisColors.successBg, Icons.check_circle);
      case 'SIMULATED':
        return const PrintJobStatusStyle('จำลอง (โหมดทดสอบ ไม่ใช่พิมพ์จริง)',
            SterelisColors.warning, SterelisColors.warningBg, Icons.science_outlined);
      case 'FAILED':
        return const PrintJobStatusStyle('พิมพ์ไม่สำเร็จ (กำลังจะลองใหม่)',
            SterelisColors.danger, SterelisColors.dangerBg, Icons.error_outline);
      case 'RETRYING':
        return const PrintJobStatusStyle('กำลังลองพิมพ์ใหม่',
            SterelisColors.warning, SterelisColors.warningBg, Icons.refresh);
      case 'DEAD_LETTER':
        return const PrintJobStatusStyle('ล้มเหลวถาวร ต้องตรวจสอบ',
            SterelisColors.danger, SterelisColors.dangerBg, Icons.report_gmailerrorred_outlined);
      case 'ACK_UNKNOWN':
        return const PrintJobStatusStyle('ไม่แน่ใจว่าพิมพ์จริง — ต้องให้หัวหน้าตัดสิน',
            SterelisColors.warning, SterelisColors.warningBg, Icons.help_outline);
      case 'RESOLVED_PRINTED':
        return const PrintJobStatusStyle('หัวหน้ายืนยันว่าพิมพ์แล้ว',
            SterelisColors.success, SterelisColors.successBg, Icons.verified_outlined);
      case 'RESOLVED_REQUEUED':
        return const PrintJobStatusStyle('หัวหน้าสั่งเปิดงานพิมพ์ใหม่',
            SterelisColors.blue600, SterelisColors.blue50, Icons.replay);
      case 'CANCELLED':
        return const PrintJobStatusStyle('ยกเลิกแล้ว',
            SterelisColors.textFaint, SterelisColors.surface2, Icons.cancel_outlined);
      default:
        return PrintJobStatusStyle(status, SterelisColors.textMuted,
            SterelisColors.surface2, Icons.help_outline);
    }
  }
}

/// ลำดับความคืบหน้าปกติ (happy path) — ใช้วาด timeline
const kPrintProgressSteps = <(String, String)>[
  ('QUEUED', 'เข้าคิว'),
  ('CLAIMED', 'รับงาน'),
  ('PRINTING', 'ส่งพิมพ์'),
  ('SENT', 'ถึงเครื่อง'),
  ('PRINTED', 'สำเร็จ'),
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
