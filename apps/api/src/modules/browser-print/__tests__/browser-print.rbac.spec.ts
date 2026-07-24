import 'reflect-metadata';
import { HttpException } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { UserRole } from '@prisma/client';
import { ROLES_KEY } from '../../../common/decorators/roles.decorator';
import { RolesGuard } from '../../../common/guards/roles.guard';
import { BrowserPrintController } from '../browser-print.controller';
import { BrowserPrintThrottleGuard } from '../browser-print-throttle.guard';
import {
  BROWSER_PRINT_THROTTLE_DEFAULTS,
  resolveBrowserPrintEnabled,
  resolveBrowserPrintThrottle,
} from '../browser-print-config';

/**
 * Regression guard สำหรับ auth/RBAC/rate-limit ของ browser print endpoints
 * (MACOS_BROWSER_PRINT_DIRECTIVE.md §13 + §14 กรณี 2) — ตรวจ metadata ของ guard
 * โดยตรงแบบเดียวกับ print-jobs.rbac.spec.ts
 */
function rolesOf(method: keyof BrowserPrintController): UserRole[] | undefined {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Reflect.getMetadata(ROLES_KEY, (BrowserPrintController.prototype as any)[method]);
}

function methodGuards(method: keyof BrowserPrintController): any[] {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Reflect.getMetadata('__guards__', (BrowserPrintController.prototype as any)[method]) ?? [];
}

describe('BrowserPrintController — auth guards (§14.2 ไม่มี auth ถูกปฏิเสธ)', () => {
  it('class-level guards = passport JWT guard + RolesGuard (ทุก endpoint ต้อง authenticate)', () => {
    const guards: any[] = Reflect.getMetadata('__guards__', BrowserPrintController);
    expect(guards).toHaveLength(2);
    expect(guards).toContain(RolesGuard);
    // AuthGuard('jwt') คืน mixin class ของ passport (memoized — เรียกซ้ำได้ class เดิม)
    const passportGuard = guards.find((g) => g !== RolesGuard);
    expect(typeof passportGuard).toBe('function');
    expect(typeof passportGuard.prototype.canActivate).toBe('function');
    expect(passportGuard).toBe(AuthGuard('jwt'));
  });

  it('ทุก mutation มี BrowserPrintThrottleGuard (rate limit ต่อผู้ใช้)', () => {
    for (const m of ['create', 'dialogOpened', 'confirm', 'cancel'] as const) {
      expect(methodGuards(m)).toContain(BrowserPrintThrottleGuard);
    }
  });

  it('read endpoints ไม่ต้องผ่าน throttle guard', () => {
    expect(methodGuards('list')).toEqual([]);
    expect(methodGuards('findOne')).toEqual([]);
  });

  it('ไม่มี @Roles จำกัด (ทุก role ที่ authenticate ใช้ได้) — ownership/IDOR บังคับใน service', () => {
    for (const m of ['create', 'list', 'findOne', 'dialogOpened', 'confirm', 'cancel'] as const) {
      expect(rolesOf(m)).toBeUndefined();
    }
  });
});

describe('BrowserPrintThrottleGuard — 429 BROWSER_PRINT_RATE_LIMITED', () => {
  const ctx = (userId: string) =>
    ({
      switchToHttp: () => ({ getRequest: () => ({ user: { id: userId }, ip: '10.0.0.1' }) }),
    }) as any;

  it('เกินโควตาต่อผู้ใช้ในหน้าต่างเวลา → HttpException 429 code BROWSER_PRINT_RATE_LIMITED', () => {
    const guard = new BrowserPrintThrottleGuard();
    for (let i = 0; i < BROWSER_PRINT_THROTTLE_DEFAULTS.maxRequests; i++) {
      expect(guard.canActivate(ctx('u1'))).toBe(true);
    }
    let caught: any;
    try {
      guard.canActivate(ctx('u1'));
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(HttpException);
    expect(caught.getStatus()).toBe(429);
    expect(caught.getResponse()).toMatchObject({ code: 'BROWSER_PRINT_RATE_LIMITED' });
    // ผู้ใช้อื่นไม่โดนหางเลข (bucket แยกต่อ user ไม่ใช่ต่อ IP)
    expect(guard.canActivate(ctx('u2'))).toBe(true);
  });
});

describe('browser-print-config — fail-fast env validation (directive §4)', () => {
  it("flag: 'true'→true, 'false'/unset→false, ค่าอื่น→throw", () => {
    expect(resolveBrowserPrintEnabled({ CSSD_BROWSER_PRINT_ENABLED: 'true' } as any)).toBe(true);
    expect(resolveBrowserPrintEnabled({ CSSD_BROWSER_PRINT_ENABLED: 'false' } as any)).toBe(false);
    expect(resolveBrowserPrintEnabled({} as any)).toBe(false);
    expect(() => resolveBrowserPrintEnabled({ CSSD_BROWSER_PRINT_ENABLED: 'TRUE' } as any)).toThrow();
    expect(() => resolveBrowserPrintEnabled({ CSSD_BROWSER_PRINT_ENABLED: '1' } as any)).toThrow();
  });

  it('throttle: default 60/60000, ค่า env ต้องเป็นจำนวนเต็มบวกเท่านั้น', () => {
    expect(resolveBrowserPrintThrottle({} as any)).toEqual({ maxRequests: 60, windowMs: 60_000 });
    expect(
      resolveBrowserPrintThrottle({
        BROWSER_PRINT_THROTTLE_MAX: '5',
        BROWSER_PRINT_THROTTLE_WINDOW_MS: '1000',
      } as any),
    ).toEqual({ maxRequests: 5, windowMs: 1000 });
    expect(() => resolveBrowserPrintThrottle({ BROWSER_PRINT_THROTTLE_MAX: '10abc' } as any)).toThrow();
    expect(() => resolveBrowserPrintThrottle({ BROWSER_PRINT_THROTTLE_MAX: '0' } as any)).toThrow();
    expect(() =>
      resolveBrowserPrintThrottle({ BROWSER_PRINT_THROTTLE_WINDOW_MS: '-1' } as any),
    ).toThrow();
  });
});
