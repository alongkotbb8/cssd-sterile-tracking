import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';

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

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final dio = Dio(BaseOptions(
    baseUrl: '$baseUrl/api/v1',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
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
    onError: (e, handler) {
      // token หมดอายุ/ไม่ถูกต้อง → บังคับออกจากระบบ (ยกเว้นตอน login เอง)
      if (e.response?.statusCode == 401 &&
          !e.requestOptions.path.contains('/auth/login')) {
        ref.read(authControllerProvider.notifier).logout();
      }
      handler.next(e);
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
