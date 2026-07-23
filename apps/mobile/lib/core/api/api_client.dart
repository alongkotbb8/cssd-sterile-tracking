import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';

/// สร้าง Idempotency-Key ใหม่ต่อ "การกดยืนยัน 1 ครั้ง" — ตาม
/// AI_DEVELOPMENT_GUARDRAILS.md ข้อ 6: ทุก mutation สำคัญ (scan in/out/return,
/// สร้าง package, บันทึกผล batch ฯลฯ) ต้องส่ง key นี้กันยิงซ้ำจาก retry/offline sync
/// (128 บิตสุ่ม พอสำหรับกันชนโดยไม่ต้องพึ่ง package uuid เพิ่ม)
String newIdempotencyKey() {
  final rnd = Random.secure();
  return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

const kPrefServerUrl = 'server_url';
// ค่าเริ่มต้น production (Render) — เปลี่ยนได้ที่หน้าตั้งค่าถ้า URL จริงต่างจากนี้
// override ได้ตอน build ด้วย --dart-define=CSSD_API_URL=... (ใช้กับ E2E ที่ชี้ไป
// local stack เช่น http://localhost:3000) ; ค่า default นี้ไม่ผ่าน validation
// (serverUrlValidationError ตรวจเฉพาะตอนผู้ใช้แก้ URL เอง) จึงตั้ง localhost ได้
const kDefaultServerUrl = String.fromEnvironment(
  'CSSD_API_URL',
  defaultValue: 'https://cssd-api.onrender.com',
);

/// override ใน main() ด้วย instance จริงก่อน runApp
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main()'),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// ที่อยู่ server — แก้ได้จากหน้าตั้งค่า
final serverUrlProvider =
    NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.read(sharedPreferencesProvider).getString(kPrefServerUrl) ??
      kDefaultServerUrl;

  Future<void> set(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    await ref.read(sharedPreferencesProvider).setString(kPrefServerUrl, normalized);
    state = normalized;
  }
}

// Render free tier "หลับ" หลังไม่มีคนใช้ ~15 นาที ตื่นใช้เวลาได้ถึง ~50-60 วินาที
// ตั้ง timeout ต่อครั้งให้พอสมควร แล้วให้ interceptor retry อัตโนมัติแทนการ
// ให้ผู้ใช้กด "ลองใหม่" เอง
const _kWakeRetryDelays = [
  Duration(seconds: 3),
  Duration(seconds: 6),
  Duration(seconds: 10),
  Duration(seconds: 15),
  Duration(seconds: 15),
];

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final dio = Dio(BaseOptions(
    baseUrl: '$baseUrl/api/v1',
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      // อ่าน token จาก AuthState ใน memory (ไม่ใช่ secure storage) กัน race
      // ตอนเพิ่ง login เสร็จแล้ว request ถัดไปยิงก่อนเขียน storage เสร็จ
      final token = ref.read(authControllerProvider).token;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (e, handler) async {
      // token หมดอายุ/ถูกเพิกถอน → บังคับออกจากระบบ (ยกเว้นตอน login เอง)
      // ใช้ clearLocalSession() ที่ **ไม่ยิง API** — ถ้าเรียก logout() ที่ยิง unregister
      // FCM ด้วย token ที่ใช้ไม่ได้แล้ว จะได้ 401 อีก → interceptor เรียกซ้ำ = ลูป
      if (e.response?.statusCode == 401 &&
          !e.requestOptions.path.contains('/auth/login')) {
        ref.read(authControllerProvider.notifier).clearLocalSession();
        handler.next(e);
        return;
      }

      // เรียกจากลูป retry ชั้นนอกอยู่แล้ว (ดู flag ด้านล่าง) ไม่ต้อง retry ซ้อน
      if (e.requestOptions.extra['_wakeRetrying'] == true) {
        handler.next(e);
        return;
      }

      var currentError = e;
      for (var attempt = 0; attempt < _kWakeRetryDelays.length; attempt++) {
        // retry อัตโนมัติเฉพาะตอน server ยังไม่ตอบ (กำลังตื่นจาก sleep)
        // - GET: retry ได้เสมอ (idempotent)
        // - POST/PATCH/DELETE: retry เฉพาะ connectTimeout/connectionError
        //   (ยังไม่เชื่อมต่อ ไม่มีทางที่ server ได้รับข้อมูลไปประมวลผลแล้ว)
        final canRetry = currentError.type ==
                DioExceptionType.connectionTimeout ||
            currentError.type == DioExceptionType.connectionError ||
            (currentError.type == DioExceptionType.receiveTimeout &&
                currentError.requestOptions.method.toUpperCase() == 'GET');
        if (!canRetry) break;

        await Future.delayed(_kWakeRetryDelays[attempt]);
        try {
          final opts = currentError.requestOptions;
          opts.extra['_wakeRetrying'] = true;
          final res = await dio.fetch(opts);
          handler.resolve(res);
          return;
        } on DioException catch (retryErr) {
          currentError = retryErr;
        }
      }
      handler.next(currentError);
    },
  ));

  return dio;
});

/// แปลง stable error code จาก backend (`data['code']` ของ HttpException /
/// `errorCode` ราย item ของ scan) เป็นข้อความตาม locale — ตาราง code ตรงกับที่
/// backend ประกาศ (apps/api services: PKG_* / BATCH_* / PRINT_JOB_* ฯลฯ)
/// คืน null เมื่อไม่มี/ไม่รู้จัก code
String? serverErrorFromCode(AppLocalizations l10n, String? code) {
  switch (code) {
    case 'AUTH_LOCKED':
      return l10n.srvAuthLocked;
    case 'AUTH_RATE_LIMITED':
      return l10n.srvAuthRateLimited;
    case 'PKG_NOT_FOUND':
      return l10n.srvPkgNotFound;
    case 'PKG_WRONG_STATUS':
      return l10n.srvPkgWrongStatus;
    case 'PKG_ALREADY_IN_THIS_BATCH':
      return l10n.srvPkgAlreadyInThisBatch;
    case 'PKG_IN_OTHER_BATCH':
      return l10n.srvPkgInOtherBatch;
    case 'PKG_CONCURRENT':
      return l10n.srvPkgConcurrent;
    case 'PKG_EXPIRED':
      return l10n.srvPkgExpired;
    case 'PKG_UNSTERILE_EXTERNAL_ONLY':
      return l10n.srvPkgUnsterileExternalOnly;
    case 'PKG_DISCARDED':
      return l10n.srvPkgDiscarded;
    case 'PKG_ID_INVALID':
      return l10n.srvPkgIdInvalid;
    case 'REPRINT_REASON_REQUIRED':
      return l10n.srvReprintReasonRequired;
    case 'RUNNING_NUMBER_FAILED':
      return l10n.srvRunningNumberFailed;
    case 'DEPT_DUPLICATE':
      return l10n.srvDeptDuplicate;
    case 'TAG_DUPLICATE':
      return l10n.srvTagDuplicate;
    case 'TEMPLATE_DUPLICATE':
      return l10n.srvTemplateDuplicate;
    case 'CLEANUP_DATE_INVALID':
      return l10n.srvCleanupDateInvalid;
    case 'IDEMPOTENCY_CONFLICT':
      return l10n.srvIdempotencyConflict;
    case 'BATCH_NOT_FOUND':
      return l10n.srvBatchNotFound;
    case 'BATCH_DUPLICATE':
      return l10n.srvBatchDuplicate;
    case 'BATCH_ALREADY_RESULTED':
      return l10n.srvBatchAlreadyResulted;
    case 'BATCH_STATE':
      return l10n.srvBatchState;
    case 'STERILIZER_NOT_FOUND':
      return l10n.srvSterilizerNotFound;
    case 'TEMPLATE_NOT_FOUND':
      return l10n.srvTemplateNotFound;
    case 'DEPT_NOT_FOUND':
      return l10n.srvDeptNotFound;
    case 'PRINT_JOB_NOT_FOUND':
      return l10n.srvPrintJobNotFound;
    case 'PRINT_JOB_FORBIDDEN':
      return l10n.srvPrintJobForbidden;
    case 'PRINT_JOB_STATE':
      return l10n.srvPrintJobState;
    case 'PRINT_JOB_NOTE_REQUIRED':
      return l10n.srvPrintJobNoteRequired;
    case 'GATEWAY_NOT_FOUND':
      return l10n.srvGatewayNotFound;
    case 'GATEWAY_REVOKED':
      return l10n.srvGatewayRevoked;
    case 'GATEWAY_CONFIG':
      return l10n.srvGatewayConfig;
    case 'PRINTER_NOT_FOUND':
      return l10n.srvPrinterNotFound;
    default:
      return null;
  }
}

/// ข้อความ error ฝั่ง server ตาม locale: code ที่รู้จัก → ARB (ทุกภาษา);
/// error ที่ยังไม่มี code → แสดงข้อความดิบจาก server ได้เฉพาะ locale ไทย
/// (server เขียนเป็นไทย) — locale อื่น **ห้าม** โชว์ข้อความไทย คืน null
/// เพื่อให้ caller ตกไปที่ generic ตาม locale แทน
String? localizedServerError(AppLocalizations l10n, dynamic data) {
  if (data is! Map) return null;
  final coded = serverErrorFromCode(l10n, data['code'] as String?);
  if (coded != null) return coded;
  final m = data['message'];
  final raw = m is List ? m.join('\n') : m?.toString();
  if (raw == null || raw.isEmpty) return null;
  return l10n.localeName.startsWith('th') ? raw : null;
}

/// แปลง DioException เป็นข้อความ error ที่ผู้ใช้อ่านรู้เรื่อง (i18n)
///
/// backend แนบ stable `code` มากับ error → map เป็น ARB ตาม locale;
/// error เก่าที่ยังไม่มี code → แสดงข้อความ server ได้เฉพาะ locale ไทย
/// ส่วน locale อื่นได้ generic — จอภาษาอังกฤษไม่มีทางเห็นข้อความไทย
String apiErrorMessage(AppLocalizations l10n, Object error) {
  if (error is DioException) {
    final fromServer = localizedServerError(l10n, error.response?.data);
    if (fromServer != null) return fromServer;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return l10n.errTimeout;
      case DioExceptionType.connectionError:
        return l10n.errConnection;
      default:
        return l10n.errGeneric('${error.response?.statusCode ?? 'network'}');
    }
  }
  return l10n.errUnknown;
}
