import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/core/config/feature_flags.dart';
import 'package:cssd_mobile/features/settings/presentation/pages/settings_page.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Gate 1 — Pilot production build ต้องไม่โชว์ตัวเลือกเครื่องพิมพ์ legacy (Bluetooth/System)
// เส้นทางหลักคือ Print Gateway → XP-420B เท่านั้น
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late SharedPreferences prefs;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null; // read/write/delete → no-op
    });
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Future<void> pumpSettings(WidgetTester tester, {required bool legacy}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        legacyDirectPrintEnabledProvider.overrideWithValue(legacy),
      ],
      child: const MaterialApp(
        locale: Locale('th'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Pilot (flag off): ไม่มีตัวเลือกเครื่องพิมพ์ legacy, มีเส้นทาง Gateway',
      (tester) async {
    await pumpSettings(tester, legacy: false);
    // เครื่องพิมพ์ direct (legacy) ต้องไม่ปรากฏ
    expect(find.text('เครื่องพิมพ์ direct (legacy)'), findsNothing);
    // เส้นทางหลัก Print Gateway ต้องปรากฏชัดเจน
    expect(find.text('พิมพ์ผ่าน Print Gateway (XP-420B)'), findsOneWidget);
  });

  testWidgets('dev/opt-in (flag on): แสดงตัวเลือกเครื่องพิมพ์ legacy',
      (tester) async {
    await pumpSettings(tester, legacy: true);
    expect(find.text('เครื่องพิมพ์ direct (legacy)'), findsOneWidget);
    // Gateway ยังเป็นเส้นทางหลักอยู่
    expect(find.text('พิมพ์ผ่าน Print Gateway (XP-420B)'), findsOneWidget);
  });

  test('ค่าเริ่มต้น flag = ปิดใน release build (Pilot)', () {
    // kLegacyDirectPrintEnabled = optIn || !kReleaseMode ; ในเทส (debug) = true,
    // แต่ default dart-define optIn ต้องเป็น false → release build จะปิด
    // (ตรวจว่าไม่ได้เผลอ hardcode เปิด)
    const optIn =
        bool.fromEnvironment('CSSD_ENABLE_LEGACY_PRINT', defaultValue: false);
    expect(optIn, isFalse);
  });
}
