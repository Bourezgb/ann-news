import 'package:flutter/material.dart';

/// ألوان الهوية البصرية للشبكة الجزائرية للأخبار (ANN)، مأخوذة من الملصقات المعتمدة.
class BrandColors {
  /// الأحمر الأساسي لخلفيات الملصقات.
  static const primary = Color(0xFFB61A1B);
  static const primaryDark = Color(0xFF8E1213);

  /// أحمر الشعار الأساسي.
  static const logoRed = Color(0xFFE50000);

  /// البرتقالي المستعمل في عناصر التمييز (مثل شارة الموقع).
  static const orange = Color(0xFFF67C01);
  static const white = Colors.white;
  static const grey = Color(0xFF8E9BA0);
}

const appFont = 'BeIN';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: BrandColors.primary, brightness: brightness).copyWith(
    primary: dark ? const Color(0xFFE05A5B) : BrandColors.primary,
    onPrimary: Colors.white,
    secondary: dark ? const Color(0xFFFFA64D) : BrandColors.orange,
    onSecondary: Colors.black,
    tertiary: BrandColors.logoRed,
    error: dark ? const Color(0xFFFF8A80) : BrandColors.logoRed,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: appFont,
    scaffoldBackgroundColor: dark ? const Color(0xFF161010) : const Color(0xFFF7F5F5),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: dark ? const Color(0xFF241716) : BrandColors.primary,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
