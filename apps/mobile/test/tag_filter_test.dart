import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/core/models/models.dart';
import 'package:cssd_mobile/core/api/repositories.dart';

// 2.7 — tag filter (model parsing + query cache key)
void main() {
  group('Tag.fromJson', () {
    test('parse id/name/colorHex', () {
      final t = Tag.fromJson({'id': 't1', 'name': 'ด่วน', 'colorHex': '#2563EB'});
      expect(t.id, 't1');
      expect(t.name, 'ด่วน');
      expect(t.colorHex, '#2563EB');
    });

    test('colorValue แปลง #RRGGBB → ARGB (เติม FF ด้านหน้า)', () {
      final t = Tag.fromJson({'id': 't', 'name': 'x', 'colorHex': '#2563EB'});
      expect(t.colorValue, 0xFF2563EB);
    });

    test('colorHex ว่าง/ผิดรูปแบบ → colorValue = null', () {
      expect(Tag.fromJson({'id': 't', 'name': 'x'}).colorValue, isNull);
      expect(
          Tag.fromJson({'id': 't', 'name': 'x', 'colorHex': 'blue'}).colorValue,
          isNull);
      expect(
          Tag.fromJson({'id': 't', 'name': 'x', 'colorHex': '#12'}).colorValue,
          isNull);
    });

    test('เทียบเท่ากันด้วย id (ใช้เลือกใน chip)', () {
      expect(const Tag(id: 'a', name: 'A'), const Tag(id: 'a', name: 'B'));
      expect(const Tag(id: 'a', name: 'A'), isNot(const Tag(id: 'b', name: 'A')));
    });
  });

  group('PackageQuery (family cache key)', () {
    test('record ที่ค่าเท่ากัน = เท่ากัน (cache ทำงานถูก)', () {
      const PackageQuery a = (status: 'STERILE', tagId: 't1', search: null);
      const PackageQuery b = (status: 'STERILE', tagId: 't1', search: null);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('status/tagId/search ต่างกัน = คนละคีย์', () {
      const PackageQuery base = (status: 'STERILE', tagId: 't1', search: null);
      expect(base == (status: 'PACKED', tagId: 't1', search: null), isFalse);
      expect(base == (status: 'STERILE', tagId: 't2', search: null), isFalse);
      expect(base == (status: 'STERILE', tagId: null, search: null), isFalse);
      expect(base == (status: 'STERILE', tagId: 't1', search: 'x'), isFalse);
    });

    test('null ทั้งหมด = กรองทั้งหมด', () {
      const PackageQuery all = (status: null, tagId: null, search: null);
      expect(all == (status: null, tagId: null, search: null), isTrue);
    });
  });
}
