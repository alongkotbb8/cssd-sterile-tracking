import { AuditService } from '../../../common/audit/audit.service';
import { ReportsService } from '../reports.service';

/**
 * dashboard(): recentMovements — latest 8 (any type) mapped ตาม contract
 * (packageId, setName, type, departmentName, receiverName, at ISO, packageStatus)
 * fake prisma คืนค่าคงที่พอสำหรับ groupBy/count และ movement.findMany (recent)
 */
function makeDb(recent: any[]) {
  return {
    package: {
      groupBy: async () => [],
      count: async () => 0,
    },
    movement: {
      groupBy: async () => [],
      findMany: async (args: any) => {
        // ต้องเป็น query ล่าสุด: orderBy createdAt desc, take 8, include package{setTemplate}+department
        expect(args.orderBy).toEqual({ createdAt: 'desc' });
        expect(args.take).toBe(8);
        expect(args.include.package.include.setTemplate).toBe(true);
        expect(args.include.department).toBe(true);
        return recent;
      },
    },
    setTemplate: { findMany: async () => [] },
    department: { findMany: async () => [] },
  };
}

const svc = (db: any) => new ReportsService(db as any, new AuditService(db as any));

describe('ReportsService.dashboard recentMovements', () => {
  it('map fields ตาม contract + at เป็น ISO string', async () => {
    const at = new Date('2026-07-23T04:05:06.000Z');
    const db = makeDb([
      {
        packageId: 'DELIV-20260101-0001',
        type: 'OUT',
        receiverName: 'พยาบาลเอ',
        createdAt: at,
        package: { status: 'ISSUED', setTemplate: { name: 'ชุดทำแผล' } },
        department: { name: 'ห้องผ่าตัด' },
      },
    ]);
    const res = await svc(db).dashboard();
    expect(res.recentMovements).toEqual([
      {
        packageId: 'DELIV-20260101-0001',
        setName: 'ชุดทำแผล',
        type: 'OUT',
        departmentName: 'ห้องผ่าตัด',
        receiverName: 'พยาบาลเอ',
        at: '2026-07-23T04:05:06.000Z',
        packageStatus: 'ISSUED',
      },
    ]);
  });

  it('department/receiver null (เช่น movement IN) → departmentName/receiverName เป็น null', async () => {
    const db = makeDb([
      {
        packageId: 'DELIV-20260101-0002',
        type: 'IN',
        receiverName: null,
        createdAt: new Date('2026-07-23T01:00:00.000Z'),
        package: { status: 'STERILE', setTemplate: { name: 'ชุดทำคลอด' } },
        department: null,
      },
    ]);
    const res = await svc(db).dashboard();
    expect(res.recentMovements[0]).toMatchObject({
      type: 'IN',
      departmentName: null,
      receiverName: null,
      packageStatus: 'STERILE',
    });
  });

  it('ไม่มี movement → recentMovements = []', async () => {
    const res = await svc(makeDb([])).dashboard();
    expect(res.recentMovements).toEqual([]);
  });
});
