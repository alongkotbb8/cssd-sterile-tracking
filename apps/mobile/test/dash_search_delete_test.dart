import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/core/auth/auth_controller.dart';
import 'package:cssd_mobile/core/models/models.dart';
import 'package:cssd_mobile/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:cssd_mobile/features/packages/presentation/pages/packages_page.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Dashboard "where-is-what" + global search + PACKED multi-delete (mobile)
//
// ครอบตามสัญญา: ปุ่มลบแสดงเฉพาะ PACKED + สิทธิ์ SUPERVISOR/ADMIN; dialog ยืนยัน
// gate การเรียก repo.bulkDelete; recentMovements เรนเดอร์; ผลค้นหาเรนเดอร์
// (ใช้ fixture adapter — ไม่ยิงเน็ตจริง)

const _kPkgId = 'DELIV-20260101-0001';

Map<String, dynamic> _pkg(String id, String status,
        {Map<String, dynamic>? movementOut}) =>
    {
      'id': id,
      'wrapType': 'SEAL',
      'status': status,
      'sterilizeDate': null,
      'expiryDate': null,
      'batchId': null,
      'notes': null,
      'isExpired': false,
      'setTemplate': {'name': 'ชุดทำคลอด'},
      'movements': movementOut != null ? [movementOut] : const [],
      'printedAt': null,
      'reprintCount': 0,
      'tags': const [],
    };

/// Adapter ปลอม — ตอบ fixture ตาม path; บันทึก POST /packages/bulk-delete
class _FixtureAdapter implements HttpClientAdapter {
  final List<RequestOptions> deletes = [];
  final String role;

  _FixtureAdapter({required this.role});

  ResponseBody _json(Object data, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final p = o.path;
    if (p == '/auth/login') {
      return _json({
        'accessToken': 'test-token',
        'user': {
          'id': 'u1',
          'name': 'ผู้ทดสอบ',
          'role': role,
          'employeeCode': 'EMP001',
        },
      });
    }
    if (p == '/packages/bulk-delete' && o.method == 'POST') {
      deletes.add(o);
      final ids = ((o.data as Map)['packageIds'] as List).cast<String>();
      return _json([
        for (final id in ids)
          {'packageId': id, 'success': true, 'error': null, 'errorCode': null},
      ]);
    }
    if (p == '/packages') {
      final search = o.queryParameters['search'] as String?;
      if (search != null && search.isNotEmpty) {
        // ผลค้นหาบนแดชบอร์ด — ห่อ ISSUED มี movement OUT (มี currentLocationName)
        return _json([
          _pkg('BIRTH-20260101-0003', 'ISSUED', movementOut: {
            'type': 'OUT',
            'createdAt': '2026-07-20T02:00:00.000Z',
            'department': {'name': 'ห้องคลอด'},
            'receiverName': null,
            'performedBy': null,
          }),
        ]);
      }
      return _json([
        _pkg(_kPkgId, 'PACKED'),
        _pkg('DRESS-20260101-0002', 'PACKED'),
      ]);
    }
    if (p == '/master-data/tags') return _json(const []);
    if (p == '/reports/dashboard') {
      return _json({
        'summary': {'expiringSoon': 0, 'expired': 0, 'awaitingReprocess': 0},
        'sterileStock': const [],
        'issuedByDept': const [],
        'recentMovements': [
          {
            'packageId': 'BIRTH-20260101-0003',
            'setName': 'ชุดทำคลอด',
            'type': 'OUT',
            'departmentName': 'ห้องคลอด',
            'receiverName': null,
            'at': '2026-07-20T02:00:00.000Z',
            'packageStatus': 'ISSUED',
          },
        ],
      });
    }
    return _json(const {});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late SharedPreferences prefs;

  setUp(() async {
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
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  /// login ผ่าน adapter (role ตามที่ตั้ง) → container พร้อมใช้กับหน้าจอ
  Future<(ProviderContainer, _FixtureAdapter)> boot(
      WidgetTester tester,
      {required String role, required Widget page}) async {
    final adapter = _FixtureAdapter(role: role);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    container.read(dioProvider).httpClientAdapter = adapter;

    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    // login ยิง dio จริง (async บน event loop จริง) — ต้องรันใน runAsync
    // ไม่งั้น await จะค้างใน fake-async zone ของ testWidgets
    await tester.runAsync(() => container
        .read(authControllerProvider.notifier)
        .login('EMP001', 'pw', l10n));
    expect(container.read(authControllerProvider).status,
        AuthStatus.authenticated);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return (container, adapter);
  }

  /// เข้าโหมดเลือก → เลือกตัวกรอง PACKED → เลือกห่อใบแรก
  Future<void> enterSelectPackedAndPick(
      WidgetTester tester, AppLocalizations l10n) async {
    // เข้าโหมดเลือก (ปุ่ม checklist)
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pump(const Duration(milliseconds: 120));
    // เลือกตัวกรอง PACKED — ระบุ FilterChip ให้ชัด (ป้าย "แพ็กแล้ว" ซ้ำกับ badge)
    await tester.tap(find.widgetWithText(FilterChip, l10n.statusPacked));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // เลือกห่อใบแรก (แตะการ์ด → toggle) — เลขห่อปรากฏครั้งเดียวในการ์ด
    await tester.tap(find.text(_kPkgId));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('ปุ่มลบแสดงเมื่อ PACKED + SUPERVISOR', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    await boot(tester, role: 'SUPERVISOR', page: const PackagesPage());
    await enterSelectPackedAndPick(tester, l10n);

    expect(find.text(l10n.pkgDeleteSelected), findsOneWidget);
  });

  testWidgets('ปุ่มลบไม่แสดงเมื่อ CSSD (สิทธิ์ไม่พอ) แม้ PACKED', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    await boot(tester, role: 'CSSD', page: const PackagesPage());
    await enterSelectPackedAndPick(tester, l10n);

    expect(find.text(l10n.pkgDeleteSelected), findsNothing);
  });

  testWidgets('ปุ่มลบไม่แสดงเมื่อสิทธิ์พอแต่ตัวกรองไม่ใช่ PACKED', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    await boot(tester, role: 'ADMIN', page: const PackagesPage());
    // เข้าโหมดเลือกแต่ไม่เลือกตัวกรอง (ตัวกรอง = ทั้งหมด/null)
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text(_kPkgId));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text(l10n.pkgDeleteSelected), findsNothing);
  });

  testWidgets('dialog ยืนยัน gate การเรียก bulkDelete: ยกเลิก = ไม่เรียก', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    final (_, adapter) =
        await boot(tester, role: 'SUPERVISOR', page: const PackagesPage());
    await enterSelectPackedAndPick(tester, l10n);

    await tester.tap(find.text(l10n.pkgDeleteSelected));
    await tester.pump(const Duration(milliseconds: 120));
    // ยืนยัน dialog ปรากฏ
    expect(find.text(l10n.pkgDeleteConfirmBody), findsOneWidget);
    // กดยกเลิก → ไม่เรียก API
    await tester.tap(find.text(l10n.pkgDeleteConfirmCancel));
    await tester.pump(const Duration(milliseconds: 120));
    expect(adapter.deletes, isEmpty);
  });

  testWidgets('dialog ยืนยัน: กดลบถาวร → เรียก bulkDelete พร้อม Idempotency-Key',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    final (_, adapter) =
        await boot(tester, role: 'SUPERVISOR', page: const PackagesPage());
    await enterSelectPackedAndPick(tester, l10n);

    await tester.tap(find.text(l10n.pkgDeleteSelected));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text(l10n.pkgDeleteConfirmAction));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(adapter.deletes.length, 1);
    final req = adapter.deletes.single;
    expect((req.data as Map)['packageIds'], [_kPkgId]);
    expect(req.headers['Idempotency-Key'], isNotNull);
  });

  testWidgets('แดชบอร์ด: section การเคลื่อนไหวล่าสุดเรนเดอร์', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('th'));
    await boot(tester, role: 'CSSD', page: const DashboardPage());

    expect(find.text(l10n.dashRecentMovementsTitle), findsOneWidget);
    // แถวการเคลื่อนไหว: เลขห่อ + บรรทัด "เบิกออก · ห้องคลอด"
    expect(find.text('BIRTH-20260101-0003'), findsWidgets);
    expect(find.textContaining('ห้องคลอด'), findsWidgets);
  });

  testWidgets('แดชบอร์ด: พิมพ์ค้นหา → ผลลัพธ์เรนเดอร์ (debounced)', (tester) async {
    await boot(tester, role: 'CSSD', page: const DashboardPage());

    await tester.enterText(find.byType(TextField).first, 'คลอด');
    // รอ debounce (350ms) + fetch
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // ผลค้นหาแสดงเลขห่อของห่อที่ตรงกับคำค้น
    expect(find.text('BIRTH-20260101-0003'), findsWidgets);
  });

  test('BulkDeleteResult.fromJson แยก success/errorCode', () {
    final ok = BulkDeleteResult.fromJson(
        {'packageId': 'A', 'success': true, 'error': null, 'errorCode': null});
    expect(ok.success, isTrue);
    final fail = BulkDeleteResult.fromJson({
      'packageId': 'B',
      'success': false,
      'error': 'มีประวัติ',
      'errorCode': 'PKG_HAS_HISTORY',
    });
    expect(fail.success, isFalse);
    expect(fail.errorCode, 'PKG_HAS_HISTORY');
  });

  test('RecentMovement.fromJson + DashboardData recentMovements parse', () {
    final d = DashboardData.fromJson({
      'summary': <String, dynamic>{},
      'recentMovements': [
        {
          'packageId': 'P1',
          'setName': 'ชุด',
          'type': 'RETURN',
          'departmentName': 'วอร์ด',
          'receiverName': null,
          'at': '2026-07-20T02:00:00.000Z',
          'packageStatus': 'RETURNED',
        },
      ],
    });
    expect(d.recentMovements.length, 1);
    expect(d.recentMovements.single.type, 'RETURN');
    expect(d.recentMovements.single.departmentName, 'วอร์ด');
    expect(d.recentMovements.single.packageStatus, 'RETURNED');
  });
}
