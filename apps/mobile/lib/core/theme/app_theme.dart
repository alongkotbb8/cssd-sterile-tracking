import 'package:flutter/material.dart';

// ============================================================================
// PULSE — Design tokens (pulse-design-system.html)
// สกัดจาก Pulse Healthcare Design System — ฟ้าการแพทย์เป็นสีหลัก, มุมโค้งใหญ่,
// เงาฟ้านุ่ม. คงชื่อคลาส `SterelisColors` ไว้ (โค้ดอ้างอิง 400+ จุด) และ token
// เดิมค่าตรงกับ Pulse อยู่แล้ว — เพิ่ม token ที่ขาด (scale เต็ม + sky/star/border-strong)
// ============================================================================
class SterelisColors {
  SterelisColors._();

  // Primary — Brand blue scale (500 = PRIMARY)
  static const blue50  = Color(0xFFEDF3FE);
  static const blue100 = Color(0xFFDCE8FD);
  static const blue200 = Color(0xFFB9D0FB);
  static const blue300 = Color(0xFF8FB2F6);
  static const blue400 = Color(0xFF5E8DEF);
  static const blue500 = Color(0xFF2F6BED); // PRIMARY
  static const blue600 = Color(0xFF1F54CC);
  static const blue700 = Color(0xFF1A45A6);

  // Deep ink (ปุ่มเข้ม / แถบนำทางล่าง / scanner)
  static const ink900 = Color(0xFF0F2233);
  static const ink800 = Color(0xFF142B40);
  static const ink700 = Color(0xFF1E3A52);

  // Teal accent (secondary / wrap-seal)
  static const teal700 = Color(0xFF15485B);
  static const teal500 = Color(0xFF2C7A92);
  static const teal100 = Color(0xFFD9EAF0);

  // Tinted surface (การ์ดฟ้าอ่อน)
  static const sky = Color(0xFFEAF1FD);

  // Neutrals
  static const textStrong  = Color(0xFF122033);
  static const text        = Color(0xFF2C3A4B);
  static const textMuted   = Color(0xFF6B7A8D);
  static const textFaint   = Color(0xFF9AA7B6);
  static const surface     = Color(0xFFF5F8FC);
  static const surface2    = Color(0xFFEEF2F8);
  static const white       = Color(0xFFFFFFFF);
  static const border      = Color(0xFFE3EAF2);
  static const borderStrong = Color(0xFFD2DBE6);

  // Semantic
  static const success   = Color(0xFF2BB673);
  static const successBg = Color(0xFFE6F7EF);
  static const warning   = Color(0xFFF5A623);
  static const warningBg = Color(0xFFFEF3E0);
  static const danger    = Color(0xFFE5484D);
  static const dangerBg  = Color(0xFFFCE9E9);
  static const star      = Color(0xFFFFB020);

  // Package status
  static const stPacked      = Color(0xFF6B7A8D);
  static const stPackedBg    = Color(0xFFEEF2F8);
  static const stSterile     = Color(0xFF2BB673);
  static const stSterileBg   = Color(0xFFE6F7EF);
  static const stIssued      = Color(0xFF2F6BED);
  static const stIssuedBg    = Color(0xFFEDF3FE);
  static const stReturned    = Color(0xFFF5A623);
  static const stReturnedBg  = Color(0xFFFEF3E0);
  static const stExpired     = Color(0xFFE5484D);
  static const stExpiredBg   = Color(0xFFFCE9E9);
  static const stDiscarded   = Color(0xFF52606D);
  static const stDiscardedBg = Color(0xFFE7EBF0);

  // Wrap type
  static const wrapSeal    = Color(0xFF2C7A92);
  static const wrapSealBg  = Color(0xFFD9EAF0);
  static const wrapCloth   = Color(0xFF8A5CF6);
  static const wrapClothBg = Color(0xFFF0EAFE);
}

/// ระยะห่าง (ฐาน 4px) ตาม Pulse spacing scale
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// มุมโค้ง ตาม Pulse radius scale
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const brSm = BorderRadius.all(Radius.circular(sm));
  static const brMd = BorderRadius.all(Radius.circular(md));
  static const brLg = BorderRadius.all(Radius.circular(lg));
  static const brXl = BorderRadius.all(Radius.circular(xl));
  static const brPill = BorderRadius.all(Radius.circular(pill));
}

/// เงา (elevation) ตาม Pulse — ฟ้านุ่ม ยกการ์ดให้ลอยเบา ๆ
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0F0F2233), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A0F2233), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x1A1F54CC), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x291F54CC), blurRadius: 44, offset: Offset(0, 18)),
  ];
  // sh-blue — เงาเรืองใต้ CTA สีฟ้า
  static const List<BoxShadow> blue = [
    BoxShadow(color: Color(0x4D2F6BED), blurRadius: 26, offset: Offset(0, 12)),
  ];
}

class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'Sarabun';

  /// gradient ของ hero/CTA เด่น (blue-500 → blue-700) ตาม Pulse
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SterelisColors.blue500, SterelisColors.blue700],
  );

  static ThemeData get light {
    const primary = SterelisColors.blue500;

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: SterelisColors.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: Colors.white,
        secondary: SterelisColors.teal500,
        onSecondary: Colors.white,
        surface: SterelisColors.white,
        onSurface: SterelisColors.textStrong,
        error: SterelisColors.danger,
        onError: Colors.white,
      ),
    );

    return base.copyWith(
      // ---- Typography (Pulse type scale) ----
      textTheme: _textTheme(base.textTheme),

      // ---- AppBar ----
      appBarTheme: const AppBarTheme(
        backgroundColor: SterelisColors.white,
        foregroundColor: SterelisColors.textStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 19,
          color: SterelisColors.textStrong,
        ),
      ),

      // ---- Bottom navigation (Pulse: ปลอดโปร่ง ขาว + indicator ฟ้าอ่อน) ----
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: SterelisColors.white,
        indicatorColor: SterelisColors.blue50,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const RoundedRectangleBorder(
            borderRadius: AppRadius.brPill),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: SterelisColors.blue600, size: 24);
          }
          return const IconThemeData(color: SterelisColors.textMuted, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: _fontFamily,
            color: selected ? SterelisColors.blue600 : SterelisColors.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          );
        }),
      ),

      // ---- Primary button = pill สีฟ้า + เงาเรือง (sh-blue) ----
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: SterelisColors.blue200,
          disabledForegroundColor: Colors.white,
          shadowColor: SterelisColors.blue500.withValues(alpha: 0.35),
          elevation: 6,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          textStyle: const TextStyle(
              fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shadowColor: SterelisColors.blue500.withValues(alpha: 0.35),
          elevation: 6,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          textStyle: const TextStyle(
              fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),

      // ---- Secondary (tonal ฟ้าอ่อน) ----
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SterelisColors.blue600,
          side: const BorderSide(color: SterelisColors.borderStrong, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
          textStyle: const TextStyle(
              fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SterelisColors.blue600,
          textStyle: const TextStyle(
              fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      // ---- FAB (Pulse: มุมโค้ง 18 + เงาฟ้า) ----
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      // ---- Card (พื้นขาว + มุมโค้ง lg + เส้นขอบบาง) ----
      cardTheme: const CardThemeData(
        color: SterelisColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: SterelisColors.border),
        ),
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // ---- Chip (category tabs / filter) ----
      chipTheme: const ChipThemeData(
        backgroundColor: SterelisColors.white,
        selectedColor: SterelisColors.blue500,
        checkmarkColor: Colors.white,
        side: BorderSide(color: SterelisColors.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brPill),
        labelStyle: TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: SterelisColors.textMuted),
        secondaryLabelStyle: TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.white),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),

      // ---- Input (มุมโค้ง md + focus ring ฟ้า) ----
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: SterelisColors.white,
        border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: SterelisColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: SterelisColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: SterelisColors.blue500, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: SterelisColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: SterelisColors.danger, width: 2),
        ),
        labelStyle: TextStyle(
            fontFamily: _fontFamily, color: SterelisColors.textMuted),
        hintStyle: TextStyle(
            fontFamily: _fontFamily, color: SterelisColors.textFaint),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ---- Dialog / BottomSheet / SnackBar ----
      dialogTheme: const DialogThemeData(
        backgroundColor: SterelisColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brXl),
        titleTextStyle: TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 19,
            color: SterelisColors.textStrong),
        contentTextStyle: TextStyle(
            fontFamily: _fontFamily, fontSize: 15, color: SterelisColors.text),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SterelisColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SterelisColors.ink900,
        contentTextStyle: TextStyle(
            fontFamily: _fontFamily, color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        insetPadding: EdgeInsets.all(16),
      ),

      dividerTheme:
          const DividerThemeData(color: SterelisColors.border, space: 1),
      splashFactory: InkRipple.splashFactory,
    );
  }

  // แมปสเกลตัวอักษร Pulse → TextTheme (Sarabun; w800 → snap เป็น 700 ที่ bundle ไว้)
  static TextTheme _textTheme(TextTheme base) {
    return base
        .apply(
          fontFamily: _fontFamily,
          bodyColor: SterelisColors.text,
          displayColor: SterelisColors.textStrong,
        )
        .copyWith(
          displaySmall: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 32,
              height: 1.15,
              letterSpacing: -0.5,
              color: SterelisColors.textStrong),
          headlineMedium: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 26,
              height: 1.2,
              color: SterelisColors.textStrong),
          headlineSmall: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1.2,
              color: SterelisColors.textStrong),
          titleLarge: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 19,
              color: SterelisColors.textStrong),
          titleMedium: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: SterelisColors.textStrong),
          bodyLarge: const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 15,
              height: 1.5,
              color: SterelisColors.text),
          bodyMedium: const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 14,
              height: 1.5,
              color: SterelisColors.text),
          bodySmall: const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 13,
              color: SterelisColors.textMuted),
          labelLarge: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 14),
          labelSmall: const TextStyle(
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.6,
              color: SterelisColors.textFaint),
        );
  }
}
