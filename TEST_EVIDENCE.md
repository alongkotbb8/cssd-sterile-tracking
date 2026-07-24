# Test Evidence — M1/M2 Re-audit + Phase 1 closeout

บันทึกผลรันจริง (ให้ผู้ตรวจ reproduce ได้) — วันที่ 2026-07-22
สภาพแวดล้อม: macOS (darwin 24.x, aarch64) · Node 20 · PostgreSQL **16.14 (Homebrew)** ที่ `localhost:5432`

> วิธี reproduce: สตาร์ท Postgres ตาม `apps/api/.env` (`DATABASE_URL`) ก่อน แล้วรันคำสั่งด้านล่าง
> ถ้า Postgres ไม่พร้อม integration suite จะรันไม่ได้ ให้ถือว่า "ยังยืนยันซ้ำไม่ได้" ไม่ใช่ "ผ่าน"

## 1. Backend — type check + unit tests

```
cd apps/api && npx tsc --noEmit      # (ไม่มี output = ผ่าน)
cd apps/api && npx jest
→ Test Suites: 5 passed, 5 total
→ Tests:       95 passed, 95 total
```

ครอบคลุม: idempotency (atomic single-tx, replay, 409 payload/user/**endpoint+method**, no-rerun-on-PENDING, crash rollback, cleanup ลบ DONE เท่านั้น—คง PENDING), print-jobs (createJob server-derived isReprint, findOne IDOR, cancel QUEUED-only, claim pool/targeted, PRINTING→SENT→PRINTED CAS, backend-decided simulation + 3-value re-check, reportIndeterminate/MAYBE_SENT, fail-before-SENT, resolveAckUnknown one-time, capability invariant, lease recovery), notifications, gateway-auth guard, domain (expiry/FEFO/state)

## 2. Backend — PostgreSQL integration/concurrency tests (FIX-07)

```
cd apps/api && npm run test:integration
→ [int] test DB cssd_inttest ready
→ Test Suites: 2 passed, 2 total
→ Tests:       12 passed, 12 total
```

ครอบคลุมกับ Postgres จริง: idempotency 10-concurrent-same-key (1 package, replay เดียวกัน, seq=1 ไม่กระโดด), key+payload ต่าง→409, crash-rollback, committed-PENDING no-rerun; print-job dual-claim (`FOR UPDATE SKIP LOCKED`), concurrent-ACK (reprintCount +1), cancel-vs-claim, concurrent-resolve, REQUEUE พร้อมกัน/ซ้ำ, CONSOLE gateway→SIMULATED เท่านั้น, lease recovery PRINTING→ACK_UNKNOWN

## 3. Migration dry-run (fresh DB)

integration global-setup สร้าง DB `cssd_inttest` ใหม่แล้ว `prisma migrate deploy` ทั้ง 9 migration — ผลรันจริง:

```
Applying migration `20260711100653_init`
Applying migration `20260715090000_add_fcm_tokens`
Applying migration `20260716040000_add_packed_out_status`
Applying migration `20260718090000_add_account_lockout`
Applying migration `20260718091000_add_tags_and_idempotency`
Applying migration `20260718092000_add_print_job_queue`
Applying migration `20260722072226_m1_m2_audit_fixes`
Applying migration `20260722140000_fix03_ackunknown_resolution`
Applying migration `20260722150000_fix05_gateway_capability`
All migrations have been successfully applied.
```

Migration บน **populated DB** (FIX-01 `expiresAt`) พิสูจน์แยกแล้ว: DB มี PENDING/DONE เดิม → 3-step
backfill → ไม่มีแถวหาย ทุกแถวมี `expiresAt`, `prisma migrate status` = up to date ไม่ drift

## 4. Print Gateway — type check + unit tests

```
cd apps/print-gateway && npx tsc --noEmit    # ผ่าน
cd apps/print-gateway && GATEWAY_API_KEY=test-key npx jest
→ Test Suites: 3 passed, 3 total
→ Tests:       25 passed, 25 total
```

ครอบคลุม: poll-loop (SENT→markSent+ack, NOT_SENT→fail, MAYBE_SENT→reportMaybeSent, unknown-error→MAYBE_SENT, payloadHash mismatch→fail, once-SENT-never-fail), config guards (FIX-06 production https-only / dev localhost-only / console-blocked-in-prod), label-renderer (QR packageId-only, ไทย/warning, TSPL injection)

## 5. dev DB migration status

```
cd apps/api && npx prisma migrate status
→ 9 migrations found · Database schema is up to date!   (ไม่ drift)
```

---

รวม: **unit 95 + integration 12 + gateway 25 = 132 tests ผ่านทั้งหมด** · type check สะอาดทั้ง 2 workspace ·
migration dry-run (fresh) + populated + status ผ่าน — **ยังไม่ deploy**
