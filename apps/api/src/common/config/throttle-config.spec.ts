import {
  resolveThrottleConfig,
  THROTTLE_DEFAULTS,
  PROD_MAX_ATTEMPTS_CEILING,
  PROD_WINDOW_MS_CEILING,
  ABS_MAX_ATTEMPTS,
} from './throttle-config';

// directive A2.4–A2.7 — validate LOGIN_THROTTLE_* env
describe('resolveThrottleConfig', () => {
  it('ไม่ตั้งค่า → ใช้ default production', () => {
    expect(resolveThrottleConfig({}, 'production')).toEqual(THROTTLE_DEFAULTS);
  });

  it('ค่าจำนวนเต็มบวกปกติ → ใช้ตามที่ตั้ง', () => {
    const c = resolveThrottleConfig(
      { LOGIN_THROTTLE_MAX: '20', LOGIN_THROTTLE_WINDOW_MS: '30000' },
      'production',
    );
    expect(c).toEqual({ maxAttempts: 20, windowMs: 30000 });
  });

  it.each(['0', '-1', '10.5', '1e3', 'abc', '10abc', '0x10'])(
    'ค่าไม่ใช่จำนวนเต็มบวก (%s) → โยน error (ไม่เงียบ ๆ fallback)',
    (bad) => {
      expect(() =>
        resolveThrottleConfig({ LOGIN_THROTTLE_MAX: bad }, 'production'),
      ).toThrow(/LOGIN_THROTTLE_MAX/);
    },
  );

  it.each(['', '   '])('ค่าว่าง/ช่องว่าง (%s) → ถือว่าไม่ได้ตั้ง ใช้ default', (v) => {
    expect(
      resolveThrottleConfig({ LOGIN_THROTTLE_MAX: v }, 'production').maxAttempts,
    ).toBe(THROTTLE_DEFAULTS.maxAttempts);
  });

  it('boundary: ค่าที่เพดาน production พอดี → ผ่าน', () => {
    expect(
      resolveThrottleConfig(
        { LOGIN_THROTTLE_MAX: String(PROD_MAX_ATTEMPTS_CEILING) },
        'production',
      ).maxAttempts,
    ).toBe(PROD_MAX_ATTEMPTS_CEILING);
  });

  it('production: เกินเพดาน max → โยน (throttle อ่อนเกินไป = fail fast)', () => {
    expect(() =>
      resolveThrottleConfig(
        { LOGIN_THROTTLE_MAX: String(PROD_MAX_ATTEMPTS_CEILING + 1) },
        'production',
      ),
    ).toThrow(/production ceiling/);
  });

  it('production: เกินเพดาน window → โยน', () => {
    expect(() =>
      resolveThrottleConfig(
        { LOGIN_THROTTLE_WINDOW_MS: String(PROD_WINDOW_MS_CEILING + 1) },
        'production',
      ),
    ).toThrow(/production ceiling/);
  });

  it.each(['test', 'e2e', 'ci', 'CI', 'E2E'])(
    'env ทดสอบ (%s): ยอมค่าเกินเพดาน production ได้ (เช่นปิด throttle ตอน E2E)',
    (envName) => {
      const c = resolveThrottleConfig(
        { LOGIN_THROTTLE_MAX: '1000' },
        envName,
      );
      expect(c.maxAttempts).toBe(1000);
    },
  );

  it('แม้ env ทดสอบ ก็ยังห้ามเกินขอบเขตสัมบูรณ์', () => {
    expect(() =>
      resolveThrottleConfig(
        { LOGIN_THROTTLE_MAX: String(ABS_MAX_ATTEMPTS + 1) },
        'test',
      ),
    ).toThrow(/absolute limit/);
  });

  it('production ที่ค่า override สูงเกิน = ปฏิเสธ (กันเผลอปิด throttle บน prod)', () => {
    expect(() =>
      resolveThrottleConfig({ LOGIN_THROTTLE_MAX: '1000' }, 'production'),
    ).toThrow(/production ceiling/);
  });
});
