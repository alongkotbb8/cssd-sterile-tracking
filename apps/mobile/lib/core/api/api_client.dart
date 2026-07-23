import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';

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
const kDefaultServerUrl = 'https://cssd-api.onrender.com';

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

/// แปลง DioException เป็นข้อความภาษาไทยที่ผู้ใช้อ่านรู้เรื่อง
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      final m = data['message'];
      return m is List ? m.join('\n') : m.toString();
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'เชื่อมต่อ server ไม่ทัน กรุณาลองใหม่';
      case DioExceptionType.connectionError:
        return 'เชื่อมต่อ server ไม่ได้ ตรวจสอบที่อยู่ server ในหน้าตั้งค่า';
      default:
        return 'เกิดข้อผิดพลาด (${error.response?.statusCode ?? 'network'})';
    }
  }
  return 'เกิดข้อผิดพลาดไม่ทราบสาเหตุ';
}
