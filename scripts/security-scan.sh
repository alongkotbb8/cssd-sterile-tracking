#!/usr/bin/env bash
# สแกนความปลอดภัยแบบรันในเครื่อง (ก่อน push) — ให้ผลใกล้เคียง CI security-scan.yml
# ใช้: bash scripts/security-scan.sh
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

echo "== npm audit (workspaces: api / print-gateway / shared) =="
if npm audit --audit-level=high; then
  echo "  ✓ ไม่มีช่องโหว่ระดับ high ขึ้นไป"
else
  echo "  ✗ พบช่องโหว่ระดับ high+ — รัน 'npm audit' ดูรายละเอียด/แก้ก่อน deploy"
  fail=1
fi

echo
echo "== secret scan (gitleaks ถ้ามีติดตั้ง) =="
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --redact; then
    echo "  ✓ ไม่พบ secret ใน git"
  else
    echo "  ✗ พบ secret ที่อาจหลุด — ตรวจก่อน commit/push"
    fail=1
  fi
else
  echo "  - ข้าม (ไม่ได้ติดตั้ง gitleaks) ; ติดตั้ง: brew install gitleaks"
fi

echo
echo "== flutter pub outdated (apps/mobile, รายงานเฉย ๆ) =="
( cd apps/mobile && flutter pub outdated || true )

echo
[ "$fail" -eq 0 ] && echo "ผลรวม: ผ่าน ✓" || echo "ผลรวม: มีปัญหาที่ต้องแก้ ✗"
exit "$fail"
