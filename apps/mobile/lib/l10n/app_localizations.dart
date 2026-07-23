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

  /// No description provided for @commonRetry.
  ///
  /// In th, this message translates to:
  /// **'ลองใหม่'**
  String get commonRetry;

  /// No description provided for @commonSelectAll.
  ///
  /// In th, this message translates to:
  /// **'เลือกทั้งหมด'**
  String get commonSelectAll;

  /// No description provided for @commonClearAll.
  ///
  /// In th, this message translates to:
  /// **'ล้างทั้งหมด'**
  String get commonClearAll;

  /// No description provided for @statusPacked.
  ///
  /// In th, this message translates to:
  /// **'แพ็กแล้ว'**
  String get statusPacked;

  /// No description provided for @statusPackedOut.
  ///
  /// In th, this message translates to:
  /// **'ส่งออกไม่ฆ่าเชื้อ'**
  String get statusPackedOut;

  /// No description provided for @statusSterile.
  ///
  /// In th, this message translates to:
  /// **'ปลอดเชื้อ'**
  String get statusSterile;

  /// No description provided for @statusIssued.
  ///
  /// In th, this message translates to:
  /// **'เบิกออก'**
  String get statusIssued;

  /// No description provided for @statusReturned.
  ///
  /// In th, this message translates to:
  /// **'รอ Reprocess'**
  String get statusReturned;

  /// No description provided for @statusExpired.
  ///
  /// In th, this message translates to:
  /// **'หมดอายุ'**
  String get statusExpired;

  /// No description provided for @filterAll.
  ///
  /// In th, this message translates to:
  /// **'ทั้งหมด'**
  String get filterAll;

  /// No description provided for @pkgListTitle.
  ///
  /// In th, this message translates to:
  /// **'รายการห่อ'**
  String get pkgListTitle;

  /// No description provided for @pkgSelectedCount.
  ///
  /// In th, this message translates to:
  /// **'เลือก {count} ห่อ'**
  String pkgSelectedCount(int count);

  /// No description provided for @pkgSelectToPrintTooltip.
  ///
  /// In th, this message translates to:
  /// **'เลือกเพื่อพิมพ์หลายใบ'**
  String get pkgSelectToPrintTooltip;

  /// No description provided for @pkgCreateNew.
  ///
  /// In th, this message translates to:
  /// **'สร้างห่อใหม่'**
  String get pkgCreateNew;

  /// No description provided for @pkgSelectToPrintHint.
  ///
  /// In th, this message translates to:
  /// **'เลือกห่อเพื่อพิมพ์'**
  String get pkgSelectToPrintHint;

  /// No description provided for @pkgPrintSelected.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์ที่เลือก ({count})'**
  String pkgPrintSelected(int count);

  /// No description provided for @pkgSearchHint.
  ///
  /// In th, this message translates to:
  /// **'ค้นหาเลขรัน / ชื่อชุด'**
  String get pkgSearchHint;

  /// No description provided for @pkgTagAll.
  ///
  /// In th, this message translates to:
  /// **'ทุกป้าย'**
  String get pkgTagAll;

  /// No description provided for @pkgNoneFound.
  ///
  /// In th, this message translates to:
  /// **'ไม่พบห่อในเงื่อนไขนี้'**
  String get pkgNoneFound;

  /// No description provided for @pkgSelectedOf.
  ///
  /// In th, this message translates to:
  /// **'เลือกแล้ว {selected}/{total}'**
  String pkgSelectedOf(int selected, int total);

  /// No description provided for @pkgExpiryOn.
  ///
  /// In th, this message translates to:
  /// **'หมดอายุ {date}'**
  String pkgExpiryOn(String date);

  /// No description provided for @pkgLocationAt.
  ///
  /// In th, this message translates to:
  /// **'อยู่ที่ {location}'**
  String pkgLocationAt(String location);

  /// No description provided for @commonConfirm.
  ///
  /// In th, this message translates to:
  /// **'ยืนยัน'**
  String get commonConfirm;

  /// No description provided for @commonClose.
  ///
  /// In th, this message translates to:
  /// **'ปิด'**
  String get commonClose;

  /// No description provided for @commonAdd.
  ///
  /// In th, this message translates to:
  /// **'เพิ่ม'**
  String get commonAdd;

  /// No description provided for @commonClear.
  ///
  /// In th, this message translates to:
  /// **'ล้าง'**
  String get commonClear;

  /// No description provided for @scanModeIn.
  ///
  /// In th, this message translates to:
  /// **'เข้ารอบนึ่ง'**
  String get scanModeIn;

  /// No description provided for @scanModeOut.
  ///
  /// In th, this message translates to:
  /// **'เบิกออก'**
  String get scanModeOut;

  /// No description provided for @scanModeReturn.
  ///
  /// In th, this message translates to:
  /// **'ส่งคืน'**
  String get scanModeReturn;

  /// No description provided for @scanModeReprocess.
  ///
  /// In th, this message translates to:
  /// **'Reprocess'**
  String get scanModeReprocess;

  /// No description provided for @scanTitle.
  ///
  /// In th, this message translates to:
  /// **'สแกน QR'**
  String get scanTitle;

  /// No description provided for @scanManualTooltip.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์เลขห่อเอง (กล้องใช้ไม่ได้)'**
  String get scanManualTooltip;

  /// No description provided for @scanSwitchCameraTooltip.
  ///
  /// In th, this message translates to:
  /// **'สลับกล้องหน้า/หลัง'**
  String get scanSwitchCameraTooltip;

  /// No description provided for @scanTorchTooltip.
  ///
  /// In th, this message translates to:
  /// **'ไฟฉาย'**
  String get scanTorchTooltip;

  /// No description provided for @scanSwitchCameraFailed.
  ///
  /// In th, this message translates to:
  /// **'สลับกล้องไม่ได้ (อาจมีกล้องเดียว)'**
  String get scanSwitchCameraFailed;

  /// No description provided for @scanInvalidQr.
  ///
  /// In th, this message translates to:
  /// **'QR นี้ไม่ใช่เลขห่อของระบบ'**
  String get scanInvalidQr;

  /// No description provided for @scanManualTitle.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์เลขห่อเอง'**
  String get scanManualTitle;

  /// No description provided for @scanManualHint.
  ///
  /// In th, this message translates to:
  /// **'เช่น DELIV-20260630-0007'**
  String get scanManualHint;

  /// No description provided for @scanManualHelper.
  ///
  /// In th, this message translates to:
  /// **'ใช้เมื่อกล้องสแกนไม่ได้ — ระบบจะบันทึกว่ากรอกเองไว้ตรวจสอบย้อนหลัง'**
  String get scanManualHelper;

  /// No description provided for @scanManualEmpty.
  ///
  /// In th, this message translates to:
  /// **'กรุณากรอกเลขห่อ'**
  String get scanManualEmpty;

  /// No description provided for @scanManualTooLong.
  ///
  /// In th, this message translates to:
  /// **'เลขห่อยาวเกินไป'**
  String get scanManualTooLong;

  /// No description provided for @scanManualCharset.
  ///
  /// In th, this message translates to:
  /// **'ใช้ได้เฉพาะตัวอักษร ตัวเลข และขีด (-)'**
  String get scanManualCharset;

  /// No description provided for @scanBlockExpired.
  ///
  /// In th, this message translates to:
  /// **'ห้ามใช้ — ห่อหมดอายุแล้ว'**
  String get scanBlockExpired;

  /// No description provided for @scanBlockStatus.
  ///
  /// In th, this message translates to:
  /// **'สถานะปัจจุบัน: {status} — {mode}ไม่ได้'**
  String scanBlockStatus(String status, String mode);

  /// No description provided for @scanWarnUnsterile.
  ///
  /// In th, this message translates to:
  /// **'⚠ ยังไม่ฆ่าเชื้อ — จะบันทึกเป็น \"ส่งออก (ยังไม่ฆ่าเชื้อ)\"'**
  String get scanWarnUnsterile;

  /// No description provided for @scanConfirmTitle.
  ///
  /// In th, this message translates to:
  /// **'ยืนยัน{mode}'**
  String scanConfirmTitle(String mode);

  /// No description provided for @scanConfirmCount.
  ///
  /// In th, this message translates to:
  /// **'{mode} {count} ห่อ'**
  String scanConfirmCount(String mode, int count);

  /// No description provided for @scanDestBatch.
  ///
  /// In th, this message translates to:
  /// **'รอบ {round} · {sterilizer}'**
  String scanDestBatch(String round, String sterilizer);

  /// No description provided for @scanDestDept.
  ///
  /// In th, this message translates to:
  /// **'แผนก {dept}'**
  String scanDestDept(String dept);

  /// No description provided for @scanReceiverSuffix.
  ///
  /// In th, this message translates to:
  /// **' · ผู้รับ {name}'**
  String scanReceiverSuffix(String name);

  /// No description provided for @scanDestReprocess.
  ///
  /// In th, this message translates to:
  /// **'กลับเป็น \"แพ็กแล้ว\" เพื่อเข้ารอบนึ่งใหม่'**
  String get scanDestReprocess;

  /// No description provided for @scanResultOkTitle.
  ///
  /// In th, this message translates to:
  /// **'{mode}สำเร็จ {count} ห่อ'**
  String scanResultOkTitle(String mode, int count);

  /// No description provided for @scanResultMixedTitle.
  ///
  /// In th, this message translates to:
  /// **'สำเร็จ {ok} · ไม่ผ่าน {fail} ห่อ'**
  String scanResultMixedTitle(int ok, int fail);

  /// No description provided for @scanUnknownReason.
  ///
  /// In th, this message translates to:
  /// **'ไม่ทราบสาเหตุ'**
  String get scanUnknownReason;

  /// No description provided for @scanRetryFailed.
  ///
  /// In th, this message translates to:
  /// **'ลองใหม่เฉพาะที่ไม่ผ่าน'**
  String get scanRetryFailed;

  /// No description provided for @scanClearTitle.
  ///
  /// In th, this message translates to:
  /// **'ล้างรายการที่สแกนไว้?'**
  String get scanClearTitle;

  /// No description provided for @scanClearBody.
  ///
  /// In th, this message translates to:
  /// **'จะลบห่อทั้ง {count} รายการออกจากรายการสแกน (ยังไม่กระทบข้อมูลในระบบ)'**
  String scanClearBody(int count);

  /// No description provided for @scanClearAction.
  ///
  /// In th, this message translates to:
  /// **'ล้างรายการ'**
  String get scanClearAction;

  /// No description provided for @scanCameraWebBlocked.
  ///
  /// In th, this message translates to:
  /// **'เบราว์เซอร์บล็อกกล้อง — กดไอคอนกล้อง/แม่กุญแจบนแถบที่อยู่ แล้วอนุญาต จากนั้นกดลองใหม่ (ต้องเปิดผ่าน https)'**
  String get scanCameraWebBlocked;

  /// No description provided for @scanCameraDenied.
  ///
  /// In th, this message translates to:
  /// **'ปิดสิทธิ์กล้องไว้ — เปิดที่ ตั้งค่าเครื่อง > แอป > CSSD > สิทธิ์'**
  String get scanCameraDenied;

  /// No description provided for @scanCameraNeed.
  ///
  /// In th, this message translates to:
  /// **'ต้องอนุญาตสิทธิ์กล้องเพื่อสแกน QR'**
  String get scanCameraNeed;

  /// No description provided for @scanOpenSettings.
  ///
  /// In th, this message translates to:
  /// **'เปิดตั้งค่า'**
  String get scanOpenSettings;

  /// No description provided for @scanCameraWebError.
  ///
  /// In th, this message translates to:
  /// **'เปิดกล้องไม่ได้ — ตรวจว่าเปิดผ่าน https และอนุญาตกล้องในเบราว์เซอร์ (ไอคอนแม่กุญแจบนแถบที่อยู่) แล้วกดลองใหม่'**
  String get scanCameraWebError;

  /// No description provided for @scanCameraError.
  ///
  /// In th, this message translates to:
  /// **'เปิดกล้องไม่ได้: {code}'**
  String scanCameraError(String code);

  /// No description provided for @scanCountLabel.
  ///
  /// In th, this message translates to:
  /// **'สแกนแล้ว {count} ห่อ'**
  String scanCountLabel(int count);

  /// No description provided for @scanEligibleSuffix.
  ///
  /// In th, this message translates to:
  /// **'(ผ่าน {count})'**
  String scanEligibleSuffix(int count);

  /// No description provided for @scanEmptyHint.
  ///
  /// In th, this message translates to:
  /// **'ชี้กล้องไปที่ QR code ของห่อ'**
  String get scanEmptyHint;

  /// No description provided for @scanSaving.
  ///
  /// In th, this message translates to:
  /// **'กำลังบันทึก...'**
  String get scanSaving;

  /// No description provided for @scanReprocessHint.
  ///
  /// In th, this message translates to:
  /// **'สแกนห่อที่ส่งคืนแล้ว (RETURNED) เพื่อกลับเป็น \"แพ็กแล้ว\" พร้อมเข้ารอบนึ่งใหม่'**
  String get scanReprocessHint;

  /// No description provided for @scanManualBadge.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์เอง'**
  String get scanManualBadge;

  /// No description provided for @scanDaysLeft.
  ///
  /// In th, this message translates to:
  /// **'เหลือ {days} วัน'**
  String scanDaysLeft(int days);

  /// No description provided for @batchLoadError.
  ///
  /// In th, this message translates to:
  /// **'โหลดรอบนึ่งไม่ได้: {error}'**
  String batchLoadError(String error);

  /// No description provided for @batchNonePending.
  ///
  /// In th, this message translates to:
  /// **'ยังไม่มีรอบที่รอนึ่ง — กด \"รอบใหม่\"'**
  String get batchNonePending;

  /// No description provided for @batchSelectLabel.
  ///
  /// In th, this message translates to:
  /// **'รอบนึ่ง (รอสแกนห่อ/รอบันทึกผล)'**
  String get batchSelectLabel;

  /// No description provided for @batchRoundLabel.
  ///
  /// In th, this message translates to:
  /// **'รอบ {round} · {sterilizer}'**
  String batchRoundLabel(String round, String sterilizer);

  /// No description provided for @batchPkgCountSuffix.
  ///
  /// In th, this message translates to:
  /// **' · {count} ห่อ'**
  String batchPkgCountSuffix(int count);

  /// No description provided for @batchNewButton.
  ///
  /// In th, this message translates to:
  /// **'รอบใหม่'**
  String get batchNewButton;

  /// No description provided for @batchRecordResultButton.
  ///
  /// In th, this message translates to:
  /// **'บันทึกผล CI/BI ของรอบ'**
  String get batchRecordResultButton;

  /// No description provided for @batchOpenTitle.
  ///
  /// In th, this message translates to:
  /// **'เปิดรอบนึ่งใหม่'**
  String get batchOpenTitle;

  /// No description provided for @batchOpenSubtitle.
  ///
  /// In th, this message translates to:
  /// **'เปิดรอบเพื่อสแกนห่อเข้ารอบก่อนนึ่ง — ห่อจะเข้าคลังเมื่อหัวหน้าบันทึกผล CI/BI ว่าผ่านแล้วเท่านั้น'**
  String get batchOpenSubtitle;

  /// No description provided for @batchSterilizerLabel.
  ///
  /// In th, this message translates to:
  /// **'เครื่องนึ่ง'**
  String get batchSterilizerLabel;

  /// No description provided for @batchRoundNo.
  ///
  /// In th, this message translates to:
  /// **'รอบที่'**
  String get batchRoundNo;

  /// No description provided for @batchOpenButton.
  ///
  /// In th, this message translates to:
  /// **'เปิดรอบ (รอสแกนห่อเข้ารอบ)'**
  String get batchOpenButton;

  /// No description provided for @batchConfirmPassTitle.
  ///
  /// In th, this message translates to:
  /// **'ยืนยันผล \"ผ่าน\"?'**
  String get batchConfirmPassTitle;

  /// No description provided for @batchConfirmFailTitle.
  ///
  /// In th, this message translates to:
  /// **'ยืนยันผล \"ไม่ผ่าน\"?'**
  String get batchConfirmFailTitle;

  /// No description provided for @batchConfirmPassBody.
  ///
  /// In th, this message translates to:
  /// **'ห่อทั้งหมดในรอบ {round} ({count} ห่อ) จะเปลี่ยนเป็น \"ปลอดเชื้อ\" และเข้าคลังทันที'**
  String batchConfirmPassBody(String round, String count);

  /// No description provided for @batchConfirmFailBody.
  ///
  /// In th, this message translates to:
  /// **'ห่อทั้งหมดในรอบจะถูกปลดออกจากรอบ (ต้องนึ่งใหม่) และระบบจะ recall ของจากรอบนี้ที่หมุนเวียนอยู่'**
  String get batchConfirmFailBody;

  /// No description provided for @batchRecordedPass.
  ///
  /// In th, this message translates to:
  /// **'บันทึกผลผ่าน — ห่อในรอบเข้าคลังปลอดเชื้อแล้ว'**
  String get batchRecordedPass;

  /// No description provided for @batchRecordedFail.
  ///
  /// In th, this message translates to:
  /// **'บันทึกผลไม่ผ่าน — ปลดห่อออกจากรอบและ recall แล้ว'**
  String get batchRecordedFail;

  /// No description provided for @batchRecordTitle.
  ///
  /// In th, this message translates to:
  /// **'บันทึกผลรอบนึ่ง (CI/BI)'**
  String get batchRecordTitle;

  /// No description provided for @batchRecordSubtitle.
  ///
  /// In th, this message translates to:
  /// **'ผ่าน → ห่อทั้งรอบเป็นปลอดเชื้อเข้าคลังอัตโนมัติ'**
  String get batchRecordSubtitle;

  /// No description provided for @batchSelectToRecord.
  ///
  /// In th, this message translates to:
  /// **'เลือกรอบที่จะบันทึกผล'**
  String get batchSelectToRecord;

  /// No description provided for @batchCiPass.
  ///
  /// In th, this message translates to:
  /// **'Chemical Indicator (CI) ผ่าน'**
  String get batchCiPass;

  /// No description provided for @batchBiPass.
  ///
  /// In th, this message translates to:
  /// **'Biological Indicator (BI) ผ่าน'**
  String get batchBiPass;

  /// No description provided for @batchRecordButton.
  ///
  /// In th, this message translates to:
  /// **'บันทึกผลตรวจ'**
  String get batchRecordButton;

  /// No description provided for @deptLoadError.
  ///
  /// In th, this message translates to:
  /// **'โหลดแผนกไม่ได้: {error}'**
  String deptLoadError(String error);

  /// No description provided for @deptDestRequired.
  ///
  /// In th, this message translates to:
  /// **'แผนกปลายทาง (บังคับ)'**
  String get deptDestRequired;

  /// No description provided for @deptReturnRequired.
  ///
  /// In th, this message translates to:
  /// **'แผนกที่ส่งของคืน (บังคับ)'**
  String get deptReturnRequired;

  /// No description provided for @deptAddPlace.
  ///
  /// In th, this message translates to:
  /// **'เพิ่มสถานที่'**
  String get deptAddPlace;

  /// No description provided for @deptReceiverOptional.
  ///
  /// In th, this message translates to:
  /// **'ชื่อผู้รับ (ไม่บังคับ)'**
  String get deptReceiverOptional;

  /// No description provided for @deptAddTitle.
  ///
  /// In th, this message translates to:
  /// **'เพิ่มสถานที่ปลายทาง'**
  String get deptAddTitle;

  /// No description provided for @deptAddSubtitle.
  ///
  /// In th, this message translates to:
  /// **'เช่น โรงพยาบาลอื่นที่ส่งชุดอุปกรณ์ไปให้'**
  String get deptAddSubtitle;

  /// No description provided for @deptCodeLabel.
  ///
  /// In th, this message translates to:
  /// **'รหัส (ห้ามซ้ำ)'**
  String get deptCodeLabel;

  /// No description provided for @deptCodeHint.
  ///
  /// In th, this message translates to:
  /// **'เช่น EXT-PYT'**
  String get deptCodeHint;

  /// No description provided for @deptNameLabel.
  ///
  /// In th, this message translates to:
  /// **'ชื่อสถานที่'**
  String get deptNameLabel;

  /// No description provided for @deptNameHint.
  ///
  /// In th, this message translates to:
  /// **'เช่น รพ.พญาไท'**
  String get deptNameHint;

  /// No description provided for @deptExternalTitle.
  ///
  /// In th, this message translates to:
  /// **'สถานที่ภายนอกโรงพยาบาล'**
  String get deptExternalTitle;

  /// No description provided for @deptExternalSubtitle.
  ///
  /// In th, this message translates to:
  /// **'แสดงป้าย \"(ภายนอก)\" ต่อท้ายชื่อ'**
  String get deptExternalSubtitle;

  /// No description provided for @deptSaveButton.
  ///
  /// In th, this message translates to:
  /// **'บันทึกสถานที่'**
  String get deptSaveButton;
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
