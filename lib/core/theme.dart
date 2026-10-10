import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// لوحة ألوان واحدة (فاتح أو داكن)
class Palette {
  final Color bg, surface, ink, muted, line, soft, red, ok, okBg, warn, warnBg, redBg;

  /// نص/أيقونة فوق تعبئة ink (الأزرار الأساسية، التبويب النشط)
  final Color onInk;

  /// نص خافت فوق تعبئة ink، وحدود فوقها، وتعبئة ثانوية فوقها
  final Color inkMuted, inkLine, ink2;

  /// خلفية الأيام الوسطى في التقويم، وخلفية صور المنتجات في الوضع الداكن، والظل
  final Color midSel, imageWell, shadow;

  const Palette({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.soft,
    required this.red,
    required this.ok,
    required this.okBg,
    required this.warn,
    required this.warnBg,
    required this.redBg,
    required this.onInk,
    required this.inkMuted,
    required this.inkLine,
    required this.ink2,
    required this.midSel,
    required this.imageWell,
    required this.shadow,
  });

  static const light = Palette(
    bg: Color(0xFFF2F0EB),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF141414),
    muted: Color(0xFF85817A),
    line: Color(0xFFE6E2DA),
    soft: Color(0xFFECE9E2),
    red: Color(0xFFB82619),
    ok: Color(0xFF2C7A45),
    okBg: Color(0xFFE3F1E6),
    warn: Color(0xFFA26A09),
    warnBg: Color(0xFFFBEFD9),
    redBg: Color(0xFFFBE3E5),
    onInk: Color(0xFFFFFFFF),
    inkMuted: Color(0xFFAAAAAA),
    inkLine: Color(0xFF333333),
    ink2: Color(0xFF2A2A2A),
    midSel: Color(0xFFDAD6CE),
    imageWell: Color(0xFFFFFFFF),
    shadow: Color(0x0D000000),
  );

  static const dark = Palette(
    bg: Color(0xFF0E0E0F),
    surface: Color(0xFF1A1A1C),
    ink: Color(0xFFF2EFE9),
    muted: Color(0xFF8E8A83),
    line: Color(0xFF2C2C2F),
    soft: Color(0xFF26262A),
    red: Color(0xFFE0483C),
    ok: Color(0xFF5CC27E),
    okBg: Color(0xFF16301F),
    warn: Color(0xFFE5A83F),
    warnBg: Color(0xFF33270F),
    redBg: Color(0xFF3A1614),
    onInk: Color(0xFF141414),
    inkMuted: Color(0xFF66625C),
    inkLine: Color(0xFFCFCBC3),
    ink2: Color(0xFFDDD9D1),
    midSel: Color(0xFF3A3A3F),
    imageWell: Color(0xFFEDEBE6),
    shadow: Color(0x55000000),
  );
}

/// ألوان التصميم المعتمد (Studio) — تتبع الوضع الحالي (فاتح/داكن).
/// تُقرأ وقت البناء، وعند تبديل الوضع يُعاد بناء كل الشاشات (انظر main.dart).
class C {
  static bool dark = false;
  static Palette get p => dark ? Palette.dark : Palette.light;

  static Color get bg => p.bg;
  static Color get surface => p.surface;
  static Color get ink => p.ink;
  static Color get muted => p.muted;
  static Color get line => p.line;
  static Color get soft => p.soft;
  static Color get red => p.red;
  static Color get ok => p.ok;
  static Color get okBg => p.okBg;
  static Color get warn => p.warn;
  static Color get warnBg => p.warnBg;
  static Color get redBg => p.redBg;
  static Color get onInk => p.onInk;
  static Color get inkMuted => p.inkMuted;
  static Color get inkLine => p.inkLine;
  static Color get ink2 => p.ink2;
  static Color get midSel => p.midSel;
  static Color get imageWell => p.imageWell;
  static Color get shadow => p.shadow;

  /// أحمر الهوية الثابت (شاشة البداية والشعار)
  static const brand = Color(0xFFB82619);
}

class AppTheme {
  static const font = 'Alexandria';

  static SystemUiOverlayStyle overlay(bool dark) => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      );

  static ThemeData build(bool dark) {
    final p = dark ? Palette.dark : Palette.light;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: font,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.ink,
        brightness: brightness,
        primary: p.ink,
        onPrimary: p.onInk,
        secondary: p.red,
        surface: p.surface,
        onSurface: p.ink,
      ),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay(dark),
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: p.surface, surfaceTintColor: Colors.transparent),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onInk : p.muted),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentTextStyle: TextStyle(fontFamily: font, color: p.onInk, fontSize: 13.5),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: font, bodyColor: p.ink, displayColor: p.ink),
    );
  }
}

/// انتقال الصفحات في أندرويد: ظهور تدريجي مع انزلاق خفيف للأعلى
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: inCurve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .06), end: Offset.zero).animate(inCurve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: .96).animate(outCurve),
          child: child,
        ),
      ),
    );
  }
}

/// أنماط نصوص متكررة (تتبع الوضع الحالي)
class Txt {
  static TextStyle get h1 => TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1.3, color: C.ink);
  static TextStyle get title => TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: C.ink);
  static TextStyle get section => TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.ink);
  static TextStyle get body => TextStyle(fontSize: 14, color: C.ink, height: 1.7);
  static TextStyle get muted => TextStyle(fontSize: 13, color: C.muted, height: 1.6);
  static TextStyle get small => TextStyle(fontSize: 11.5, color: C.muted);
}
