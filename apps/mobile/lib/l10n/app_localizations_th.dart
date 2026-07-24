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
  String get settingsLabelSize => 'ขนาดฉลาก';

  @override
  String get settingsGatewayPrimaryTitle => 'พิมพ์ผ่าน Print Gateway (XP-420B)';

  @override
  String get settingsGatewayPrimarySubtitle =>
      'งานพิมพ์ทั้งหมดส่งผ่าน Gateway → ติดตามสถานะที่แท็บ \"งานพิมพ์\"';

  @override
  String get settingsLegacyPrinterTitle => 'เครื่องพิมพ์ direct (legacy)';

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

  @override
  String get commonRetry => 'ลองใหม่';

  @override
  String get navDashboard => 'แดชบอร์ด';

  @override
  String get navScan => 'สแกน';

  @override
  String get navPackages => 'รายการ';

  @override
  String get navPrintJobs => 'งานพิมพ์';

  @override
  String get navSettings => 'ตั้งค่า';

  @override
  String get deptExternalSuffix => ' (ภายนอก)';

  @override
  String get errLoginInvalid => 'รหัสพนักงานหรือรหัสผ่านไม่ถูกต้อง';

  @override
  String get errTimeout => 'เชื่อมต่อ server ไม่ทัน กรุณาลองใหม่';

  @override
  String get errConnection =>
      'เชื่อมต่อ server ไม่ได้ ตรวจสอบที่อยู่ server ในหน้าตั้งค่า';

  @override
  String errGeneric(String code) {
    return 'เกิดข้อผิดพลาด ($code)';
  }

  @override
  String get errUnknown => 'เกิดข้อผิดพลาดไม่ทราบสาเหตุ';

  @override
  String get srvAuthRateLimited =>
      'พยายามเข้าสู่ระบบบ่อยเกินไป กรุณาลองใหม่อีกครั้งภายหลัง';

  @override
  String get srvAuthLocked =>
      'บัญชีถูกล็อกชั่วคราวจากการใส่รหัสผิดหลายครั้ง — กรุณาลองใหม่ภายหลัง';

  @override
  String get srvPkgNotFound => 'ไม่พบห่อ';

  @override
  String get srvPkgIdInvalid => 'รูปแบบเลขห่อไม่ถูกต้อง';

  @override
  String get srvRunningNumberFailed => 'ออกเลขรันไม่สำเร็จ กรุณาลองใหม่';

  @override
  String get srvDeptDuplicate => 'รหัสแผนก/สถานที่นี้มีอยู่แล้ว';

  @override
  String get srvTagDuplicate => 'มีแท็กชื่อนี้อยู่แล้ว';

  @override
  String get srvTemplateDuplicate => 'รหัสชุดอุปกรณ์นี้มีอยู่แล้ว';

  @override
  String get srvCleanupDateInvalid => 'วันที่ตัดข้อมูลต้องเป็นอดีตเท่านั้น';

  @override
  String get srvIdempotencyConflict =>
      'คำขอนี้ถูกส่งซ้ำ — โหลดใหม่แล้วลองอีกครั้ง';

  @override
  String get srvBrowserPrintDisabled => 'โหมดพิมพ์ผ่านเบราว์เซอร์ถูกปิดใช้งาน';

  @override
  String get srvBrowserPrintNotFound => 'ไม่พบคำขอพิมพ์ผ่านเบราว์เซอร์นี้';

  @override
  String get srvBrowserPrintForbidden => 'ไม่มีสิทธิ์เข้าถึงคำขอพิมพ์นี้';

  @override
  String get srvBrowserPrintState =>
      'สถานะคำขอพิมพ์ไม่ถูกต้องสำหรับการดำเนินการนี้';

  @override
  String get srvBrowserPrintReprintReasonRequired =>
      'ห่อนี้เคยสั่งพิมพ์แล้ว ต้องระบุเหตุผลการพิมพ์ซ้ำ';

  @override
  String get srvBrowserPrintRateLimited =>
      'สั่งพิมพ์บ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่';

  @override
  String get srvPkgWrongStatus => 'สถานะห่อไม่ถูกต้องสำหรับการดำเนินการนี้';

  @override
  String get srvPkgAlreadyInThisBatch => 'ห่อนี้อยู่ในรอบนี้แล้ว';

  @override
  String get srvPkgInOtherBatch => 'ห่อนี้อยู่ในรอบนึ่งอื่นอยู่แล้ว';

  @override
  String get srvPkgConcurrent => 'ห่อนี้ถูกดำเนินการไปพร้อมกันจากที่อื่นแล้ว';

  @override
  String get srvPkgExpired => '⛔ ห้ามใช้ — ห่อหมดอายุแล้ว';

  @override
  String get srvPkgUnsterileExternalOnly =>
      'ห่อนี้ยังไม่ผ่านการฆ่าเชื้อ — ส่งออกได้เฉพาะปลายทางภายนอก (external) เท่านั้น';

  @override
  String get srvPkgDiscarded => 'ห่อนี้ถูกทิ้งไปแล้ว';

  @override
  String get srvReprintReasonRequired =>
      'ห่อนี้เคยพิมพ์แล้ว ต้องระบุเหตุผลการพิมพ์ซ้ำ';

  @override
  String get srvBatchNotFound => 'ไม่พบรอบนึ่ง';

  @override
  String get srvBatchDuplicate => 'มีรอบนึ่งนี้อยู่แล้ว (เครื่อง/วัน/รอบซ้ำ)';

  @override
  String get srvBatchAlreadyResulted => 'รอบนึ่งนี้บันทึกผลไปแล้ว';

  @override
  String get srvBatchState => 'สถานะรอบนึ่งไม่ถูกต้องสำหรับการดำเนินการนี้';

  @override
  String get srvSterilizerNotFound => 'ไม่พบเครื่องนึ่งที่ระบุ';

  @override
  String get srvTemplateNotFound => 'ไม่พบชุดอุปกรณ์ที่ระบุ';

  @override
  String get srvDeptNotFound => 'ไม่พบแผนกที่ระบุ';

  @override
  String get srvPrintJobNotFound => 'ไม่พบงานพิมพ์';

  @override
  String get srvPrintJobForbidden => 'ไม่มีสิทธิ์ดำเนินการกับงานพิมพ์นี้';

  @override
  String get srvPrintJobState =>
      'สถานะงานพิมพ์เปลี่ยนไปแล้ว — โหลดใหม่แล้วลองอีกครั้ง';

  @override
  String get srvPrintJobNoteRequired => 'ต้องระบุหมายเหตุการตัดสินใจ';

  @override
  String get srvGatewayNotFound => 'ไม่พบ gateway';

  @override
  String get srvGatewayRevoked => 'gateway นี้ถูกเพิกถอนแล้ว';

  @override
  String get srvGatewayConfig => 'ค่าตั้ง gateway ไม่ถูกต้อง';

  @override
  String get srvPrinterNotFound => 'ไม่พบเครื่องพิมพ์ที่ระบุ';

  @override
  String get urlErrFormat =>
      'รูปแบบ URL ไม่ถูกต้อง (ต้องขึ้นต้นด้วย http:// หรือ https://)';

  @override
  String urlErrAllowlist(String hosts) {
    return 'production ต้องชี้ไปเซิร์ฟเวอร์ที่อนุมัติเท่านั้น ($hosts)';
  }

  @override
  String get urlErrHttpsOnly =>
      'production ต้องใช้ https:// เท่านั้น (http:// ใช้ไม่ได้แม้เป็น LAN)';

  @override
  String get urlErrExternalHttps =>
      'server ภายนอกต้องใช้ https:// (http:// ใช้ได้เฉพาะ localhost/LAN ตอน dev)';

  @override
  String get fcmChannelName => 'แจ้งเตือน CSSD';

  @override
  String get fcmChannelDesc => 'แจ้งเตือนใกล้หมดอายุและสรุปประจำวัน';

  @override
  String get commonSelectAll => 'เลือกทั้งหมด';

  @override
  String get commonClearAll => 'ล้างทั้งหมด';

  @override
  String get statusPacked => 'แพ็กแล้ว';

  @override
  String get statusPackedOut => 'ส่งออกไม่ฆ่าเชื้อ';

  @override
  String get statusSterile => 'ปลอดเชื้อ';

  @override
  String get statusIssued => 'เบิกออก';

  @override
  String get statusReturned => 'รอ Reprocess';

  @override
  String get statusExpired => 'หมดอายุ';

  @override
  String get statusDiscarded => 'ทิ้ง/ชำรุด';

  @override
  String get filterAll => 'ทั้งหมด';

  @override
  String get dmQrForScan => 'QR สำหรับสแกน';

  @override
  String get dmWrapSeal => 'ห่อซีล · 180 วัน';

  @override
  String get dmWrapCloth => 'ห่อผ้า · 7 วัน';

  @override
  String get dmDaysShort => 'วัน';

  @override
  String get brandTagline => 'ระบบตามรอยอุปกรณ์หัตถการปลอดเชื้อ (CSSD)';

  @override
  String get loginTitle => 'เข้าสู่ระบบ';

  @override
  String get loginSubtitle => 'ใช้รหัสพนักงานที่ได้รับจากผู้ดูแลระบบ';

  @override
  String get loginEmployeeCode => 'รหัสพนักงาน';

  @override
  String get loginEmployeeCodeRequired => 'กรอกรหัสพนักงาน';

  @override
  String get loginPassword => 'รหัสผ่าน';

  @override
  String get loginPasswordRequired => 'กรอกรหัสผ่าน';

  @override
  String get loginSubmit => 'เข้าสู่ระบบ';

  @override
  String get dashTitle => 'แดชบอร์ด';

  @override
  String dashGreeting(String name) {
    return 'สวัสดี $name';
  }

  @override
  String get dashReportTooltip => 'รายงานสรุป / พิมพ์';

  @override
  String get dashSterileStockTitle => 'คงเหลือปลอดเชื้อ (แยกตามชุด)';

  @override
  String get dashSterileStockCenter => 'ห่อพร้อมใช้';

  @override
  String get dashIssuedByDeptTitle => 'เบิกแยกตามแผนก (30 วัน)';

  @override
  String get dashIssuedCenter => 'ครั้งที่เบิก';

  @override
  String get dashExpiringSoon => 'ใกล้หมดอายุ';

  @override
  String get dashNoData => 'ยังไม่มีข้อมูล';

  @override
  String get cpCreatedOne => 'สร้างห่อสำเร็จ';

  @override
  String cpCreatedMany(int count) {
    return 'สร้าง $count ห่อสำเร็จ';
  }

  @override
  String cpPrintAll(int count) {
    return 'พิมพ์ทั้งหมด ($count)';
  }

  @override
  String cpPrintSentOne(String printer) {
    return 'ส่งพิมพ์ไปยัง $printer แล้ว';
  }

  @override
  String cpPrintSentMany(int ok, String printer) {
    return 'ส่งพิมพ์ $ok label ไปยัง $printer แล้ว';
  }

  @override
  String get cpPrintFailed => 'พิมพ์ไม่สำเร็จ ตรวจสอบเครื่องพิมพ์';

  @override
  String get cpTitle => 'สร้างห่อใหม่';

  @override
  String get cpSubtitle => 'ระบบจะออกเลขรันให้อัตโนมัติเมื่อบันทึก';

  @override
  String get cpSetLabel => 'ชุดอุปกรณ์';

  @override
  String get cpNewSet => 'ชุดใหม่';

  @override
  String get cpWrapType => 'ชนิดห่อ';

  @override
  String get cpQuantity => 'จำนวน';

  @override
  String get cpMaxQty => 'สร้างได้สูงสุด 50 ห่อต่อครั้ง';

  @override
  String get cpNotes => 'หมายเหตุ (ไม่บังคับ)';

  @override
  String cpSavingProgress(int done, int total) {
    return 'กำลังสร้าง $done/$total...';
  }

  @override
  String get cpSaveOne => 'บันทึก + ออกเลขรัน';

  @override
  String cpSaveMany(int count) {
    return 'บันทึก $count ห่อ + ออกเลขรัน';
  }

  @override
  String get ctTitle => 'สร้างชุดอุปกรณ์ใหม่';

  @override
  String get ctSubtitle => 'ระบุว่าในอุปกรณ์ 1 ชุดมีอะไรบ้าง';

  @override
  String get ctCode => 'รหัสชุด (ใช้ขึ้นต้นเลขรัน)';

  @override
  String get ctCodeHint => 'เช่น DELIV';

  @override
  String get ctName => 'ชื่อชุดอุปกรณ์';

  @override
  String get ctNameHint => 'เช่น ชุดทำคลอด';

  @override
  String get ctDefaultWrap => 'ชนิดห่อเริ่มต้น';

  @override
  String get ctItems => 'รายการอุปกรณ์ในชุด';

  @override
  String ctItemN(int n) {
    return 'อุปกรณ์ชิ้นที่ $n';
  }

  @override
  String get ctAddItem => 'เพิ่มรายการอุปกรณ์';

  @override
  String get ctValidationError =>
      'กรอกรหัส ชื่อชุด และรายการอุปกรณ์อย่างน้อย 1 รายการ';

  @override
  String get ctSave => 'บันทึกชุดอุปกรณ์';

  @override
  String get commonEdit => 'แก้ไข';

  @override
  String get pdReprintTooltip => 'พิมพ์ label ซ้ำ';

  @override
  String get pdExpiredDetail => 'นำกลับไป reprocess ที่หน่วยจ่ายกลางเท่านั้น';

  @override
  String get pdStepPacked => 'แพ็ก';

  @override
  String get pdStepSterile => 'ปลอดเชื้อ';

  @override
  String get pdStepIssued => 'เบิกออก';

  @override
  String get pdStepReturned => 'ส่งคืน';

  @override
  String get pdPackedOutTitle => 'ส่งออกโดยยังไม่ฆ่าเชื้อ';

  @override
  String pdLocationNotReturned(String location) {
    return 'อยู่ที่ $location · ยังไม่คืนคลัง';
  }

  @override
  String get pdNotReturned => 'ยังไม่คืนคลัง';

  @override
  String get pdPackedOutHint =>
      'เมื่อสแกนรับคืน สถานะจะกลับเป็น \"แพ็กแล้ว\" พร้อมเข้ารอบนึ่งต่อ';

  @override
  String get pdLifecycleTitle => 'วงจรชีวิต';

  @override
  String get pdTerminalExpired => 'สถานะปัจจุบัน: หมดอายุ — ห้ามใช้';

  @override
  String get pdTerminalDiscarded => 'สถานะปัจจุบัน: ทิ้ง/ชำรุด';

  @override
  String get pdFieldSterilizeDate => 'วันที่นึ่ง';

  @override
  String get pdFieldExpiryDate => 'วันหมดอายุ';

  @override
  String get pdFieldDaysLeft => 'เหลืออีก';

  @override
  String pdDaysValue(int days) {
    return '$days วัน';
  }

  @override
  String get pdFieldBatch => 'รอบนึ่ง';

  @override
  String pdReprintSuffix(int count) {
    return ' · พิมพ์ซ้ำ $count ครั้ง';
  }

  @override
  String get pdFieldNotes => 'หมายเหตุ';

  @override
  String get pdInfoTitle => 'ข้อมูลห่อ';

  @override
  String get pdTagsTitle => 'ป้ายกำกับ';

  @override
  String get pdNoTags => 'ยังไม่มีป้ายกำกับ';

  @override
  String get pdEditTagsTitle => 'ป้ายกำกับของห่อ';

  @override
  String get pdEditTagsSubtitle =>
      'เลือกป้ายที่ต้องการให้ห่อนี้มี (แตะเพื่อเปิด/ปิด)';

  @override
  String get pdNoTagsInSystem =>
      'ยังไม่มีป้ายในระบบ — เพิ่มได้ที่เมนูข้อมูลตั้งต้น (SUPERVISOR/ADMIN)';

  @override
  String get pdSaveTags => 'บันทึกป้ายกำกับ';

  @override
  String get pdMoveIn => 'สแกนเข้าคลังปลอดเชื้อ';

  @override
  String get pdHistoryTitle => 'ประวัติการเคลื่อนไหว';

  @override
  String get pdNoHistory => 'ยังไม่มีการเคลื่อนไหว';

  @override
  String pdMoveDept(String dept) {
    return 'แผนก: $dept';
  }

  @override
  String pdMoveReceiver(String name) {
    return 'ผู้รับ: $name';
  }

  @override
  String pdMoveBy(String name) {
    return 'โดย: $name';
  }

  @override
  String get pkgListTitle => 'รายการห่อ';

  @override
  String pkgSelectedCount(int count) {
    return 'เลือก $count ห่อ';
  }

  @override
  String get pkgSelectToPrintTooltip => 'เลือกเพื่อพิมพ์หลายใบ';

  @override
  String get pkgCreateNew => 'สร้างห่อใหม่';

  @override
  String get pkgSelectToPrintHint => 'เลือกห่อเพื่อพิมพ์';

  @override
  String pkgPrintSelected(int count) {
    return 'พิมพ์ที่เลือก ($count)';
  }

  @override
  String get pkgSearchHint => 'ค้นหาเลขรัน / ชื่อชุด';

  @override
  String get pkgTagAll => 'ทุกป้าย';

  @override
  String get pkgNoneFound => 'ไม่พบห่อในเงื่อนไขนี้';

  @override
  String pkgSelectedOf(int selected, int total) {
    return 'เลือกแล้ว $selected/$total';
  }

  @override
  String pkgExpiryOn(String date) {
    return 'หมดอายุ $date';
  }

  @override
  String pkgLocationAt(String location) {
    return 'อยู่ที่ $location';
  }

  @override
  String get commonConfirm => 'ยืนยัน';

  @override
  String get commonClose => 'ปิด';

  @override
  String get commonAdd => 'เพิ่ม';

  @override
  String get commonClear => 'ล้าง';

  @override
  String get scanModeIn => 'เข้ารอบนึ่ง';

  @override
  String get scanModeOut => 'เบิกออก';

  @override
  String get scanModeReturn => 'ส่งคืน';

  @override
  String get scanModeReprocess => 'Reprocess';

  @override
  String get scanTitle => 'สแกน QR';

  @override
  String get scanManualTooltip => 'พิมพ์เลขห่อเอง (กล้องใช้ไม่ได้)';

  @override
  String get scanSwitchCameraTooltip => 'สลับกล้องหน้า/หลัง';

  @override
  String get scanTorchTooltip => 'ไฟฉาย';

  @override
  String get scanSwitchCameraFailed => 'สลับกล้องไม่ได้ (อาจมีกล้องเดียว)';

  @override
  String get scanInvalidQr => 'QR นี้ไม่ใช่เลขห่อของระบบ';

  @override
  String get scanManualTitle => 'พิมพ์เลขห่อเอง';

  @override
  String get scanManualHint => 'เช่น DELIV-20260630-0007';

  @override
  String get scanManualHelper =>
      'ใช้เมื่อกล้องสแกนไม่ได้ — ระบบจะบันทึกว่ากรอกเองไว้ตรวจสอบย้อนหลัง';

  @override
  String get scanManualEmpty => 'กรุณากรอกเลขห่อ';

  @override
  String get scanManualTooLong => 'เลขห่อยาวเกินไป';

  @override
  String get scanManualCharset => 'ใช้ได้เฉพาะตัวอักษร ตัวเลข และขีด (-)';

  @override
  String get scanBlockExpired => 'ห้ามใช้ — ห่อหมดอายุแล้ว';

  @override
  String scanBlockStatus(String status, String mode) {
    return 'สถานะปัจจุบัน: $status — $modeไม่ได้';
  }

  @override
  String get scanWarnUnsterile =>
      '⚠ ยังไม่ฆ่าเชื้อ — จะบันทึกเป็น \"ส่งออก (ยังไม่ฆ่าเชื้อ)\"';

  @override
  String scanConfirmTitle(String mode) {
    return 'ยืนยัน$mode';
  }

  @override
  String scanConfirmCount(String mode, int count) {
    return '$mode $count ห่อ';
  }

  @override
  String scanDestBatch(String round, String sterilizer) {
    return 'รอบ $round · $sterilizer';
  }

  @override
  String scanDestDept(String dept) {
    return 'แผนก $dept';
  }

  @override
  String scanReceiverSuffix(String name) {
    return ' · ผู้รับ $name';
  }

  @override
  String get scanDestReprocess => 'กลับเป็น \"แพ็กแล้ว\" เพื่อเข้ารอบนึ่งใหม่';

  @override
  String scanResultOkTitle(String mode, int count) {
    return '$modeสำเร็จ $count ห่อ';
  }

  @override
  String scanResultMixedTitle(int ok, int fail) {
    return 'สำเร็จ $ok · ไม่ผ่าน $fail ห่อ';
  }

  @override
  String get scanUnknownReason => 'ไม่ทราบสาเหตุ';

  @override
  String get scanRetryFailed => 'ลองใหม่เฉพาะที่ไม่ผ่าน';

  @override
  String get scanClearTitle => 'ล้างรายการที่สแกนไว้?';

  @override
  String scanClearBody(int count) {
    return 'จะลบห่อทั้ง $count รายการออกจากรายการสแกน (ยังไม่กระทบข้อมูลในระบบ)';
  }

  @override
  String get scanClearAction => 'ล้างรายการ';

  @override
  String get scanCameraWebBlocked =>
      'เบราว์เซอร์บล็อกกล้อง — กดไอคอนกล้อง/แม่กุญแจบนแถบที่อยู่ แล้วอนุญาต จากนั้นกดลองใหม่ (ต้องเปิดผ่าน https)';

  @override
  String get scanCameraDenied =>
      'ปิดสิทธิ์กล้องไว้ — เปิดที่ ตั้งค่าเครื่อง > แอป > CSSD > สิทธิ์';

  @override
  String get scanCameraNeed => 'ต้องอนุญาตสิทธิ์กล้องเพื่อสแกน QR';

  @override
  String get scanOpenSettings => 'เปิดตั้งค่า';

  @override
  String get scanCameraWebError =>
      'เปิดกล้องไม่ได้ — ตรวจว่าเปิดผ่าน https และอนุญาตกล้องในเบราว์เซอร์ (ไอคอนแม่กุญแจบนแถบที่อยู่) แล้วกดลองใหม่';

  @override
  String scanCameraError(String code) {
    return 'เปิดกล้องไม่ได้: $code';
  }

  @override
  String get scanErrPermissionDenied =>
      'ต้องอนุญาตสิทธิ์กล้องเพื่อสแกน QR — กดอนุญาตเมื่อเบราว์เซอร์ถาม แล้วลองใหม่';

  @override
  String get scanErrPermissionRevoked =>
      'สิทธิ์กล้องถูกปิดระหว่างใช้งาน — เปิดสิทธิ์กล้องอีกครั้ง (ไอคอนกล้อง/แม่กุญแจบนแถบที่อยู่บน Safari) แล้วลองใหม่';

  @override
  String get scanErrInsecureContext =>
      'กล้องใช้ได้เฉพาะเมื่อเปิดผ่าน https เท่านั้น — เปิดหน้าเว็บผ่าน https แล้วลองใหม่';

  @override
  String get scanErrNoCamera =>
      'ไม่พบกล้องบนอุปกรณ์นี้ — ใช้การพิมพ์เลขห่อเองแทนได้';

  @override
  String get scanErrCameraInUse =>
      'กล้องถูกแอปอื่นใช้งานอยู่ — ปิดแอปที่ใช้กล้อง แล้วลองใหม่';

  @override
  String get scanErrUnsupportedConstraint =>
      'อุปกรณ์นี้ไม่รองรับค่ากล้องที่ตั้งไว้ — ลองสลับกล้อง หรือพิมพ์เลขห่อเอง';

  @override
  String get scanErrGeneric => 'เปิดกล้องไม่ได้ — ลองใหม่ หรือพิมพ์เลขห่อเอง';

  @override
  String get scanStateInitializing => 'กำลังเปิดกล้อง…';

  @override
  String get scanTorchFailed => 'เปิด/ปิดไฟฉายไม่ได้บนอุปกรณ์นี้';

  @override
  String scanCountLabel(int count) {
    return 'สแกนแล้ว $count ห่อ';
  }

  @override
  String scanEligibleSuffix(int count) {
    return '(ผ่าน $count)';
  }

  @override
  String get scanEmptyHint => 'ชี้กล้องไปที่ QR code ของห่อ';

  @override
  String get scanSaving => 'กำลังบันทึก...';

  @override
  String get scanReprocessHint =>
      'สแกนห่อที่ส่งคืนแล้ว (RETURNED) เพื่อกลับเป็น \"แพ็กแล้ว\" พร้อมเข้ารอบนึ่งใหม่';

  @override
  String get scanManualBadge => 'พิมพ์เอง';

  @override
  String scanDaysLeft(int days) {
    return 'เหลือ $days วัน';
  }

  @override
  String batchLoadError(String error) {
    return 'โหลดรอบนึ่งไม่ได้: $error';
  }

  @override
  String get batchNonePending => 'ยังไม่มีรอบที่รอนึ่ง — กด \"รอบใหม่\"';

  @override
  String get batchSelectLabel => 'รอบนึ่ง (รอสแกนห่อ/รอบันทึกผล)';

  @override
  String batchRoundLabel(String round, String sterilizer) {
    return 'รอบ $round · $sterilizer';
  }

  @override
  String batchPkgCountSuffix(int count) {
    return ' · $count ห่อ';
  }

  @override
  String get batchNewButton => 'รอบใหม่';

  @override
  String get batchRecordResultButton => 'บันทึกผล CI/BI ของรอบ';

  @override
  String get batchOpenTitle => 'เปิดรอบนึ่งใหม่';

  @override
  String get batchOpenSubtitle =>
      'เปิดรอบเพื่อสแกนห่อเข้ารอบก่อนนึ่ง — ห่อจะเข้าคลังเมื่อหัวหน้าบันทึกผล CI/BI ว่าผ่านแล้วเท่านั้น';

  @override
  String get batchSterilizerLabel => 'เครื่องนึ่ง';

  @override
  String get batchRoundNo => 'รอบที่';

  @override
  String get batchOpenButton => 'เปิดรอบ (รอสแกนห่อเข้ารอบ)';

  @override
  String get batchConfirmPassTitle => 'ยืนยันผล \"ผ่าน\"?';

  @override
  String get batchConfirmFailTitle => 'ยืนยันผล \"ไม่ผ่าน\"?';

  @override
  String batchConfirmPassBody(String round, String count) {
    return 'ห่อทั้งหมดในรอบ $round ($count ห่อ) จะเปลี่ยนเป็น \"ปลอดเชื้อ\" และเข้าคลังทันที';
  }

  @override
  String get batchConfirmFailBody =>
      'ห่อทั้งหมดในรอบจะถูกปลดออกจากรอบ (ต้องนึ่งใหม่) และระบบจะ recall ของจากรอบนี้ที่หมุนเวียนอยู่';

  @override
  String get batchRecordedPass =>
      'บันทึกผลผ่าน — ห่อในรอบเข้าคลังปลอดเชื้อแล้ว';

  @override
  String get batchRecordedFail =>
      'บันทึกผลไม่ผ่าน — ปลดห่อออกจากรอบและ recall แล้ว';

  @override
  String get batchRecordTitle => 'บันทึกผลรอบนึ่ง (CI/BI)';

  @override
  String get batchRecordSubtitle =>
      'ผ่าน → ห่อทั้งรอบเป็นปลอดเชื้อเข้าคลังอัตโนมัติ';

  @override
  String get batchSelectToRecord => 'เลือกรอบที่จะบันทึกผล';

  @override
  String get batchCiPass => 'Chemical Indicator (CI) ผ่าน';

  @override
  String get batchBiPass => 'Biological Indicator (BI) ผ่าน';

  @override
  String get batchRecordButton => 'บันทึกผลตรวจ';

  @override
  String deptLoadError(String error) {
    return 'โหลดแผนกไม่ได้: $error';
  }

  @override
  String get deptDestRequired => 'แผนกปลายทาง (บังคับ)';

  @override
  String get deptReturnRequired => 'แผนกที่ส่งของคืน (บังคับ)';

  @override
  String get deptAddPlace => 'เพิ่มสถานที่';

  @override
  String get deptReceiverOptional => 'ชื่อผู้รับ (ไม่บังคับ)';

  @override
  String get deptAddTitle => 'เพิ่มสถานที่ปลายทาง';

  @override
  String get deptAddSubtitle => 'เช่น โรงพยาบาลอื่นที่ส่งชุดอุปกรณ์ไปให้';

  @override
  String get deptCodeLabel => 'รหัส (ห้ามซ้ำ)';

  @override
  String get deptCodeHint => 'เช่น EXT-PYT';

  @override
  String get deptNameLabel => 'ชื่อสถานที่';

  @override
  String get deptNameHint => 'เช่น รพ.พญาไท';

  @override
  String get deptExternalTitle => 'สถานที่ภายนอกโรงพยาบาล';

  @override
  String get deptExternalSubtitle => 'แสดงป้าย \"(ภายนอก)\" ต่อท้ายชื่อ';

  @override
  String get deptSaveButton => 'บันทึกสถานที่';

  @override
  String get reportTitle => 'รายงานสรุป';

  @override
  String get reportPrintTooltip => 'พิมพ์รายงาน (PDF)';

  @override
  String get reportPeriodToday => 'วันนี้';

  @override
  String get reportPeriodWeek => '7 วันล่าสุด';

  @override
  String get reportPeriodMonth => 'เดือนนี้';

  @override
  String get moveIn => 'นำเข้าคลัง';

  @override
  String get moveOut => 'เบิกออก';

  @override
  String get moveReturn => 'ส่งคืน';

  @override
  String get reportTotal => 'รวม';

  @override
  String reportMovementsTitle(int count) {
    return 'รายการเคลื่อนไหว ($count)';
  }

  @override
  String get reportNoMovements => 'ไม่มีการเคลื่อนไหวในช่วงนี้';

  @override
  String reportDeptLine(String dept) {
    return 'แผนก $dept';
  }

  @override
  String reportByLine(String name) {
    return 'โดย $name';
  }

  @override
  String get pdfReportTitle => 'รายงานระบบตามรอยอุปกรณ์ปลอดเชื้อ (CSSD)';

  @override
  String pdfDateRange(String from, String to, String printed) {
    return 'ช่วงวันที่ $from – $to · พิมพ์เมื่อ $printed';
  }

  @override
  String get pdfNoMovements => '— ไม่มีการเคลื่อนไหวในช่วงนี้ —';

  @override
  String get pdfColDatetime => 'วัน-เวลา';

  @override
  String get pdfColType => 'ประเภท';

  @override
  String get pdfColPackage => 'เลขห่อ';

  @override
  String get pdfColSet => 'ชุด';

  @override
  String get pdfColDept => 'แผนก';

  @override
  String get pdfColUser => 'ผู้ทำรายการ';

  @override
  String get pdfInspector => 'ผู้ตรวจสอบ / หัวหน้าหน่วยจ่ายกลาง';

  @override
  String pdfError(String error) {
    return 'สร้าง PDF ไม่สำเร็จ: $error';
  }

  @override
  String get cleanupTitle => 'ล้างข้อมูลเก่า (ประหยัดพื้นที่)';

  @override
  String get cleanupDesc =>
      'หลังพิมพ์รายงานเก็บเข้าแฟ้มแล้ว สามารถลบประวัติเก่าออกจากระบบได้ โดยห่อที่ยังอยู่ในคลังและอยู่ระหว่างใช้งานจะไม่ถูกลบ';

  @override
  String get cleanupButton => 'ลบประวัติก่อนช่วงนี้';

  @override
  String get cleanupConfirmTitle => 'ล้างข้อมูลเก่า?';

  @override
  String cleanupConfirmBody(String date) {
    return 'จะลบประวัติการเคลื่อนไหวและห่อที่ทิ้งแล้ว ที่เกิดก่อนวันที่ $date อย่างถาวร';
  }

  @override
  String get cleanupKeep =>
      '✓ ห่อที่ยังอยู่ในคลัง/วงจร (แพ็ก·ปลอดเชื้อ·เบิกออก·รอ reprocess) จะไม่ถูกลบ';

  @override
  String get cleanupIrreversible =>
      '✗ ข้อมูลที่ลบแล้วกู้คืนไม่ได้ ควรพิมพ์รายงานเก็บเข้าแฟ้มก่อน';

  @override
  String get cleanupConfirmAction => 'ลบถาวร';

  @override
  String cleanupDone(int m, int p) {
    return 'ล้างข้อมูลแล้ว: ประวัติ $m รายการ · ห่อที่ทิ้งแล้ว $p ห่อ';
  }

  @override
  String get commonYes => 'ใช่';

  @override
  String get pjStatusQueued => 'รอเครื่องพิมพ์รับงาน';

  @override
  String get pjStatusClaimed => 'เครื่องพิมพ์รับงานแล้ว';

  @override
  String get pjStatusPrinting => 'กำลังส่งไปเครื่องพิมพ์';

  @override
  String get pjStatusSent => 'ส่งข้อมูลถึงเครื่องพิมพ์แล้ว';

  @override
  String get pjStatusPrinted => 'พิมพ์สำเร็จ';

  @override
  String get pjStatusSimulated => 'จำลอง (โหมดทดสอบ ไม่ใช่พิมพ์จริง)';

  @override
  String get pjStatusFailed => 'พิมพ์ไม่สำเร็จ (กำลังจะลองใหม่)';

  @override
  String get pjStatusRetrying => 'กำลังลองพิมพ์ใหม่';

  @override
  String get pjStatusDeadLetter => 'ล้มเหลวถาวร ต้องตรวจสอบ';

  @override
  String get pjStatusAckUnknown =>
      'ไม่แน่ใจว่าพิมพ์จริง — ต้องให้หัวหน้าตัดสิน';

  @override
  String get pjStatusResolvedPrinted => 'หัวหน้ายืนยันว่าพิมพ์แล้ว';

  @override
  String get pjStatusResolvedRequeued => 'หัวหน้าสั่งเปิดงานพิมพ์ใหม่';

  @override
  String get pjStatusCancelled => 'ยกเลิกแล้ว';

  @override
  String get pjStepQueued => 'เข้าคิว';

  @override
  String get pjStepClaimed => 'รับงาน';

  @override
  String get pjStepPrinting => 'ส่งพิมพ์';

  @override
  String get pjStepSent => 'ถึงเครื่อง';

  @override
  String get pjStepPrinted => 'สำเร็จ';

  @override
  String get pjScopeAll => 'ทั้งระบบ';

  @override
  String get pjScopeMine => 'ของฉัน';

  @override
  String get pjPageTitle => 'งานพิมพ์';

  @override
  String get pjNone => 'ยังไม่มีงานพิมพ์';

  @override
  String pjScopeLine(String scope) {
    return 'ขอบเขต: $scope';
  }

  @override
  String pjNeedAttention(int count) {
    return 'ต้องดูแล $count';
  }

  @override
  String get pjCancelTitle => 'ยกเลิกงานพิมพ์?';

  @override
  String get pjCancelBody => 'ยกเลิกได้เฉพาะงานที่ยังไม่ถูกเครื่องพิมพ์รับไป';

  @override
  String get pjCancelNo => 'ไม่';

  @override
  String get pjCancelYes => 'ยกเลิกงาน';

  @override
  String get pjResolveConfirm => 'ยืนยันว่าพิมพ์จริงแล้ว';

  @override
  String get pjResolveRequeue => 'เปิดงานพิมพ์ใหม่ (ไม่ยืนยันว่าพิมพ์)';

  @override
  String get pjResolveNote => 'หมายเหตุการตัดสินใจ (บังคับ)';

  @override
  String get pjResolveNoteHint => 'เช่น ตรวจกับเครื่องพิมพ์แล้วพบว่า...';

  @override
  String get pjResolveNoteRequired => 'ต้องระบุหมายเหตุการตัดสินใจ';

  @override
  String get pjResolveDone => 'บันทึกการตัดสินใจแล้ว';

  @override
  String get pjDetailTitle => 'สถานะงานพิมพ์';

  @override
  String get pjSimulatedBanner =>
      'โหมดทดสอบ (SIMULATED) — ไม่ใช่การพิมพ์จริง ไม่นับเป็นประวัติการพิมพ์';

  @override
  String get pjAckBanner =>
      'ไม่แน่ใจว่าพิมพ์จริงหรือไม่ — กรุณาติดต่อหัวหน้า (SUPERVISOR/ADMIN) เพื่อตรวจสอบและตัดสิน';

  @override
  String get pjDeadBanner =>
      'พิมพ์ล้มเหลวครบจำนวนครั้งแล้ว — ต้องตรวจสอบเครื่องพิมพ์แล้วสั่งพิมพ์ใหม่';

  @override
  String get pjCancelButton => 'ยกเลิกงานพิมพ์';

  @override
  String pjPackageTitle(String id) {
    return 'ห่อ $id';
  }

  @override
  String get pjFieldCreated => 'สร้างเมื่อ';

  @override
  String get pjFieldPrinter => 'เครื่องพิมพ์';

  @override
  String get pjFieldAttempts => 'จำนวนครั้งที่พยายาม';

  @override
  String get pjFieldReprint => 'พิมพ์ซ้ำ';

  @override
  String get pjFieldReprintReason => 'เหตุผลพิมพ์ซ้ำ';

  @override
  String get pjFieldErrorCode => 'รหัสข้อผิดพลาด';

  @override
  String get pjFieldSentAt => 'ส่งถึงเครื่องเมื่อ';

  @override
  String get pjFieldPrintedAt => 'พิมพ์เสร็จเมื่อ';

  @override
  String get pjFieldResolvedAt => 'หัวหน้าตัดสินเมื่อ';

  @override
  String get pjFieldResolutionNote => 'หมายเหตุการตัดสิน';

  @override
  String get pjResolveSectionTitle => 'ตัดสินใจ (หัวหน้า)';

  @override
  String get pjResolveSectionHint =>
      'งานนี้ส่งถึงเครื่องพิมพ์แล้วแต่ยืนยันผลไม่ได้ — ตรวจกับเครื่องพิมพ์จริงก่อนตัดสิน';

  @override
  String get pjResolveConfirmBtn => 'ยืนยันว่าพิมพ์แล้ว';

  @override
  String get pjResolveRequeueBtn => 'ไม่ยืนยัน — เปิดงานพิมพ์ใหม่';

  @override
  String get pjReprintReasonRequired =>
      'มีห่อที่เคยพิมพ์แล้ว — ต้องระบุเหตุผลการพิมพ์ซ้ำ';

  @override
  String get pjCreatedOne => 'สร้างงานพิมพ์แล้ว — รอเครื่องพิมพ์รับงาน';

  @override
  String pjCreatedMany(int count) {
    return 'สร้างงานพิมพ์ $count งานแล้ว';
  }

  @override
  String get pjPrintLabel => 'พิมพ์ label';

  @override
  String pjPrintLabelCount(int count) {
    return 'พิมพ์ label $count ห่อ';
  }

  @override
  String get pjSubmitDesc =>
      'ระบบจะสร้างงานพิมพ์แล้วส่งให้เครื่องพิมพ์ (Gateway) — ติดตามสถานะได้จนพิมพ์จริง';

  @override
  String get pjTargetPrinter => 'เครื่องพิมพ์ปลายทาง';

  @override
  String get pjAutoAnyPrinter => 'อัตโนมัติ (เครื่องไหนก็ได้)';

  @override
  String get pjOfflineSuffix => ' · ออฟไลน์';

  @override
  String get pjReprintReasonLabel => 'เหตุผลการพิมพ์ซ้ำ';

  @override
  String get pjReprintReasonHint => 'เช่น label เดิมชำรุด/หลุด';

  @override
  String pjCreatingProgress(int done, int total) {
    return 'กำลังสร้างงาน $done/$total...';
  }

  @override
  String get pjCreateButton => 'สร้างงานพิมพ์';

  @override
  String pjCreateButtonCount(int count) {
    return 'สร้างงานพิมพ์ $count งาน';
  }

  @override
  String get pjAutoHint => 'ส่งแบบอัตโนมัติ — เครื่องพิมพ์ที่ว่างจะรับงานเอง';

  @override
  String get bpSheetTitle => 'พิมพ์ผ่านเบราว์เซอร์';

  @override
  String get bpPrintViaThisDevice => 'พิมพ์ผ่านเครื่องนี้';

  @override
  String get bpCreateRequest => 'สร้างคำขอพิมพ์';

  @override
  String get bpCreating => 'กำลังสร้างคำขอพิมพ์...';

  @override
  String get bpPreviewTitle => 'ตัวอย่าง Label';

  @override
  String get bpUnsterileNotice => 'ยังไม่ผ่านการฆ่าเชื้อ — Label ไม่แสดงวันที่';

  @override
  String bpDatesLine(String sterilize, String expiry) {
    return 'นึ่ง $sterilize · หมดอายุ $expiry';
  }

  @override
  String get bpCopies => 'จำนวนสำเนา';

  @override
  String bpCopiesLine(int count) {
    return 'จำนวนสำเนา: $count (ต่อห่อ)';
  }

  @override
  String bpPackagesCount(int count) {
    return '$count ห่อ';
  }

  @override
  String get bpReprintWarning =>
      'ห่อนี้เคยสั่งพิมพ์แล้ว — ต้องระบุเหตุผลการพิมพ์ซ้ำ';

  @override
  String bpReprintLast(String at, String name, String status) {
    return 'ล่าสุด: $at · โดย $name · $status';
  }

  @override
  String get bpReprintReasonLabel => 'เหตุผลการพิมพ์ซ้ำ (บังคับ)';

  @override
  String get bpReprintReasonHint => 'เช่น label เดิมชำรุด/หลุด';

  @override
  String get bpReprintReasonRequired => 'ต้องระบุเหตุผลการพิมพ์ซ้ำ';

  @override
  String get bpSettingsTitle => 'ตรวจการตั้งค่าในหน้าต่างพิมพ์ก่อนกด Print';

  @override
  String get bpSettingsPrinter => 'Printer: Xprinter XP-420B';

  @override
  String bpSettingsPaper(int w, int h) {
    return 'Paper size: $w × $h มม.';
  }

  @override
  String get bpSettingsScale => 'Scale: 100%';

  @override
  String get bpSettingsMargins => 'Margins: None';

  @override
  String get bpSettingsHeaders => 'Headers and footers: ปิด';

  @override
  String get bpCannotVerifyWarning =>
      'ระบบ Browser ไม่สามารถตรวจสอบกระดาษที่ออกจากเครื่องได้ กรุณาตรวจ Label ก่อนยืนยัน';

  @override
  String get bpResultQuestion => 'ผลการพิมพ์เป็นอย่างไร?';

  @override
  String get bpResultPrinted => 'กระดาษออกถูกต้อง';

  @override
  String get bpResultNotPrinted => 'ไม่ได้พิมพ์ / ยกเลิก';

  @override
  String get bpResultLater => 'ตรวจสอบภายหลัง';

  @override
  String get bpConfirmedSnack => 'บันทึกแล้ว: ผู้ใช้ยืนยันว่ากระดาษออกแล้ว';

  @override
  String get bpCancelledSnack => 'บันทึกแล้ว: ไม่ได้พิมพ์/ยกเลิก';

  @override
  String get bpStatusCreated => 'สร้างคำขอแล้ว';

  @override
  String get bpStatusDialogOpened => 'เปิดหน้าต่างพิมพ์แล้ว ยังไม่ยืนยันผล';

  @override
  String get bpStatusUserConfirmed => 'ผู้ใช้ยืนยันว่ากระดาษออกแล้ว';

  @override
  String get bpStatusCancelled => 'ผู้ใช้แจ้งว่าไม่ได้พิมพ์หรือยกเลิก';

  @override
  String get bpHistoryTitle => 'ประวัติพิมพ์ผ่านเบราว์เซอร์';

  @override
  String get bpHistoryNone => 'ยังไม่มีคำขอพิมพ์ผ่านเบราว์เซอร์';

  @override
  String bpHistoryBy(String name) {
    return 'ผู้สั่ง: $name';
  }

  @override
  String bpHistoryMeta(String mode, int copies, String version) {
    return 'โหมด $mode · สำเนา $copies · เทมเพลต v$version';
  }

  @override
  String bpHistoryReason(String reason) {
    return 'เหตุผลพิมพ์ซ้ำ: $reason';
  }

  @override
  String bpHistoryRequestId(String id) {
    return 'คำขอ $id';
  }

  @override
  String get bpSegGateway => 'Gateway';

  @override
  String get bpSegBrowser => 'เบราว์เซอร์';
}
