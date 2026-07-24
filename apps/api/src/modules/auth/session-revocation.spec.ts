import { UnauthorizedException } from '@nestjs/common';

// Session revocation (Track A) — JWT tokenVersion (ver) ต้องตรงกับ user.tokenVersion
// มิฉะนั้นถือว่า session ถูกเพิกถอน (logout-all / ADMIN revoke)
describe('Session revocation', () => {
  const OLD_SECRET = process.env.JWT_SECRET;
  beforeAll(() => {
    process.env.JWT_SECRET = 'test-secret-for-strategy';
  });
  afterAll(() => {
    process.env.JWT_SECRET = OLD_SECRET;
  });

  describe('JwtStrategy.validate — ver check', () => {
    // require หลังตั้ง env (constructor เรียก requireEnv('JWT_SECRET'))
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { JwtStrategy } = require('./jwt.strategy');

    function strategyWith(user: any) {
      const prisma = { user: { findUnique: jest.fn().mockResolvedValue(user) } };
      return new JwtStrategy(prisma as any);
    }

    const activeUser = { id: 'u1', role: 'CSSD', name: 'A', status: 'ACTIVE', tokenVersion: 2 };

    it('ver ตรงกับ tokenVersion → ผ่าน', async () => {
      const s = strategyWith(activeUser);
      await expect(
        s.validate({ sub: 'u1', role: 'CSSD', name: 'A', ver: 2 }),
      ).resolves.toEqual({ id: 'u1', role: 'CSSD', name: 'A' });
    });

    it('ver ไม่ตรง (token เก่าถูกเพิกถอน) → 401', async () => {
      const s = strategyWith(activeUser);
      await expect(
        s.validate({ sub: 'u1', role: 'CSSD', name: 'A', ver: 1 }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('token เก่าที่ไม่มี ver (ก่อนมีฟีเจอร์) → 401 (ต้อง login ใหม่)', async () => {
      const s = strategyWith(activeUser);
      await expect(
        s.validate({ sub: 'u1', role: 'CSSD', name: 'A' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('user ไม่ ACTIVE → 401 (ตรวจก่อน ver)', async () => {
      const s = strategyWith({ ...activeUser, status: 'INACTIVE' });
      await expect(
        s.validate({ sub: 'u1', role: 'CSSD', name: 'A', ver: 2 }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });

  describe('AuthService.revokeSessions', () => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { AuthService } = require('./auth.service');

    it('เพิ่ม tokenVersion + เขียน AuditLog ใน tx เดียว', async () => {
      const update = jest.fn().mockResolvedValue({});
      const auditLogCreate = jest.fn().mockResolvedValue({});
      const tx = { user: { update }, auditLog: { create: auditLogCreate } };
      const prisma = {
        user: { findUnique: jest.fn().mockResolvedValue({ id: 'u1' }) },
        $transaction: jest.fn(async (fn: any) => fn(tx)),
      };
      const audit = {
        logTx: (t: any, actorId: string, action: string, targetId: string, meta: any) =>
          t.auditLog.create({ data: { userId: actorId, action, targetId, metadata: meta } }),
      };
      const svc = new AuthService(prisma as any, {} as any, audit as any);

      const res = await svc.revokeSessions('u1', 'admin1');
      expect(res).toEqual({ revoked: true });
      expect(update).toHaveBeenCalledWith({
        where: { id: 'u1' },
        data: { tokenVersion: { increment: 1 } },
      });
      expect(auditLogCreate).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ action: 'SESSION_REVOKE', targetId: 'u1' }),
        }),
      );
    });

    it('ผู้ใช้ไม่มีอยู่ → throw', async () => {
      const prisma = {
        user: { findUnique: jest.fn().mockResolvedValue(null) },
        $transaction: jest.fn(),
      };
      const svc = new AuthService(prisma as any, {} as any, {} as any);
      await expect(svc.revokeSessions('nope', 'admin1')).rejects.toBeTruthy();
    });
  });
});
