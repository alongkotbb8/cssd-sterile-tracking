import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/auth/auth_controller.dart';
import 'core/notifications/fcm_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await FcmService.init();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const CssdApp(),
  ));
}

class CssdApp extends ConsumerWidget {
  const CssdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // ลงทะเบียน FCM token ทันทีที่ล็อกอินสำเร็จ (รวมถึงตอนเปิดแอปแล้ว restore
    // session เดิมได้) — เงียบและไม่มีผลใดๆ ถ้ายังไม่ได้ตั้งค่า Firebase จริง
    ref.listen(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated &&
          previous?.status != AuthStatus.authenticated) {
        registerFcmToken(ref);
      }
    });
    return MaterialApp.router(
      title: 'CSSD Sterile Tracking',
      theme: AppTheme.light,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate, // ข้อความ user-facing (gen-l10n จาก lib/l10n/*.arb)
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales, // th (หลัก) + en
      locale: const Locale('th'), // บังคับไทยเป็นค่าเริ่มต้น (เปลี่ยนได้ภายหลัง)
    );
  }
}
