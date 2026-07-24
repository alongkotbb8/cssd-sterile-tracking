-- Browser Print mode (MACOS_BROWSER_PRINT_DIRECTIVE.md §5)
-- ตารางประวัติการพิมพ์ผ่าน browser/macOS system print dialog — แยก semantics จาก
-- print_jobs (Gateway) เด็ดขาด: สถานะมีได้เฉพาะ CREATED/DIALOG_OPENED/USER_CONFIRMED/
-- CANCELLED (ห้าม PRINTED/SENT/ACK_UNKNOWN) และไม่มี path ใดแตะ packages.printedAt
--
-- Migration นี้ additive ล้วน (ตารางใหม่ + enum ใหม่ ไม่แตะข้อมูล/ตารางเดิม)
-- จึงปลอดภัยทั้งฐานข้อมูลใหม่และฐานที่มีข้อมูลเดิม. Reversible (down):
--   DROP TABLE "browser_print_requests";
--   DROP TYPE "BrowserPrintStatus"; DROP TYPE "BrowserPrintMode"; DROP TYPE "BrowserPrintOrigin";

-- CreateEnum
CREATE TYPE "BrowserPrintStatus" AS ENUM ('CREATED', 'DIALOG_OPENED', 'USER_CONFIRMED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "BrowserPrintMode" AS ENUM ('BROWSER_DIALOG');

-- CreateEnum
CREATE TYPE "BrowserPrintOrigin" AS ENUM ('CREATE_PACKAGE', 'PACKAGE_DETAIL', 'PRINT_JOBS');

-- CreateTable
CREATE TABLE "browser_print_requests" (
    "id" TEXT NOT NULL,
    "packageId" TEXT NOT NULL,
    "requestedByUserId" TEXT NOT NULL,
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "mode" "BrowserPrintMode" NOT NULL DEFAULT 'BROWSER_DIALOG',
    "templateVersion" VARCHAR(30) NOT NULL,
    "copies" INTEGER NOT NULL,
    "isReprint" BOOLEAN NOT NULL DEFAULT false,
    "reprintReason" VARCHAR(200),
    "status" "BrowserPrintStatus" NOT NULL DEFAULT 'CREATED',
    "dialogOpenedAt" TIMESTAMP(3),
    "userConfirmedAt" TIMESTAMP(3),
    "cancelledAt" TIMESTAMP(3),
    "createdFrom" "BrowserPrintOrigin" NOT NULL,
    "userAgent" VARCHAR(300),
    "idempotencyKey" VARCHAR(100) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "browser_print_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "browser_print_requests_packageId_createdAt_idx" ON "browser_print_requests"("packageId", "createdAt");

-- CreateIndex
CREATE INDEX "browser_print_requests_requestedByUserId_idx" ON "browser_print_requests"("requestedByUserId");

-- CreateIndex
CREATE INDEX "browser_print_requests_status_idx" ON "browser_print_requests"("status");

-- AddForeignKey
ALTER TABLE "browser_print_requests" ADD CONSTRAINT "browser_print_requests_packageId_fkey" FOREIGN KEY ("packageId") REFERENCES "packages"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "browser_print_requests" ADD CONSTRAINT "browser_print_requests_requestedByUserId_fkey" FOREIGN KEY ("requestedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
