import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/features/scan/presentation/pages/scan_page.dart';

// 2.4 — validate package id จาก QR/พิมพ์เอง ก่อน lookup
void main() {
  group('isValidPackageId', () {
    test('เลขรันรูปแบบมาตรฐาน → ok', () {
      expect(isValidPackageId('DELIV-20260630-0007'), isTrue);
      expect(isValidPackageId('WOUND-20260101-0001'), isTrue);
    });

    test('ตัวอักษร/ตัวเลข/ขีด ล้วน → ok', () {
      expect(isValidPackageId('ABC123'), isTrue);
      expect(isValidPackageId('a-b-c-1-2-3'), isTrue);
      expect(isValidPackageId('X'), isTrue);
    });

    test('ค่าว่าง → ไม่ผ่าน', () {
      expect(isValidPackageId(''), isFalse);
    });

    test('ยาวเกิน 60 ตัว → ไม่ผ่าน', () {
      expect(isValidPackageId('A' * 60), isTrue);
      expect(isValidPackageId('A' * 61), isFalse);
    });

    test('QR ที่ไม่ใช่เลขห่อ (ลิงก์/ข้อความ/อักขระพิเศษ) → ไม่ผ่าน', () {
      expect(isValidPackageId('https://evil.example.com/x'), isFalse);
      expect(isValidPackageId('DELIV 20260630 0007'), isFalse); // มีช่องว่าง
      expect(isValidPackageId('DELIV_20260630'), isFalse); // underscore ไม่อยู่ใน charset
      expect(isValidPackageId('{"id":"x"}'), isFalse);
      expect(isValidPackageId('เลขไทย๑๒๓'), isFalse);
    });
  });
}
