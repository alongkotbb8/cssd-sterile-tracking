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

final templatesProvider = FutureProvider.autoDispose<List<SetTemplate>>((ref) async {
  final res =
      await ref.watch(dioProvider).get<List<dynamic>>('/master-data/templates');
  return res.data!
      .map((e) => SetTemplate.fromJson(e as Map<String, dynamic>))
      .toList();
});

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
      List<String> packageIds, String batchId) async {
    final res = await _ref.read(dioProvider).post<List<dynamic>>(
      '/scan/in',
      data: {'packageIds': packageIds, 'batchId': batchId},
    );
    return _results(res.data!);
  }

  Future<List<ScanResultItem>> scanOut(
    List<String> packageIds,
    String departmentId, {
    String? receiverName,
  }) async {
    final res = await _ref.read(dioProvider).post<List<dynamic>>(
      '/scan/out',
      data: {
        'packageIds': packageIds,
        'departmentId': departmentId,
        if (receiverName != null && receiverName.isNotEmpty)
          'receiverName': receiverName,
      },
    );
    return _results(res.data!);
  }

  Future<List<ScanResultItem>> scanReturn(
      List<String> packageIds, String departmentId) async {
    final res = await _ref.read(dioProvider).post<List<dynamic>>(
      '/scan/return',
      data: {'packageIds': packageIds, 'departmentId': departmentId},
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

  /// เปิดรอบนึ่งใหม่ + บันทึกผล CI/BI ผ่าน (batch พร้อมใช้นำเข้าคลังทันที)
  Future<SterilizationBatch> createPassed({
    required String sterilizerId,
    required int roundNo,
    bool biResult = true,
  }) async {
    final dio = _ref.read(dioProvider);
    final created = await dio.post<Map<String, dynamic>>(
      '/batches',
      data: {
        'sterilizerId': sterilizerId,
        'roundNo': roundNo,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final id = created.data!['id'] as String;
    // บันทึกผลตรวจ CI (+BI) ผ่าน → backend เปลี่ยนสถานะเป็น PASSED
    final result = await dio.post<Map<String, dynamic>>(
      '/batches/$id/result',
      data: {'ciResult': true, 'biResult': biResult},
    );
    return SterilizationBatch.fromJson(result.data!);
  }
}
