import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/packages/presentation/pages/package_detail_page.dart';
import '../../features/packages/presentation/pages/packages_page.dart';
import '../../features/print_jobs/presentation/pages/print_job_detail_page.dart';
import '../../features/print_jobs/presentation/pages/print_jobs_page.dart';
import '../../features/reports/presentation/pages/report_page.dart';
import '../../features/scan/presentation/pages/scan_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../auth/auth_controller.dart';
import '../theme/app_theme.dart';

final _shellKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    // เริ่มที่ /login เสมอ (ไม่ใช่ /dashboard) เพราะตอน build แรก authState
    // ยังเป็น unknown อยู่ — ถ้าเริ่มที่ /dashboard หน้านั้นจะ mount และยิง
    // API ทั้งที่ยังไม่มี token ทำให้ error 401 ถูก cache ค้างใน provider
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final onLogin = state.matchedLocation == '/login';
      switch (auth.status) {
        case AuthStatus.unknown:
          return onLogin ? null : '/login'; // ยังไม่รู้ → รอที่ login ก่อน
        case AuthStatus.unauthenticated:
          return onLogin ? null : '/login';
        case AuthStatus.authenticated:
          return onLogin ? '/dashboard' : null;
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginPage()),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/scan', builder: (c, s) => const ScanPage()),
          GoRoute(path: '/packages', builder: (c, s) => const PackagesPage()),
          GoRoute(path: '/print-jobs', builder: (c, s) => const PrintJobsPage()),
          GoRoute(path: '/dashboard', builder: (c, s) => const DashboardPage()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
        ],
      ),
      // Detail routes pushed above the shell
      GoRoute(
        path: '/packages/:id',
        builder: (c, s) => PackageDetailPage(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/print-jobs/:id',
        builder: (c, s) => PrintJobDetailPage(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/reports', builder: (c, s) => const ReportPage()),
    ],
  );
});

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    ('/dashboard', Icons.bar_chart_rounded, 'แดชบอร์ด'),
    ('/scan', Icons.qr_code_scanner_rounded, 'สแกน'),
    ('/packages', Icons.inventory_2_outlined, 'รายการ'),
    ('/print-jobs', Icons.print_outlined, 'งานพิมพ์'),
    ('/settings', Icons.settings_outlined, 'ตั้งค่า'),
  ];

  int _indexOf(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => loc.startsWith(t.$1));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexOf(context),
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        backgroundColor: SterelisColors.white,
        destinations: _tabs
            .map((t) => NavigationDestination(icon: Icon(t.$2), label: t.$3))
            .toList(),
      ),
    );
  }
}
