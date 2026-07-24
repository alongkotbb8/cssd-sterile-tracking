import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { GatewayAuthGuard } from '../gateway-auth.guard';

function makeContext(headers: Record<string, string>) {
  const req: any = { headers };
  return {
    switchToHttp: () => ({ getRequest: () => req }),
  } as any;
}

describe('GatewayAuthGuard', () => {
  const keyId = 'abc123';
  const secret = 'super-secret-value';
  let apiKeyHash: string;

  beforeAll(async () => {
    apiKeyHash = await bcrypt.hash(secret, 10);
  });

  function makePrisma(printer: any) {
    return { printerDevice: { findUnique: async () => printer } };
  }

  it('accepts a valid keyId.secret and attaches req.gateway', async () => {
    const printer = { id: 'printer-1', name: 'CSSD ชั้น 2', keyId, apiKeyHash, isActive: true, revokedAt: null };
    const guard = new GatewayAuthGuard(makePrisma(printer) as any);
    const ctx = makeContext({ 'x-gateway-key': `${keyId}.${secret}` });

    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(ctx.switchToHttp().getRequest().gateway).toEqual({ id: 'printer-1', name: 'CSSD ชั้น 2' });
  });

  it('rejects when the header is missing', async () => {
    const guard = new GatewayAuthGuard(makePrisma(null) as any);
    const ctx = makeContext({});
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a malformed header (no keyId.secret separator)', async () => {
    const guard = new GatewayAuthGuard(makePrisma(null) as any);
    const ctx = makeContext({ 'x-gateway-key': 'not-a-valid-key' });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an unknown keyId', async () => {
    const guard = new GatewayAuthGuard(makePrisma(null) as any);
    const ctx = makeContext({ 'x-gateway-key': `${keyId}.${secret}` });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a revoked gateway even with the correct secret', async () => {
    const printer = {
      id: 'printer-1',
      name: 'X',
      keyId,
      apiKeyHash,
      isActive: false,
      revokedAt: new Date(),
    };
    const guard = new GatewayAuthGuard(makePrisma(printer) as any);
    const ctx = makeContext({ 'x-gateway-key': `${keyId}.${secret}` });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects the wrong secret for a valid keyId', async () => {
    const printer = { id: 'printer-1', name: 'X', keyId, apiKeyHash, isActive: true, revokedAt: null };
    const guard = new GatewayAuthGuard(makePrisma(printer) as any);
    const ctx = makeContext({ 'x-gateway-key': `${keyId}.wrong-secret` });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
