-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "PrintJobStatus" ADD VALUE 'RESOLVED_PRINTED';
ALTER TYPE "PrintJobStatus" ADD VALUE 'RESOLVED_REQUEUED';

-- AlterTable
ALTER TABLE "print_jobs" ADD COLUMN     "requeuedFromJobId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "print_jobs_requeuedFromJobId_key" ON "print_jobs"("requeuedFromJobId");

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_requeuedFromJobId_fkey" FOREIGN KEY ("requeuedFromJobId") REFERENCES "print_jobs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

