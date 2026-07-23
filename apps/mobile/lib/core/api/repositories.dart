import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_client.dart';

/// ---------- Master data ----------

final departmentsProvider = FutureProvider.autoDispose<List<Department>>((ref) async {
  final res = await ref.watch(dioProvider).get<List<dynamic>>('/departments');
  return res.data!
      .map((e) => Department.fromJson(e as Map<String, dynamic>))
      .toList();
});

final departmentRepositoryProvider =
    Provider<DepartmentRepository>((ref) => DepartmentRepository(ref));

class DepartmentRepository {
  DepartmentRepository(this._ref);
  final Ref _ref;

  /// เพิ่มแผนก/สถานที่ปลายทางใหม่ (SUPERVISOR/ADMIN เท่านั้น)
  /// [type] = 'external' สำหรับสถานที่นอกโรงพยาบาล เช่น รพ.อื่น
  Future<Department> create({
    required String code,
    required String name,
    String? type,
  }) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/departments',
      data: {
        'code': code,
        'name': name,
        if (type != null) 'type': type,
      },
    );
    return Department.fromJson(res.data!);
  }
}

final templatesProvider = FutureProvider.autoDispose<List<SetTemplate>>((ref) async {
  final res =
      await ref.watch(dioProvider).get<List<dynamic>>('/master-data/templates');
  return res.data!
      .map((e) => SetTemplate.fromJson(e as Map<String, dynamic>))
      .toList();
});

final templateRepositoryProvider =
    Provider<TemplateRepository>((ref) => TemplateRepository(ref));

class TemplateRepository {
  TemplateRepository(this._ref);
  final Ref _ref;

  /// สร้างชุดอุปกรณ์ใหม่ (SUPERVISOR/ADMIN เท่านั้น)
  Future<SetTemplate> create({
    required String code,
    required String name,
    required List<String> itemList,
    String defaultWrapType = 'SEAL',
  }) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/master-data/templates',
      data: {
        'code': code,
        'name': name,
        'itemList': itemList,
        'defaultWrapType': defaultWrapType,
      },
    );
    return SetTemplate.fromJson(res.data!);
  }
}

final sterilizersProvider =
    FutureProvider.autoDispose<List<Sterilizer>>((ref) async {
  final res = await ref
      .watch(dioProvider)
      .get<List<dynamic>>('/master-data/sterilizers');
  return res.data!
      .map((e) => Sterilizer.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// ---------- Dashboard ----------

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final res =
      await ref.watch(dioProvider).get<Map<String, dynamic>>('/reports/dashboard');
  return DashboardData.fromJson(res.data!);
});

/// รายงานช่วงวันที่ (from/to เป็น yyyy-MM-dd) — record เทียบค่าได้ ใช้เป็น family key
typedef ReportRange = ({String from, String to});

final weeklyReportProvider =
    FutureProvider.autoDispose.family<WeeklyReport, ReportRange>(
        (ref, range) async {
  final res = await ref.watch(dioProvider).get<Map<String, dynamic>>(
    '/reports/weekly',
    queryParameters: {'from': range.from, 'to': range.to},
  );
  return WeeklyReport.fromJson(res.data!);
});

final reportRepositoryProvider =
    Provider<ReportRepository>((ref) => ReportRepository(ref));

class ReportRepository {
  ReportRepository(this._ref);
  final Ref _ref;

  /// ล้างประวัติเก่ากว่า [before] (ADMIN เท่านั้น) — คืนจำนวนที่ลบ
  Future<Map<String, dynamic>> cleanup(DateTime before) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/reports/cleanup',
      data: {'before': before.toUtc().toIso8601String()},
    );
    return res.data!;
  }
}

/// ---------- Packages ----------

/// filter = null → ทั้งหมด, มิฉะนั้นส่ง status ไปกรองที่ server (เรียง FEFO จาก server)
/// 'EXPIRED' เป็นค่าคำนวณ ไม่ใช่สถานะใน DB — ดึงของในคลังแล้วกรอง isExpired ฝั่งนี้
final packagesProvider =
    FutureProvider.autoDispose.family<List<PackageModel>, String?>((ref, status) async {
  final isExpiredFilter = status == 'EXPIRED';
  final res = await ref.watch(dioProvider).get<List<dynamic>>(
    '/packages',
    queryParameters: {
      if (status != null) 'status': isExpiredFilter ? 'STERILE' : status,
    },
  );
  final list = res.data!
      .map((e) => PackageModel.fromJson(e as Map<String, dynamic>))
      .toList();
  return isExpiredFilter ? list.where((p) => p.isExpired).toList() : list;
});

final packageDetailProvider =
    FutureProvider.autoDispose.family<PackageModel, String>((ref, id) async {
  final res = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>('/packages/${Uri.encodeComponent(id)}');
  return PackageModel.fromJson(res.data!);
});

final packageRepositoryProvider = Provider<PackageRepository>(
  (ref) => PackageRepository(ref),
);

class PackageRepository {
  PackageRepository(this._ref);
  final Ref _ref;

  Future<PackageModel> create({
    required String setTemplateId,
    String? wrapType,
    String? notes,
  }) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/packages',
      data: {
        'setTemplateId': setTemplateId,
        if (wrapType != null) 'wrapType': wrapType,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
    );
    return PackageModel.fromJson(res.data!);
  }
}

/// ---------- Scan ----------

final scanRepositoryProvider = Provider<ScanRepository>((ref) => ScanRepository(ref));

class ScanRepository {
  ScanRepository(this._ref);
  final Ref _ref;

  Future<LookupResult> lookup(String packageId) async {
    final res = await _ref
        .read(dioProvider)
        .get<Map<String, dynamic>>('/scan/lookup/${Uri.encodeComponent(packageId)}');
    return LookupResult.fromJson(res.data!);
  }

  Future<List<ScanResultItem>> scanIn(
    List<String> packageIds,
    String batchId, {
    bool manualEntry = false,
  }) async {
    final res = await _ref.read(dioProvider).post<List<dynamic>>(
      '/scan/in',
      data: {
        'packageIds': packageIds,
        'batchId': batchId,
        if (manualEntry) 'manualEntry': true,
      },
      options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
    );
    return _results(res.data!);
  }

  Future<List<ScanResultItem>> scanOut(
    List<String> packageIds,
    String departmentId, {
    String? receiverName,
    bool manualEntry = false,
  }) async {
    final res = await _ref.read(dioProvider).post<List<dynamic>>(
      '/scan/out',
      data: {
        'packageIds': packageIds,
        'departmentId': departmentId,
        if (receiverName != null && receiverName.isNotEmpty)
          'receiverName': receiverName,
        if (manualEntry) 'manualEntry': true,
      },
      options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
    );
    return _results(res.data!);
  }

  Future<List<ScanResultItem>> scanReturn(
    List<String> packageIds,
    String departmentId, {
    bool manualEntry = false,
  }) async {
    final res = await _ref.read(dioProvider).post<List<dynamic>>(
      '/scan/return',
      data: {
        'packageIds': packageIds,
        'departmentId': departmentId,
        if (manualEntry) 'manualEntry': true,
      },
      options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
    );
    return _results(res.data!);
  }

  List<ScanResultItem> _results(List<dynamic> data) => data
      .map((e) => ScanResultItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// ---------- Batches ----------

final batchesProvider = FutureProvider.autoDispose.family<List<SterilizationBatch>, String?>(
    (ref, status) async {
  final res = await ref.watch(dioProvider).get<List<dynamic>>(
    '/batches',
    queryParameters: {if (status != null) 'status': status},
  );
  return res.data!
      .map((e) => SterilizationBatch.fromJson(e as Map<String, dynamic>))
      .toList();
});

final batchRepositoryProvider =
    Provider<BatchRepository>((ref) => BatchRepository(ref));

class BatchRepository {
  BatchRepository(this._ref);
  final Ref _ref;

  /// เปิดรอบนึ่งใหม่ (สถานะ PENDING) — สแกนห่อเข้ารอบก่อน แล้วค่อยบันทึกผล
  /// CI/BI ทีหลังตามลำดับที่ถูกหลัก traceability (ห้ามเปิดรอบพร้อมผลผ่านทันที)
  Future<SterilizationBatch> create({
    required String sterilizerId,
    required int roundNo,
  }) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/batches',
      data: {
        'sterilizerId': sterilizerId,
        'roundNo': roundNo,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      },
      options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
    );
    return SterilizationBatch.fromJson(res.data!);
  }

  /// บันทึกผล CI/BI ของรอบ (SUPERVISOR/ADMIN เท่านั้น — backend บังคับ)
  /// ผ่าน → ห่อทุกใบในรอบเป็น STERILE อัตโนมัติ, ไม่ผ่าน → ห่อถูกปลดออกจากรอบ
  Future<SterilizationBatch> recordResult(
    String batchId, {
    required bool ciResult,
    bool? biResult,
  }) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/batches/$batchId/result',
      data: {
        'ciResult': ciResult,
        if (biResult != null) 'biResult': biResult,
      },
      options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
    );
    return SterilizationBatch.fromJson(res.data!);
  }
}

/// ---------- Print Jobs (M2 — Print Job Queue + Gateway) ----------

/// รายการงานพิมพ์ (ของตัวเอง; SUPERVISOR/ADMIN เห็นทั้งหมด) — กรองตาม packageId ได้
final printJobsProvider =
    FutureProvider.autoDispose.family<List<PrintJob>, String?>((ref, packageId) async {
  final res = await ref.watch(dioProvider).get<List<dynamic>>(
    '/print-jobs',
    queryParameters: {if (packageId != null) 'packageId': packageId},
  );
  return res.data!.map((e) => PrintJob.fromJson(e as Map<String, dynamic>)).toList();
});

/// สถานะงานพิมพ์รายตัว — poll ซ้ำได้เรื่อยๆ ผ่าน ref.invalidate/refresh
final printJobDetailProvider =
    FutureProvider.autoDispose.family<PrintJob, String>((ref, id) async {
  final res = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>('/print-jobs/${Uri.encodeComponent(id)}');
  return PrintJob.fromJson(res.data!);
});

/// รายการ gateway ที่ลงทะเบียน (SUPERVISOR/ADMIN) — ใช้เลือกปลายทางพิมพ์
final gatewaysProvider = FutureProvider.autoDispose<List<PrinterGateway>>((ref) async {
  final res = await ref.watch(dioProvider).get<List<dynamic>>('/print-jobs/gateways/list');
  return res.data!.map((e) => PrinterGateway.fromJson(e as Map<String, dynamic>)).toList();
});

final printJobRepositoryProvider =
    Provider<PrintJobRepository>((ref) => PrintJobRepository(ref));

class PrintJobRepository {
  PrintJobRepository(this._ref);
  final Ref _ref;

  /// สร้างงานพิมพ์ label ของห่อ — backend ตัดสิน isReprint เอง (จาก package.printedAt)
  /// ถ้าห่อเคยพิมพ์แล้ว **ต้อง** ส่ง [reprintReason] (ไม่งั้น backend ตอบ 400)
  /// [requestedPrinterId] = gateway ที่ระบุ (null = เครื่องไหนก็ claim ได้)
  /// [idempotencyKey] — ผู้เรียก **ต้องส่ง key ที่คงเดิม** ต่อ 1 operation แล้วใช้ซ้ำเมื่อ
  /// ผู้ใช้กดลองใหม่ (กันสร้าง print job ซ้ำเมื่อ response แรกหาย) ถ้าไม่ส่งจะ gen ใหม่
  /// (ปลอดภัยเฉพาะ dio auto-retry ภายใน call เดียว ไม่กัน user-retry)
  Future<PrintJob> create(
    String packageId, {
    String? requestedPrinterId,
    String? reprintReason,
    String? idempotencyKey,
  }) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/print-jobs',
      data: {
        'packageId': packageId,
        if (requestedPrinterId != null) 'requestedPrinterId': requestedPrinterId,
        if (reprintReason != null && reprintReason.isNotEmpty) 'reprintReason': reprintReason,
      },
      options: Options(headers: {'Idempotency-Key': idempotencyKey ?? newIdempotencyKey()}),
    );
    _ref.invalidate(printJobsProvider);
    return PrintJob.fromJson(res.data!);
  }

  /// ยกเลิกงานพิมพ์ — backend อนุญาตเฉพาะสถานะ QUEUED (claim แล้วยกเลิกไม่ได้)
  Future<void> cancel(String jobId) async {
    await _ref
        .read(dioProvider)
        .post<Map<String, dynamic>>('/print-jobs/${Uri.encodeComponent(jobId)}/cancel');
    _ref.invalidate(printJobsProvider);
    _ref.invalidate(printJobDetailProvider(jobId));
  }

  /// SUPERVISOR/ADMIN ตัดสินงานที่ค้าง ACK_UNKNOWN
  /// [decision] = 'CONFIRM_PRINTED' (ยืนยันพิมพ์จริง) | 'REQUEUE' (เปิดงานใหม่)
  Future<PrintJob> resolve(String jobId, String decision, String note) async {
    final res = await _ref.read(dioProvider).post<Map<String, dynamic>>(
      '/print-jobs/${Uri.encodeComponent(jobId)}/resolve',
      data: {'decision': decision, 'note': note},
    );
    _ref.invalidate(printJobsProvider);
    _ref.invalidate(printJobDetailProvider(jobId));
    return PrintJob.fromJson(res.data!);
  }
}
