import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/core/auth/auth_controller.dart';

/// Adapter ปลอม — บันทึกทุก request (method, path) แล้วตอบตาม route ที่ตั้งไว้
/// ใช้ทดสอบ logout flow โดยไม่ยิงเน็ตจริง (ไม่ต้องเพิ่ม dependency)
class _RecordingAdapter implements HttpClientAdapter {
  final List<(String, String)> recorded = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    recorded.add((options.method, options.path));
    ResponseBody json(Object data, int status) => ResponseBody.fromString(
          jsonEncode(data),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    switch (options.path) {
      case '/auth/login':
        return json({
          'accessToken': 'test-token',
          'user': {
            'id': 'u1',
            'name': 'ผู้ทดสอบ',
            'role': 'CSSD',
            'employeeCode': 'EMP001',
          },
        }, 200);
      case '/auth/logout-all':
        return json({'revoked': true}, 200);
      default:
        // ทุก path อื่น (รวม /protected, /notifications/fcm-token) → 401 (token ถูกเพิกถอน)
        return json({'message': 'unauthorized'}, 401);
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late _RecordingAdapter adapter;
  late ProviderContainer container;
  late Dio dio;

  setUp(() async {
    // secure storage ปลอมแบบ in-memory (ไม่มี native plugin ในเทส)
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'readAll':
          return store;
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(args['key'] as String);
      }
      return null;
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    adapter = _RecordingAdapter();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    // ใช้ dio จริง (มี interceptor ตัวที่ทดสอบ) แต่สลับ adapter เป็นตัวปลอม
    dio = container.read(dioProvider);
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    container.dispose();
  });

  AuthController notifier() => container.read(authControllerProvider.notifier);

  test('logoutAllDevices: เรียก /auth/logout-all ครั้งเดียว แล้วเคลียร์ session', () async {
    expect(await notifier().login('EMP001', 'pw'), isNull);
    expect(container.read(authControllerProvider).status,
        AuthStatus.authenticated);

    adapter.recorded.clear();
    await notifier().logoutAllDevices();

    // ออกจากระบบเครื่องนี้แล้ว
    expect(container.read(authControllerProvider).status,
        AuthStatus.unauthenticated);
    // เรียก logout-all พอดี 1 ครั้ง (ไม่ซ้ำ)
    expect(
      adapter.recorded.where((r) => r.$2 == '/auth/logout-all').length,
      1,
    );
    // ไม่มีการยิง unregister FCM ซ้ำด้วย token ที่ถูกเพิกถอน (กันลูป)
    expect(
      adapter.recorded.any((r) => r.$2.contains('/notifications/fcm-token')),
      isFalse,
    );
  });

  test('revoked-token 401: interceptor เคลียร์ session โดยไม่ยิง API ซ้ำ (ไม่ลูป)',
      () async {
    expect(await notifier().login('EMP001', 'pw'), isNull);
    adapter.recorded.clear();

    // request ที่ถูกป้องกัน → 401 (จำลอง token ถูกเพิกถอนจากอีกอุปกรณ์)
    await expectLater(
      dio.get<dynamic>('/protected'),
      throwsA(isA<DioException>()),
    );

    // interceptor ต้องเคลียร์ session ทันที (ตั้ง state แบบ sync)
    expect(container.read(authControllerProvider).status,
        AuthStatus.unauthenticated);
    // ยิงแค่ /protected ครั้งเดียว — ไม่มี retry loop, ไม่มี unregister FCM
    expect(adapter.recorded.where((r) => r.$2 == '/protected').length, 1);
    expect(
      adapter.recorded.any((r) => r.$2.contains('/notifications/fcm-token')),
      isFalse,
    );
    expect(
      adapter.recorded.any((r) => r.$2.contains('/auth/logout')),
      isFalse,
    );
  });

  test('clearLocalSession: idempotent — เรียกซ้ำไม่พังและคง unauthenticated', () async {
    expect(await notifier().login('EMP001', 'pw'), isNull);
    await notifier().clearLocalSession();
    await notifier().clearLocalSession(); // ซ้ำ
    expect(container.read(authControllerProvider).status,
        AuthStatus.unauthenticated);
    expect(container.read(authControllerProvider).token, isNull);
  });
}
