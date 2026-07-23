/** Jest config สำหรับ integration test กับ PostgreSQL จริง (FIX-07)
 *  แยกจาก unit suite (`npm test`) เพื่อไม่บังคับให้ทุกคน/CI ต้องมี Postgres
 *  รันด้วย `npm run test:integration` (ต้องมี local Postgres ตาม DATABASE_URL)
 */
const path = require('path');
const root = path.resolve(__dirname, '../..');

module.exports = {
  rootDir: root,
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['<rootDir>/test/integration/**/*.int-spec.ts'],
  globalSetup: '<rootDir>/test/integration/global-setup.ts',
  globalTeardown: '<rootDir>/test/integration/global-teardown.ts',
  testTimeout: 30000,
  maxWorkers: 1, // ทดสอบ concurrency ภายใน process เดียว (Promise.all) ไม่ใช่ข้าม worker
  moduleNameMapper: {
    '^@cssd/shared$': '<rootDir>/../../packages/shared/src/index.ts',
  },
};
