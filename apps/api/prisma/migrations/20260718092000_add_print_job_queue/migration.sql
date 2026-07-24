-- Print Job Queue + Gateway (AI_DEVELOPMENT_GUARDRAILS.md ข้อ 5)
CREATE TYPE "PrintJobStatus" AS ENUM (
  'QUEUED', 'CLAIMED', 'PRINTING', 'PRINTED', 'FAILED', 'RETRYING', 'DEAD_LETTER', 'CANCELLED'
);

CREATE TABLE "printer_devices" (
    "id" TEXT NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "keyId" VARCHAR(24) NOT NULL,
    "apiKeyHash" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "lastHeartbeatAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "printer_devices_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "printer_devices_keyId_key" ON "printer_devices"("keyId");

CREATE TABLE "print_jobs" (
    "id" TEXT NOT NULL,
    "packageId" TEXT NOT NULL,
    "printerId" TEXT,
    "requestedById" TEXT NOT NULL,
    "status" "PrintJobStatus" NOT NULL DEFAULT 'QUEUED',
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "isReprint" BOOLEAN NOT NULL DEFAULT false,
    "reprintReason" VARCHAR(200),
    "payload" JSONB NOT NULL,
    "payloadHash" VARCHAR(64) NOT NULL,
    "errorCode" VARCHAR(100),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMP(3),
    "printingAt" TIMESTAMP(3),
    "printedAt" TIMESTAMP(3),
    "failedAt" TIMESTAMP(3),

    CONSTRAINT "print_jobs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "print_jobs_status_idx" ON "print_jobs"("status");
CREATE INDEX "print_jobs_packageId_idx" ON "print_jobs"("packageId");
CREATE INDEX "print_jobs_printerId_idx" ON "print_jobs"("printerId");

ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_packageId_fkey" FOREIGN KEY ("packageId") REFERENCES "packages"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "printer_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_requestedById_fkey" FOREIGN KEY ("requestedById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
