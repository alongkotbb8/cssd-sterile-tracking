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

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSelectAll => 'Select all';

  @override
  String get commonClearAll => 'Clear all';

  @override
  String get statusPacked => 'Packed';

  @override
  String get statusPackedOut => 'Sent (unsterile)';

  @override
  String get statusSterile => 'Sterile';

  @override
  String get statusIssued => 'Issued';

  @override
  String get statusReturned => 'Awaiting reprocess';

  @override
  String get statusExpired => 'Expired';

  @override
  String get filterAll => 'All';

  @override
  String get pkgListTitle => 'Packages';

  @override
  String pkgSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get pkgSelectToPrintTooltip => 'Select to print multiple';

  @override
  String get pkgCreateNew => 'New package';

  @override
  String get pkgSelectToPrintHint => 'Select packages to print';

  @override
  String pkgPrintSelected(int count) {
    return 'Print selected ($count)';
  }

  @override
  String get pkgSearchHint => 'Search running no. / set name';

  @override
  String get pkgTagAll => 'All tags';

  @override
  String get pkgNoneFound => 'No packages match';

  @override
  String pkgSelectedOf(int selected, int total) {
    return 'Selected $selected/$total';
  }

  @override
  String pkgExpiryOn(String date) {
    return 'Expires $date';
  }

  @override
  String pkgLocationAt(String location) {
    return 'At $location';
  }

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonClose => 'Close';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonClear => 'Clear';

  @override
  String get scanModeIn => 'To batch';

  @override
  String get scanModeOut => 'Issue';

  @override
  String get scanModeReturn => 'Return';

  @override
  String get scanModeReprocess => 'Reprocess';

  @override
  String get scanTitle => 'Scan QR';

  @override
  String get scanManualTooltip =>
      'Enter package no. manually (camera unavailable)';

  @override
  String get scanSwitchCameraTooltip => 'Switch front/back camera';

  @override
  String get scanTorchTooltip => 'Torch';

  @override
  String get scanSwitchCameraFailed =>
      'Can\'t switch camera (only one available)';

  @override
  String get scanInvalidQr => 'This QR is not a system package number';

  @override
  String get scanManualTitle => 'Enter package number';

  @override
  String get scanManualHint => 'e.g. DELIV-20260630-0007';

  @override
  String get scanManualHelper =>
      'Use when the camera can\'t scan — recorded as manual entry for audit';

  @override
  String get scanManualEmpty => 'Please enter a package number';

  @override
  String get scanManualTooLong => 'Package number too long';

  @override
  String get scanManualCharset => 'Only letters, digits and hyphen (-) allowed';

  @override
  String get scanBlockExpired => 'Do not use — package expired';

  @override
  String scanBlockStatus(String status, String mode) {
    return 'Current status: $status — cannot $mode';
  }

  @override
  String get scanWarnUnsterile =>
      '⚠ Not sterilized — will be recorded as \"sent (unsterile)\"';

  @override
  String scanConfirmTitle(String mode) {
    return 'Confirm $mode';
  }

  @override
  String scanConfirmCount(String mode, int count) {
    return '$mode $count packages';
  }

  @override
  String scanDestBatch(String round, String sterilizer) {
    return 'Round $round · $sterilizer';
  }

  @override
  String scanDestDept(String dept) {
    return 'Dept $dept';
  }

  @override
  String scanReceiverSuffix(String name) {
    return ' · receiver $name';
  }

  @override
  String get scanDestReprocess =>
      'Back to \"packed\" for a new sterilization round';

  @override
  String scanResultOkTitle(String mode, int count) {
    return '$mode succeeded — $count packages';
  }

  @override
  String scanResultMixedTitle(int ok, int fail) {
    return '$ok ok · $fail failed';
  }

  @override
  String get scanUnknownReason => 'Unknown reason';

  @override
  String get scanRetryFailed => 'Retry failed only';

  @override
  String get scanClearTitle => 'Clear scanned list?';

  @override
  String scanClearBody(int count) {
    return 'This removes all $count items from the scan list (no data change yet)';
  }

  @override
  String get scanClearAction => 'Clear list';

  @override
  String get scanCameraWebBlocked =>
      'Browser blocked the camera — tap the camera/lock icon in the address bar, allow it, then retry (must be https)';

  @override
  String get scanCameraDenied =>
      'Camera permission off — enable in Settings > Apps > CSSD > Permissions';

  @override
  String get scanCameraNeed => 'Camera permission is required to scan QR';

  @override
  String get scanOpenSettings => 'Open settings';

  @override
  String get scanCameraWebError =>
      'Can\'t open camera — ensure https and allow the camera in the browser (lock icon in address bar), then retry';

  @override
  String scanCameraError(String code) {
    return 'Can\'t open camera: $code';
  }

  @override
  String scanCountLabel(int count) {
    return 'Scanned $count packages';
  }

  @override
  String scanEligibleSuffix(int count) {
    return '($count ok)';
  }

  @override
  String get scanEmptyHint => 'Point the camera at a package QR code';

  @override
  String get scanSaving => 'Saving...';

  @override
  String get scanReprocessHint =>
      'Scan returned packages (RETURNED) to set them back to \"packed\" for a new sterilization round';

  @override
  String get scanManualBadge => 'manual';

  @override
  String scanDaysLeft(int days) {
    return '$days days left';
  }

  @override
  String batchLoadError(String error) {
    return 'Can\'t load rounds: $error';
  }

  @override
  String get batchNonePending => 'No pending rounds — tap \"New round\"';

  @override
  String get batchSelectLabel => 'Round (awaiting scan/result)';

  @override
  String batchRoundLabel(String round, String sterilizer) {
    return 'Round $round · $sterilizer';
  }

  @override
  String batchPkgCountSuffix(int count) {
    return ' · $count packages';
  }

  @override
  String get batchNewButton => 'New round';

  @override
  String get batchRecordResultButton => 'Record CI/BI result';

  @override
  String get batchOpenTitle => 'Open a new round';

  @override
  String get batchOpenSubtitle =>
      'Open a round to scan packages in before sterilizing — packages enter stock only after a supervisor records a passing CI/BI result';

  @override
  String get batchSterilizerLabel => 'Sterilizer';

  @override
  String get batchRoundNo => 'Round no.';

  @override
  String get batchOpenButton => 'Open round (awaiting scan-in)';

  @override
  String get batchConfirmPassTitle => 'Confirm \"pass\"?';

  @override
  String get batchConfirmFailTitle => 'Confirm \"fail\"?';

  @override
  String batchConfirmPassBody(String round, String count) {
    return 'All packages in round $round ($count) become \"sterile\" and enter stock immediately';
  }

  @override
  String get batchConfirmFailBody =>
      'All packages are unbound from the round (must re-sterilize) and circulating items from this round are recalled';

  @override
  String get batchRecordedPass =>
      'Recorded pass — packages entered sterile stock';

  @override
  String get batchRecordedFail =>
      'Recorded fail — packages unbound and recalled';

  @override
  String get batchRecordTitle => 'Record round result (CI/BI)';

  @override
  String get batchRecordSubtitle =>
      'Pass → all packages become sterile and enter stock automatically';

  @override
  String get batchSelectToRecord => 'Select a round to record';

  @override
  String get batchCiPass => 'Chemical Indicator (CI) passed';

  @override
  String get batchBiPass => 'Biological Indicator (BI) passed';

  @override
  String get batchRecordButton => 'Record result';

  @override
  String deptLoadError(String error) {
    return 'Can\'t load departments: $error';
  }

  @override
  String get deptDestRequired => 'Destination department (required)';

  @override
  String get deptReturnRequired => 'Returning department (required)';

  @override
  String get deptAddPlace => 'Add place';

  @override
  String get deptReceiverOptional => 'Receiver name (optional)';

  @override
  String get deptAddTitle => 'Add destination place';

  @override
  String get deptAddSubtitle => 'e.g. another hospital you send sets to';

  @override
  String get deptCodeLabel => 'Code (unique)';

  @override
  String get deptCodeHint => 'e.g. EXT-PYT';

  @override
  String get deptNameLabel => 'Place name';

  @override
  String get deptNameHint => 'e.g. Phyathai Hospital';

  @override
  String get deptExternalTitle => 'External place (outside hospital)';

  @override
  String get deptExternalSubtitle => 'Shows \"(external)\" after the name';

  @override
  String get deptSaveButton => 'Save place';
}
