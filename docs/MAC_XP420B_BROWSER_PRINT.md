# คู่มือ: พิมพ์ label ผ่าน Browser บน Mac + Xprinter XP-420B (`BROWSER_DIALOG`)

> อ้างอิง: [MACOS_BROWSER_PRINT_DIRECTIVE.md](../MACOS_BROWSER_PRINT_DIRECTIVE.md) (REQUIRED/LOCKED)
> โหมดนี้ใช้ได้เฉพาะ **Mac ที่เสียบ XP-420B ทาง USB และเปิด PWA บนเครื่องเดียวกัน**
> — iPhone/iPad/Android ควบคุมเครื่องพิมพ์บน Mac ผ่านโหมดนี้ไม่ได้ (ใช้ Print Gateway)
> Browser **พิสูจน์ผล hardware ไม่ได้** — ผู้ใช้ต้องตรวจกระดาษจริงแล้วยืนยันเองใน PWA

## 1. การติดตั้ง (ครั้งเดียวต่อเครื่อง Mac)

1. ต่อ XP-420B เข้า Mac ทาง USB แล้วเปิดเครื่องพิมพ์
2. ติดตั้ง driver ของ Xprinter สำหรับ macOS (จากแผ่น/เว็บผู้ผลิต)
3. System Settings → **Printers & Scanners** → ต้องเห็น XP-420B ในรายการ
4. ตั้งขนาดกระดาษ (paper size) แบบ custom = ขนาด label จริง เริ่มต้น **60 × 40 มม.**
5. พิมพ์ test page จาก macOS ให้สำเร็จก่อนใช้งานจาก PWA

## 2. การเปิดใช้โหมด (feature flag — default ปิด)

| ฝั่ง | วิธีเปิด |
|---|---|
| Backend (API) | env `CSSD_BROWSER_PRINT_ENABLED=true` (ค่าอื่นนอกจาก true/false → API ไม่ยอมบูต) |
| PWA (build) | `flutter build web --release --dart-define=CSSD_BROWSER_PRINT_ENABLED=true` |
| ขนาด label | `--dart-define=CSSD_LABEL_WIDTH_MM=60 --dart-define=CSSD_LABEL_HEIGHT_MM=40` (ค่าเริ่มต้น 60×40) |
| Rate limit | env `BROWSER_PRINT_THROTTLE_MAX` (ค่าเริ่มต้น 60 คำขอ/นาที/ผู้ใช้) |

ปิดฝั่งใดฝั่งหนึ่ง = ใช้งานไม่ได้ (backend ตรวจ flag ทุก endpoint ไม่พึ่งการซ่อนปุ่มอย่างเดียว)

## 3. วิธีใช้งาน (ผู้ใช้)

1. เปิด PWA ด้วย Chrome หรือ Safari **บน Mac เครื่องที่ต่อเครื่องพิมพ์**
2. สร้างห่อใหม่ หรือเปิดรายละเอียดห่อ → กดปุ่ม **"พิมพ์ผ่านเครื่องนี้"**
3. ระบบสร้างคำขอพิมพ์ที่ backend และแสดง **ตัวอย่าง label** (ข้อมูล/วันที่มาจาก backend
   เท่านั้น; ห่อที่ยังไม่ผ่านการนึ่งจะมีแถบ "ยังไม่ผ่านการฆ่าเชื้อ" แทนวันที่)
4. ถ้าห่อนี้เคยสั่งพิมพ์แล้ว ระบบจะเตือนและ**บังคับกรอกเหตุผลการพิมพ์ซ้ำ**
5. กด "พิมพ์ผ่านเครื่องนี้" → ระบบบันทึก `DIALOG_OPENED` แล้วเปิดหน้าต่างพิมพ์ของ macOS
6. ในหน้าต่างพิมพ์ ตรวจให้ครบ:
   - **Printer**: Xprinter XP-420B
   - **Paper size**: ขนาด label ที่ตั้งไว้ (60×40 มม.)
   - **Scale**: 100%
   - **Margins**: None (หรือค่าที่ผ่านการทดสอบ)
   - **Headers and footers**: Off
7. กด Print แล้ว**ตรวจกระดาษที่ออกจากเครื่องจริง** จากนั้นกลับมาเลือกผลใน PWA:
   - `กระดาษออกถูกต้อง` → บันทึกเป็น **USER_CONFIRMED** (ผู้ใช้ยืนยันเอง)
   - `ไม่ได้พิมพ์ / ยกเลิก` → บันทึกเป็น **CANCELLED**
   - `ตรวจสอบภายหลัง` → คงสถานะ **DIALOG_OPENED** ไว้ก่อน

> ⚠️ ระบบ Browser ไม่สามารถตรวจสอบกระดาษที่ออกจากเครื่องได้ กรุณาตรวจ label ก่อนยืนยัน
> การกด Print/ปิดหน้าต่างพิมพ์ **ไม่ใช่** หลักฐานว่าพิมพ์สำเร็จ

## 4. ความหมายของสถานะ (ห้ามตีความเกินจริง)

| สถานะ | ความหมาย |
|---|---|
| `CREATED` | สร้างคำขอแล้ว (ยังไม่เปิดหน้าต่างพิมพ์) |
| `DIALOG_OPENED` | เปิดหน้าต่างพิมพ์แล้ว ยังไม่ยืนยันผล |
| `USER_CONFIRMED` | **ผู้ใช้**ยืนยันว่ากระดาษออกแล้ว (ไม่ใช่เครื่องพิมพ์ยืนยัน) |
| `CANCELLED` | ผู้ใช้แจ้งว่าไม่ได้พิมพ์หรือยกเลิก |

โหมดนี้**ไม่ตั้ง** `printedAt`/`reprintCount` ของห่อ (สองค่านั้นมาจาก Print Gateway ACK
เท่านั้น) — ประวัติ browser print ดูได้ในหน้ารายละเอียดห่อและหน้ารวมงานพิมพ์

## 5. Manual Hardware Acceptance — Mac + XP-420B (directive §15)

> ผู้ทดสอบต้องบันทึกหลักฐานทุกข้อ ก่อนที่ QA จะประกาศ `HARDWARE_VERIFIED` ได้
> (automated test แทนการทดสอบเครื่องจริงไม่ได้)

| # | รายการ | ผล | หลักฐาน |
|---|---|---|---|
| 1 | macOS เห็น XP-420B ใน Printers & Scanners | ☐ | |
| 2 | พิมพ์ test page จาก macOS สำเร็จ | ☐ | |
| 3 | Chrome เปิด print dialog และเห็น XP-420B | ☐ | |
| 4 | Safari เปิด print dialog และเห็น XP-420B | ☐ | |
| 5 | ขนาด label จริงตรงกับค่าที่กำหนด (60×40 มม.) | ☐ | |
| 6 | ภาษาไทยไม่แตก ไม่หาย ไม่เป็นสี่เหลี่ยม | ☐ | |
| 7 | QR สแกนกลับได้ด้วย Chrome บน Android | ☐ | |
| 8 | QR สแกนกลับได้ด้วย Safari บน iPhone/iPad | ☐ | |
| 9 | วันนึ่งและวันหมดอายุถูกต้อง (ห่อ STERILE) | ☐ | |
| 10 | Label ห่อยังไม่ผ่านการนึ่ง ไม่มีวันที่ต้องห้าม + มีแถบเตือน | ☐ | |
| 11 | History แสดง `DIALOG_OPENED` ก่อนยืนยัน | ☐ | |
| 12 | History แสดง `USER_CONFIRMED` หลังผู้ใช้ยืนยัน | ☐ | |
| 13 | Cancel แล้วแสดง `CANCELLED` | ☐ | |
| 14 | Reprint มี warning, reason และ Audit ครบ | ☐ | |
| 15 | พิมพ์ต่อเนื่อง 10 ใบ ไม่ซ้ำ/ไม่ข้าม | ☐ | |
| 16 | พิมพ์ต่อเนื่อง 50 ใบ ก่อนอนุมัติ Pilot | ☐ | |

หลักฐานขั้นต่ำที่ต้องแนบ: รุ่น macOS · รุ่น Chrome/Safari · รุ่น driver · ชื่อ printer queue ·
ขนาด/ชนิด label · ภาพ label จริง · ผลสแกน QR · API/Audit evidence · ปัญหาและวิธีแก้

## 6. Troubleshooting

- **ไม่เห็นปุ่ม "พิมพ์ผ่านเครื่องนี้"** — build PWA ไม่ได้เปิด dart-define หรือ backend ปิด flag
- **กดพิมพ์แล้ว error โหมดถูกปิด** — backend ไม่ได้ตั้ง `CSSD_BROWSER_PRINT_ENABLED=true`
- **label ย่อ/ขยายผิดขนาด** — ตรวจ Scale = 100% + paper size = ขนาด label (ไม่ใช่ A4)
- **มีหัว/ท้ายกระดาษเกิน** — ปิด Headers and footers ในหน้าต่างพิมพ์ (PDF ปกติไม่มี)
- **เตือนพิมพ์ซ้ำทั้งที่ยังไม่เคยพิมพ์** — ห่อนั้นมีประวัติ `DIALOG_OPENED` ค้าง (เคยเปิด
  หน้าต่างพิมพ์แล้วไม่ยืนยันผล) — directive นับเป็น "เคยสั่งพิมพ์แล้ว" เพื่อ fail closed
