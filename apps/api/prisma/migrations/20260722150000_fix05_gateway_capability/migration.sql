-- CreateEnum
CREATE TYPE "GatewayEnvironment" AS ENUM ('DEVELOPMENT', 'TEST', 'PRODUCTION');

-- CreateEnum
CREATE TYPE "GatewayTransportMode" AS ENUM ('CONSOLE', 'SERIAL', 'BLUETOOTH');

-- AlterTable
ALTER TABLE "printer_devices" ADD COLUMN     "canConfirmRealPrint" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "environment" "GatewayEnvironment" NOT NULL DEFAULT 'DEVELOPMENT',
ADD COLUMN     "transportMode" "GatewayTransportMode" NOT NULL DEFAULT 'CONSOLE';

