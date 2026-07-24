import 'reflect-metadata';
import { UserRole } from '@prisma/client';
import { ROLES_KEY } from '../../../common/decorators/roles.decorator';
import { PackagesController } from '../packages.controller';

/**
 * Regression guard สำหรับ RBAC ของ packages endpoints — ตรวจ @Roles metadata บน
 * handler โดยตรง ถ้าใครเผลอลบ @Roles ออกจาก bulk-delete (ลบถาวร) เทสนี้ fail ทันที
 */
function rolesOf(method: keyof PackagesController): UserRole[] | undefined {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Reflect.getMetadata(ROLES_KEY, (PackagesController.prototype as any)[method]);
}

describe('PackagesController — RBAC metadata', () => {
  it('bulk-delete (ลบถาวร) requires SUPERVISOR/ADMIN', () => {
    expect(rolesOf('bulkDelete')).toEqual([UserRole.SUPERVISOR, UserRole.ADMIN]);
  });

  it('read/create/tags endpoints ไม่มี @Roles (ผู้ใช้ที่ยืนยันตัวตนแล้วเข้าถึงได้)', () => {
    expect(rolesOf('create')).toBeUndefined();
    expect(rolesOf('findAll')).toBeUndefined();
    expect(rolesOf('findOne')).toBeUndefined();
    expect(rolesOf('setTags')).toBeUndefined();
  });
});
