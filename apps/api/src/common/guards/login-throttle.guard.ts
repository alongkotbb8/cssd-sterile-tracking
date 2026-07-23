import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { Request } from 'express';
import { resolveThrottleConfig } from '../config/throttle-config';

// อ่าน+validate env ตอนโหลดโมดูล (fail fast: production ตั้งค่าผิด/เกินเพดาน →
// โยน error ทันที ไม่เปิดเซิร์ฟเวอร์ที่ป้องกัน brute-force อ่อนเกินไปโดยเงียบ ๆ)
const { windowMs: WINDOW_MS, maxAttempts: MAX_ATTEMPTS } =
  resolveThrottleConfig(process.env);

interface Bucket {
  count: number;
  resetAt: number;
}

/**
 * Simple in-memory rate limiter for the login endpoint (brute-force protection).
 * Single-instance deployment (Phase 1) — swap for a shared store if scaled out.
 */
@Injectable()
export class LoginThrottleGuard implements CanActivate {
  private buckets = new Map<string, Bucket>();

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<Request>();
    const ip = req.ip ?? req.socket?.remoteAddress ?? 'unknown';
    const now = Date.now();

    // Opportunistic cleanup so the map cannot grow unbounded.
    if (this.buckets.size > 10_000) {
      for (const [key, bucket] of this.buckets) {
        if (bucket.resetAt <= now) this.buckets.delete(key);
      }
    }

    const bucket = this.buckets.get(ip);
    if (!bucket || bucket.resetAt <= now) {
      this.buckets.set(ip, { count: 1, resetAt: now + WINDOW_MS });
      return true;
    }

    bucket.count += 1;
    if (bucket.count > MAX_ATTEMPTS) {
      throw new HttpException(
        {
          message: 'พยายามเข้าสู่ระบบบ่อยเกินไป กรุณาลองใหม่อีกครั้งภายหลัง',
          code: 'AUTH_RATE_LIMITED',
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    return true;
  }
}
