/**
 * MACOS_BROWSER_PRINT_DIRECTIVE.md §4 — feature flag + rate-limit config ของโหมด
 * `BROWSER_DIALOG` อ่าน+validate จาก env แบบ **fail fast** (ตั้งค่าผิด → โยน error
 * ตอนบูต ไม่ silently fallback) ตามแนวเดียวกับ common/config/throttle-config.ts
 *
 * ค่า default ต้องปลอดภัย: ไม่ตั้ง env = ปิดโหมด browser print เสมอ (production
 * ห้ามเปิดโดยไม่ตั้งใจ) และต้องปฏิเสธค่า mode ที่ไม่รู้จัก (ห้ามเดา)
 */

/** template version ของ label ฝั่ง browser print — เก็บลงทุก request เพื่อ traceability */
export const BROWSER_PRINT_TEMPLATE_VERSION = '1';

export const BROWSER_PRINT_THROTTLE_DEFAULTS = {
  maxRequests: 60, // ต่อผู้ใช้ ต่อหน้าต่างเวลา
  windowMs: 60_000, // 1 นาที
};

export interface BrowserPrintThrottleConfig {
  maxRequests: number;
  windowMs: number;
}

/**
 * `CSSD_BROWSER_PRINT_ENABLED` รับได้เฉพาะ 'true' / 'false' / ไม่ตั้ง (=ปิด)
 * ค่าอื่น (เช่น '1', 'yes', 'TRUE') = ตั้งค่าผิด → โยน error ตอนบูตทันที
 */
export function resolveBrowserPrintEnabled(env: NodeJS.ProcessEnv): boolean {
  const raw = env.CSSD_BROWSER_PRINT_ENABLED;
  if (raw === undefined) return false; // unset = ปิด (safe default)
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  throw new Error(
    `CSSD_BROWSER_PRINT_ENABLED must be 'true', 'false' or unset, got "${raw}"`,
  );
}

function parsePositiveInt(raw: string | undefined, name: string): number | undefined {
  if (raw === undefined || raw.trim() === '') return undefined;
  // ต้องเป็นจำนวนเต็มล้วน (กัน "10abc", "1e3", "10.5", ค่าติดลบ)
  if (!/^\d+$/.test(raw.trim())) {
    throw new Error(`${name} must be a positive integer, got "${raw}"`);
  }
  const n = Number(raw.trim());
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error(`${name} must be a positive integer > 0, got "${raw}"`);
  }
  return n;
}

/** rate limit ต่อผู้ใช้ของ mutation endpoints (directive §13: rate limit endpoint ที่อาจถูกกดซ้ำ) */
export function resolveBrowserPrintThrottle(env: NodeJS.ProcessEnv): BrowserPrintThrottleConfig {
  const maxRequests =
    parsePositiveInt(env.BROWSER_PRINT_THROTTLE_MAX, 'BROWSER_PRINT_THROTTLE_MAX') ??
    BROWSER_PRINT_THROTTLE_DEFAULTS.maxRequests;
  const windowMs =
    parsePositiveInt(env.BROWSER_PRINT_THROTTLE_WINDOW_MS, 'BROWSER_PRINT_THROTTLE_WINDOW_MS') ??
    BROWSER_PRINT_THROTTLE_DEFAULTS.windowMs;
  return { maxRequests, windowMs };
}
