-- CreateEnum
CREATE TYPE "BatchAttemptResult" AS ENUM ('PENDING', 'PASSED', 'FAILED', 'RECALLED');

-- AlterEnum
ALTER TYPE "BatchStatus" ADD VALUE 'PENDING_BI';

-- CreateTable
CREATE TABLE "package_batch_attempts" (
    "id" TEXT NOT NULL,
    "packageId" TEXT NOT NULL,
    "batchId" TEXT NOT NULL,
    "result" "BatchAttemptResult" NOT NULL DEFAULT 'PENDING',
    "boundAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "package_batch_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "package_batch_attempts_packageId_idx" ON "package_batch_attempts"("packageId");

-- CreateIndex
CREATE INDEX "package_batch_attempts_batchId_idx" ON "package_batch_attempts"("batchId");

-- AddForeignKey
ALTER TABLE "package_batch_attempts" ADD CONSTRAINT "package_batch_attempts_packageId_fkey" FOREIGN KEY ("packageId") REFERENCES "packages"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "package_batch_attempts" ADD CONSTRAINT "package_batch_attempts_batchId_fkey" FOREIGN KEY ("batchId") REFERENCES "sterilization_batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Backfill: ห่อที่ผูกรอบอยู่ก่อน migration นี้ยังไม่มีประวัติ attempt — สร้างให้ 1 แถว/ห่อ
-- (ตามที่ยืนยัน: การผูกห่อ–รอบต้องมีประวัติถาวร) result อิงสถานะรอบปัจจุบัน:
--   PASSED → PASSED, FAILED → FAILED, PENDING/PENDING_BI → PENDING (resolvedAt = NULL จนกว่าจะตัดสิน)
-- idempotent: NOT EXISTS กันสร้างซ้ำถ้ารันซ้ำ
--
-- ⚠️ ข้อจำกัด (ต้องตรวจก่อน deploy จริง): backfill นี้กู้ได้เฉพาะห่อที่ "ยังมี batchId" อยู่
--    รอบ FAILED จากโค้ดเก่า (ก่อน early-release) ที่ล้าง Package.batchId ทิ้งไปแล้ว จะ
--    สร้างประวัติที่สูญหายกลับมา "อัตโนมัติไม่ได้" — ต้องตรวจข้อมูล production ก่อน migrate
--    และกู้ประวัติจาก AuditLog (action BATCH_RESULT/RECALL_BATCH เก็บ affected/released
--    package ids ไว้) หรือ backup แล้ว INSERT ด้วยมือ ดูขั้นตอนใน OPERATIONAL_READINESS.md
INSERT INTO "package_batch_attempts" ("id", "packageId", "batchId", "result", "boundAt", "resolvedAt")
SELECT
    gen_random_uuid()::text,
    p."id",
    p."batchId",
    CASE b."status"
        WHEN 'PASSED' THEN 'PASSED'::"BatchAttemptResult"
        WHEN 'FAILED' THEN 'FAILED'::"BatchAttemptResult"
        ELSE 'PENDING'::"BatchAttemptResult"
    END,
    COALESCE(b."startedAt", CURRENT_TIMESTAMP),
    CASE WHEN b."status" IN ('PASSED', 'FAILED') THEN COALESCE(b."finishedAt", CURRENT_TIMESTAMP) ELSE NULL END
FROM "packages" p
JOIN "sterilization_batches" b ON b."id" = p."batchId"
WHERE p."batchId" IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM "package_batch_attempts" a
      WHERE a."packageId" = p."id" AND a."batchId" = p."batchId"
  );

