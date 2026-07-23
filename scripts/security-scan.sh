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
echo "== Flutter/Dart CVE scan (osv-scanner, blocking — เหมือน CI security-scan.yml) =="
OSV_VERSION=v2.4.0
osv_sha256_for() {
  case "$1" in
    darwin_amd64) echo 088119325156321c34c456ac3703d6013538fd71cbac82b891ab34db491e4d66 ;;
    darwin_arm64) echo 9ca3185ad63e9ab54f7cb90f46a7362be02d80e37f0123d095a54355ea202f5d ;;
    linux_amd64) echo 15314940c10d26af9c6649f150b8a47c1262e8fc7e17b1d1029b0e479e8ed8a0 ;;
    linux_arm64) echo 44e580752910f0ff36ec99aff59af20f65df1e859aa31e5605a8f0d055b496e9 ;;
  esac
}
if command -v osv-scanner >/dev/null 2>&1; then
  OSV_BIN=osv-scanner
else
  case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS= ;; esac
  case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH= ;; esac
  PLATFORM="${OS}_${ARCH}"
  SHA256=$(osv_sha256_for "$PLATFORM")
  if [ -n "$OS" ] && [ -n "$ARCH" ] && [ -n "$SHA256" ]; then
    OSV_BIN="$(mktemp -t osv-scanner)"
    if curl -sSfL "https://github.com/google/osv-scanner/releases/download/${OSV_VERSION}/osv-scanner_${PLATFORM}" -o "$OSV_BIN" \
      && echo "${SHA256}  ${OSV_BIN}" | shasum -a 256 -c - >/dev/null 2>&1; then
      chmod +x "$OSV_BIN"
    else
      echo "  ✗ ดาวน์โหลด/ตรวจ SHA256 ของ osv-scanner ไม่ผ่าน — ข้าม (ติดตั้งเอง: brew install osv-scanner)"
      OSV_BIN=""
      fail=1
    fi
  else
    echo "  - ไม่รู้จัก platform ($(uname -s)/$(uname -m)) สำหรับดาวน์โหลดอัตโนมัติ — ติดตั้งเอง: brew install osv-scanner"
    OSV_BIN=""
  fi
fi
if [ -n "${OSV_BIN:-}" ]; then
  if ( cd apps/mobile && "$OSV_BIN" scan --lockfile=pubspec.lock ); then
    echo "  ✓ ไม่พบ CVE ใน Flutter/Dart deps"
  else
    echo "  ✗ พบ CVE ใน Flutter/Dart deps — ตรวจก่อน deploy"
    fail=1
  fi
fi

echo
echo "== flutter pub outdated (apps/mobile, รายงานเฉย ๆ) =="
( cd apps/mobile && flutter pub outdated || true )

echo
[ "$fail" -eq 0 ] && echo "ผลรวม: ผ่าน ✓" || echo "ผลรวม: มีปัญหาที่ต้องแก้ ✗"
exit "$fail"
