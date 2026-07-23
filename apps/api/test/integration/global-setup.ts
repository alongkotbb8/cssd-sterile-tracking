import { execSync } from 'child_process';
import { PG, TEST_DATABASE_URL, TEST_DB_NAME } from './config';

/** สร้าง test DB ใหม่สดๆ + apply migration ทั้งหมด (พิสูจน์ migration บน DB จริงด้วย) */
export default async function globalSetup(): Promise<void> {
  const env = { ...process.env, PGPASSWORD: PG.password };
  const conn = `-h ${PG.host} -p ${PG.port} -U ${PG.user}`;
  execSync(`dropdb --if-exists ${conn} ${TEST_DB_NAME}`, { env, stdio: 'ignore' });
  execSync(`createdb ${conn} ${TEST_DB_NAME}`, { env, stdio: 'inherit' });
  execSync('npx prisma migrate deploy', {
    env: { ...process.env, DATABASE_URL: TEST_DATABASE_URL },
    stdio: 'inherit',
  });
  // eslint-disable-next-line no-console
  console.log(`[int] test DB ${TEST_DB_NAME} ready`);
}
