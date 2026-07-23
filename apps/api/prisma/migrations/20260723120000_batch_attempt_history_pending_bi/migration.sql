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

