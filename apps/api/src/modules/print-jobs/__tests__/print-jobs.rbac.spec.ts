import 'reflect-metadata';
import { UserRole } from '@prisma/client';
import { ROLES_KEY } from '../../../common/decorators/roles.decorator';
import { PrintJobsController } from '../print-jobs.controller';

/**
 * Phase 5 — regression guard สำหรับ RBAC ของ print-job endpoints
 * ตรวจ @Roles metadata บน handler โดยตรง — ถ้าใครเผลอลบ @Roles ออกจาก endpoint
 * ที่ต้องจำกัดสิทธิ์ เทสนี้จะ fail ทันที (กันสิทธิ์หลุดเงียบ ๆ)
 */
function rolesOf(method: keyof PrintJobsController): UserRole[] | undefined {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Reflect.getMetadata(ROLES_KEY, (PrintJobsController.prototype as any)[method]);
}

describe('PrintJobsController — RBAC metadata (Phase 5)', () => {
  it('gateway management (register/capability/rotate-key/revoke) requires ADMIN', () => {
    expect(rolesOf('registerGateway')).toEqual([UserRole.ADMIN]);
    expect(rolesOf('updateGatewayCapability')).toEqual([UserRole.ADMIN]);
    expect(rolesOf('rotateGatewayKey')).toEqual([UserRole.ADMIN]);
    expect(rolesOf('revokeGateway')).toEqual([UserRole.ADMIN]);
  });

  it('gateways list + ACK_UNKNOWN resolve require SUPERVISOR/ADMIN', () => {
    expect(rolesOf('listGateways')).toEqual([UserRole.SUPERVISOR, UserRole.ADMIN]);
    expect(rolesOf('resolveAckUnknown')).toEqual([UserRole.SUPERVISOR, UserRole.ADMIN]);
  });

  it('create/list/findOne/cancel have no @Roles (any authenticated user) — authz enforced in service (ownership/IDOR)', () => {
    expect(rolesOf('create')).toBeUndefined();
    expect(rolesOf('list')).toBeUndefined();
    expect(rolesOf('findOne')).toBeUndefined();
    expect(rolesOf('cancel')).toBeUndefined();
  });
});
