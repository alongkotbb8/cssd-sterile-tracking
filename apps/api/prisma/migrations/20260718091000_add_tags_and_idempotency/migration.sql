-- Tags
CREATE TABLE "tags" (
    "id" TEXT NOT NULL,
    "name" VARCHAR(50) NOT NULL,
    "colorHex" VARCHAR(9),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "tags_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "tags_name_key" ON "tags"("name");

CREATE TABLE "package_tags" (
    "packageId" TEXT NOT NULL,
    "tagId" TEXT NOT NULL,

    CONSTRAINT "package_tags_pkey" PRIMARY KEY ("packageId","tagId")
);
ALTER TABLE "package_tags" ADD CONSTRAINT "package_tags_packageId_fkey" FOREIGN KEY ("packageId") REFERENCES "packages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "package_tags" ADD CONSTRAINT "package_tags_tagId_fkey" FOREIGN KEY ("tagId") REFERENCES "tags"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Idempotent requests (atomic CAS via unique PK on "key" — see IdempotencyService)
CREATE TYPE "IdempotencyStatus" AS ENUM ('PENDING', 'DONE');

CREATE TABLE "idempotent_requests" (
    "key" VARCHAR(100) NOT NULL,
    "userId" TEXT NOT NULL,
    "endpoint" VARCHAR(60) NOT NULL,
    "method" VARCHAR(10) NOT NULL,
    "requestHash" VARCHAR(64) NOT NULL,
    "status" "IdempotencyStatus" NOT NULL DEFAULT 'PENDING',
    "response" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "idempotent_requests_pkey" PRIMARY KEY ("key")
);
CREATE INDEX "idempotent_requests_createdAt_idx" ON "idempotent_requests"("createdAt");
