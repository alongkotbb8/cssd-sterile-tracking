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

## สถานะ

- ✅ โครงสร้าง gen-l10n + wiring ใน `main.dart` (delegate + supportedLocales)
- ✅ แปลงครบทุกหน้าหลัก user-facing: **settings, packages, scan, batches,
  departments, reports, print jobs** (th = template, en = fallback, default ไทย)
- ถ้ามีหน้า/ข้อความใหม่ ให้เพิ่ม key ใน ARB แล้วใช้ `AppLocalizations.of(context)`
  ตาม pattern เดิม (อย่า hard-code ไทยในโค้ด)

> ไฟล์ `app_localizations*.dart` เป็น generated — แก้ ARB แล้ว gen ใหม่ ไม่แก้ไฟล์ .dart มือ
