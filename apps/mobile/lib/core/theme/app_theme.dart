import 'package:flutter/material.dart';

// Design tokens from Sterelis (cssd-design-system.html)
class SterelisColors {
  SterelisColors._();

  // Primary
  static const blue500 = Color(0xFF2F6BED);
  static const blue600 = Color(0xFF1F54CC);
  static const blue100 = Color(0xFFDCE8FD);
  static const blue50  = Color(0xFFEDF3FE);

  // Teal (secondary / wrap-seal)
  static const teal700 = Color(0xFF15485B);
  static const teal500 = Color(0xFF2C7A92);
  static const teal100 = Color(0xFFD9EAF0);

  // Deep ink (แถบเข้ม / scanner)
  static const ink900 = Color(0xFF0F2233);
  static const ink800 = Color(0xFF142B40);
  static const blue300 = Color(0xFF8FB2F6);
  static const blue400 = Color(0xFF5E8DEF);

  // Neutrals
  static const textStrong = Color(0xFF122033);
  static const text       = Color(0xFF2C3A4B);
  static const textMuted  = Color(0xFF6B7A8D);
  static const textFaint  = Color(0xFF9AA7B6);
  static const surface    = Color(0xFFF5F8FC);
  static const surface2   = Color(0xFFEEF2F8);
  static const white      = Color(0xFFFFFFFF);
  static const border     = Color(0xFFE3EAF2);

  // Semantic
  static const success   = Color(0xFF2BB673);
  static const successBg = Color(0xFFE6F7EF);
  static const warning   = Color(0xFFF5A623);
  static const warningBg = Color(0xFFFEF3E0);
  static const danger    = Color(0xFFE5484D);
  static const dangerBg  = Color(0xFFFCE9E9);

  // Package status
  static const stPacked     = Color(0xFF6B7A8D);
  static const stPackedBg   = Color(0xFFEEF2F8);
  static const stSterile    = Color(0xFF2BB673);
  static const stSterileBg  = Color(0xFFE6F7EF);
  static const stIssued     = Color(0xFF2F6BED);
  static const stIssuedBg   = Color(0xFFEDF3FE);
  static const stReturned   = Color(0xFFF5A623);
  static const stReturnedBg = Color(0xFFFEF3E0);
  static const stExpired    = Color(0xFFE5484D);
  static const stExpiredBg  = Color(0xFFFCE9E9);
  static const stDiscarded  = Color(0xFF52606D);
  static const stDiscardedBg = Color(0xFFE7EBF0);

  // Wrap type
  static const wrapSeal    = Color(0xFF2C7A92);
  static const wrapSealBg  = Color(0xFFD9EAF0);
  static const wrapCloth   = Color(0xFF8A5CF6);
  static const wrapClothBg = Color(0xFFF0EAFE);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    const primary = SterelisColors.blue500;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: Colors.white,
        secondary: SterelisColors.teal500,
        surface: SterelisColors.surface,
        error: SterelisColors.danger,
      ),
      scaffoldBackgroundColor: SterelisColors.surface,
      fontFamily: 'Anuphan',

      appBarTheme: const AppBarTheme(
        backgroundColor: SterelisColors.white,
        foregroundColor: SterelisColors.textStrong,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Anuphan',
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: SterelisColors.textStrong,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SterelisColors.white,
        indicatorColor: SterelisColors.blue50,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: SterelisColors.blue500);
          }
          return const IconThemeData(color: SterelisColors.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: SterelisColors.blue500,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(color: SterelisColors.textMuted, fontSize: 12);
        }),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),

      cardTheme: CardThemeData(
        color: SterelisColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: SterelisColors.border),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SterelisColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SterelisColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SterelisColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SterelisColors.blue500, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      dividerTheme: const DividerThemeData(color: SterelisColors.border, space: 1),
    );
  }
}
