// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CSSD Sterile Tracking';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsPrinter => 'Printer';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsPrinterInUse => 'Printer in use';

  @override
  String get settingsServerUrl => 'API server address';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionLogout => 'Log out';

  @override
  String get actionLogoutAll => 'Log out of all devices';

  @override
  String get actionLogoutAllSubtitle => 'Revoke all sessions (e.g. lost phone)';

  @override
  String get logoutConfirmTitle => 'Log out?';

  @override
  String get logoutConfirmBody => 'You will need to sign in again next time.';

  @override
  String get logoutAllConfirmTitle => 'Log out of all devices?';

  @override
  String get logoutAllConfirmBody =>
      'Every device signed in with this account will be signed out immediately and must log in again.';

  @override
  String get logoutAllConfirmAction => 'Log out all';
}
