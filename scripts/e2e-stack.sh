#!/usr/bin/env bash
# ยก stack สำหรับรัน E2E ในเครื่อง: Postgres (docker compose) + API (Node) + PWA web (static)
#   bash scripts/e2e-stack.sh up     # ยก stack + build/serve web แล้วพร้อมรัน Playwright
#   bash scripts/e2e-stack.sh down   # หยุดทุกอย่าง + ลบ db container
#
# หลัง up: cd e2e && E2E_BASE_URL=http://localhost:8080 npm test
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

API_URL="http://localhost:3000"
WEB_PORT="${WEB_PORT:-8080}"
PID_FILE="$ROOT/.e2e-stack.pids"
export DATABASE_URL="${DATABASE_URL:-postgresql://cssd:cssd_dev_pw@localhost:5432/cssd_db?schema=public}"
export JWT_SECRET="${JWT_SECRET:-e2e-local-secret-not-for-prod}"
# NODE_ENV=e2e = non-production → seed ใช้รหัส default (ADMIN001/Admin@1234 ฯลฯ) + CORS เปิด
# (main.ts/seed.ts แยกเฉพาะ === 'production') และ throttle guard ยอมรับค่า override ที่ผ่อนปรน
export NODE_ENV=e2e
# E2E ทุก request มาจาก IP เดียว — ยกเพดาน per-IP login throttle เฉพาะ e2e/ci (RELAXED_ENVS)
export LOGIN_THROTTLE_MAX="${LOGIN_THROTTLE_MAX:-1000}"
# Browser Print mode — เปิดเฉพาะ stack ทดสอบ (production default = ปิด)
export CSSD_BROWSER_PRINT_ENABLED="${CSSD_BROWSER_PRINT_ENABLED:-true}"
export BROWSER_PRINT_THROTTLE_MAX="${BROWSER_PRINT_THROTTLE_MAX:-1000}"

dc() { if docker compose version >/dev/null 2>&1; then docker compose "$@"; else docker-compose "$@"; fi; }

up() {
  echo "== 1/5 Postgres (docker compose) =="
  dc up -d db
  echo "-- รอ Postgres พร้อม (fail-fast) --"
  ok=0
  for _ in $(seq 1 30); do
    if dc exec -T db pg_isready -U cssd >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "ERROR: Postgres ไม่พร้อมภายใน 30s" >&2; exit 1; }

  echo "== 2/5 migrate + seed =="
  npm run -w apps/api prisma:generate >/dev/null
  npm run -w apps/api prisma:migrate:deploy
  npm run -w apps/api prisma:seed

  echo "== 3/5 build + start API (background) =="
  npm run -w apps/api build >/dev/null
  ( cd apps/api && node dist/main >/tmp/cssd-e2e-api.log 2>&1 & echo $! >"$PID_FILE" )
  echo "-- รอ API พร้อม ($API_URL/api/v1/health) fail-fast --"
  # ยิง /api/v1/health (คืน {status:ok}) เท่านั้น — /api/v1 เป็น 404 route ไม่ใช่ readiness
  ok=0
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "$API_URL/api/v1/health" 2>/dev/null; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "ERROR: API ไม่พร้อมภายใน 30s (ดู /tmp/cssd-e2e-api.log)" >&2; exit 1; }

  echo "== 4/5 build PWA web (ชี้ API → $API_URL) =="
  ( cd apps/mobile && flutter build web --release \
      --dart-define=CSSD_API_URL="$API_URL" \
      --dart-define=CSSD_BROWSER_PRINT_ENABLED=true )

  echo "== 5/5 serve web ที่ :$WEB_PORT (background) =="
  # http-server pinned ใน root lockfile (npm ci ติดตั้งให้แล้ว — ไม่ดาวน์โหลดตอนรัน)
  ( "$ROOT/node_modules/.bin/http-server" "$ROOT/apps/mobile/build/web" -p "$WEB_PORT" -s >/tmp/cssd-e2e-web.log 2>&1 & echo $! >>"$PID_FILE" )
  echo "-- รอ PWA web พร้อม (http://localhost:$WEB_PORT) fail-fast --"
  ok=0
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://localhost:$WEB_PORT" 2>/dev/null; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "ERROR: PWA web ไม่พร้อมภายใน 30s (ดู /tmp/cssd-e2e-web.log)" >&2; exit 1; }

  echo
  echo "✓ stack พร้อม:"
  echo "    API : $API_URL/api/v1"
  echo "    Web : http://localhost:$WEB_PORT"
  echo "    รัน : cd e2e && E2E_BASE_URL=http://localhost:$WEB_PORT npm run test:e2e"
  echo "    หยุด: bash scripts/e2e-stack.sh down"
}

down() {
  if [ -f "$PID_FILE" ]; then
    while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done <"$PID_FILE"
    rm -f "$PID_FILE"
  fi
  dc down
  echo "✓ หยุด stack แล้ว"
}

case "${1:-up}" in
  up) up ;;
  down) down ;;
  *) echo "ใช้: $0 [up|down]"; exit 1 ;;
esac
