#!/usr/bin/env bash
# ย้ายฐานข้อมูล PostgreSQL จาก DB เดิม (Render) → Railway Postgres
# ใช้: OLD='postgresql://...' NEW='postgresql://...' bash scripts/migrate-db-to-railway.sh
#
# ทำ pg_dump เต็ม (schema + data + ประวัติ _prisma_migrations) แล้ว restore เข้า NEW
# หลัง restore เสร็จ prisma migrate deploy ในการ deploy ถัดไปจะเป็น no-op
set -euo pipefail

OLD="${OLD:-}"
NEW="${NEW:-}"
if [[ -z "$OLD" || -z "$NEW" ]]; then
  echo "ERROR: ต้องกำหนดทั้ง OLD และ NEW" >&2
  echo "  OLD='postgresql://user:pw@old-host/db' NEW='postgresql://user:pw@new-host/db' bash $0" >&2
  exit 1
fi

command -v pg_dump  >/dev/null || { echo "ERROR: ไม่มี pg_dump (ติดตั้ง postgresql client ก่อน)" >&2; exit 1; }
command -v pg_restore >/dev/null || { echo "ERROR: ไม่มี pg_restore" >&2; exit 1; }

DUMP="$(mktemp -t cssd-dump.XXXXXX).dump"
trap 'rm -f "$DUMP"' EXIT

echo "==> pg_dump จาก DB เดิม ..."
pg_dump "$OLD" --no-owner --no-privileges --format=custom --file="$DUMP"
echo "    dump ขนาด: $(du -h "$DUMP" | cut -f1)"

echo "==> pg_restore เข้า Railway (clean ของเดิมถ้ามี) ..."
# --clean --if-exists กันกรณี NEW มี schema อยู่แล้ว (เช่น deploy รัน migrate ไปก่อน)
pg_restore --no-owner --no-privileges --clean --if-exists --no-comments \
  --dbname="$NEW" "$DUMP"

echo "==> ตรวจนับตารางหลัก ..."
# ชื่อตารางจริงเป็น snake_case (Prisma @@map) — ไม่ใช่ชื่อ model
psql "$NEW" -c 'SELECT
  (SELECT count(*) FROM users)        AS users,
  (SELECT count(*) FROM packages)     AS packages,
  (SELECT count(*) FROM movements)    AS movements,
  (SELECT count(*) FROM _prisma_migrations) AS migrations;' || \
  echo "(ข้ามการนับ — ตรวจเองภายหลังได้)"

echo "✅ ย้ายข้อมูลเสร็จ"
