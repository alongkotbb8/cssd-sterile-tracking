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
  String get settingsLabelSize => 'Label size';

  @override
  String get settingsGatewayPrimaryTitle => 'Print via Print Gateway (XP-420B)';

  @override
  String get settingsGatewayPrimarySubtitle =>
      'All print jobs go through the Gateway → track status in the \"Print jobs\" tab';

  @override
  String get settingsLegacyPrinterTitle => 'Direct printer (legacy)';

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
  String get navDashboard => 'Dashboard';

  @override
  String get navScan => 'Scan';

  @override
  String get navPackages => 'Packages';

  @override
  String get navPrintJobs => 'Print jobs';

  @override
  String get navSettings => 'Settings';

  @override
  String get deptExternalSuffix => ' (external)';

  @override
  String get errLoginInvalid => 'Incorrect employee code or password';

  @override
  String get errTimeout => 'Server timed out — please try again';

  @override
  String get errConnection =>
      'Can\'t reach the server — check the server address in settings';

  @override
  String errGeneric(String code) {
    return 'An error occurred ($code)';
  }

  @override
  String get errUnknown => 'An unknown error occurred';

  @override
  String get srvAuthRateLimited =>
      'Too many sign-in attempts — please try again later';

  @override
  String get srvAuthLocked =>
      'Account temporarily locked after repeated failed attempts — please try again later';

  @override
  String get srvPkgNotFound => 'Package not found';

  @override
  String get srvPkgIdInvalid => 'Invalid package number format';

  @override
  String get srvRunningNumberFailed =>
      'Could not issue a running number — please try again';

  @override
  String get srvDeptDuplicate => 'That department/location code already exists';

  @override
  String get srvTagDuplicate => 'A tag with that name already exists';

  @override
  String get srvTemplateDuplicate => 'That instrument-set code already exists';

  @override
  String get srvCleanupDateInvalid => 'The cutoff date must be in the past';

  @override
  String get srvIdempotencyConflict =>
      'This request was sent twice — reload and try again';

  @override
  String get srvBrowserPrintDisabled => 'Browser printing mode is disabled';

  @override
  String get srvBrowserPrintNotFound => 'Browser print request not found';

  @override
  String get srvBrowserPrintForbidden =>
      'You do not have access to this print request';

  @override
  String get srvBrowserPrintState =>
      'The print request state does not allow this action';

  @override
  String get srvBrowserPrintReprintReasonRequired =>
      'This package was already printed — a reprint reason is required';

  @override
  String get srvBrowserPrintRateLimited =>
      'Too many print requests — please wait and try again';

  @override
  String get srvPkgWrongStatus =>
      'The package status does not allow this action';

  @override
  String get srvPkgAlreadyInThisBatch =>
      'This package is already in this batch';

  @override
  String get srvPkgInOtherBatch => 'This package is already in another batch';

  @override
  String get srvPkgConcurrent =>
      'This package was just processed from another device';

  @override
  String get srvPkgExpired => '⛔ Do not use — this package has expired';

  @override
  String get srvPkgUnsterileExternalOnly =>
      'This package is not sterilized — it can only be sent to an external destination';

  @override
  String get srvPkgDiscarded => 'This package has been discarded';

  @override
  String get srvReprintReasonRequired =>
      'This label was printed before — a reprint reason is required';

  @override
  String get srvBatchNotFound => 'Sterilization batch not found';

  @override
  String get srvBatchDuplicate =>
      'This batch already exists (same machine/date/round)';

  @override
  String get srvBatchAlreadyResulted =>
      'This batch result has already been recorded';

  @override
  String get srvBatchState => 'The batch status does not allow this action';

  @override
  String get srvSterilizerNotFound => 'Sterilizer not found';

  @override
  String get srvTemplateNotFound => 'Instrument set template not found';

  @override
  String get srvDeptNotFound => 'Department not found';

  @override
  String get srvPrintJobNotFound => 'Print job not found';

  @override
  String get srvPrintJobForbidden =>
      'You do not have permission for this print job';

  @override
  String get srvPrintJobState =>
      'The print job status has changed — reload and try again';

  @override
  String get srvPrintJobNoteRequired => 'A resolution note is required';

  @override
  String get srvGatewayNotFound => 'Gateway not found';

  @override
  String get srvGatewayRevoked => 'This gateway has been revoked';

  @override
  String get srvGatewayConfig => 'Invalid gateway configuration';

  @override
  String get srvPrinterNotFound => 'Printer not found';

  @override
  String get urlErrFormat =>
      'Invalid URL (must start with http:// or https://)';

  @override
  String urlErrAllowlist(String hosts) {
    return 'Production must point to an approved server only ($hosts)';
  }

  @override
  String get urlErrHttpsOnly =>
      'Production must use https:// only (http:// not allowed even on LAN)';

  @override
  String get urlErrExternalHttps =>
      'External servers must use https:// (http:// only for localhost/LAN in dev)';

  @override
  String get fcmChannelName => 'CSSD alerts';

  @override
  String get fcmChannelDesc => 'Near-expiry and daily-summary alerts';

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
  String get statusDiscarded => 'Discarded/damaged';

  @override
  String get filterAll => 'All';

  @override
  String get dmQrForScan => 'QR for scanning';

  @override
  String get dmWrapSeal => 'Seal · 180 days';

  @override
  String get dmWrapCloth => 'Cloth · 7 days';

  @override
  String get dmDaysShort => 'days';

  @override
  String get brandTagline => 'Sterile surgical instrument tracking (CSSD)';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitle =>
      'Use the employee code issued by your administrator';

  @override
  String get loginEmployeeCode => 'Employee code';

  @override
  String get loginEmployeeCodeRequired => 'Enter your employee code';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginPasswordRequired => 'Enter your password';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String get dashTitle => 'Dashboard';

  @override
  String dashGreeting(String name) {
    return 'Hello $name';
  }

  @override
  String get dashReportTooltip => 'Summary report / print';

  @override
  String get dashSterileStockTitle => 'Sterile stock (by set)';

  @override
  String get dashSterileStockCenter => 'ready packages';

  @override
  String get dashIssuedByDeptTitle => 'Issued by department (30 days)';

  @override
  String get dashIssuedCenter => 'issues';

  @override
  String get dashExpiringSoon => 'Expiring soon';

  @override
  String get dashNoData => 'No data yet';

  @override
  String get cpCreatedOne => 'Package created';

  @override
  String cpCreatedMany(int count) {
    return 'Created $count packages';
  }

  @override
  String cpPrintAll(int count) {
    return 'Print all ($count)';
  }

  @override
  String cpPrintSentOne(String printer) {
    return 'Sent to print at $printer';
  }

  @override
  String cpPrintSentMany(int ok, String printer) {
    return 'Sent $ok labels to print at $printer';
  }

  @override
  String get cpPrintFailed => 'Print failed — check the printer';

  @override
  String get cpTitle => 'New package';

  @override
  String get cpSubtitle => 'A running number is issued automatically on save';

  @override
  String get cpSetLabel => 'Instrument set';

  @override
  String get cpNewSet => 'New set';

  @override
  String get cpWrapType => 'Wrap type';

  @override
  String get cpQuantity => 'Quantity';

  @override
  String get cpMaxQty => 'Up to 50 packages at a time';

  @override
  String get cpNotes => 'Notes (optional)';

  @override
  String cpSavingProgress(int done, int total) {
    return 'Creating $done/$total...';
  }

  @override
  String get cpSaveOne => 'Save + issue number';

  @override
  String cpSaveMany(int count) {
    return 'Save $count packages + issue numbers';
  }

  @override
  String get ctTitle => 'New instrument set';

  @override
  String get ctSubtitle => 'Define what one instrument set contains';

  @override
  String get ctCode => 'Set code (prefixes the running number)';

  @override
  String get ctCodeHint => 'e.g. DELIV';

  @override
  String get ctName => 'Set name';

  @override
  String get ctNameHint => 'e.g. Delivery set';

  @override
  String get ctDefaultWrap => 'Default wrap type';

  @override
  String get ctItems => 'Items in the set';

  @override
  String ctItemN(int n) {
    return 'Item $n';
  }

  @override
  String get ctAddItem => 'Add item';

  @override
  String get ctValidationError => 'Enter code, set name and at least one item';

  @override
  String get ctSave => 'Save set';

  @override
  String get commonEdit => 'Edit';

  @override
  String get pdReprintTooltip => 'Reprint label';

  @override
  String get pdExpiredDetail => 'Return to CSSD for reprocessing only';

  @override
  String get pdStepPacked => 'Packed';

  @override
  String get pdStepSterile => 'Sterile';

  @override
  String get pdStepIssued => 'Issued';

  @override
  String get pdStepReturned => 'Returned';

  @override
  String get pdPackedOutTitle => 'Sent out unsterilized';

  @override
  String pdLocationNotReturned(String location) {
    return 'At $location · not yet returned';
  }

  @override
  String get pdNotReturned => 'Not yet returned';

  @override
  String get pdPackedOutHint =>
      'When scanned back in, the status returns to \"packed\", ready for a sterilization round';

  @override
  String get pdLifecycleTitle => 'Lifecycle';

  @override
  String get pdTerminalExpired => 'Current status: expired — do not use';

  @override
  String get pdTerminalDiscarded => 'Current status: discarded/damaged';

  @override
  String get pdFieldSterilizeDate => 'Sterilized on';

  @override
  String get pdFieldExpiryDate => 'Expires on';

  @override
  String get pdFieldDaysLeft => 'Remaining';

  @override
  String pdDaysValue(int days) {
    return '$days days';
  }

  @override
  String get pdFieldBatch => 'Sterilization round';

  @override
  String pdReprintSuffix(int count) {
    return ' · reprinted $count times';
  }

  @override
  String get pdFieldNotes => 'Notes';

  @override
  String get pdInfoTitle => 'Package info';

  @override
  String get pdTagsTitle => 'Tags';

  @override
  String get pdNoTags => 'No tags yet';

  @override
  String get pdEditTagsTitle => 'Package tags';

  @override
  String get pdEditTagsSubtitle =>
      'Choose the tags for this package (tap to toggle)';

  @override
  String get pdNoTagsInSystem =>
      'No tags in the system yet — add them in Master data (SUPERVISOR/ADMIN)';

  @override
  String get pdSaveTags => 'Save tags';

  @override
  String get pdMoveIn => 'Scanned into sterile stock';

  @override
  String get pdHistoryTitle => 'Movement history';

  @override
  String get pdNoHistory => 'No movements yet';

  @override
  String pdMoveDept(String dept) {
    return 'Dept: $dept';
  }

  @override
  String pdMoveReceiver(String name) {
    return 'Receiver: $name';
  }

  @override
  String pdMoveBy(String name) {
    return 'By: $name';
  }

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
  String get scanErrPermissionDenied =>
      'Camera permission is required to scan QR — allow it when the browser asks, then retry';

  @override
  String get scanErrPermissionRevoked =>
      'Camera permission was turned off while in use — re-enable the camera (camera/lock icon in Safari\'s address bar), then retry';

  @override
  String get scanErrInsecureContext =>
      'The camera only works over https — open this page via https and retry';

  @override
  String get scanErrNoCamera =>
      'No camera found on this device — you can type the package number manually instead';

  @override
  String get scanErrCameraInUse =>
      'The camera is being used by another app — close it, then retry';

  @override
  String get scanErrUnsupportedConstraint =>
      'This device doesn\'t support the requested camera settings — try switching cameras or type the package number';

  @override
  String get scanErrGeneric =>
      'Can\'t open the camera — retry, or type the package number manually';

  @override
  String get scanStateInitializing => 'Opening camera…';

  @override
  String get scanTorchFailed => 'Can\'t toggle the flashlight on this device';

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

  @override
  String get reportTitle => 'Summary report';

  @override
  String get reportPrintTooltip => 'Print report (PDF)';

  @override
  String get reportPeriodToday => 'Today';

  @override
  String get reportPeriodWeek => 'Last 7 days';

  @override
  String get reportPeriodMonth => 'This month';

  @override
  String get moveIn => 'In';

  @override
  String get moveOut => 'Out';

  @override
  String get moveReturn => 'Return';

  @override
  String get reportTotal => 'Total';

  @override
  String reportMovementsTitle(int count) {
    return 'Movements ($count)';
  }

  @override
  String get reportNoMovements => 'No movements in this period';

  @override
  String reportDeptLine(String dept) {
    return 'Dept $dept';
  }

  @override
  String reportByLine(String name) {
    return 'by $name';
  }

  @override
  String get pdfReportTitle => 'CSSD sterile tracking report';

  @override
  String pdfDateRange(String from, String to, String printed) {
    return 'Period $from – $to · printed $printed';
  }

  @override
  String get pdfNoMovements => '— No movements in this period —';

  @override
  String get pdfColDatetime => 'Date-time';

  @override
  String get pdfColType => 'Type';

  @override
  String get pdfColPackage => 'Package';

  @override
  String get pdfColSet => 'Set';

  @override
  String get pdfColDept => 'Dept';

  @override
  String get pdfColUser => 'User';

  @override
  String get pdfInspector => 'Inspector / CSSD supervisor';

  @override
  String pdfError(String error) {
    return 'Failed to create PDF: $error';
  }

  @override
  String get cleanupTitle => 'Clean up old data (save space)';

  @override
  String get cleanupDesc =>
      'After archiving the printed report, you can delete old history from the system; packages still in stock or in use are not deleted';

  @override
  String get cleanupButton => 'Delete history before this period';

  @override
  String get cleanupConfirmTitle => 'Clean up old data?';

  @override
  String cleanupConfirmBody(String date) {
    return 'This permanently deletes movement history and discarded packages created before $date';
  }

  @override
  String get cleanupKeep =>
      '✓ Packages still in stock/circulation (packed·sterile·issued·awaiting reprocess) are kept';

  @override
  String get cleanupIrreversible =>
      '✗ Deleted data cannot be recovered — archive a printed report first';

  @override
  String get cleanupConfirmAction => 'Delete permanently';

  @override
  String cleanupDone(int m, int p) {
    return 'Cleaned up: $m history entries · $p discarded packages';
  }

  @override
  String get commonYes => 'Yes';

  @override
  String get pjStatusQueued => 'Waiting for printer to claim';

  @override
  String get pjStatusClaimed => 'Printer claimed the job';

  @override
  String get pjStatusPrinting => 'Sending to printer';

  @override
  String get pjStatusSent => 'Data sent to printer';

  @override
  String get pjStatusPrinted => 'Printed successfully';

  @override
  String get pjStatusSimulated => 'Simulated (test mode, not a real print)';

  @override
  String get pjStatusFailed => 'Print failed (retrying)';

  @override
  String get pjStatusRetrying => 'Retrying print';

  @override
  String get pjStatusDeadLetter => 'Permanently failed — needs review';

  @override
  String get pjStatusAckUnknown =>
      'Unsure if actually printed — needs supervisor decision';

  @override
  String get pjStatusResolvedPrinted => 'Supervisor confirmed printed';

  @override
  String get pjStatusResolvedRequeued => 'Supervisor requeued the job';

  @override
  String get pjStatusCancelled => 'Cancelled';

  @override
  String get pjStepQueued => 'Queued';

  @override
  String get pjStepClaimed => 'Claimed';

  @override
  String get pjStepPrinting => 'Sending';

  @override
  String get pjStepSent => 'At printer';

  @override
  String get pjStepPrinted => 'Done';

  @override
  String get pjScopeAll => 'All';

  @override
  String get pjScopeMine => 'Mine';

  @override
  String get pjPageTitle => 'Print jobs';

  @override
  String get pjNone => 'No print jobs yet';

  @override
  String pjScopeLine(String scope) {
    return 'Scope: $scope';
  }

  @override
  String pjNeedAttention(int count) {
    return '$count need attention';
  }

  @override
  String get pjCancelTitle => 'Cancel print job?';

  @override
  String get pjCancelBody =>
      'Only jobs not yet claimed by a printer can be cancelled';

  @override
  String get pjCancelNo => 'No';

  @override
  String get pjCancelYes => 'Cancel job';

  @override
  String get pjResolveConfirm => 'Confirm it was actually printed';

  @override
  String get pjResolveRequeue => 'Requeue the job (not confirming print)';

  @override
  String get pjResolveNote => 'Decision note (required)';

  @override
  String get pjResolveNoteHint => 'e.g. checked the printer and found...';

  @override
  String get pjResolveNoteRequired => 'A decision note is required';

  @override
  String get pjResolveDone => 'Decision saved';

  @override
  String get pjDetailTitle => 'Print job status';

  @override
  String get pjSimulatedBanner =>
      'Test mode (SIMULATED) — not a real print, not counted as print history';

  @override
  String get pjAckBanner =>
      'Unsure whether it actually printed — please contact a supervisor (SUPERVISOR/ADMIN) to check and decide';

  @override
  String get pjDeadBanner =>
      'Printing failed the maximum number of times — check the printer and reprint';

  @override
  String get pjCancelButton => 'Cancel print job';

  @override
  String pjPackageTitle(String id) {
    return 'Package $id';
  }

  @override
  String get pjFieldCreated => 'Created';

  @override
  String get pjFieldPrinter => 'Printer';

  @override
  String get pjFieldAttempts => 'Attempts';

  @override
  String get pjFieldReprint => 'Reprint';

  @override
  String get pjFieldReprintReason => 'Reprint reason';

  @override
  String get pjFieldErrorCode => 'Error code';

  @override
  String get pjFieldSentAt => 'Sent to printer at';

  @override
  String get pjFieldPrintedAt => 'Printed at';

  @override
  String get pjFieldResolvedAt => 'Resolved at';

  @override
  String get pjFieldResolutionNote => 'Resolution note';

  @override
  String get pjResolveSectionTitle => 'Decision (supervisor)';

  @override
  String get pjResolveSectionHint =>
      'This job reached the printer but the result can\'t be confirmed — check the physical printer before deciding';

  @override
  String get pjResolveConfirmBtn => 'Confirm printed';

  @override
  String get pjResolveRequeueBtn => 'Don\'t confirm — requeue';

  @override
  String get pjReprintReasonRequired =>
      'Some packages were printed before — a reprint reason is required';

  @override
  String get pjCreatedOne =>
      'Print job created — waiting for the printer to claim it';

  @override
  String pjCreatedMany(int count) {
    return 'Created $count print jobs';
  }

  @override
  String get pjPrintLabel => 'Print label';

  @override
  String pjPrintLabelCount(int count) {
    return 'Print $count labels';
  }

  @override
  String get pjSubmitDesc =>
      'The system creates print jobs and sends them to the printer (Gateway) — track status until actually printed';

  @override
  String get pjTargetPrinter => 'Target printer';

  @override
  String get pjAutoAnyPrinter => 'Automatic (any printer)';

  @override
  String get pjOfflineSuffix => ' · offline';

  @override
  String get pjReprintReasonLabel => 'Reprint reason';

  @override
  String get pjReprintReasonHint => 'e.g. previous label damaged/fell off';

  @override
  String pjCreatingProgress(int done, int total) {
    return 'Creating job $done/$total...';
  }

  @override
  String get pjCreateButton => 'Create print job';

  @override
  String pjCreateButtonCount(int count) {
    return 'Create $count print jobs';
  }

  @override
  String get pjAutoHint =>
      'Sent automatically — a free printer will claim the job';

  @override
  String get bpSheetTitle => 'Print via browser';

  @override
  String get bpPrintViaThisDevice => 'Print via this device';

  @override
  String get bpCreateRequest => 'Create print request';

  @override
  String get bpCreating => 'Creating print request...';

  @override
  String get bpPreviewTitle => 'Label preview';

  @override
  String get bpUnsterileNotice =>
      'Not sterilized — no dates shown on the label';

  @override
  String bpDatesLine(String sterilize, String expiry) {
    return 'Sterilized $sterilize · expires $expiry';
  }

  @override
  String get bpCopies => 'Copies';

  @override
  String bpCopiesLine(int count) {
    return 'Copies: $count';
  }

  @override
  String get bpReprintWarning =>
      'This package was already printed — a reprint reason is required';

  @override
  String bpReprintLast(String at, String name, String status) {
    return 'Last: $at · by $name · $status';
  }

  @override
  String get bpReprintReasonLabel => 'Reprint reason (required)';

  @override
  String get bpReprintReasonHint => 'e.g. previous label damaged/fell off';

  @override
  String get bpReprintReasonRequired => 'A reprint reason is required';

  @override
  String get bpSettingsTitle =>
      'Check the print dialog settings before pressing Print';

  @override
  String get bpSettingsPrinter => 'Printer: Xprinter XP-420B';

  @override
  String bpSettingsPaper(int w, int h) {
    return 'Paper size: $w × $h mm';
  }

  @override
  String get bpSettingsScale => 'Scale: 100%';

  @override
  String get bpSettingsMargins => 'Margins: none';

  @override
  String get bpSettingsHeaders => 'Headers and footers: off';

  @override
  String get bpCannotVerifyWarning =>
      'The browser cannot verify that a label actually came out of the printer — check the physical label before confirming';

  @override
  String get bpResultQuestion => 'What was the print result?';

  @override
  String get bpResultPrinted => 'Label came out correctly';

  @override
  String get bpResultNotPrinted => 'Not printed / cancel';

  @override
  String get bpResultLater => 'Check later';

  @override
  String get bpConfirmedSnack => 'Saved: user confirmed the label came out';

  @override
  String get bpCancelledSnack => 'Saved: not printed / cancelled';

  @override
  String get bpStatusCreated => 'Request created';

  @override
  String get bpStatusDialogOpened =>
      'Print dialog opened — result not confirmed yet';

  @override
  String get bpStatusUserConfirmed => 'User confirmed the label came out';

  @override
  String get bpStatusCancelled => 'User reported not printed or cancelled';

  @override
  String get bpHistoryTitle => 'Browser print history';

  @override
  String get bpHistoryNone => 'No browser print requests yet';

  @override
  String bpHistoryBy(String name) {
    return 'By: $name';
  }

  @override
  String bpHistoryMeta(String mode, int copies, String version) {
    return 'Mode $mode · copies $copies · template v$version';
  }

  @override
  String bpHistoryReason(String reason) {
    return 'Reprint reason: $reason';
  }

  @override
  String bpHistoryRequestId(String id) {
    return 'Request $id';
  }

  @override
  String get bpSegGateway => 'Gateway';

  @override
  String get bpSegBrowser => 'Browser';
}
