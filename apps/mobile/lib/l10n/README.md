# i18n (gen-l10n)

ข้อความ user-facing ควรอยู่ในไฟล์ ARB ที่นี่ ไม่ hard-code ปนในโค้ด
(ตาม `CLAUDE.md` §5) — ภาษาหลัก = **ไทย** (`app_th.arb` = template), `app_en.arb` = fallback

## เพิ่ม/แก้ข้อความ

1. เพิ่ม key ใน `app_th.arb` (+ คำแปลใน `app_en.arb`)
2. รัน `flutter gen-l10n` (หรือ `flutter pub get` / build จะ gen ให้เองเพราะ `generate: true`)
3. ใช้ในวิดเจ็ต:
   ```dart
   import '<relative>/l10n/app_localizations.dart';
   final l10n = AppLocalizations.of(context);
   Text(l10n.settingsTitle);
   ```

## สถานะ (migration แบบค่อยเป็นค่อยไป)

- ✅ โครงสร้าง gen-l10n + wiring ใน `main.dart` (delegate + supportedLocales)
- ✅ หน้า **ตั้งค่า (settings)** แปลงเป็น l10n แล้ว = หน้าอ้างอิง (reference) ของ pattern
- ⏳ หน้าที่เหลือ (scan, packages, batches, reports, print jobs ฯลฯ) ยัง hard-code ไทยอยู่
  ทยอยย้ายเข้ามาทีละหน้าโดยใช้ pattern เดียวกัน (ดู task ต่อเนื่องใน PROGRESS.md)

> ไฟล์ `app_localizations*.dart` เป็น generated — แก้ ARB แล้ว gen ใหม่ ไม่แก้ไฟล์ .dart มือ
