const DAY_MS = 86_400_000;

/**
 * นิยามวันหมดอายุ (ตกลงชัดเจนตามผล audit):
 * `expiryDate` (คอลัมน์ DATE, เที่ยงคืน UTC) = **วันสุดท้ายที่ยังใช้ได้**
 * ห่อใช้ได้ตลอดวันหมดอายุ และถูกบล็อกตั้งแต่ 00:00 UTC ของวันถัดไป
 *
 * ก่อนหน้านี้โค้ดเทียบ `expiryDate < now` ตรงๆ ซึ่งบล็อกตั้งแต่เที่ยงคืน
 * ของวันหมดอายุเอง (เสียวันใช้งานไป 1 วัน) — helper นี้คือจุดเดียวของความจริง
 * ห้ามเทียบวันหมดอายุเองที่อื่น
 */
export function isExpired(expiryDate: Date, now: Date = new Date()): boolean {
  return now.getTime() >= expiryDate.getTime() + DAY_MS;
}

/** จำนวนวันที่เหลือใช้ (0 = วันนี้เป็นวันสุดท้าย, ติดลบ = หมดอายุแล้ว) */
export function daysLeft(expiryDate: Date, now: Date = new Date()): number {
  return Math.floor((expiryDate.getTime() + DAY_MS - now.getTime()) / DAY_MS);
}

/** เที่ยงคืน UTC ของวันนี้ — ใช้สร้าง where clause ฝั่ง SQL ให้ตรงกับ isExpired() */
export function startOfTodayUtc(now: Date = new Date()): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}
