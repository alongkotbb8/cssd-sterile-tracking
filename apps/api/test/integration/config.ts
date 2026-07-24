import 'dotenv/config';

// ใช้ DATABASE_URL ของ dev เป็นฐาน แล้วสลับชื่อ DB เป็น test DB แยกต่างหาก
// (ไม่แตะข้อมูล dev/prod เลย) — integration test สร้าง/ลบ DB นี้เองใน global setup
const base = process.env.DATABASE_URL ?? 'postgresql://cssd:cssd_dev_pw@localhost:5432/cssd_db';

const parsed = new URL(base);
export const TEST_DB_NAME = 'cssd_inttest';

const testUrl = new URL(base);
testUrl.pathname = `/${TEST_DB_NAME}`;
export const TEST_DATABASE_URL = testUrl.toString();

export const PG = {
  host: parsed.hostname,
  port: parsed.port || '5432',
  user: decodeURIComponent(parsed.username),
  password: decodeURIComponent(parsed.password),
};
