/// โมเดลข้อมูลฝั่ง client — แมปตรงกับ response ของ NestJS API
/// (เขียนมือ ไม่ใช้ codegen เพื่อให้อ่าน/แก้ง่าย)
library;

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

  /// ชื่อที่ใช้แสดงใน dropdown — ต่อท้าย "(ภายนอก)" ให้เห็นชัดว่าออกนอกโรงพยาบาล
  String get displayName => isExternal ? '$name (ภายนอก)' : name;

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

  const ScanResultItem({
    required this.packageId,
    required this.success,
    this.error,
  });

  factory ScanResultItem.fromJson(Map<String, dynamic> j) => ScanResultItem(
        packageId: j['packageId'] as String,
        success: (j['success'] ?? false) as bool,
        error: j['error'] as String?,
      );
}

class SterilizationBatch {
  final String id;
  final int? roundNo;
  final String status; // PENDING | PASSED | FAILED
  final DateTime? startedAt;
  final String? sterilizerName;

  const SterilizationBatch({
    required this.id,
    required this.status,
    this.roundNo,
    this.startedAt,
    this.sterilizerName,
  });

  factory SterilizationBatch.fromJson(Map<String, dynamic> j) =>
      SterilizationBatch(
        id: j['id'] as String,
        status: (j['status'] ?? 'PENDING') as String,
        roundNo: j['roundNo'] as int?,
        startedAt: _date(j['startedAt']),
        sterilizerName:
            (j['sterilizer'] as Map<String, dynamic>?)?['name'] as String?,
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
