import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_th.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('th')
  ];

  /// ชื่อแอป (title bar / task switcher)
  ///
  /// In th, this message translates to:
  /// **'CSSD Sterile Tracking'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In th, this message translates to:
  /// **'ตั้งค่า'**
  String get settingsTitle;

  /// No description provided for @settingsAccount.
  ///
  /// In th, this message translates to:
  /// **'บัญชีผู้ใช้'**
  String get settingsAccount;

  /// No description provided for @settingsPrinter.
  ///
  /// In th, this message translates to:
  /// **'เครื่องพิมพ์'**
  String get settingsPrinter;

  /// No description provided for @settingsSystem.
  ///
  /// In th, this message translates to:
  /// **'ระบบ'**
  String get settingsSystem;

  /// No description provided for @settingsPrinterInUse.
  ///
  /// In th, this message translates to:
  /// **'เครื่องพิมพ์ที่ใช้'**
  String get settingsPrinterInUse;

  /// No description provided for @settingsServerUrl.
  ///
  /// In th, this message translates to:
  /// **'ที่อยู่ Server API'**
  String get settingsServerUrl;

  /// No description provided for @actionCancel.
  ///
  /// In th, this message translates to:
  /// **'ยกเลิก'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In th, this message translates to:
  /// **'บันทึก'**
  String get actionSave;

  /// No description provided for @actionLogout.
  ///
  /// In th, this message translates to:
  /// **'ออกจากระบบ'**
  String get actionLogout;

  /// No description provided for @actionLogoutAll.
  ///
  /// In th, this message translates to:
  /// **'ออกจากระบบทุกอุปกรณ์'**
  String get actionLogoutAll;

  /// No description provided for @actionLogoutAllSubtitle.
  ///
  /// In th, this message translates to:
  /// **'เพิกถอนการเข้าสู่ระบบทั้งหมด (เช่น ทำโทรศัพท์หาย)'**
  String get actionLogoutAllSubtitle;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In th, this message translates to:
  /// **'ออกจากระบบ?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In th, this message translates to:
  /// **'ต้องเข้าสู่ระบบใหม่ในการใช้งานครั้งถัดไป'**
  String get logoutConfirmBody;

  /// No description provided for @logoutAllConfirmTitle.
  ///
  /// In th, this message translates to:
  /// **'ออกจากระบบทุกอุปกรณ์?'**
  String get logoutAllConfirmTitle;

  /// No description provided for @logoutAllConfirmBody.
  ///
  /// In th, this message translates to:
  /// **'ทุกอุปกรณ์ที่เข้าสู่ระบบด้วยบัญชีนี้จะถูกบังคับออกทันที ต้องเข้าสู่ระบบใหม่ทั้งหมด'**
  String get logoutAllConfirmBody;

  /// No description provided for @logoutAllConfirmAction.
  ///
  /// In th, this message translates to:
  /// **'ออกทุกอุปกรณ์'**
  String get logoutAllConfirmAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'th'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'th':
      return AppLocalizationsTh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
