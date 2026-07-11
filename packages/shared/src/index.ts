// @cssd/shared — constants and types shared between API and any future web dashboard

export const SHELF_LIFE_DAYS = {
  SEAL: 180,
  CLOTH: 7,
} as const;

export type WrapType = keyof typeof SHELF_LIFE_DAYS;

export const PACKAGE_STATUSES = ['PACKED', 'STERILE', 'ISSUED', 'RETURNED', 'DISCARDED'] as const;
export type PackageStatus = typeof PACKAGE_STATUSES[number];

export const MOVEMENT_TYPES = ['IN', 'OUT', 'RETURN'] as const;
export type MovementType = typeof MOVEMENT_TYPES[number];

export const USER_ROLES = ['CSSD', 'SUPERVISOR', 'ADMIN'] as const;
export type UserRole = typeof USER_ROLES[number];

/** Compute expiry date server-side — never on device. UTC-based so the result
 *  does not depend on the server's local timezone. */
export function calcExpiryDate(sterilizeDate: Date, wrapType: WrapType): Date {
  const d = new Date(sterilizeDate);
  d.setUTCDate(d.getUTCDate() + SHELF_LIFE_DAYS[wrapType]);
  return d;
}

/** Running number format: {CODE}-{YYYYMMDD}-{SEQ4} */
export function formatPackageId(code: string, date: Date, seq: number): string {
  const yyyymmdd = date.toISOString().slice(0, 10).replace(/-/g, '');
  return `${code}-${yyyymmdd}-${String(seq).padStart(4, '0')}`;
}

/** Validate that a status transition is allowed */
const ALLOWED_TRANSITIONS: Record<PackageStatus, PackageStatus[]> = {
  PACKED:     ['STERILE', 'DISCARDED'],
  STERILE:    ['ISSUED', 'DISCARDED'],
  ISSUED:     ['RETURNED', 'DISCARDED'],
  RETURNED:   ['PACKED', 'DISCARDED'], // PACKED = reprocess loop (CLAUDE.md state machine)
  DISCARDED:  [],
};

export function isValidTransition(from: PackageStatus, to: PackageStatus): boolean {
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}
