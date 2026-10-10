import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ألوان التصميم المعتمد (Studio) + أحمر هوية Ghani Group
class C {
  static const bg = Color(0xFFF2F0EB);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF141414);
  static const muted = Color(0xFF85817A);
  static const line = Color(0xFFE6E2DA);
  static const soft = Color(0xFFECE9E2);
  static const red = Color(0xFFB82619);
  static const ok = Color(0xFF2C7A45);
  static const okBg = Color(0xFFE3F1E6);
  static const warn = Color(0xFFA26A09);
  static const warnBg = Color(0xFFFBEFD9);
  static const redBg = Color(0xFFFBE3E5);
}

class AppTheme {
  static const font = 'Alexandria';

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: font,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: C.ink,
        primary: C.ink,
        onPrimary: Colors.white,
        secondary: C.red,
        surface: C.surface,
        brightness: Brightness.light,
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: C.bg,
        foregroundColor: C.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: C.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentTextStyle: const TextStyle(fontFamily: font, color: Colors.white, fontSize: 13.5),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: font, bodyColor: C.ink, displayColor: C.ink),
    );
  }
}

/// أنماط نصوص متكررة
class Txt {
  static const h1 = TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1.3, color: C.ink);
  static const title = TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: C.ink);
  static const section = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.ink);
  static const body = TextStyle(fontSize: 14, color: C.ink, height: 1.7);
  static const muted = TextStyle(fontSize: 13, color: C.muted, height: 1.6);
  static const small = TextStyle(fontSize: 11.5, color: C.muted);
}
