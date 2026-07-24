import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/core/api/repositories.dart';

/// #2 — Idempotency-Key ต้องคงเดิมเมื่อผู้ใช้กดลองใหม่ (กันสร้าง print job ซ้ำ)
/// ดัก request ผ่าน HttpClientAdapter ปลอม เพื่ออ่าน header ที่ส่งจริง
class _CapturingAdapter implements HttpClientAdapter {
  final List<String?> idemKeys = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    idemKeys.add(options.headers['Idempotency-Key'] as String?);
    final body = jsonEncode({
      'id': 'job-1',
      'packageId': 'PKG-1',
      'status': 'QUEUED',
      'attemptCount': 0,
      'isReprint': false,
      'createdAt': '2026-07-23T00:00:00.000Z',
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

ProviderContainer _containerWith(Dio dio) {
  final c = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('PrintJobRepository.create — Idempotency-Key', () {
    test('ใช้ key ที่ caller ส่งมา (คงเดิมเมื่อ retry → backend replay ไม่สร้างซ้ำ)', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))..httpClientAdapter = adapter;
      final repo = _containerWith(dio).read(printJobRepositoryProvider);

      // จำลองผู้ใช้กดลองใหม่ 2 ครั้งด้วย key เดิม (เหมือน submit sheet ที่เก็บ key ต่อห่อ)
      await repo.create('PKG-1', idempotencyKey: 'stable-key-123');
      await repo.create('PKG-1', idempotencyKey: 'stable-key-123');

      expect(adapter.idemKeys, ['stable-key-123', 'stable-key-123']);
    });

    test('ไม่ส่ง key → generate ใหม่ทุกครั้ง (ปลอดภัยเฉพาะ auto-retry ภายใน call เดียว)', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))..httpClientAdapter = adapter;
      final repo = _containerWith(dio).read(printJobRepositoryProvider);

      await repo.create('PKG-1');
      await repo.create('PKG-1');

      expect(adapter.idemKeys[0], isNotNull);
      expect(adapter.idemKeys[1], isNotNull);
      expect(adapter.idemKeys[0], isNot(equals(adapter.idemKeys[1])));
    });
  });
}
