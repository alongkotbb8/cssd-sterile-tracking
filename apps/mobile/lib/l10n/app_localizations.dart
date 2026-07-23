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

  /// No description provided for @reportTitle.
  ///
  /// In th, this message translates to:
  /// **'รายงานสรุป'**
  String get reportTitle;

  /// No description provided for @reportPrintTooltip.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์รายงาน (PDF)'**
  String get reportPrintTooltip;

  /// No description provided for @reportPeriodToday.
  ///
  /// In th, this message translates to:
  /// **'วันนี้'**
  String get reportPeriodToday;

  /// No description provided for @reportPeriodWeek.
  ///
  /// In th, this message translates to:
  /// **'7 วันล่าสุด'**
  String get reportPeriodWeek;

  /// No description provided for @reportPeriodMonth.
  ///
  /// In th, this message translates to:
  /// **'เดือนนี้'**
  String get reportPeriodMonth;

  /// No description provided for @moveIn.
  ///
  /// In th, this message translates to:
  /// **'นำเข้าคลัง'**
  String get moveIn;

  /// No description provided for @moveOut.
  ///
  /// In th, this message translates to:
  /// **'เบิกออก'**
  String get moveOut;

  /// No description provided for @moveReturn.
  ///
  /// In th, this message translates to:
  /// **'ส่งคืน'**
  String get moveReturn;

  /// No description provided for @reportTotal.
  ///
  /// In th, this message translates to:
  /// **'รวม'**
  String get reportTotal;

  /// No description provided for @reportMovementsTitle.
  ///
  /// In th, this message translates to:
  /// **'รายการเคลื่อนไหว ({count})'**
  String reportMovementsTitle(int count);

  /// No description provided for @reportNoMovements.
  ///
  /// In th, this message translates to:
  /// **'ไม่มีการเคลื่อนไหวในช่วงนี้'**
  String get reportNoMovements;

  /// No description provided for @reportDeptLine.
  ///
  /// In th, this message translates to:
  /// **'แผนก {dept}'**
  String reportDeptLine(String dept);

  /// No description provided for @reportByLine.
  ///
  /// In th, this message translates to:
  /// **'โดย {name}'**
  String reportByLine(String name);

  /// No description provided for @pdfReportTitle.
  ///
  /// In th, this message translates to:
  /// **'รายงานระบบตามรอยอุปกรณ์ปลอดเชื้อ (CSSD)'**
  String get pdfReportTitle;

  /// No description provided for @pdfDateRange.
  ///
  /// In th, this message translates to:
  /// **'ช่วงวันที่ {from} – {to} · พิมพ์เมื่อ {printed}'**
  String pdfDateRange(String from, String to, String printed);

  /// No description provided for @pdfNoMovements.
  ///
  /// In th, this message translates to:
  /// **'— ไม่มีการเคลื่อนไหวในช่วงนี้ —'**
  String get pdfNoMovements;

  /// No description provided for @pdfColDatetime.
  ///
  /// In th, this message translates to:
  /// **'วัน-เวลา'**
  String get pdfColDatetime;

  /// No description provided for @pdfColType.
  ///
  /// In th, this message translates to:
  /// **'ประเภท'**
  String get pdfColType;

  /// No description provided for @pdfColPackage.
  ///
  /// In th, this message translates to:
  /// **'เลขห่อ'**
  String get pdfColPackage;

  /// No description provided for @pdfColSet.
  ///
  /// In th, this message translates to:
  /// **'ชุด'**
  String get pdfColSet;

  /// No description provided for @pdfColDept.
  ///
  /// In th, this message translates to:
  /// **'แผนก'**
  String get pdfColDept;

  /// No description provided for @pdfColUser.
  ///
  /// In th, this message translates to:
  /// **'ผู้ทำรายการ'**
  String get pdfColUser;

  /// No description provided for @pdfInspector.
  ///
  /// In th, this message translates to:
  /// **'ผู้ตรวจสอบ / หัวหน้าหน่วยจ่ายกลาง'**
  String get pdfInspector;

  /// No description provided for @pdfError.
  ///
  /// In th, this message translates to:
  /// **'สร้าง PDF ไม่สำเร็จ: {error}'**
  String pdfError(String error);

  /// No description provided for @cleanupTitle.
  ///
  /// In th, this message translates to:
  /// **'ล้างข้อมูลเก่า (ประหยัดพื้นที่)'**
  String get cleanupTitle;

  /// No description provided for @cleanupDesc.
  ///
  /// In th, this message translates to:
  /// **'หลังพิมพ์รายงานเก็บเข้าแฟ้มแล้ว สามารถลบประวัติเก่าออกจากระบบได้ โดยห่อที่ยังอยู่ในคลังและอยู่ระหว่างใช้งานจะไม่ถูกลบ'**
  String get cleanupDesc;

  /// No description provided for @cleanupButton.
  ///
  /// In th, this message translates to:
  /// **'ลบประวัติก่อนช่วงนี้'**
  String get cleanupButton;

  /// No description provided for @cleanupConfirmTitle.
  ///
  /// In th, this message translates to:
  /// **'ล้างข้อมูลเก่า?'**
  String get cleanupConfirmTitle;

  /// No description provided for @cleanupConfirmBody.
  ///
  /// In th, this message translates to:
  /// **'จะลบประวัติการเคลื่อนไหวและห่อที่ทิ้งแล้ว ที่เกิดก่อนวันที่ {date} อย่างถาวร'**
  String cleanupConfirmBody(String date);

  /// No description provided for @cleanupKeep.
  ///
  /// In th, this message translates to:
  /// **'✓ ห่อที่ยังอยู่ในคลัง/วงจร (แพ็ก·ปลอดเชื้อ·เบิกออก·รอ reprocess) จะไม่ถูกลบ'**
  String get cleanupKeep;

  /// No description provided for @cleanupIrreversible.
  ///
  /// In th, this message translates to:
  /// **'✗ ข้อมูลที่ลบแล้วกู้คืนไม่ได้ ควรพิมพ์รายงานเก็บเข้าแฟ้มก่อน'**
  String get cleanupIrreversible;

  /// No description provided for @cleanupConfirmAction.
  ///
  /// In th, this message translates to:
  /// **'ลบถาวร'**
  String get cleanupConfirmAction;

  /// No description provided for @cleanupDone.
  ///
  /// In th, this message translates to:
  /// **'ล้างข้อมูลแล้ว: ประวัติ {m} รายการ · ห่อที่ทิ้งแล้ว {p} ห่อ'**
  String cleanupDone(int m, int p);

  /// No description provided for @commonYes.
  ///
  /// In th, this message translates to:
  /// **'ใช่'**
  String get commonYes;

  /// No description provided for @pjStatusQueued.
  ///
  /// In th, this message translates to:
  /// **'รอเครื่องพิมพ์รับงาน'**
  String get pjStatusQueued;

  /// No description provided for @pjStatusClaimed.
  ///
  /// In th, this message translates to:
  /// **'เครื่องพิมพ์รับงานแล้ว'**
  String get pjStatusClaimed;

  /// No description provided for @pjStatusPrinting.
  ///
  /// In th, this message translates to:
  /// **'กำลังส่งไปเครื่องพิมพ์'**
  String get pjStatusPrinting;

  /// No description provided for @pjStatusSent.
  ///
  /// In th, this message translates to:
  /// **'ส่งข้อมูลถึงเครื่องพิมพ์แล้ว'**
  String get pjStatusSent;

  /// No description provided for @pjStatusPrinted.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์สำเร็จ'**
  String get pjStatusPrinted;

  /// No description provided for @pjStatusSimulated.
  ///
  /// In th, this message translates to:
  /// **'จำลอง (โหมดทดสอบ ไม่ใช่พิมพ์จริง)'**
  String get pjStatusSimulated;

  /// No description provided for @pjStatusFailed.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์ไม่สำเร็จ (กำลังจะลองใหม่)'**
  String get pjStatusFailed;

  /// No description provided for @pjStatusRetrying.
  ///
  /// In th, this message translates to:
  /// **'กำลังลองพิมพ์ใหม่'**
  String get pjStatusRetrying;

  /// No description provided for @pjStatusDeadLetter.
  ///
  /// In th, this message translates to:
  /// **'ล้มเหลวถาวร ต้องตรวจสอบ'**
  String get pjStatusDeadLetter;

  /// No description provided for @pjStatusAckUnknown.
  ///
  /// In th, this message translates to:
  /// **'ไม่แน่ใจว่าพิมพ์จริง — ต้องให้หัวหน้าตัดสิน'**
  String get pjStatusAckUnknown;

  /// No description provided for @pjStatusResolvedPrinted.
  ///
  /// In th, this message translates to:
  /// **'หัวหน้ายืนยันว่าพิมพ์แล้ว'**
  String get pjStatusResolvedPrinted;

  /// No description provided for @pjStatusResolvedRequeued.
  ///
  /// In th, this message translates to:
  /// **'หัวหน้าสั่งเปิดงานพิมพ์ใหม่'**
  String get pjStatusResolvedRequeued;

  /// No description provided for @pjStatusCancelled.
  ///
  /// In th, this message translates to:
  /// **'ยกเลิกแล้ว'**
  String get pjStatusCancelled;

  /// No description provided for @pjStepQueued.
  ///
  /// In th, this message translates to:
  /// **'เข้าคิว'**
  String get pjStepQueued;

  /// No description provided for @pjStepClaimed.
  ///
  /// In th, this message translates to:
  /// **'รับงาน'**
  String get pjStepClaimed;

  /// No description provided for @pjStepPrinting.
  ///
  /// In th, this message translates to:
  /// **'ส่งพิมพ์'**
  String get pjStepPrinting;

  /// No description provided for @pjStepSent.
  ///
  /// In th, this message translates to:
  /// **'ถึงเครื่อง'**
  String get pjStepSent;

  /// No description provided for @pjStepPrinted.
  ///
  /// In th, this message translates to:
  /// **'สำเร็จ'**
  String get pjStepPrinted;

  /// No description provided for @pjScopeAll.
  ///
  /// In th, this message translates to:
  /// **'ทั้งระบบ'**
  String get pjScopeAll;

  /// No description provided for @pjScopeMine.
  ///
  /// In th, this message translates to:
  /// **'ของฉัน'**
  String get pjScopeMine;

  /// No description provided for @pjPageTitle.
  ///
  /// In th, this message translates to:
  /// **'งานพิมพ์'**
  String get pjPageTitle;

  /// No description provided for @pjNone.
  ///
  /// In th, this message translates to:
  /// **'ยังไม่มีงานพิมพ์'**
  String get pjNone;

  /// No description provided for @pjScopeLine.
  ///
  /// In th, this message translates to:
  /// **'ขอบเขต: {scope}'**
  String pjScopeLine(String scope);

  /// No description provided for @pjNeedAttention.
  ///
  /// In th, this message translates to:
  /// **'ต้องดูแล {count}'**
  String pjNeedAttention(int count);

  /// No description provided for @pjCancelTitle.
  ///
  /// In th, this message translates to:
  /// **'ยกเลิกงานพิมพ์?'**
  String get pjCancelTitle;

  /// No description provided for @pjCancelBody.
  ///
  /// In th, this message translates to:
  /// **'ยกเลิกได้เฉพาะงานที่ยังไม่ถูกเครื่องพิมพ์รับไป'**
  String get pjCancelBody;

  /// No description provided for @pjCancelNo.
  ///
  /// In th, this message translates to:
  /// **'ไม่'**
  String get pjCancelNo;

  /// No description provided for @pjCancelYes.
  ///
  /// In th, this message translates to:
  /// **'ยกเลิกงาน'**
  String get pjCancelYes;

  /// No description provided for @pjResolveConfirm.
  ///
  /// In th, this message translates to:
  /// **'ยืนยันว่าพิมพ์จริงแล้ว'**
  String get pjResolveConfirm;

  /// No description provided for @pjResolveRequeue.
  ///
  /// In th, this message translates to:
  /// **'เปิดงานพิมพ์ใหม่ (ไม่ยืนยันว่าพิมพ์)'**
  String get pjResolveRequeue;

  /// No description provided for @pjResolveNote.
  ///
  /// In th, this message translates to:
  /// **'หมายเหตุการตัดสินใจ (บังคับ)'**
  String get pjResolveNote;

  /// No description provided for @pjResolveNoteHint.
  ///
  /// In th, this message translates to:
  /// **'เช่น ตรวจกับเครื่องพิมพ์แล้วพบว่า...'**
  String get pjResolveNoteHint;

  /// No description provided for @pjResolveNoteRequired.
  ///
  /// In th, this message translates to:
  /// **'ต้องระบุหมายเหตุการตัดสินใจ'**
  String get pjResolveNoteRequired;

  /// No description provided for @pjResolveDone.
  ///
  /// In th, this message translates to:
  /// **'บันทึกการตัดสินใจแล้ว'**
  String get pjResolveDone;

  /// No description provided for @pjDetailTitle.
  ///
  /// In th, this message translates to:
  /// **'สถานะงานพิมพ์'**
  String get pjDetailTitle;

  /// No description provided for @pjSimulatedBanner.
  ///
  /// In th, this message translates to:
  /// **'โหมดทดสอบ (SIMULATED) — ไม่ใช่การพิมพ์จริง ไม่นับเป็นประวัติการพิมพ์'**
  String get pjSimulatedBanner;

  /// No description provided for @pjAckBanner.
  ///
  /// In th, this message translates to:
  /// **'ไม่แน่ใจว่าพิมพ์จริงหรือไม่ — กรุณาติดต่อหัวหน้า (SUPERVISOR/ADMIN) เพื่อตรวจสอบและตัดสิน'**
  String get pjAckBanner;

  /// No description provided for @pjDeadBanner.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์ล้มเหลวครบจำนวนครั้งแล้ว — ต้องตรวจสอบเครื่องพิมพ์แล้วสั่งพิมพ์ใหม่'**
  String get pjDeadBanner;

  /// No description provided for @pjCancelButton.
  ///
  /// In th, this message translates to:
  /// **'ยกเลิกงานพิมพ์'**
  String get pjCancelButton;

  /// No description provided for @pjPackageTitle.
  ///
  /// In th, this message translates to:
  /// **'ห่อ {id}'**
  String pjPackageTitle(String id);

  /// No description provided for @pjFieldCreated.
  ///
  /// In th, this message translates to:
  /// **'สร้างเมื่อ'**
  String get pjFieldCreated;

  /// No description provided for @pjFieldPrinter.
  ///
  /// In th, this message translates to:
  /// **'เครื่องพิมพ์'**
  String get pjFieldPrinter;

  /// No description provided for @pjFieldAttempts.
  ///
  /// In th, this message translates to:
  /// **'จำนวนครั้งที่พยายาม'**
  String get pjFieldAttempts;

  /// No description provided for @pjFieldReprint.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์ซ้ำ'**
  String get pjFieldReprint;

  /// No description provided for @pjFieldReprintReason.
  ///
  /// In th, this message translates to:
  /// **'เหตุผลพิมพ์ซ้ำ'**
  String get pjFieldReprintReason;

  /// No description provided for @pjFieldErrorCode.
  ///
  /// In th, this message translates to:
  /// **'รหัสข้อผิดพลาด'**
  String get pjFieldErrorCode;

  /// No description provided for @pjFieldSentAt.
  ///
  /// In th, this message translates to:
  /// **'ส่งถึงเครื่องเมื่อ'**
  String get pjFieldSentAt;

  /// No description provided for @pjFieldPrintedAt.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์เสร็จเมื่อ'**
  String get pjFieldPrintedAt;

  /// No description provided for @pjFieldResolvedAt.
  ///
  /// In th, this message translates to:
  /// **'หัวหน้าตัดสินเมื่อ'**
  String get pjFieldResolvedAt;

  /// No description provided for @pjFieldResolutionNote.
  ///
  /// In th, this message translates to:
  /// **'หมายเหตุการตัดสิน'**
  String get pjFieldResolutionNote;

  /// No description provided for @pjResolveSectionTitle.
  ///
  /// In th, this message translates to:
  /// **'ตัดสินใจ (หัวหน้า)'**
  String get pjResolveSectionTitle;

  /// No description provided for @pjResolveSectionHint.
  ///
  /// In th, this message translates to:
  /// **'งานนี้ส่งถึงเครื่องพิมพ์แล้วแต่ยืนยันผลไม่ได้ — ตรวจกับเครื่องพิมพ์จริงก่อนตัดสิน'**
  String get pjResolveSectionHint;

  /// No description provided for @pjResolveConfirmBtn.
  ///
  /// In th, this message translates to:
  /// **'ยืนยันว่าพิมพ์แล้ว'**
  String get pjResolveConfirmBtn;

  /// No description provided for @pjResolveRequeueBtn.
  ///
  /// In th, this message translates to:
  /// **'ไม่ยืนยัน — เปิดงานพิมพ์ใหม่'**
  String get pjResolveRequeueBtn;

  /// No description provided for @pjReprintReasonRequired.
  ///
  /// In th, this message translates to:
  /// **'มีห่อที่เคยพิมพ์แล้ว — ต้องระบุเหตุผลการพิมพ์ซ้ำ'**
  String get pjReprintReasonRequired;

  /// No description provided for @pjCreatedOne.
  ///
  /// In th, this message translates to:
  /// **'สร้างงานพิมพ์แล้ว — รอเครื่องพิมพ์รับงาน'**
  String get pjCreatedOne;

  /// No description provided for @pjCreatedMany.
  ///
  /// In th, this message translates to:
  /// **'สร้างงานพิมพ์ {count} งานแล้ว'**
  String pjCreatedMany(int count);

  /// No description provided for @pjPrintLabel.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์ label'**
  String get pjPrintLabel;

  /// No description provided for @pjPrintLabelCount.
  ///
  /// In th, this message translates to:
  /// **'พิมพ์ label {count} ห่อ'**
  String pjPrintLabelCount(int count);

  /// No description provided for @pjSubmitDesc.
  ///
  /// In th, this message translates to:
  /// **'ระบบจะสร้างงานพิมพ์แล้วส่งให้เครื่องพิมพ์ (Gateway) — ติดตามสถานะได้จนพิมพ์จริง'**
  String get pjSubmitDesc;

  /// No description provided for @pjTargetPrinter.
  ///
  /// In th, this message translates to:
  /// **'เครื่องพิมพ์ปลายทาง'**
  String get pjTargetPrinter;

  /// No description provided for @pjAutoAnyPrinter.
  ///
  /// In th, this message translates to:
  /// **'อัตโนมัติ (เครื่องไหนก็ได้)'**
  String get pjAutoAnyPrinter;

  /// No description provided for @pjOfflineSuffix.
  ///
  /// In th, this message translates to:
  /// **' · ออฟไลน์'**
  String get pjOfflineSuffix;

  /// No description provided for @pjReprintReasonLabel.
  ///
  /// In th, this message translates to:
  /// **'เหตุผลการพิมพ์ซ้ำ'**
  String get pjReprintReasonLabel;

  /// No description provided for @pjReprintReasonHint.
  ///
  /// In th, this message translates to:
  /// **'เช่น label เดิมชำรุด/หลุด'**
  String get pjReprintReasonHint;

  /// No description provided for @pjCreatingProgress.
  ///
  /// In th, this message translates to:
  /// **'กำลังสร้างงาน {done}/{total}...'**
  String pjCreatingProgress(int done, int total);

  /// No description provided for @pjCreateButton.
  ///
  /// In th, this message translates to:
  /// **'สร้างงานพิมพ์'**
  String get pjCreateButton;

  /// No description provided for @pjCreateButtonCount.
  ///
  /// In th, this message translates to:
  /// **'สร้างงานพิมพ์ {count} งาน'**
  String pjCreateButtonCount(int count);

  /// No description provided for @pjAutoHint.
  ///
  /// In th, this message translates to:
  /// **'ส่งแบบอัตโนมัติ — เครื่องพิมพ์ที่ว่างจะรับงานเอง'**
  String get pjAutoHint;
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
