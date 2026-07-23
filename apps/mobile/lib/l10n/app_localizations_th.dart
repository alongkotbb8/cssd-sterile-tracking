// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get appTitle => 'CSSD Sterile Tracking';

  @override
  String get settingsTitle => 'ตั้งค่า';

  @override
  String get settingsAccount => 'บัญชีผู้ใช้';

  @override
  String get settingsPrinter => 'เครื่องพิมพ์';

  @override
  String get settingsSystem => 'ระบบ';

  @override
  String get settingsPrinterInUse => 'เครื่องพิมพ์ที่ใช้';

  @override
  String get settingsServerUrl => 'ที่อยู่ Server API';

  @override
  String get actionCancel => 'ยกเลิก';

  @override
  String get actionSave => 'บันทึก';

  @override
  String get actionLogout => 'ออกจากระบบ';

  @override
  String get actionLogoutAll => 'ออกจากระบบทุกอุปกรณ์';

  @override
  String get actionLogoutAllSubtitle =>
      'เพิกถอนการเข้าสู่ระบบทั้งหมด (เช่น ทำโทรศัพท์หาย)';

  @override
  String get logoutConfirmTitle => 'ออกจากระบบ?';

  @override
  String get logoutConfirmBody => 'ต้องเข้าสู่ระบบใหม่ในการใช้งานครั้งถัดไป';

  @override
  String get logoutAllConfirmTitle => 'ออกจากระบบทุกอุปกรณ์?';

  @override
  String get logoutAllConfirmBody =>
      'ทุกอุปกรณ์ที่เข้าสู่ระบบด้วยบัญชีนี้จะถูกบังคับออกทันที ต้องเข้าสู่ระบบใหม่ทั้งหมด';

  @override
  String get logoutAllConfirmAction => 'ออกทุกอุปกรณ์';
}
