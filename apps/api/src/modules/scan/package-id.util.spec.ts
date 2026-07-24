import { BadRequestException } from '@nestjs/common';
import { isValidPackageId, assertValidPackageId } from './package-id.util';

// P1 #5 — backend validate package id (กัน API-direct bypass ของ client validation)
describe('package-id.util', () => {
  describe('isValidPackageId', () => {
    it('เลขรันมาตรฐาน / charset ที่อนุญาต → true', () => {
      expect(isValidPackageId('DELIV-20260630-0007')).toBe(true);
      expect(isValidPackageId('ABC123')).toBe(true);
      expect(isValidPackageId('X')).toBe(true);
      expect(isValidPackageId('A'.repeat(60))).toBe(true);
    });

    it('ว่าง / ยาวเกิน 60 / อักขระนอก charset → false', () => {
      expect(isValidPackageId('')).toBe(false);
      expect(isValidPackageId('A'.repeat(61))).toBe(false);
      expect(isValidPackageId('has space')).toBe(false);
      expect(isValidPackageId('under_score')).toBe(false);
      expect(isValidPackageId('https://evil.example.com')).toBe(false);
      expect(isValidPackageId('เลขไทย')).toBe(false);
      expect(isValidPackageId('{"id":1}')).toBe(false);
    });
  });

  describe('assertValidPackageId', () => {
    it('รูปแบบถูก → ไม่ throw', () => {
      expect(() => assertValidPackageId('DELIV-20260630-0007')).not.toThrow();
    });
    it('รูปแบบผิด → โยน BadRequestException', () => {
      expect(() => assertValidPackageId('bad id!')).toThrow(BadRequestException);
      expect(() => assertValidPackageId('')).toThrow(BadRequestException);
    });
  });
});
