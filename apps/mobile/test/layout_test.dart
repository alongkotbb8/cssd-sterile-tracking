import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cssd_mobile/core/api/api_client.dart';
import 'package:cssd_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:cssd_mobile/features/settings/presentation/pages/settings_page.dart';
import 'package:cssd_mobile/l10n/app_localizations.dart';

// Gate 1 §1B — Layout tests: 320px / Pixel 7 / Desktop Chrome ที่ text scale
// 1.0 และ 1.3 ทั้ง th/en ต้องไม่มี overflow (RenderFlex overflow โยน exception
// ใน widget test → จับด้วย tester.takeException)
//
// ครอบหน้า public/self-contained ที่ pump ได้โดยไม่ต้องมี backend: Login, Settings
// (หน้า interior ที่เหลือใช้ข้อมูลจาก API — ตรวจใน E2E/Gate 4 บนอุปกรณ์จริง)

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

  Future<void> pumpAt(
    WidgetTester tester, {
    required Widget page,
    required Size size,
    required double scale,
    required Locale locale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
    await tester.pumpAndSettle();
  }

  for (final entry in _sizes.entries) {
    for (final scale in _scales) {
      for (final locale in _locales) {
        final label =
            '${entry.key} · scale $scale · ${locale.languageCode}';

        testWidgets('Login ไม่ overflow @ $label', (tester) async {
          await pumpAt(tester,
              page: const LoginPage(),
              size: entry.value,
              scale: scale,
              locale: locale);
          expect(tester.takeException(), isNull,
              reason: 'layout overflow/exception ที่ $label');
        });

        testWidgets('Settings ไม่ overflow @ $label', (tester) async {
          await pumpAt(tester,
              page: const SettingsPage(),
              size: entry.value,
              scale: scale,
              locale: locale);
          expect(tester.takeException(), isNull,
              reason: 'layout overflow/exception ที่ $label');
        });
      }
    }
  }
}
