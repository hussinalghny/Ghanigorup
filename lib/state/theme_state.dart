import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

enum AppThemeMode { system, light, dark }

/// وضع المظهر (تلقائي حسب النظام / فاتح / داكن) — محفوظ على الجهاز
class ThemeState extends ChangeNotifier with WidgetsBindingObserver {
  static const _key = 'gg_theme_mode';
  AppThemeMode mode = AppThemeMode.system;

  /// نقطة بداية حركة التبديل الدائرية (موضع زر التبديل على الشاشة)
  Offset? revealFrom;

  bool get isDark {
    if (mode == AppThemeMode.dark) return true;
    if (mode == AppThemeMode.light) return false;
    return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
  }

  /// يُستدعى قبل runApp حتى تظهر أول شاشة بالوضع الصحيح بدون وميض
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      mode = AppThemeMode.values.firstWhere((m) => m.name == v, orElse: () => AppThemeMode.system);
    } catch (_) {}
    C.dark = isDark;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> set(AppThemeMode m, {Offset? from}) async {
    if (m == mode) return;
    mode = m;
    revealFrom = from;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, m.name);
    } catch (_) {}
  }

  @override
  void didChangePlatformBrightness() {
    if (mode == AppThemeMode.system) {
      revealFrom = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
