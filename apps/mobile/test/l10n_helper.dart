import 'package:flutter/material.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

/// ครอบ widget ด้วย MaterialApp + AppLocalizations delegates สำหรับ widget test
/// เลือก locale ได้ (ค่าเริ่มต้น th) — ใช้ทดสอบทั้งสองภาษา
Widget wrapLocalized(Widget child, {Locale locale = const Locale('th')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}
