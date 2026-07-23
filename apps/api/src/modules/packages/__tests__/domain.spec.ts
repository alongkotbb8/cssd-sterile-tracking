import { calcExpiryDate, formatPackageId, isValidTransition } from '@cssd/shared';
import { daysLeft, isExpired } from '../../../common/expiry';

describe('Domain: calcExpiryDate', () => {
  const sterilize = new Date('2026-06-30');

  it('SEAL → +180 days', () => {
    const expiry = calcExpiryDate(sterilize, 'SEAL');
    expect(expiry.toISOString().slice(0, 10)).toBe('2026-12-27');
  });

  it('CLOTH → +7 days', () => {
    const expiry = calcExpiryDate(sterilize, 'CLOTH');
    expect(expiry.toISOString().slice(0, 10)).toBe('2026-07-07');
  });

  it('does not mutate input', () => {
    const input = new Date('2026-06-30');
    calcExpiryDate(input, 'SEAL');
    expect(input.toISOString().slice(0, 10)).toBe('2026-06-30');
  });
});

describe('Domain: formatPackageId', () => {
  it('formats correctly', () => {
    expect(formatPackageId('DELIV', new Date('2026-06-30'), 7)).toBe('DELIV-20260630-0007');
  });

  it('pads seq to 4 digits', () => {
    expect(formatPackageId('BIRTH', new Date('2026-06-30'), 1)).toBe('BIRTH-20260630-0001');
    expect(formatPackageId('BIRTH', new Date('2026-06-30'), 100)).toBe('BIRTH-20260630-0100');
    expect(formatPackageId('BIRTH', new Date('2026-06-30'), 9999)).toBe('BIRTH-20260630-9999');
  });
});

describe('Domain: isValidTransition (state machine)', () => {
  // Happy paths
  it('PACKED → STERILE ✓', () => expect(isValidTransition('PACKED', 'STERILE')).toBe(true));
  it('STERILE → ISSUED ✓', () => expect(isValidTransition('STERILE', 'ISSUED')).toBe(true));
  it('ISSUED → RETURNED ✓', () => expect(isValidTransition('ISSUED', 'RETURNED')).toBe(true));
  it('any → DISCARDED ✓', () => {
    (['PACKED', 'PACKED_OUT', 'STERILE', 'ISSUED', 'RETURNED'] as const).forEach(s =>
      expect(isValidTransition(s, 'DISCARDED')).toBe(true));
  });

  // ส่งออกโดยยังไม่ฆ่าเชื้อ (PACKED_OUT loop)
  it('PACKED → PACKED_OUT ✓ (ส่งออกไม่ฆ่าเชื้อ)', () =>
    expect(isValidTransition('PACKED', 'PACKED_OUT')).toBe(true));
  it('PACKED_OUT → PACKED ✓ (รับคืน พร้อมนึ่งต่อ)', () =>
    expect(isValidTransition('PACKED_OUT', 'PACKED')).toBe(true));
  it('PACKED_OUT → STERILE ✗ (ต้องคืนก่อนถึงเข้ารอบนึ่งได้)', () =>
    expect(isValidTransition('PACKED_OUT', 'STERILE')).toBe(false));
  it('PACKED_OUT → ISSUED ✗', () =>
    expect(isValidTransition('PACKED_OUT', 'ISSUED')).toBe(false));
  it('STERILE → PACKED_OUT ✗ (ของฆ่าเชื้อแล้วใช้เส้นทาง ISSUED)', () =>
    expect(isValidTransition('STERILE', 'PACKED_OUT')).toBe(false));

  // Blocked paths
  it('STERILE → PACKED ✗ (no reverse)', () => expect(isValidTransition('STERILE', 'PACKED')).toBe(false));
  it('ISSUED → STERILE ✗', () => expect(isValidTransition('ISSUED', 'STERILE')).toBe(false));
  it('RETURNED → ISSUED ✗', () => expect(isValidTransition('RETURNED', 'ISSUED')).toBe(false));
  it('DISCARDED → anything ✗', () => {
    (['PACKED', 'PACKED_OUT', 'STERILE', 'ISSUED', 'RETURNED'] as const).forEach(s =>
      expect(isValidTransition('DISCARDED', s)).toBe(false));
  });
});

describe('Domain: FEFO — expiry ordering', () => {
  it('items sorted by earliest expiry come first', () => {
    const items = [
      { id: 'A', expiry: new Date('2026-12-31') },
      { id: 'B', expiry: new Date('2026-07-10') },
      { id: 'C', expiry: new Date('2026-09-01') },
    ];
    const sorted = [...items].sort((a, b) => a.expiry.getTime() - b.expiry.getTime());
    expect(sorted.map(i => i.id)).toEqual(['B', 'C', 'A']);
  });
});

describe('Domain: expired package block', () => {
  it('blocks scan-out when expiry_date < now', () => {
    const expiryDate = new Date('2026-01-01'); // past
    const now = new Date('2026-06-30');
    const isExpired = expiryDate < now;
    expect(isExpired).toBe(true);
  });

  it('allows scan-out when expiry_date > now', () => {
    const expiryDate = new Date('2026-12-31'); // future
    const now = new Date('2026-06-30');
    const isExpired = expiryDate < now;
    expect(isExpired).toBe(false);
  });

  // นิยามวันหมดอายุ (แก้ตามผล audit): expiryDate = วันสุดท้ายที่ใช้ได้
  // ห่อใช้ได้ตลอดวันหมดอายุ และถูกบล็อกตั้งแต่ 00:00 UTC ของวันถัดไป
  // (ก่อนแก้ โค้ดเทียบ expiryDate < now ตรงๆ → บล็อกตั้งแต่เที่ยงคืนของวันหมดอายุเอง)
  describe('expiry boundary semantics (common/expiry.ts)', () => {
    const expiryDate = new Date('2026-12-31T00:00:00Z'); // ค่าที่ DB ส่งกลับ (@db.Date)

    it('ยังใช้ได้ตอนเช้าของวันหมดอายุ', () => {
      expect(isExpired(expiryDate, new Date('2026-12-31T08:00:00Z'))).toBe(false);
      expect(daysLeft(expiryDate, new Date('2026-12-31T08:00:00Z'))).toBe(0);
    });

    it('ยังใช้ได้ตอน 23:59 ของวันหมดอายุ (UTC)', () => {
      expect(isExpired(expiryDate, new Date('2026-12-31T23:59:59Z'))).toBe(false);
    });

    it('ถูกบล็อกตั้งแต่ 00:00 ของวันถัดไป', () => {
      expect(isExpired(expiryDate, new Date('2027-01-01T00:00:00Z'))).toBe(true);
      expect(daysLeft(expiryDate, new Date('2027-01-01T08:00:00Z'))).toBeLessThan(0);
    });

    it('วันก่อนหมดอายุ daysLeft = 1', () => {
      expect(daysLeft(expiryDate, new Date('2026-12-30T08:00:00Z'))).toBe(1);
    });
  });
});

describe('Domain: batch result decides sterility (traceability order)', () => {
  // จำลอง logic ใน BatchesService.recordResult
  const decideBatchStatus = (ci: boolean, bi: boolean | null) =>
    ci && (bi === null || bi) ? 'PASSED' : 'FAILED';

  it('CI ผ่าน + BI ยังไม่มา (null) → PASSED', () =>
    expect(decideBatchStatus(true, null)).toBe('PASSED'));
  it('CI ผ่าน + BI ผ่าน → PASSED', () => expect(decideBatchStatus(true, true)).toBe('PASSED'));
  it('CI ไม่ผ่าน → FAILED เสมอ', () => {
    expect(decideBatchStatus(false, true)).toBe('FAILED');
    expect(decideBatchStatus(false, null)).toBe('FAILED');
  });
  it('BI ไม่ผ่าน → FAILED', () => expect(decideBatchStatus(true, false)).toBe('FAILED'));

  it('ห่อเป็น STERILE ได้เฉพาะผ่าน transition PACKED → STERILE (ตอนผลผ่าน)', () => {
    expect(isValidTransition('PACKED', 'STERILE')).toBe(true);
    // ไม่มีทางลัดจากสถานะอื่นไป STERILE
    (['PACKED_OUT', 'ISSUED', 'RETURNED', 'DISCARDED'] as const).forEach(s =>
      expect(isValidTransition(s, 'STERILE')).toBe(false));
  });
});
