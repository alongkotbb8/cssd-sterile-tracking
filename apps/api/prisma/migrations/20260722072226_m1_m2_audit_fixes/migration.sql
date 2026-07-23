-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.
ALTER TYPE "PrintJobStatus" ADD VALUE 'SENT';
ALTER TYPE "PrintJobStatus" ADD VALUE 'SIMULATED';
ALTER TYPE "PrintJobStatus" ADD VALUE 'ACK_UNKNOWN';

-- AlterTable
ALTER TABLE "print_jobs" ADD COLUMN     "requestedPrinterId" TEXT,
ADD COLUMN     "resolutionNote" VARCHAR(300),
ADD COLUMN     "resolvedAt" TIMESTAMP(3),
ADD COLUMN     "resolvedById" TEXT,
ADD COLUMN     "sentAt" TIMESTAMP(3);

-- AlterTable: idempotent_requests."expiresAt" (FIX-01)
-- ต้องทำเป็น 3 ขั้นแบบ backfill-friendly — ห้ามเพิ่มคอลัมน์ NOT NULL ตรงๆ เพราะจะ
-- ล้มเหลวทันทีถ้าตารางมีข้อมูลเดิม (idempotent_requests อาจมีแถว PENDING/DONE
-- ค้างอยู่แล้วในระบบที่รันมาก่อน migration นี้)
-- ขั้น 1: เพิ่มเป็น nullable ก่อน
ALTER TABLE "idempotent_requests" ADD COLUMN "expiresAt" TIMESTAMP(3);

-- ขั้น 2: backfill แถวเดิมด้วยกติกาเดียวกับโค้ด (DONE = createdAt + 24 ชม.,
-- อื่นๆ/PENDING = createdAt + 5 นาที) แถวเก่าจึงถูกจัดเข้าเกณฑ์ cleanup ได้ทันที
UPDATE "idempotent_requests"
SET "expiresAt" = CASE
  WHEN "status" = 'DONE' THEN "createdAt" + INTERVAL '24 hours'
  ELSE "createdAt" + INTERVAL '5 minutes'
END
WHERE "expiresAt" IS NULL;

-- ขั้น 3: บังคับ NOT NULL หลัง backfill ครบแล้ว
ALTER TABLE "idempotent_requests" ALTER COLUMN "expiresAt" SET NOT NULL;

-- CreateIndex
CREATE INDEX "idempotent_requests_status_expiresAt_idx" ON "idempotent_requests"("status", "expiresAt");

-- CreateIndex
CREATE INDEX "print_jobs_requestedPrinterId_idx" ON "print_jobs"("requestedPrinterId");

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_requestedPrinterId_fkey" FOREIGN KEY ("requestedPrinterId") REFERENCES "printer_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_resolvedById_fkey" FOREIGN KEY ("resolvedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
