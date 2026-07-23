-- Session revocation: tokenVersion ฝังใน JWT (ver) — เพิ่มค่านี้เพื่อเพิกถอน token เก่าทั้งหมด
-- backfill-safe: DEFAULT 0 (token ที่ออกหลัง migration จะฝัง ver=0 ตรงกับค่าเริ่มต้น)
ALTER TABLE "users" ADD COLUMN "tokenVersion" INTEGER NOT NULL DEFAULT 0;
