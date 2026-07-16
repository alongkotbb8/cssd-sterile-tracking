import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// การ์ด QR code ของห่อ — เก็บเฉพาะ package_id ตามกฎโดเมน (ห้ามยัดข้อมูลอื่นลง QR)
class PackageQrCard extends StatelessWidget {
  const PackageQrCard({super.key, required this.packageId, this.size = 180});
  final String packageId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SterelisColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SterelisColors.border),
      ),
      child: Column(children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('QR สำหรับสแกน',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: SterelisColors.textStrong)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SterelisColors.border),
          ),
          child: QrImageView(
            data: packageId,
            version: QrVersions.auto,
            size: size,
            gapless: false,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: SterelisColors.ink900,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: SterelisColors.ink900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(packageId,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SterelisColors.textMuted)),
      ]),
    );
  }
}

/// สี/ป้ายของสถานะห่อ — ผูกกับ state machine ใน design system
({Color fg, Color bg, String label}) packageStatusStyle(String status) {
  switch (status) {
    case 'PACKED':
      return (
        fg: SterelisColors.stPacked,
        bg: SterelisColors.stPackedBg,
        label: 'แพ็กแล้ว'
      );
    case 'PACKED_OUT':
      // ส่งออกโดยยังไม่ฆ่าเชื้อ — โทนม่วง แยกจาก ISSUED (น้ำเงิน) ให้เห็นชัด
      return (
        fg: const Color(0xFF8B5CF6),
        bg: const Color(0xFFF3EEFE),
        label: 'ส่งออก (ยังไม่ฆ่าเชื้อ)'
      );
    case 'STERILE':
      return (
        fg: SterelisColors.stSterile,
        bg: SterelisColors.stSterileBg,
        label: 'ปลอดเชื้อ'
      );
    case 'ISSUED':
      return (
        fg: SterelisColors.stIssued,
        bg: SterelisColors.stIssuedBg,
        label: 'เบิกออก'
      );
    case 'RETURNED':
      return (
        fg: SterelisColors.stReturned,
        bg: SterelisColors.stReturnedBg,
        label: 'รอ Reprocess'
      );
    case 'EXPIRED':
      return (
        fg: SterelisColors.stExpired,
        bg: SterelisColors.stExpiredBg,
        label: 'หมดอายุ'
      );
    case 'DISCARDED':
      return (
        fg: SterelisColors.stDiscarded,
        bg: SterelisColors.stDiscardedBg,
        label: 'ทิ้ง/ชำรุด'
      );
    default:
      return (
        fg: SterelisColors.textMuted,
        bg: SterelisColors.stPackedBg,
        label: status
      );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = packageStatusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: s.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(s.label,
              style: TextStyle(
                  color: s.fg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class WrapBadge extends StatelessWidget {
  const WrapBadge(this.wrapType, {super.key});
  final String wrapType; // SEAL | CLOTH

  @override
  Widget build(BuildContext context) {
    final isSeal = wrapType == 'SEAL';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: isSeal ? SterelisColors.wrapSealBg : SterelisColors.wrapClothBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isSeal ? 'ห่อซีล · 180 วัน' : 'ห่อผ้า · 7 วัน',
        style: TextStyle(
          color: isSeal ? SterelisColors.wrapSeal : SterelisColors.wrapCloth,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// วงแหวนวันหมดอายุ — เขียว/เหลือง/แดง ตามวันคงเหลือ
class ExpiryRing extends StatelessWidget {
  const ExpiryRing({super.key, required this.pkg, this.size = 54});
  final PackageModel pkg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final daysLeft = pkg.daysLeft;
    if (pkg.expiryDate == null) {
      return SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: Icon(Icons.hourglass_empty,
              color: SterelisColors.textFaint, size: 20),
        ),
      );
    }

    final expired = daysLeft! < 0;
    final warnThreshold = pkg.wrapType == 'CLOTH' ? 2 : 14;
    final color = expired
        ? SterelisColors.danger
        : daysLeft <= warnThreshold
            ? SterelisColors.warning
            : SterelisColors.success;
    final value =
        expired ? 1.0 : (daysLeft / pkg.shelfLifeDays).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: SterelisColors.border,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expired ? '!' : '$daysLeft',
                style: TextStyle(
                  fontSize: expired ? 18 : 14,
                  fontWeight: FontWeight.w800,
                  color: expired ? SterelisColors.danger : SterelisColors.textStrong,
                  height: 1,
                ),
              ),
              if (!expired)
                const Text('วัน',
                    style: TextStyle(
                        fontSize: 8,
                        color: SterelisColors.textFaint,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
            ],
          ),
        ],
      ),
    );
  }
}

/// การ์ดแจ้งบล็อก "ห้ามใช้" สีแดง — ตาม pattern .blocked ใน design system
class BlockedCard extends StatelessWidget {
  const BlockedCard({super.key, required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SterelisColors.dangerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF4BFC1), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: SterelisColors.danger,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.block, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: SterelisColors.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                Text(detail,
                    style: const TextStyle(
                        color: Color(0xFFA23B3F), fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
