import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/core/config/feature_flags.dart';
import 'package:cssd_mobile/core/models/models.dart';
import 'package:cssd_mobile/core/printer/printer_adapter.dart';
import 'package:cssd_mobile/features/browser_print/presentation/widgets/browser_print_history_card.dart';
import 'package:cssd_mobile/features/browser_print/presentation/widgets/browser_print_sheet.dart';
import 'package:cssd_mobile/features/browser_print/print_pdf_seam.dart';
import 'package:cssd_mobile/features/packages/presentation/pages/package_detail_page.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Browser print (BROWSER_DIALOG) — Flutter tests ตาม MACOS_BROWSER_PRINT_DIRECTIVE.md §14
// ดัก HTTP ผ่าน HttpClientAdapter ปลอม (บันทึก request ตามลำดับ) + override
// print seam / render seam ผ่าน ProviderScope เพื่อตรวจ **ลำดับการเรียก** ที่บังคับ:
// create → dialog-opened → เปิด print dialog → ผู้ใช้เลือกผลเอง (ไม่ auto-confirm)

const _kPkgId = 'DELIV-20260101-0001';

/// PNG 1×1 ใส (ถูกต้องตามฟอร์แมต) — ใช้เป็นผลลัพธ์ของ render seam ปลอม
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _pkgJson({String? printedAt}) => {
      'id': _kPkgId,
      'wrapType': 'SEAL',
      'status': 'STERILE',
      'sterilizeDate': '2026-07-01T00:00:00.000Z',
      'expiryDate': '2026-12-28T00:00:00.000Z',
      'batchId': null,
      'notes': null,
      'isExpired': false,
      'setTemplate': {'name': 'ชุดทำคลอด'},
      'movements': const [],
      'printedAt': printedAt,
      'reprintCount': 0,
      'tags': const [],
    };

PackageModel _pkgModel({DateTime? printedAt}) => PackageModel(
      id: _kPkgId,
      wrapType: 'SEAL',
      status: 'STERILE',
      templateName: 'ชุดทำคลอด',
      printedAt: printedAt,
    );

/// Adapter ปลอม — ตอบ fixture ตาม path + **บันทึกลำดับเหตุการณ์** ลง [events]
/// (print seam ปลอมก็ push ลง list เดียวกัน → assert ลำดับ create→dialog-opened→seam ได้)
class _BpAdapter implements HttpClientAdapter {
  _BpAdapter({
    this.reprintRequired = false,
    this.failDialogOpened = false,
    this.sterileLabel = true,
    List<Map<String, dynamic>>? listItems,
  }) : listItems = listItems ?? const [];

  final List<String> events = [];
  final Map<String, List<String?>> idemKeys = {};
  final List<Map<String, dynamic>> createBodies = [];

  /// true = backend ตัดสินว่าเป็น reprint → create ที่ไม่มีเหตุผลตอบ 400
  bool reprintRequired;
  final bool failDialogOpened;
  final bool sterileLabel;
  final List<Map<String, dynamic>> listItems;

  Map<String, dynamic> row({
    String status = 'CREATED',
    bool withLabel = false,
    String? reprintReason,
  }) =>
      {
        'id': 'bpr-00000001',
        'packageId': _kPkgId,
        'requestedByUserId': 'u1',
        'requestedByName': 'สมหญิง ใจดี',
        'requestedAt': '2026-07-24T01:00:00.000Z',
        'mode': 'BROWSER_DIALOG',
        'templateVersion': '1',
        'copies': 1,
        'isReprint': reprintRequired,
        'reprintReason': reprintReason,
        'status': status,
        'dialogOpenedAt':
            status == 'CREATED' ? null : '2026-07-24T01:01:00.000Z',
        'userConfirmedAt':
            status == 'USER_CONFIRMED' ? '2026-07-24T01:02:00.000Z' : null,
        'cancelledAt':
            status == 'CANCELLED' ? '2026-07-24T01:02:00.000Z' : null,
        'createdFrom': 'PACKAGE_DETAIL',
        'createdAt': '2026-07-24T01:00:00.000Z',
        'updatedAt': '2026-07-24T01:00:00.000Z',
        if (withLabel)
          'label': {
            'packageId': _kPkgId,
            'templateName': 'ชุดทำคลอด',
            'wrapType': 'SEAL',
            'status': sterileLabel ? 'STERILE' : 'PACKED',
            'sterilizeDate':
                sterileLabel ? '2026-07-01T00:00:00.000Z' : null,
            'expiryDate': sterileLabel ? '2026-12-28T00:00:00.000Z' : null,
            'isSterilized': sterileLabel,
          },
        if (withLabel)
          'priorPrints': {
            'count': 0,
            'lastAt': null,
            'lastByName': null,
            'lastStatus': null,
            'lastSource': null,
          },
      };

  ResponseBody _json(Object data, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  void _record(String op, RequestOptions o) {
    events.add(op);
    idemKeys
        .putIfAbsent(op, () => [])
        .add(o.headers['Idempotency-Key'] as String?);
  }

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final p = o.path;
    if (p == '/browser-print-requests' && o.method == 'POST') {
      _record('POST create', o);
      final body = (o.data as Map?)?.cast<String, dynamic>() ?? const {};
      createBodies.add(body);
      final reason = body['reprintReason'] as String?;
      if (reprintRequired && (reason == null || reason.isEmpty)) {
        return _json({
          'message': 'ต้องระบุเหตุผลการพิมพ์ซ้ำ',
          'code': 'BROWSER_PRINT_REPRINT_REASON_REQUIRED',
          'prior': {
            'count': 2,
            'lastAt': '2026-07-20T03:00:00.000Z',
            'lastByName': 'สมศรี มั่นคง',
            'lastStatus': 'USER_CONFIRMED',
            'lastSource': 'BROWSER',
          },
        }, 400);
      }
      return _json(row(withLabel: true, reprintReason: reason));
    }
    if (p.endsWith('/dialog-opened') && o.method == 'POST') {
      _record('POST dialog-opened', o);
      if (failDialogOpened) {
        return _json(
            {'message': 'สถานะไม่ถูกต้อง', 'code': 'BROWSER_PRINT_STATE'}, 409);
      }
      return _json(row(status: 'DIALOG_OPENED'));
    }
    if (p.endsWith('/confirm') && o.method == 'POST') {
      _record('POST confirm', o);
      return _json(row(status: 'USER_CONFIRMED'));
    }
    if (p.endsWith('/cancel') && o.method == 'POST') {
      _record('POST cancel', o);
      return _json(row(status: 'CANCELLED'));
    }
    if (p == '/browser-print-requests' && o.method == 'GET') {
      events.add('GET list');
      return _json({
        'items': listItems,
        'total': listItems.length,
        'page': 1,
        'pageSize': 20,
      });
    }
    if (p.startsWith('/packages/')) return _json(_pkgJson());
    return _json(const {});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations th;
  setUpAll(() async {
    th = await AppLocalizations.delegate.load(const Locale('th'));
  });

  Future<void> pumpN(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// สร้าง container + pump [home] ภายใต้ overrides ครบชุด (dio ปลอม + flag +
  /// print seam + render seam) — คืน adapter/บันทึกที่ใช้ assert
  Future<void> pumpApp(
    WidgetTester tester, {
    required _BpAdapter adapter,
    required Widget home,
    bool flagOn = true,
    List<LabelData>? renderedLabels,
  }) async {
    // จอสูงพอให้เนื้อหาทั้ง sheet/ListView ถูก build (ListView สร้าง child แบบ lazy)
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
      ..httpClientAdapter = adapter;
    final container = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(dio),
      browserPrintEnabledProvider.overrideWithValue(flagOn),
      printPdfProvider.overrideWithValue((bytes, name) async {
        adapter.events.add('print-seam');
      }),
      renderLabelPngProvider.overrideWithValue(
          (LabelData data, {int widthMm = 60, int heightMm = 40}) async {
        renderedLabels?.add(data);
        return _tinyPng;
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ));
    await pumpN(tester);
  }

  /// host เปิด sheet (ฟังก์ชัน show ต้องมี context+ref) — sheetHost pattern
  Widget sheetHost(PackageModel pkg) => Consumer(builder: (context, ref, _) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBrowserPrintSheet(context, ref,
                  pkg: pkg, createdFrom: 'PACKAGE_DETAIL'),
              child: const Text('open'),
            ),
          ),
        );
      });

  Future<void> openSheet(
    WidgetTester tester, {
    required _BpAdapter adapter,
    PackageModel? pkg,
    List<LabelData>? renderedLabels,
  }) async {
    await pumpApp(tester,
        adapter: adapter,
        home: sheetHost(pkg ?? _pkgModel()),
        renderedLabels: renderedLabels);
    await tester.tap(find.text('open'));
    await pumpN(tester);
  }

  Future<void> tapInSheet(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await pumpN(tester);
  }

  group('feature flag (§14.1–§14.2)', () {
    testWidgets('§14.1 flag ปิด → ไม่มีปุ่มพิมพ์ผ่านเครื่องนี้และไม่มีการ์ดประวัติ',
        (tester) async {
      await pumpApp(tester,
          adapter: _BpAdapter(),
          home: const PackageDetailPage(id: _kPkgId),
          flagOn: false);
      expect(find.byTooltip(th.bpPrintViaThisDevice), findsNothing);
      expect(find.text(th.bpHistoryTitle), findsNothing);
      // ปุ่มพิมพ์ผ่าน Gateway เดิมยังอยู่ (ไม่กระทบเส้นทางหลัก)
      expect(find.byTooltip(th.pdReprintTooltip), findsOneWidget);
    });

    testWidgets('§14.2 flag เปิด → มีปุ่มพิมพ์ผ่านเครื่องนี้ + การ์ดประวัติ',
        (tester) async {
      await pumpApp(tester,
          adapter: _BpAdapter(),
          home: const PackageDetailPage(id: _kPkgId));
      expect(find.byTooltip(th.bpPrintViaThisDevice), findsOneWidget);
      expect(find.text(th.bpHistoryTitle), findsOneWidget);
    });
  });

  group('preview (§14.3–§14.5)', () {
    testWidgets('§14.3 แสดง preview จาก label ของ backend + กล่องคำแนะนำ + คำเตือน',
        (tester) async {
      final adapter = _BpAdapter();
      final rendered = <LabelData>[];
      await openSheet(tester, adapter: adapter, renderedLabels: rendered);
      // สร้างคำขอที่ backend แล้ว (auto-create ตอนเปิด sheet)
      expect(adapter.events, contains('POST create'));
      // preview รูป label + คำแนะนำการตั้งค่า §11 + คำเตือน §10
      expect(find.byType(Image), findsOneWidget);
      // บรรทัดคำแนะนำ render เป็น bullet ('• ...') → ใช้ textContaining
      expect(find.textContaining(th.bpSettingsPrinter), findsOneWidget);
      expect(find.textContaining(th.bpSettingsScale), findsOneWidget);
      expect(find.text(th.bpCannotVerifyWarning), findsOneWidget);
      expect(find.text(th.bpPrintViaThisDevice), findsOneWidget);
      // §14.5: LabelData ที่ส่งเข้า renderer = packageId ตรงจาก payload (QR = id เท่านั้น)
      expect(rendered, hasLength(1));
      expect(rendered.single.packageId, _kPkgId);
      expect(rendered.single.setName, 'ชุดทำคลอด');
    });

    test('§14.4 mapper: label ยังไม่ sterile → LabelData ไม่มีวันที่ (แม้ payload หลุดมา)',
        () {
      final unsterile = BrowserPrintLabel(
        packageId: _kPkgId,
        templateName: 'ชุดทำคลอด',
        wrapType: 'SEAL',
        status: 'PACKED',
        // จำลอง payload ผิดปกติที่มีวันที่มาแต่ isSterilized=false — ต้องไม่แสดง
        sterilizeDate: DateTime(2026, 7, 1),
        expiryDate: DateTime(2026, 12, 28),
        isSterilized: false,
      );
      final data = browserPrintLabelData(unsterile);
      expect(data.sterilizeDate, isNull);
      expect(data.expiryDate, isNull);
      expect(data.isSterilized, isFalse);

      final sterile = BrowserPrintLabel(
        packageId: _kPkgId,
        templateName: 'ชุดทำคลอด',
        wrapType: 'SEAL',
        status: 'STERILE',
        sterilizeDate: DateTime(2026, 7, 1),
        expiryDate: DateTime(2026, 12, 28),
        isSterilized: true,
      );
      expect(browserPrintLabelData(sterile).sterilizeDate, DateTime(2026, 7, 1));
    });

    testWidgets('§14.4 UI: ห่อยังไม่ sterile → แสดงป้ายยังไม่ผ่านการฆ่าเชื้อ ไม่มีบรรทัดวันที่',
        (tester) async {
      final adapter = _BpAdapter(sterileLabel: false);
      await openSheet(tester, adapter: adapter);
      expect(find.text(th.bpUnsterileNotice), findsOneWidget);
      expect(find.textContaining('หมดอายุ'), findsNothing);
    });

    test('§14.5 QR content = package id เท่านั้น (passthrough ไม่แต่งเติม)', () {
      const label = BrowserPrintLabel(
        packageId: _kPkgId,
        templateName: 'ชุดทำคลอด',
        wrapType: 'SEAL',
        status: 'STERILE',
      );
      // label_renderer วาด QR จาก LabelData.packageId ตรง ๆ (กฎโดเมน:
      // QR เก็บแค่ id) — mapper ต้องส่งผ่านค่าเดิมโดยไม่ผสมข้อมูลอื่น
      expect(browserPrintLabelData(label).packageId, same(label.packageId));
    });
  });

  group('ลำดับ create → dialog-opened → print (§14.6–§14.8)', () {
    testWidgets('§14.6 สร้าง request ที่ backend ก่อนเรียก print เสมอ',
        (tester) async {
      final adapter = _BpAdapter();
      await openSheet(tester, adapter: adapter);
      await tapInSheet(tester, th.bpPrintViaThisDevice);
      expect(adapter.events, contains('POST create'));
      expect(adapter.events, contains('print-seam'));
      expect(adapter.events.indexOf('POST create'),
          lessThan(adapter.events.indexOf('print-seam')));
    });

    testWidgets('§14.7 บันทึก dialog-opened สำเร็จก่อน จึงเรียก print seam (+ มี Idempotency-Key)',
        (tester) async {
      final adapter = _BpAdapter();
      await openSheet(tester, adapter: adapter);
      await tapInSheet(tester, th.bpPrintViaThisDevice);
      final openedAt = adapter.events.indexOf('POST dialog-opened');
      final printedAt = adapter.events.indexOf('print-seam');
      expect(openedAt, isNonNegative);
      expect(printedAt, isNonNegative);
      expect(openedAt, lessThan(printedAt));
      expect(adapter.idemKeys['POST dialog-opened']!.single, isNotNull);
    });

    testWidgets('§14.7 dialog-opened ล้มเหลว → ห้ามเรียก print seam',
        (tester) async {
      final adapter = _BpAdapter(failDialogOpened: true);
      await openSheet(tester, adapter: adapter);
      await tapInSheet(tester, th.bpPrintViaThisDevice);
      expect(adapter.events, contains('POST dialog-opened'));
      expect(adapter.events, isNot(contains('print-seam')));
      // ยังอยู่หน้า preview (ปุ่มพิมพ์ยังอยู่ ให้ผู้ใช้ตัดสินใจเอง — ไม่ auto-retry)
      expect(find.text(th.bpPrintViaThisDevice), findsWidgets);
    });

    testWidgets('§14.8 หลัง print seam คืนค่า → ไม่ auto-confirm ต้องให้ผู้ใช้เลือกผล 3 ทาง',
        (tester) async {
      final adapter = _BpAdapter();
      await openSheet(tester, adapter: adapter);
      await tapInSheet(tester, th.bpPrintViaThisDevice);
      expect(adapter.events, isNot(contains('POST confirm')));
      expect(adapter.events, isNot(contains('POST cancel')));
      expect(find.text(th.bpResultQuestion), findsOneWidget);
      expect(find.text(th.bpResultPrinted), findsOneWidget);
      expect(find.text(th.bpResultNotPrinted), findsOneWidget);
      expect(find.text(th.bpResultLater), findsOneWidget);
    });
  });

  group('การยืนยันผลโดยผู้ใช้ (§14.9–§14.10)', () {
    testWidgets('§14.9 ปุ่ม "กระดาษออกถูกต้อง" เรียก POST /confirm', (tester) async {
      final adapter = _BpAdapter();
      await openSheet(tester, adapter: adapter);
      await tapInSheet(tester, th.bpPrintViaThisDevice);
      await tapInSheet(tester, th.bpResultPrinted);
      expect(adapter.events, contains('POST confirm'));
      expect(adapter.idemKeys['POST confirm']!.single, isNotNull);
      // sheet ปิดแล้ว
      expect(find.text(th.bpResultQuestion), findsNothing);
    });

    testWidgets('§14.10 ปุ่ม "ไม่ได้พิมพ์/ยกเลิก" เรียก POST /cancel', (tester) async {
      final adapter = _BpAdapter();
      await openSheet(tester, adapter: adapter);
      await tapInSheet(tester, th.bpPrintViaThisDevice);
      await tapInSheet(tester, th.bpResultNotPrinted);
      expect(adapter.events, contains('POST cancel'));
      expect(adapter.events, isNot(contains('POST confirm')));
      expect(find.text(th.bpResultQuestion), findsNothing);
    });
  });

  group('reprint (§14.11)', () {
    testWidgets('§14.11 ห่อเคยพิมพ์ (printedAt) → เตือน + บังคับเหตุผลก่อนสร้างคำขอ',
        (tester) async {
      final adapter = _BpAdapter();
      await openSheet(tester,
          adapter: adapter,
          pkg: _pkgModel(printedAt: DateTime(2026, 7, 20, 10)));
      // ยังไม่สร้างคำขอ (ไม่ auto-create เมื่อเป็น reprint)
      expect(adapter.events, isNot(contains('POST create')));
      expect(find.text(th.bpReprintWarning), findsOneWidget);
      // กดสร้างโดยไม่กรอกเหตุผล → ถูกบล็อก ไม่ยิง API
      await tapInSheet(tester, th.bpCreateRequest);
      expect(adapter.events, isNot(contains('POST create')));
      expect(find.text(th.bpReprintReasonRequired), findsOneWidget);
      // กรอกเหตุผลแล้วสร้างได้ — เหตุผลติดไปกับ payload
      await tester.enterText(find.byType(TextField), 'label เดิมชำรุด');
      await tapInSheet(tester, th.bpCreateRequest);
      expect(adapter.events, contains('POST create'));
      expect(adapter.createBodies.single['reprintReason'], 'label เดิมชำรุด');
    });

    testWidgets('§14.11 backend ตอบ 400 REPRINT_REASON_REQUIRED → เตือนพร้อม prior แล้ว retry ด้วย key เดิม',
        (tester) async {
      final adapter = _BpAdapter(reprintRequired: true);
      await openSheet(tester, adapter: adapter); // printedAt=null → auto-create
      // create แรกโดน 400 → กลับมาหน้าเตือน + เหตุผล (แสดงข้อมูลครั้งก่อนจาก error body)
      expect(adapter.events, contains('POST create'));
      expect(find.text(th.bpReprintWarning), findsOneWidget);
      expect(find.textContaining('สมศรี มั่นคง'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'label สูญหาย');
      await tapInSheet(tester, th.bpCreateRequest);
      final keys = adapter.idemKeys['POST create']!;
      expect(keys, hasLength(2));
      expect(keys[0], isNotNull);
      // retry ใช้ Idempotency-Key **เดิม** — backend replay ไม่สร้างคำขอซ้ำ
      expect(keys[1], keys[0]);
      // ได้ preview ตามปกติหลังส่งเหตุผล
      expect(find.text(th.bpPrintViaThisDevice), findsOneWidget);
    });
  });

  group('ประวัติ (§14.12)', () {
    testWidgets('§14.12 การ์ดประวัติแสดงสถานะตามความหมาย §12 (USER_CONFIRMED = ผู้ใช้ยืนยัน)',
        (tester) async {
      final base = _BpAdapter();
      final adapter = _BpAdapter(listItems: [
        base.row(status: 'CREATED'),
        {...base.row(status: 'DIALOG_OPENED'), 'id': 'bpr-00000002'},
        {
          ...base.row(status: 'USER_CONFIRMED'),
          'id': 'bpr-00000003',
          'isReprint': true,
          'reprintReason': 'label เดิมชำรุด',
        },
        {...base.row(status: 'CANCELLED'), 'id': 'bpr-00000004'},
      ]);
      await pumpApp(tester,
          adapter: adapter,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: BrowserPrintHistoryCard(packageId: _kPkgId),
            ),
          ));
      // ข้อความสถานะภาษาไทยตรงตาม directive §12 ทุกตัว
      expect(find.text('สร้างคำขอแล้ว'), findsOneWidget);
      expect(find.text('เปิดหน้าต่างพิมพ์แล้ว ยังไม่ยืนยันผล'), findsOneWidget);
      expect(find.text('ผู้ใช้ยืนยันว่ากระดาษออกแล้ว'), findsOneWidget);
      expect(find.text('ผู้ใช้แจ้งว่าไม่ได้พิมพ์หรือยกเลิก'), findsOneWidget);
      // ฟิลด์ §12: ผู้สั่ง / mode+สำเนา+template version / เหตุผล reprint / เลขคำขอ
      expect(find.text(th.bpHistoryReason('label เดิมชำรุด')), findsOneWidget);
      expect(find.text(th.bpHistoryRequestId('bpr-0000')), findsWidgets);
      expect(find.textContaining('สมหญิง ใจดี'), findsNWidgets(4));
      expect(find.textContaining('BROWSER_DIALOG'), findsNWidgets(4));
    });

    test('§14.12 ข้อความ ARB ตรงตาม directive แบบคำต่อคำ (กันสื่อความหมายผิด)', () {
      expect(th.bpStatusCreated, 'สร้างคำขอแล้ว');
      expect(th.bpStatusDialogOpened, 'เปิดหน้าต่างพิมพ์แล้ว ยังไม่ยืนยันผล');
      expect(th.bpStatusUserConfirmed, 'ผู้ใช้ยืนยันว่ากระดาษออกแล้ว');
      expect(th.bpStatusCancelled, 'ผู้ใช้แจ้งว่าไม่ได้พิมพ์หรือยกเลิก');
      expect(th.bpCannotVerifyWarning,
          'ระบบ Browser ไม่สามารถตรวจสอบกระดาษที่ออกจากเครื่องได้ กรุณาตรวจ Label ก่อนยืนยัน');
    });
  });
}
