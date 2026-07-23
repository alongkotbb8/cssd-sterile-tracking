import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:cssd_mobile/features/packages/presentation/pages/package_detail_page.dart';
import 'package:cssd_mobile/features/packages/presentation/pages/packages_page.dart';
import 'package:cssd_mobile/features/packages/presentation/widgets/create_package_sheet.dart';
import 'package:cssd_mobile/features/print_jobs/presentation/pages/print_jobs_page.dart';
import 'package:cssd_mobile/features/scan/presentation/pages/scan_page.dart';
import 'package:cssd_mobile/features/settings/presentation/pages/settings_page.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Gate 1 §1B — Layout tests: 320px / Pixel 7 / Desktop Chrome ที่ text scale
// 1.0 และ 1.3 ทั้ง th/en ต้องไม่มี overflow (RenderFlex overflow โยน exception
// ใน widget test → จับด้วย tester.takeException)
//
// ครอบทุกหน้าตามที่ Gate กำหนด: Login, Settings, รายการห่อ, สร้างห่อ,
// รายละเอียดห่อ, Scan, Print Jobs — หน้า data-driven ใช้ fake HTTP adapter
// (fixture JSON) เพื่อให้เรนเดอร์ **สถานะมีข้อมูลจริง** ไม่ใช่แค่ error state

const _kPkgId = 'DELIV-20260101-0001';

Map<String, dynamic> _pkg(String id, String status,
        {String? sterilize, String? expiry}) =>
    {
      'id': id,
      'wrapType': 'SEAL',
      'status': status,
      'sterilizeDate': sterilize,
      'expiryDate': expiry,
      'batchId': null,
      'notes': null,
      'isExpired': false,
      'setTemplate': {'name': 'ชุดทำคลอด'},
      'movements': const [],
      'printedAt': null,
      'reprintCount': 0,
      'tags': const [],
    };

/// Adapter ปลอม — ตอบ fixture JSON ตาม path (ไม่ยิงเน็ตจริง)
class _FixtureAdapter implements HttpClientAdapter {
  ResponseBody _json(Object data, [int status = 200]) => ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s,
      Future<void>? c) async {
    final p = o.path;
    if (p == '/packages') {
      return _json([
        _pkg(_kPkgId, 'STERILE',
            sterilize: '2026-07-01', expiry: '2026-12-28'),
        _pkg('DRESS-20260101-0002', 'PACKED'),
        _pkg('BIRTH-20260101-0003', 'ISSUED',
            sterilize: '2026-07-01', expiry: '2026-12-28'),
      ]);
    }
    if (p.startsWith('/packages/')) {
      return _json(_pkg(_kPkgId, 'STERILE',
          sterilize: '2026-07-01', expiry: '2026-12-28'));
    }
    if (p == '/master-data/templates') {
      return _json([
        {'id': 't1', 'code': 'DELIV', 'name': 'ชุดทำคลอด', 'defaultWrapType': 'SEAL'},
        {'id': 't2', 'code': 'DRESS', 'name': 'ชุดทำแผล', 'defaultWrapType': 'CLOTH'},
      ]);
    }
    if (p == '/master-data/tags') return _json(const []);
    if (p == '/master-data/sterilizers') {
      return _json([
        {'id': 's1', 'code': 'ST-1', 'name': 'เครื่องนึ่ง 1'},
      ]);
    }
    if (p == '/departments') {
      return _json([
        {'id': 'd1', 'code': 'DENT', 'name': 'ห้องทันตกรรม', 'type': 'clinic'},
        {'id': 'd2', 'code': 'EXT', 'name': 'รพ.ภายนอก', 'type': 'external'},
      ]);
    }
    if (p == '/print-jobs') {
      return _json([
        {
          'id': 'job-1',
          'packageId': _kPkgId,
          'status': 'QUEUED',
          'attemptCount': 0,
          'isReprint': false,
          'createdAt': '2026-07-23T08:00:00Z',
        },
        {
          'id': 'job-2',
          'packageId': 'DRESS-20260101-0002',
          'status': 'ACK_UNKNOWN',
          'attemptCount': 1,
          'isReprint': false,
          'createdAt': '2026-07-23T07:00:00Z',
        },
      ]);
    }
    if (p == '/print-jobs/gateways/list') return _json(const []);
    if (p.startsWith('/batches')) return _json(const []);
    if (p == '/reports/dashboard') return _json(const {});
    // path อื่น: ตอบ 200 ว่าง — layout test สนใจการเรนเดอร์ ไม่ใช่ข้อมูลครบ
    return _json(const {});
  }

  @override
  void close({bool force = false}) {}
}

const _sizes = <String, Size>{
  '320px (จอแคบสุด)': Size(320, 568),
  'Pixel 7': Size(412, 915),
  'Desktop 1366x768': Size(1366, 768),
};
const _scales = [1.0, 1.3];
const _locales = [Locale('th'), Locale('en')];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late SharedPreferences prefs;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Future<ProviderContainer> pumpAt(
    WidgetTester tester, {
    required Widget page,
    required Size size,
    required double scale,
    required Locale locale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    // สลับ HTTP adapter ของ dio จริงเป็นตัว fixture (โค้ด provider เดิมทั้งหมด)
    container.read(dioProvider).httpClientAdapter = _FixtureAdapter();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ));
    // pumpAndSettle ไม่ได้กับหน้าที่มี animation ค้าง (เช่น spinner ตอนกล้องโหลด)
    // — pump เป็นรอบ ๆ พอให้ FutureProvider ตอบและ layout จบ
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return container;
  }

  /// host สำหรับเปิด CreatePackageSheet (ฟังก์ชัน show ต้องมี context+ref)
  Widget sheetHost() => Consumer(builder: (context, ref, _) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCreatePackageSheet(context, ref),
              child: const Text('open'),
            ),
          ),
        );
      });

  for (final entry in _sizes.entries) {
    for (final scale in _scales) {
      for (final locale in _locales) {
        final label = '${entry.key} · scale $scale · ${locale.languageCode}';

        Future<void> expectNoOverflow(
            WidgetTester tester, Widget page) async {
          // ดัก FlutterError เองเพื่อให้ได้ diagnostics เต็ม (รวมบรรทัด "The
          // relevant error-causing widget was" ชี้ไฟล์:บรรทัดของ Row/Column ที่ล้น)
          final captured = <FlutterErrorDetails>[];
          final prev = FlutterError.onError;
          FlutterError.onError = captured.add;
          try {
            await pumpAt(tester,
                page: page, size: entry.value, scale: scale, locale: locale);
          } finally {
            FlutterError.onError = prev;
          }
          tester.takeException(); // เคลียร์ของ binding (ถ้ามี)
          for (final d in captured) {
            debugPrint('── OVERFLOW @ $label ──\n$d');
          }
          expect(captured, isEmpty,
              reason: 'layout overflow/exception ที่ $label');
        }

        testWidgets('Login ไม่ overflow @ $label', (tester) async {
          await expectNoOverflow(tester, const LoginPage());
        });

        testWidgets('Settings ไม่ overflow @ $label', (tester) async {
          await expectNoOverflow(tester, const SettingsPage());
        });

        testWidgets('รายการห่อ ไม่ overflow @ $label', (tester) async {
          await expectNoOverflow(tester, const PackagesPage());
        });

        testWidgets('รายละเอียดห่อ ไม่ overflow @ $label', (tester) async {
          await expectNoOverflow(
              tester, const PackageDetailPage(id: _kPkgId));
        });

        testWidgets('Scan ไม่ overflow @ $label', (tester) async {
          await expectNoOverflow(tester, const ScanPage());
        });

        testWidgets('Print Jobs ไม่ overflow @ $label', (tester) async {
          await expectNoOverflow(tester, const PrintJobsPage());
        });

        testWidgets('สร้างห่อ (sheet) ไม่ overflow @ $label', (tester) async {
          await pumpAt(tester,
              page: sheetHost(),
              size: entry.value,
              scale: scale,
              locale: locale);
          final captured = <FlutterErrorDetails>[];
          final prev = FlutterError.onError;
          FlutterError.onError = captured.add;
          try {
            await tester.tap(find.text('open'));
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 120));
            }
          } finally {
            FlutterError.onError = prev;
          }
          tester.takeException();
          for (final d in captured) {
            debugPrint('── OVERFLOW(sheet) @ $label ──\n$d');
          }
          expect(captured, isEmpty,
              reason: 'layout overflow/exception ที่ $label');
        });
      }
    }
  }
}
