/**
 * Master directive A2.4–A2.7 — parse + validate login-throttle env vars.
 *
 * ต้องเป็นจำนวนเต็ม > 0 และไม่เกินเพดานปลอดภัย; production ที่ตั้งค่าผิดต้อง
 * **fail fast** (โยน error ตอนบูต) แทนที่จะเงียบ ๆ fallback แล้วเปิดช่องโจมตี
 * ค่า override ที่ "ผ่อนปรน" (เกินเพดาน production เช่นปิด throttle ตอน E2E)
 * อนุญาตเฉพาะเมื่อ NODE_ENV เป็น test/e2e/ci เท่านั้น
 */
export interface ThrottleConfig {
  windowMs: number;
  maxAttempts: number;
}

export const THROTTLE_DEFAULTS: ThrottleConfig = {
  windowMs: 60_000, // 1 นาที
  maxAttempts: 10, // ต่อ IP ต่อหน้าต่าง
};

// เพดานปลอดภัยของ production (ค่ามากกว่านี้ = throttle อ่อนเกินไป/ถูกปิด)
export const PROD_MAX_ATTEMPTS_CEILING = 100;
export const PROD_WINDOW_MS_CEILING = 60 * 60_000; // 1 ชั่วโมง
// ขอบเขตดูดี (กันตั้งค่าเพี้ยน) ใช้ทุก environment
export const ABS_MAX_ATTEMPTS = 1_000_000;
export const ABS_MAX_WINDOW_MS = 24 * 60 * 60_000; // 1 วัน

const RELAXED_ENVS = new Set(['test', 'e2e', 'ci']);

function parsePositiveInt(raw: string | undefined, name: string): number | undefined {
  if (raw === undefined || raw.trim() === '') return undefined;
  // ต้องเป็นจำนวนเต็มล้วน (กัน "10abc", "1e3", "10.5", " ", ค่าติดลบ)
  if (!/^\d+$/.test(raw.trim())) {
    throw new Error(`${name} must be a positive integer, got "${raw}"`);
  }
  const n = Number(raw.trim());
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error(`${name} must be a positive integer > 0, got "${raw}"`);
  }
  return n;
}

/**
 * คำนวณ config จาก env — pure (รับ env + nodeEnv เข้ามาเพื่อ unit-test)
 * โยน Error เมื่อค่าไม่ถูกต้อง หรือเกินเพดานใน production
 */
export function resolveThrottleConfig(
  env: NodeJS.ProcessEnv,
  nodeEnv: string | undefined = env.NODE_ENV,
): ThrottleConfig {
  const relaxed = RELAXED_ENVS.has((nodeEnv ?? '').toLowerCase());

  const maxAttempts =
    parsePositiveInt(env.LOGIN_THROTTLE_MAX, 'LOGIN_THROTTLE_MAX') ??
    THROTTLE_DEFAULTS.maxAttempts;
  const windowMs =
    parsePositiveInt(env.LOGIN_THROTTLE_WINDOW_MS, 'LOGIN_THROTTLE_WINDOW_MS') ??
    THROTTLE_DEFAULTS.windowMs;

  // ขอบเขตสัมบูรณ์ (กันค่าเพี้ยนสุดโต่งทุก environment)
  if (maxAttempts > ABS_MAX_ATTEMPTS) {
    throw new Error(`LOGIN_THROTTLE_MAX exceeds absolute limit ${ABS_MAX_ATTEMPTS}`);
  }
  if (windowMs > ABS_MAX_WINDOW_MS) {
    throw new Error(`LOGIN_THROTTLE_WINDOW_MS exceeds absolute limit ${ABS_MAX_WINDOW_MS}`);
  }

  // เพดาน production — ค่าที่อ่อนกว่านี้ยอมรับเฉพาะ test/e2e/ci
  if (!relaxed) {
    if (maxAttempts > PROD_MAX_ATTEMPTS_CEILING) {
      throw new Error(
        `LOGIN_THROTTLE_MAX=${maxAttempts} exceeds the production ceiling ` +
          `${PROD_MAX_ATTEMPTS_CEILING}; a value this high effectively disables ` +
          `brute-force protection. Only test/e2e/ci may relax it.`,
      );
    }
    if (windowMs > PROD_WINDOW_MS_CEILING) {
      throw new Error(
        `LOGIN_THROTTLE_WINDOW_MS=${windowMs} exceeds the production ceiling ` +
          `${PROD_WINDOW_MS_CEILING}. Only test/e2e/ci may relax it.`,
      );
    }
  }

  return { windowMs, maxAttempts };
}
