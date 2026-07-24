/// โมเดลข้อมูลฝั่ง client — แมปตรงกับ response ของ NestJS API
/// (เขียนมือ ไม่ใช้ codegen เพื่อให้อ่าน/แก้ง่าย)
library;

import '../../l10n/app_localizations.dart';

// server ส่งเวลาเป็น UTC (ISO + Z) — แปลงเป็นเวลาท้องถิ่นก่อนเสมอ
// ไม่งั้นหน้าจอจะแสดงเวลาเพี้ยนไป 7 ชั่วโมง (UTC vs เวลาไทย)
DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v as String)?.toLocal();

class AppUser {
  final String id;
  final String name;
  final String role;
  final String employeeCode;

  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.employeeCode,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        employeeCode: j['employeeCode'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'role': role, 'employeeCode': employeeCode};
}

class Department {
  final String id;
  final String code;
  final String name;
  final String? type; // clinic | ward | er | external (สถานที่นอกโรงพยาบาล)

  const Department(
      {required this.id, required this.code, required this.name, this.type});

  bool get isExternal => type == 'external';

  /// ชื่อที่ใช้แสดงใน dropdown — ต่อท้าย "(ภายนอก)" ให้เห็นชัดว่าออกนอกโรงพยาบาล (i18n)
  String displayName(AppLocalizations l10n) =>
      isExternal ? '$name${l10n.deptExternalSuffix}' : name;

  factory Department.fromJson(Map<String, dynamic> j) => Department(
        id: j['id'] as String,
        code: (j['code'] ?? '') as String,
        name: j['name'] as String,
        type: j['type'] as String?,
      );

  // เทียบด้วย id — ให้ dropdown จับคู่ค่าที่เลือกไว้กับ list ที่ refetch ใหม่ได้
  // (จำเป็นตอนกด "เพิ่มสถานที่" แล้ว invalidate departmentsProvider)
  @override
  bool operator ==(Object other) => other is Department && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SetTemplate {
  final String id;
  final String code;
  final String name;
  final String defaultWrapType; // SEAL | CLOTH

  const SetTemplate({
    required this.id,
    required this.code,
    required this.name,
    required this.defaultWrapType,
  });

  factory SetTemplate.fromJson(Map<String, dynamic> j) => SetTemplate(
        id: j['id'] as String,
        code: (j['code'] ?? '') as String,
        name: j['name'] as String,
        defaultWrapType: (j['defaultWrapType'] ?? 'SEAL') as String,
      );
}

class Sterilizer {
  final String id;
  final String code;
  final String name;

  const Sterilizer({required this.id, required this.code, required this.name});

  factory Sterilizer.fromJson(Map<String, dynamic> j) => Sterilizer(
        id: j['id'] as String,
        code: (j['code'] ?? '') as String,
        name: j['name'] as String,
      );
}

/// ป้ายกำกับห่อ (จัดกลุ่ม/กรอง) — มาจาก GET /master-data/tags
class Tag {
  final String id;
  final String name;
  final String? colorHex; // เช่น "#2563EB" (nullable)

  const Tag({required this.id, required this.name, this.colorHex});

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        id: j['id'] as String,
        name: j['name'] as String,
        colorHex: j['colorHex'] as String?,
      );

  /// แปลง colorHex ("#RRGGBB") → int ARGB สำหรับ Color(); คืน null ถ้าไม่ถูกต้อง
  int? get colorValue {
    final h = colorHex;
    if (h == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(h)) return null;
    return int.parse('FF${h.substring(1)}', radix: 16);
  }

  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Movement {
  final String type; // IN | OUT | RETURN
  final DateTime? createdAt;
  final String? departmentName;
  final String? receiverName;
  final String? performedByName;

  const Movement({
    required this.type,
    this.createdAt,
    this.departmentName,
    this.receiverName,
    this.performedByName,
  });

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        type: j['type'] as String,
        createdAt: _date(j['createdAt']),
        departmentName: (j['department'] as Map<String, dynamic>?)?['name'] as String?,
        receiverName: j['receiverName'] as String?,
        performedByName: (j['performedBy'] as Map<String, dynamic>?)?['name'] as String?,
      );
}

class PackageModel {
  final String id;
  final String wrapType; // SEAL | CLOTH
  final String status; // PACKED STERILE ISSUED RETURNED EXPIRED DISCARDED
  final DateTime? sterilizeDate;
  final DateTime? expiryDate;
  final String? batchId;
  final String? notes;
  final bool isExpired;
  final String templateName;
  final List<Movement> movements;
  final DateTime? printedAt; // พิมพ์ label ล่าสุดเมื่อไหร่
  final int reprintCount; // จำนวนครั้งที่พิมพ์ซ้ำ (ไม่นับครั้งแรก)
  final List<Tag> tags; // ป้ายกำกับที่ผูกกับห่อ (จาก detail endpoint)

  const PackageModel({
    required this.id,
    required this.wrapType,
    required this.status,
    this.sterilizeDate,
    this.expiryDate,
    this.batchId,
    this.notes,
    this.isExpired = false,
    this.templateName = '',
    this.movements = const [],
    this.printedAt,
    this.reprintCount = 0,
    this.tags = const [],
  });

  factory PackageModel.fromJson(Map<String, dynamic> j) => PackageModel(
        id: j['id'] as String,
        wrapType: (j['wrapType'] ?? 'SEAL') as String,
        status: (j['status'] ?? 'PACKED') as String,
        sterilizeDate: _date(j['sterilizeDate']),
        expiryDate: _date(j['expiryDate']),
        batchId: j['batchId'] as String?,
        notes: j['notes'] as String?,
        isExpired: (j['isExpired'] ?? false) as bool,
        templateName:
            ((j['setTemplate'] as Map<String, dynamic>?)?['name'] ?? '') as String,
        movements: ((j['movements'] as List?) ?? const [])
            .map((m) => Movement.fromJson(m as Map<String, dynamic>))
            .toList(),
        printedAt: _date(j['printedAt']),
        reprintCount: (j['reprintCount'] ?? 0) as int,
        // detail endpoint ส่ง tags เป็น [{ tag: {id,name,colorHex} }] (join table)
        tags: ((j['tags'] as List?) ?? const [])
            .map((e) => Tag.fromJson(
                (e as Map<String, dynamic>)['tag'] as Map<String, dynamic>))
            .toList(),
      );

  int? get daysLeft => expiryDate?.difference(DateTime.now()).inDays;

  int get shelfLifeDays => wrapType == 'CLOTH' ? 7 : 180;

  /// ตำแหน่งปัจจุบันของห่อ — มีค่าเมื่อห่อออกไปอยู่ข้างนอก (ISSUED/PACKED_OUT)
  /// อ่านจาก movement OUT ล่าสุด (list endpoint ส่ง movement ล่าสุด 1 รายการ,
  /// detail endpoint ส่งทั้งหมด — จึงค้นตัวแรกที่เป็น OUT จากรายการเรียงล่าสุดก่อน)
  String? get currentLocationName {
    if (status != 'ISSUED' && status != 'PACKED_OUT') return null;
    final sorted = [...movements]..sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    for (final m in sorted) {
      if (m.type == 'OUT') return m.departmentName;
    }
    return null;
  }
}

class LookupResult {
  final PackageModel package;
  final bool isExpired;
  final int? daysLeft;

  const LookupResult({
    required this.package,
    required this.isExpired,
    this.daysLeft,
  });

  factory LookupResult.fromJson(Map<String, dynamic> j) => LookupResult(
        package: PackageModel.fromJson(j),
        isExpired: (j['isExpired'] ?? false) as bool,
        daysLeft: j['daysLeft'] as int?,
      );
}

class ScanResultItem {
  final String packageId;
  final bool success;
  final String? error;

  /// stable code จาก backend — client map เป็นข้อความตาม locale
  /// (ดู serverErrorFromCode ใน api_client.dart); [error] ไทยคงไว้เป็น fallback
  final String? errorCode;

  const ScanResultItem({
    required this.packageId,
    required this.success,
    this.error,
    this.errorCode,
  });

  factory ScanResultItem.fromJson(Map<String, dynamic> j) => ScanResultItem(
        packageId: j['packageId'] as String,
        success: (j['success'] ?? false) as bool,
        error: j['error'] as String?,
        errorCode: j['errorCode'] as String?,
      );
}

class SterilizationBatch {
  final String id;
  final int? roundNo;
  final String status; // PENDING | PASSED | FAILED
  final DateTime? startedAt;
  final String? sterilizerName;

  /// จำนวนห่อที่ผูกกับรอบนี้ (จาก _count ของ backend) — ใช้ตอนบันทึกผล
  final int? packageCount;

  const SterilizationBatch({
    required this.id,
    required this.status,
    this.roundNo,
    this.startedAt,
    this.sterilizerName,
    this.packageCount,
  });

  factory SterilizationBatch.fromJson(Map<String, dynamic> j) =>
      SterilizationBatch(
        id: j['id'] as String,
        status: (j['status'] ?? 'PENDING') as String,
        roundNo: j['roundNo'] as int?,
        startedAt: _date(j['startedAt']),
        sterilizerName:
            (j['sterilizer'] as Map<String, dynamic>?)?['name'] as String?,
        packageCount:
            ((j['_count'] as Map<String, dynamic>?)?['packages']) as int?,
      );

  // เทียบด้วย id เพื่อให้ dropdown จับคู่ค่าที่เลือกกับ list ที่ refetch มาได้ถูก
  @override
  bool operator ==(Object other) =>
      other is SterilizationBatch && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// แถวรายการเคลื่อนไหวในรายงาน (จาก /reports/weekly)
class ReportMovement {
  final String type; // IN | OUT | RETURN
  final DateTime? createdAt;
  final String packageId;
  final String templateName;
  final String? departmentName;
  final String? receiverName;
  final String? performedByName;

  const ReportMovement({
    required this.type,
    required this.packageId,
    required this.templateName,
    this.createdAt,
    this.departmentName,
    this.receiverName,
    this.performedByName,
  });

  factory ReportMovement.fromJson(Map<String, dynamic> j) {
    final pkg = j['package'] as Map<String, dynamic>?;
    return ReportMovement(
      type: j['type'] as String,
      createdAt: _date(j['createdAt']),
      packageId: (j['packageId'] ?? pkg?['id'] ?? '') as String,
      templateName:
          ((pkg?['setTemplate'] as Map<String, dynamic>?)?['name'] ?? '')
              as String,
      departmentName:
          (j['department'] as Map<String, dynamic>?)?['name'] as String?,
      receiverName: j['receiverName'] as String?,
      performedByName:
          (j['performedBy'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

class WeeklyReport {
  final List<ReportMovement> movements;
  final int inCount;
  final int outCount;
  final int returnCount;

  const WeeklyReport({
    required this.movements,
    required this.inCount,
    required this.outCount,
    required this.returnCount,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> j) {
    final summary = (j['summary'] ?? const {}) as Map<String, dynamic>;
    return WeeklyReport(
      movements: ((j['movements'] as List?) ?? const [])
          .map((e) => ReportMovement.fromJson(e as Map<String, dynamic>))
          .toList(),
      inCount: (summary['IN'] ?? 0) as int,
      outCount: (summary['OUT'] ?? 0) as int,
      returnCount: (summary['RETURN'] ?? 0) as int,
    );
  }
}

class DashboardSlice {
  final String name;
  final int count;

  const DashboardSlice({required this.name, required this.count});
}

class DashboardData {
  final List<DashboardSlice> sterileStock;
  final List<DashboardSlice> issuedByDept;
  final int expiringSoon;
  final int expired;
  final int awaitingReprocess;

  const DashboardData({
    required this.sterileStock,
    required this.issuedByDept,
    required this.expiringSoon,
    required this.expired,
    required this.awaitingReprocess,
  });

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final summary = (j['summary'] ?? const {}) as Map<String, dynamic>;
    return DashboardData(
      sterileStock: ((j['sterileStock'] as List?) ?? const [])
          .map((e) => DashboardSlice(
                name: (e['templateName'] ?? '') as String,
                count: (e['count'] ?? 0) as int,
              ))
          .toList(),
      issuedByDept: ((j['issuedByDept'] as List?) ?? const [])
          .map((e) => DashboardSlice(
                name: (e['departmentName'] ?? '') as String,
                count: (e['count'] ?? 0) as int,
              ))
          .toList(),
      expiringSoon: (summary['expiringSoon'] ?? 0) as int,
      expired: (summary['expired'] ?? 0) as int,
      awaitingReprocess: (summary['awaitingReprocess'] ?? 0) as int,
    );
  }

  int get sterileTotal => sterileStock.fold(0, (a, b) => a + b.count);
  int get issuedTotal => issuedByDept.fold(0, (a, b) => a + b.count);
}

/// ---------- Print Job Queue (M2) ----------
///
/// PWA ไม่พิมพ์ตรงและไม่ตั้งสถานะ PRINTED เอง — สร้าง PrintJob แล้ว poll สถานะ
/// จนกว่า Print Gateway จะ claim/พิมพ์/ACK (ดู apps/print-gateway)
/// สถานะ (ตรงกับ PrintJobStatus enum ฝั่ง backend):
///   QUEUED → CLAIMED → PRINTING → SENT → PRINTED
///   FAILED → RETRYING → (QUEUED | DEAD_LETTER)
///   ACK_UNKNOWN → (RESOLVED_PRINTED | RESOLVED_REQUEUED)  ← หัวหน้าตัดสิน
///   SIMULATED (dev/console เท่านั้น) · CANCELLED (ยกเลิกตอน QUEUED)
class PrintJob {
  final String id;
  final String packageId;
  final String status;
  final String? requestedPrinterId; // เครื่องที่ผู้ใช้ระบุ (null = เครื่องไหนก็ได้)
  final String? printerId; // เครื่องที่ claim ไปจริง
  final int attemptCount;
  final bool isReprint;
  final String? reprintReason;
  final String? errorCode;
  final String? resolutionNote;
  final String? requeuedFromJobId;
  final DateTime createdAt;
  final DateTime? claimedAt;
  final DateTime? printingAt;
  final DateTime? sentAt;
  final DateTime? printedAt;
  final DateTime? failedAt;
  final DateTime? resolvedAt;

  const PrintJob({
    required this.id,
    required this.packageId,
    required this.status,
    required this.attemptCount,
    required this.isReprint,
    required this.createdAt,
    this.requestedPrinterId,
    this.printerId,
    this.reprintReason,
    this.errorCode,
    this.resolutionNote,
    this.requeuedFromJobId,
    this.claimedAt,
    this.printingAt,
    this.sentAt,
    this.printedAt,
    this.failedAt,
    this.resolvedAt,
  });

  factory PrintJob.fromJson(Map<String, dynamic> j) => PrintJob(
        id: j['id'] as String,
        packageId: j['packageId'] as String,
        status: (j['status'] ?? 'QUEUED') as String,
        requestedPrinterId: j['requestedPrinterId'] as String?,
        printerId: j['printerId'] as String?,
        attemptCount: (j['attemptCount'] ?? 0) as int,
        isReprint: (j['isReprint'] ?? false) as bool,
        reprintReason: j['reprintReason'] as String?,
        errorCode: j['errorCode'] as String?,
        resolutionNote: j['resolutionNote'] as String?,
        requeuedFromJobId: j['requeuedFromJobId'] as String?,
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        claimedAt: _date(j['claimedAt']),
        printingAt: _date(j['printingAt']),
        sentAt: _date(j['sentAt']),
        printedAt: _date(j['printedAt']),
        failedAt: _date(j['failedAt']),
        resolvedAt: _date(j['resolvedAt']),
      );

  /// จบงานแล้ว (ไม่ต้อง poll ต่อ)
  bool get isTerminal => const {
        'PRINTED', 'SIMULATED', 'CANCELLED', 'DEAD_LETTER',
        'RESOLVED_PRINTED', 'RESOLVED_REQUEUED',
      }.contains(status);

  /// ยกเลิกได้เฉพาะตอนยังไม่ถูก claim
  bool get canCancel => status == 'QUEUED';

  /// ต้องให้ SUPERVISOR/ADMIN เข้ามาตัดสิน
  bool get needsSupervisor => status == 'ACK_UNKNOWN';

  bool get isSuccess => status == 'PRINTED' || status == 'RESOLVED_PRINTED';
  bool get isSimulated => status == 'SIMULATED';
}

/// ---------- Browser Print (BROWSER_DIALOG — MACOS_BROWSER_PRINT_DIRECTIVE.md) ----------
///
/// คำขอพิมพ์ผ่าน macOS system print dialog — แยก semantics จาก PrintJob เด็ดขาด
/// สถานะจำกัด: CREATED → DIALOG_OPENED → USER_CONFIRMED | CANCELLED
/// (USER_CONFIRMED = **ผู้ใช้ยืนยันเอง** ไม่ใช่ hardware-confirmed — ห้ามใช้
/// PRINTED/SENT/ACK_UNKNOWN กับโหมดนี้ และไม่แตะ printedAt/reprintCount)

/// ข้อมูล label ที่ **backend เป็นผู้ชี้ขาด** (authoritative) แนบมากับ response
/// ตอนสร้างคำขอ — วันที่มาจาก DB เท่านั้น (null เมื่อยังไม่ผ่านการฆ่าเชื้อ)
/// client ห้ามคำนวณวันนึ่ง/วันหมดอายุเองเด็ดขาด
class BrowserPrintLabel {
  final String packageId;
  final String templateName;
  final String wrapType; // SEAL | CLOTH
  final String status;
  final DateTime? sterilizeDate;
  final DateTime? expiryDate;
  final bool isSterilized;

  const BrowserPrintLabel({
    required this.packageId,
    required this.templateName,
    required this.wrapType,
    required this.status,
    this.sterilizeDate,
    this.expiryDate,
    this.isSterilized = false,
  });

  factory BrowserPrintLabel.fromJson(Map<String, dynamic> j) =>
      BrowserPrintLabel(
        packageId: j['packageId'] as String,
        templateName: (j['templateName'] ?? '') as String,
        wrapType: (j['wrapType'] ?? 'SEAL') as String,
        status: (j['status'] ?? '') as String,
        sterilizeDate: _date(j['sterilizeDate']),
        expiryDate: _date(j['expiryDate']),
        isSterilized: (j['isSterilized'] ?? false) as bool,
      );
}

/// สรุปประวัติการพิมพ์ก่อนหน้า (นับรวมทั้ง browser และ gateway) — ใช้แสดง
/// คำเตือน reprint (backend คำนวณ; แนบมากับ create response และ error 400
/// BROWSER_PRINT_REPRINT_REASON_REQUIRED)
class BrowserPrintPrior {
  final int count;
  final DateTime? lastAt;
  final String? lastByName;
  final String? lastStatus;
  final String? lastSource; // BROWSER | GATEWAY | null

  const BrowserPrintPrior({
    required this.count,
    this.lastAt,
    this.lastByName,
    this.lastStatus,
    this.lastSource,
  });

  factory BrowserPrintPrior.fromJson(Map<String, dynamic> j) =>
      BrowserPrintPrior(
        count: (j['count'] ?? 0) as int,
        lastAt: _date(j['lastAt']),
        lastByName: j['lastByName'] as String?,
        lastStatus: j['lastStatus'] as String?,
        lastSource: j['lastSource'] as String?,
      );
}

class BrowserPrintRequest {
  final String id;
  final String packageId;
  final String requestedByUserId;
  final String requestedByName;
  final DateTime? requestedAt;
  final String mode; // BROWSER_DIALOG เท่านั้น
  final String templateVersion;
  final int copies;
  final bool isReprint;
  final String? reprintReason;
  final String status; // CREATED | DIALOG_OPENED | USER_CONFIRMED | CANCELLED
  final DateTime? dialogOpenedAt;
  final DateTime? userConfirmedAt;
  final DateTime? cancelledAt;
  final String createdFrom; // CREATE_PACKAGE | PACKAGE_DETAIL | PRINT_JOBS
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// แนบมาเฉพาะ create response (endpoint อื่นเป็น null)
  final BrowserPrintLabel? label;
  final BrowserPrintPrior? priorPrints;

  const BrowserPrintRequest({
    required this.id,
    required this.packageId,
    required this.requestedByUserId,
    required this.requestedByName,
    required this.mode,
    required this.templateVersion,
    required this.copies,
    required this.isReprint,
    required this.status,
    required this.createdFrom,
    this.requestedAt,
    this.reprintReason,
    this.dialogOpenedAt,
    this.userConfirmedAt,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
    this.label,
    this.priorPrints,
  });

  factory BrowserPrintRequest.fromJson(Map<String, dynamic> j) =>
      BrowserPrintRequest(
        id: j['id'] as String,
        packageId: j['packageId'] as String,
        requestedByUserId: (j['requestedByUserId'] ?? '') as String,
        requestedByName: (j['requestedByName'] ?? '') as String,
        requestedAt: _date(j['requestedAt']),
        mode: (j['mode'] ?? 'BROWSER_DIALOG') as String,
        templateVersion: (j['templateVersion'] ?? '1') as String,
        copies: (j['copies'] ?? 1) as int,
        isReprint: (j['isReprint'] ?? false) as bool,
        reprintReason: j['reprintReason'] as String?,
        status: (j['status'] ?? 'CREATED') as String,
        dialogOpenedAt: _date(j['dialogOpenedAt']),
        userConfirmedAt: _date(j['userConfirmedAt']),
        cancelledAt: _date(j['cancelledAt']),
        createdFrom: (j['createdFrom'] ?? '') as String,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
        label: j['label'] is Map<String, dynamic>
            ? BrowserPrintLabel.fromJson(j['label'] as Map<String, dynamic>)
            : null,
        priorPrints: j['priorPrints'] is Map<String, dynamic>
            ? BrowserPrintPrior.fromJson(
                j['priorPrints'] as Map<String, dynamic>)
            : null,
      );
}

/// Gateway (เครื่องพิมพ์) ที่ลงทะเบียนไว้ — ใช้เลือกปลายทางตอนสร้าง PrintJob
/// มาจาก GET /print-jobs/gateways/list (SUPERVISOR/ADMIN)
class PrinterGateway {
  final String id;
  final String name;
  final bool isActive;
  final String environment; // DEVELOPMENT | TEST | PRODUCTION
  final String transportMode; // CONSOLE | SERIAL | BLUETOOTH
  final bool canConfirmRealPrint;
  final DateTime? lastHeartbeatAt;
  final DateTime? revokedAt;

  const PrinterGateway({
    required this.id,
    required this.name,
    required this.isActive,
    required this.environment,
    required this.transportMode,
    required this.canConfirmRealPrint,
    this.lastHeartbeatAt,
    this.revokedAt,
  });

  factory PrinterGateway.fromJson(Map<String, dynamic> j) => PrinterGateway(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        isActive: (j['isActive'] ?? false) as bool,
        environment: (j['environment'] ?? 'DEVELOPMENT') as String,
        transportMode: (j['transportMode'] ?? 'CONSOLE') as String,
        canConfirmRealPrint: (j['canConfirmRealPrint'] ?? false) as bool,
        lastHeartbeatAt: _date(j['lastHeartbeatAt']),
        revokedAt: _date(j['revokedAt']),
      );

  /// ออนไลน์ = active, ไม่ถูก revoke, และ heartbeat ภายใน 90 วินาที
  bool get isOnline {
    if (!isActive || revokedAt != null) return false;
    final hb = lastHeartbeatAt;
    if (hb == null) return false;
    return DateTime.now().difference(hb).inSeconds < 90;
  }
}
