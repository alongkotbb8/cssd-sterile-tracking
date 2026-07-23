# Operational & Security Readiness (Phase 5)

> ขอบเขต Phase 5: security hardening ที่ทำได้ในโค้ด + ขั้นตอน ops/SOP ที่ทีมต้องทำเอง
> สถานะ: โค้ด security ทำเสร็จ+ทดสอบแล้ว · ops (cert/backup/monitoring/SOP) เป็น checklist ให้ทีม
> ยังไม่ deploy — ต้องผ่านทั้งตารางนี้ + FIX-08 (Xprinter จริง) + UAT ก่อน Pilot

---

## 1. RBAC / IDOR audit — ทุก endpoint ของ Print Job (ตรวจแล้ว ✅)

| Endpoint | Auth | สิทธิ์ | Authz เชิงข้อมูล | ทดสอบ |
|---|---|---|---|---|
| `POST /print-jobs` (create) | JWT | ผู้ใช้ที่ล็อกอิน | สร้างงานของตัวเอง; isReprint/payload backend กำหนด | unit |
| `GET /print-jobs` (list) | JWT | ทุก role | CSSD เห็นของตัวเอง, SUP/ADMIN เห็นทั้งหมด | unit |
| `GET /print-jobs/:id` | JWT | ทุก role | **ownership check** (เจ้าของ/SUP/ADMIN) — กัน IDOR | unit |
| `POST /print-jobs/:id/cancel` | JWT | ทุก role | เจ้าของ หรือ SUP/ADMIN + เฉพาะ QUEUED | unit |
| `POST /print-jobs/:id/resolve` | JWT | **SUP/ADMIN** | CAS resolvedAt IS NULL (resolve ครั้งเดียว) | unit + RBAC + integration |
| `GET /print-jobs/gateways/list` | JWT | **SUP/ADMIN** | — | RBAC |
| `POST /print-jobs/gateways` | JWT | **ADMIN** | capability invariant | RBAC + unit |
| `POST /print-jobs/gateways/:id/capability` | JWT | **ADMIN** | invariant + AuditLog | RBAC + unit |
| `POST /print-jobs/gateways/:id/rotate-key` | JWT | **ADMIN** | reject ถ้า revoked + AuditLog | RBAC + unit |
| `POST /print-jobs/gateways/:id/revoke` | JWT | **ADMIN** | AuditLog | RBAC |
| `POST /print-gateway/*` (heartbeat/claim/printing/sent/maybe-sent/ack/fail) | **X-Gateway-Key** (ไม่ใช่ JWT) | gateway เท่านั้น | `assertOwnedByGateway` ทุก job op; guard reject revoked/inactive | guard spec + unit |

- Regression guard: `print-jobs.rbac.spec.ts` ตรวจ `@Roles` metadata — ถ้าลบ `@Roles` ออกจาก endpoint ที่ต้องจำกัด เทสจะ fail
- IDOR: `findOne` มี ownership check (FIX-32), gateway ops มี `assertOwnedByGateway`

## 2. Gateway key lifecycle (SOP)

- **ออก key:** `POST /print-jobs/gateways` (ADMIN) → คืน `{keyId}.{secret}` **แสดงครั้งเดียว** เก็บลง `GATEWAY_API_KEY` ของ gateway process
- **หมุน key (รั่ว/ตามรอบ):** `POST /print-jobs/gateways/:id/rotate-key` (ADMIN) → key เดิมใช้ไม่ได้ทันที, **PrinterDevice.id ไม่เปลี่ยน** (งานเดิมไม่พัง) → อัปเดต `GATEWAY_API_KEY` ที่เครื่อง gateway แล้ว restart
- **เพิกถอน (เครื่องหาย/เลิกใช้):** `POST /print-jobs/gateways/:id/revoke` → auth ไม่ผ่านทันที (guard เช็ค `revokedAt`)
- เก็บ `secret` เป็น bcrypt hash เท่านั้น (ไม่เก็บ plaintext) · ทุกการกระทำมี AuditLog (`GATEWAY_REGISTER/KEY_ROTATE/REVOKE/CAPABILITY_CHANGE`)
- **Production gateway credential ห้ามใช้กับ test gateway** (คนละ record/คนละ capability)

## 3. Rate limiting & Audit

- **ทำแล้ว:** login throttle ต่อ IP + account lockout (fail 5 → ล็อก 15 นาที) — `login-throttle.guard.ts` + `User.failedLoginCount/lockedUntil`
- **AuditLog:** ทุก mutation สำคัญเขียน audit ใน transaction เดียวกัน (scan/package/batch/print/gateway) + cleanup **ไม่ลบ AuditLog** (ลบเฉพาะ Movement + DISCARDED)
- **⚠️ ยังไม่ทำ (ตัดสินใจระดับ ops ก่อน):** global API rate limit ทุก endpoint
  - เหตุผลที่ยังไม่ใส่: (ก) เป็น dependency ใหม่ (`@nestjs/throttler`) ต้องขออนุมัติ (ข) หน้าสถานะพิมพ์ **poll ทุก 2.5 วิ** → ถ้าตั้ง limit ต่ำจะโดน throttle เอง ต้องตั้ง limit เผื่อ polling (ค) in-memory ใช้ได้เฉพาะ single instance — multi-instance ต้องใช้ Redis
  - แนะนำ: ใส่ตอนตัดสินใจ deployment topology (single vs multi instance) แล้ว + ตั้ง limit ให้สอดคล้อง polling

## 4. HTTPS / TLS

- **API** (Render): TLS จัดการโดย platform — ยืนยัน custom domain + auto-cert ทำงาน
- **PWA** (Cloudflare Pages): TLS โดย Cloudflare — กล้องเว็บ (getUserMedia) ต้องการ https จึงบังคับอยู่แล้ว
- **Gateway → API:** `config.ts` บังคับ `https://` เมื่อ `NODE_ENV=production` (FIX-06 — Private IP ก็ไม่ยอม http)
- ☐ ยืนยัน HSTS header ทำงานบน production (helmet ตั้งไว้) — ทดสอบด้วย `curl -I`

## 5. Backup / Restore rehearsal (ต้องซ้อมจริง)

- ☐ ตั้ง automated backup ของ PostgreSQL (Render มี daily backup ในแผนที่รองรับ — ยืนยันเปิด)
- ☐ **ซ้อม restore จริง**: `pg_dump` → สร้าง DB ใหม่ → `pg_restore`/`psql` → ตรวจข้อมูลครบ + แอปต่อได้
- ☐ บันทึก RTO/RPO ที่ยอมรับได้ + ผู้รับผิดชอบ
- ☐ ทดสอบว่า migration ใหม่ apply บน DB ที่ restore มาได้ (มี migration dry-run แล้ว — ดู `TEST_EVIDENCE.md`)

## 6. Monitoring

- **Gateway heartbeat:** `GET /print-jobs/gateways/list` คืน `lastHeartbeatAt` + `isOnline` (mobile UI แสดงแล้ว) — ☐ ตั้ง alert ถ้า gateway ที่ควรออนไลน์เงียบ > X นาที
- **Dead-letter:** query `PrintJob` ที่ `status='DEAD_LETTER'` — ☐ ตั้ง alert/แดชบอร์ดให้หัวหน้าเห็น
- **ACK_UNKNOWN:** query `status='ACK_UNKNOWN'` — ต้องมีคนตาม resolve (mobile ดันขึ้นบนสุดในหน้างานพิมพ์แล้ว)
- ☐ พิจารณา endpoint สรุป ops (นับ dead-letter/ack-unknown/กล้อง gateway offline) สำหรับแดชบอร์ด (ยังไม่ทำ)

## 7. SOP (ต้องเขียนเป็นคู่มือผู้ใช้จริง)

- **ACK_UNKNOWN:** หัวหน้าไปตรวจ label ที่เครื่องพิมพ์จริง → ถ้าออกจริง กด "ยืนยันว่าพิมพ์แล้ว"; ถ้าไม่ออก/ไม่แน่ใจ กด "เปิดงานพิมพ์ใหม่" (ระบบสร้างงานใหม่ให้ ไม่พิมพ์ซ้ำเอง)
- **เครื่องพิมพ์เสีย/ออฟไลน์:** งานจะค้าง QUEUED (ยังไม่ถูก claim) → ตรวจ gateway/เครื่องพิมพ์ → เมื่อกลับมา งานถูก claim ต่อ; ถ้าค้าง CLAIMED นานเกิน lease timeout ระบบคืนเป็น QUEUED ให้เอง (CLAIMED) หรือ ACK_UNKNOWN (PRINTING/SENT)
- **DEAD_LETTER:** พิมพ์ล้มเหลวครบจำนวนครั้ง → ตรวจเครื่องพิมพ์ → สั่งพิมพ์ใหม่ (สร้างงานใหม่)
- **ระบบออนไลน์อย่างเดียว (online-only):** ไม่มี offline queue — ถ้าเน็ตหลุด สแกน/พิมพ์ไม่ได้ชั่วคราว (ขึ้น error ชัดเจน) รอเน็ตกลับแล้วทำใหม่ (Idempotency-Key กันซ้ำถ้ากดไปแล้ว)

---

## สรุปสถานะ Phase 5

- ✅ โค้ด: RBAC/IDOR ครบ + regression test, gateway key rotation, audit coverage, HTTPS enforcement (gateway), helmet/CORS/body-limit/Swagger-guard
- 📋 ต้องทำโดยทีม: backup/restore drill, monitoring alerts, SOP เป็นคู่มือ, ตัดสินใจ global rate limit + deployment topology
- ⏳ ก่อน Pilot: + FIX-08 (Xprinter จริง) + E2E + UAT (Phase 6)
