import { execSync } from 'child_process';
import { PG, TEST_DB_NAME } from './config';

export default async function globalTeardown(): Promise<void> {
  const env = { ...process.env, PGPASSWORD: PG.password };
  const conn = `-h ${PG.host} -p ${PG.port} -U ${PG.user}`;
  // ปิด connection ค้างก่อนลบ (เผื่อ pool ยังไม่ปล่อย)
  execSync(`dropdb --if-exists --force ${conn} ${TEST_DB_NAME}`, { env, stdio: 'ignore' });
}
