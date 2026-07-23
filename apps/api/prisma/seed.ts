import { PrismaClient, UserRole, WrapType } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  // Departments
  const departments = await Promise.all([
    prisma.department.upsert({
      where: { code: 'DENT' },
      update: {},
      create: { code: 'DENT', name: 'ห้องทันตกรรม', type: 'clinic' },
    }),
    prisma.department.upsert({
      where: { code: 'ER' },
      update: {},
      create: { code: 'ER', name: 'ห้องฉุกเฉิน', type: 'er' },
    }),
    prisma.department.upsert({
      where: { code: 'OB' },
      update: {},
      create: { code: 'OB', name: 'ห้องคลอด', type: 'ward' },
    }),
    prisma.department.upsert({
      where: { code: 'WOUND' },
      update: {},
      create: { code: 'WOUND', name: 'ห้องทำแผล', type: 'clinic' },
    }),
    // สถานที่ภายนอก (type: 'external') — ปลายทางของการส่งชุด PACKED ออกนอกโรงพยาบาล
    prisma.department.upsert({
      where: { code: 'EXT-PYT' },
      update: {},
      create: { code: 'EXT-PYT', name: 'รพ.พญาไท', type: 'external' },
    }),
  ]);
  console.log(`✅ Departments: ${departments.length}`);

  // Set templates
  const templates = await Promise.all([
    prisma.setTemplate.upsert({
      where: { code: 'DELIV' },
      update: {},
      create: {
        code: 'DELIV',
        name: 'ชุดถอนฟัน',
        itemList: ['คีมถอนฟัน', 'หัวกรอฟัน', 'กระจกส่องปาก', 'ที่ขูดหินปูน'],
        defaultWrapType: WrapType.SEAL,
      },
    }),
    prisma.setTemplate.upsert({
      where: { code: 'BIRTH' },
      update: {},
      create: {
        code: 'BIRTH',
        name: 'ชุดทำคลอด',
        itemList: ['กรรไกรตัดสาย', 'ที่หนีบสาย', 'ถาดรองเลือด', 'ผ้าก๊อซ'],
        defaultWrapType: WrapType.SEAL,
      },
    }),
    prisma.setTemplate.upsert({
      where: { code: 'DRESS' },
      update: {},
      create: {
        code: 'DRESS',
        name: 'ชุดทำแผล',
        itemList: ['ปากคีบ', 'กรรไกรตัดไหม', 'ถาดสเตนเลส', 'ผ้าก๊อซ'],
        defaultWrapType: WrapType.CLOTH,
      },
    }),
  ]);
  console.log(`✅ Set templates: ${templates.length}`);

  // Sterilizers
  const sterilizers = await Promise.all([
    prisma.sterilizer.upsert({
      where: { code: 'AUTO-1' },
      update: {},
      create: { code: 'AUTO-1', name: 'เครื่องนึ่งไอน้ำ #1 (Autoclave)' },
    }),
    prisma.sterilizer.upsert({
      where: { code: 'PLASMA-1' },
      update: {},
      create: { code: 'PLASMA-1', name: 'เครื่องนึ่ง Plasma #1' },
    }),
  ]);
  console.log(`✅ Sterilizers: ${sterilizers.length}`);

  // Users — production ต้องตั้งรหัสผ่านผ่าน env (SEED_ADMIN_PASSWORD ฯลฯ)
  // ค่า fallback ใช้ได้เฉพาะ dev; ใน production ถ้าไม่ตั้ง env จะ throw ทันที
  const isProd = process.env.NODE_ENV === 'production';
  const seedPassword = (envKey: string, devFallback: string): string => {
    const fromEnv = process.env[envKey];
    if (fromEnv && fromEnv.length >= 8) return fromEnv;
    if (isProd) {
      throw new Error(
        `Production seed requires ${envKey} (>=8 chars) — refusing to seed default password`,
      );
    }
    return devFallback;
  };

  const hash = (pw: string) => bcrypt.hash(pw, 10);
  const users = await Promise.all([
    prisma.user.upsert({
      where: { employeeCode: 'ADMIN001' },
      update: {},
      create: {
        employeeCode: 'ADMIN001',
        name: 'ผู้ดูแลระบบ',
        email: 'admin@cssd.local',
        passwordHash: await hash(seedPassword('SEED_ADMIN_PASSWORD', 'Admin@1234')),
        role: UserRole.ADMIN,
      },
    }),
    prisma.user.upsert({
      where: { employeeCode: 'SUP001' },
      update: {},
      create: {
        employeeCode: 'SUP001',
        name: 'หัวหน้าหน่วย CSSD',
        email: 'supervisor@cssd.local',
        passwordHash: await hash(seedPassword('SEED_SUPERVISOR_PASSWORD', 'Sup@1234')),
        role: UserRole.SUPERVISOR,
      },
    }),
    prisma.user.upsert({
      where: { employeeCode: 'STAFF001' },
      update: {},
      create: {
        employeeCode: 'STAFF001',
        name: 'เจ้าหน้าที่ CSSD 1',
        email: 'staff1@cssd.local',
        passwordHash: await hash(seedPassword('SEED_STAFF_PASSWORD', 'Staff@1234')),
        role: UserRole.CSSD,
      },
    }),
  ]);
  console.log(`✅ Users: ${users.length}`);
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
