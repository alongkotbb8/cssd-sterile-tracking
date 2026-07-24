import { BadRequestException } from '@nestjs/common';

/**
 * รูปแบบเลขห่อ (running number) — ใช้ตรวจฝั่ง backend ทั้ง DTO (body) และ path param
 * ให้ตรงกับ client (`isValidPackageId` ฝั่ง Flutter) รูปแบบ {SET}-{YYYYMMDD}-{SEQ}
 * อักขระที่อนุญาต: ตัวอักษร/ตัวเลข/ขีด (-) เท่านั้น
 */
export const PACKAGE_ID_PATTERN = /^[A-Za-z0-9-]+$/;
export const PACKAGE_ID_MAX_LEN = 60;

export function isValidPackageId(id: string): boolean {
  return (
    typeof id === 'string' &&
    id.length > 0 &&
    id.length <= PACKAGE_ID_MAX_LEN &&
    PACKAGE_ID_PATTERN.test(id)
  );
}

/** ตรวจ path param (lookup/:id) — โยน 400 ถ้ารูปแบบไม่ถูกต้อง (กัน API-direct bypass) */
export function assertValidPackageId(id: string): void {
  if (!isValidPackageId(id)) {
    throw new BadRequestException({ message: 'รูปแบบเลขห่อไม่ถูกต้อง', code: 'PKG_ID_INVALID' });
  }
}
