import 'package:cssd_mobile/core/models/models.dart';
import 'package:cssd_mobile/core/widgets/domain_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('packageStatusStyle', () {
    test('รู้จักทุกสถานะใน state machine', () {
      for (final s in [
        'PACKED',
        'STERILE',
        'ISSUED',
        'RETURNED',
        'EXPIRED',
        'DISCARDED'
      ]) {
        expect(packageStatusStyle(s).label, isNot(equals(s)),
            reason: 'สถานะ $s ควรมีป้ายภาษาไทย');
      }
    });
  });

  group('PackageModel', () {
    test('parse JSON จาก API และคำนวณ shelf life ตามชนิดห่อ', () {
      final pkg = PackageModel.fromJson({
        'id': 'DELIV-20260630-0007',
        'wrapType': 'CLOTH',
        'status': 'STERILE',
        'sterilizeDate': '2026-06-30T08:00:00.000Z',
        'expiryDate': '2026-07-07T08:00:00.000Z',
        'isExpired': false,
        'setTemplate': {'name': 'ชุดทำคลอด'},
      });
      expect(pkg.shelfLifeDays, 7);
      expect(pkg.templateName, 'ชุดทำคลอด');
      expect(pkg.expiryDate, isNotNull);

      final seal = PackageModel.fromJson({'id': 'X', 'wrapType': 'SEAL'});
      expect(seal.shelfLifeDays, 180);
    });
  });

  testWidgets('StatusBadge แสดงป้ายสถานะปลอดเชื้อ', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatusBadge('STERILE')),
    ));
    expect(find.text('ปลอดเชื้อ'), findsOneWidget);
  });

  testWidgets('BlockedCard แสดงข้อความห้ามใช้', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BlockedCard(title: 'ห้ามใช้ — หมดอายุแล้ว', detail: 'ทดสอบ'),
      ),
    ));
    expect(find.text('ห้ามใช้ — หมดอายุแล้ว'), findsOneWidget);
  });
}
