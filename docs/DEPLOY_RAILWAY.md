# Deploy API + PostgreSQL บน Railway (แทน Render — ไม่มี cold-start / ไม่หลับ)

> ✅ **ทำจริงแล้ว (2026-07-24)** — production รันบน Railway:
> - โปรเจกต์ Railway: `cssd-sterile` (workspace `alongkotbb8's Projects`)
> - service `cssd-api` + `Postgres` (region sfo/US-East) — API: `https://cssd-api-production-3f39.up.railway.app`
> - ข้อมูลย้ายจาก Neon เดิม → Railway Postgres เรียบร้อย (pg_dump/pg_restore v18)
> - PWA (`https://sterelis-cssd.pages.dev`) rebuild ชี้ Railway แล้ว
> - Render (`cssd-api.onrender.com`) = fallback เท่านั้น (rollback ได้โดย rebuild PWA ชี้ URL เดิม)
> - เครื่องมือ client v18: `brew install libpq` → `/opt/homebrew/opt/libpq/bin/{pg_dump,pg_restore,psql}`
>   (จำเป็นเพราะทั้ง Neon และ Railway เป็น PG18 — pg_dump ต้อง ≥ เวอร์ชัน server)
> ขั้นตอนด้านล่างคือ runbook ทั่วไป/สำหรับทำซ้ำ.


> เหตุผลที่ย้าย: Render free web service **หลับหลังไม่มีคนใช้ ~15 นาที** (คำขอแรกช้า 30–60 วิ
> หรือ error 522) และ Render free Postgres **หมดอายุใน 90 วัน**. Railway ไม่หลับและมี Postgres ในตัว.
> PWA (Cloudflare Pages) **ไม่ต้องย้าย** — แค่ rebuild ให้ชี้ URL ใหม่.

การ build ของ API เหมือน Render ทุกอย่าง (root = `apps/api`, `@cssd/shared` เป็น path alias
ตอน test เท่านั้น จึง build เดี่ยวได้). ค่าพร้อมใช้อยู่ใน [`apps/api/railway.json`](../apps/api/railway.json).

---

## ขั้นตอน (ทำครั้งเดียว)

### 1) สร้างโปรเจกต์บน Railway
1. เข้า https://railway.app → **Login with GitHub**
2. **New Project → Deploy from GitHub repo → `alongkotbb8/cssd-sterile-tracking`**
3. เลือก branch = `main`

### 2) ตั้ง Root Directory ของ service
Service ที่เพิ่งสร้าง → **Settings → Root Directory** = `apps/api`
(Railway จะอ่าน `apps/api/railway.json` เอง: build/start/healthcheck ตรงกับที่ Render ใช้)

### 3) เพิ่ม PostgreSQL
ในโปรเจกต์เดียวกัน → **New → Database → Add PostgreSQL**
(Railway จะสร้างตัวแปร `DATABASE_URL` ของ Postgres ให้อัตโนมัติ)

### 4) ตั้ง Environment Variables ของ service API
ไปที่ service API → **Variables** ใส่ตามนี้:

| Key | Value | หมายเหตุ |
|---|---|---|
| `NODE_ENV` | `production` | |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | อ้างอิงจาก Postgres service (พิมพ์แบบนี้เป๊ะ ๆ) |
| `JWT_SECRET` | *(สุ่มใหม่)* | สร้างด้วย `openssl rand -base64 48` แล้ววาง (ผู้ใช้ต้อง re-login หนึ่งครั้ง) |
| `JWT_EXPIRES_IN` | `8h` | |
| `CORS_ORIGINS` | `https://sterelis-cssd.pages.dev` | **สำคัญมาก** — ถ้าไม่ตั้ง production จะบล็อก PWA ทุก origin |
| `CSSD_BROWSER_PRINT_ENABLED` | `true` | เปิดโหมดพิมพ์ผ่านเบราว์เซอร์ (ทดสอบ XP-420B บน Mac) |
| `NIXPACKS_NODE_VERSION` | `20` | กัน Nixpacks เลือก Node เวอร์ชันอื่น (เผื่อไว้; `engines` ก็ pin แล้ว) |

> `PORT` ไม่ต้องตั้ง — Railway ฉีดให้เอง และแอป `listen(process.env.PORT, '0.0.0.0')` อยู่แล้ว

### 5) Deploy + เอา URL
- Railway จะ build+deploy อัตโนมัติ (ครั้งแรกจะรัน `prisma migrate deploy` สร้าง schema ให้)
- Service API → **Settings → Networking → Generate Domain** → ได้ URL เช่น
  `https://cssd-api-production-xxxx.up.railway.app`
- ทดสอบ: เปิด `<URL>/api/v1/health` ต้องได้ `{"status":"ok"}`

### 6) ย้ายข้อมูลจาก DB เดิม → Railway Postgres (ถ้าต้องการเก็บข้อมูลที่ทดสอบไว้)
มีสคริปต์ให้แล้ว: [`scripts/migrate-db-to-railway.sh`](../scripts/migrate-db-to-railway.sh)

```bash
# OLD = connection string ของ DB เดิม (จากหน้า Render → ตัวแปร DATABASE_URL)
# NEW = connection string ของ Railway Postgres (Railway → Postgres → Connect → Postgres Connection URL)
OLD='postgresql://...old...' NEW='postgresql://...railway...' bash scripts/migrate-db-to-railway.sh
```
สคริปต์ทำ `pg_dump` เต็ม (schema + data + ประวัติ migration) แล้ว restore เข้า Railway
— หลัง restore, `prisma migrate deploy` ของ deploy ถัดไปจะเป็น no-op (migration ถูกบันทึกครบแล้ว)

> ถ้าเพิ่งเริ่มทดสอบ ข้อมูลยังน้อย จะ **เริ่มใหม่ (ไม่ย้าย)** ก็ได้ — ข้ามขั้นนี้แล้วให้ seed
> รันเอง (`npm run prisma:seed` ใน Railway shell) หรือปล่อยให้ deploy สร้าง schema เปล่า

### 7) ต่อ PWA เข้ากับ API ใหม่ (ผมทำให้)
```bash
cd apps/mobile
flutter build web --release \
  --dart-define=CSSD_API_URL=<Railway URL> \
  --dart-define=CSSD_BROWSER_PRINT_ENABLED=true
npx wrangler pages deploy build/web --project-name=sterelis-cssd --branch=main
```

### 8) ปิด Render (หลังยืนยัน Railway ใช้งานได้)
Render dashboard → service `cssd-api` → **Suspend** (หรือ Delete). เก็บ DB เดิมไว้จนกว่าจะมั่นใจ.

---

## Rollback
ถ้า Railway มีปัญหา: rebuild PWA ชี้กลับ Render URL เดิม (`https://cssd-api.onrender.com`) แล้ว
deploy ใหม่ — โค้ด API ตัวเดียวกัน รันได้ทั้งสองที่.
