import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { Request } from 'express';
import { resolveBrowserPrintThrottle } from './browser-print-config';

// อ่าน+validate env ตอนโหลดโมดูล (fail fast) — แนวเดียวกับ login-throttle.guard.ts
const { windowMs: WINDOW_MS, maxRequests: MAX_REQUESTS } =
  resolveBrowserPrintThrottle(process.env);

interface Bucket {
  count: number;
  resetAt: number;
}

/**
 * In-memory rate limiter ต่อ **ผู้ใช้** สำหรับ mutation ของ browser print
 * (MACOS_BROWSER_PRINT_DIRECTIVE.md §13: ต้อง rate limit endpoint ที่อาจถูกกดซ้ำ)
 *
 * ต้องรันหลัง AuthGuard('jwt') เสมอ (ใช้ req.user.id เป็น key) — Nest รัน guard
 * ระดับ class ก่อนระดับ method ดังนั้นการใส่ guard นี้ที่ method จึงได้ลำดับถูกต้อง
 * Single-instance deployment (Phase 1) — swap for a shared store if scaled out.
 */
@Injectable()
export class BrowserPrintThrottleGuard implements CanActivate {
  private buckets = new Map<string, Bucket>();

  canActivate(context: ExecutionContext): boolean {
    const req = context
      .switchToHttp()
      .getRequest<Request & { user?: { id?: string } }>();
    const key = req.user?.id ?? req.ip ?? 'unknown';
    const now = Date.now();

    // Opportunistic cleanup so the map cannot grow unbounded.
    if (this.buckets.size > 10_000) {
      for (const [k, bucket] of this.buckets) {
        if (bucket.resetAt <= now) this.buckets.delete(k);
      }
    }

    const bucket = this.buckets.get(key);
    if (!bucket || bucket.resetAt <= now) {
      this.buckets.set(key, { count: 1, resetAt: now + WINDOW_MS });
      return true;
    }

    bucket.count += 1;
    if (bucket.count > MAX_REQUESTS) {
      throw new HttpException(
        {
          message: 'ส่งคำขอพิมพ์ผ่านเบราว์เซอร์ถี่เกินไป กรุณาลองใหม่อีกครั้งภายหลัง',
          code: 'BROWSER_PRINT_RATE_LIMITED',
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    return true;
  }
}
