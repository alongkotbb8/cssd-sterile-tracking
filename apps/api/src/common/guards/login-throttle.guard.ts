import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { Request } from 'express';

// ค่า default = พฤติกรรม production เดิม; override ได้ผ่าน env เฉพาะสภาพแวดล้อม
// ทดสอบ (E2E ทุก request มาจาก IP เดียวกัน — per-IP throttle จะปัดตกเทสทั้งชุด)
// การ override ไม่ได้ปิด guard: logic เดิมยังทำงานครบทุก request
const WINDOW_MS = Number(process.env.LOGIN_THROTTLE_WINDOW_MS) || 60_000; // 1 minute
const MAX_ATTEMPTS = Number(process.env.LOGIN_THROTTLE_MAX) || 10; // per IP per window

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
        'พยายามเข้าสู่ระบบบ่อยเกินไป กรุณาลองใหม่อีกครั้งภายหลัง',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    return true;
  }
}
