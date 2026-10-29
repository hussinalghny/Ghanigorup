import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// لغة الواجهة الحالية — تُقرأ وقت البناء (مثل ألوان C)
class L {
  static bool en = false;
  static String get code => en ? 'en' : 'ar';
  static TextDirection get dir => en ? TextDirection.ltr : TextDirection.rtl;
}

/// نص بلغتين: العربي هو الأصل، والإنكليزي يظهر عند اختيار English
String tr(String ar, String en) => L.en ? en : ar;

enum AppLang { system, ar, en }

/// اختيار اللغة (تلقائي حسب لغة الجهاز / العربية / English) — محفوظ على الجهاز
class LangState extends ChangeNotifier with WidgetsBindingObserver {
  static const _key = 'gg_lang';
  AppLang lang = AppLang.system;

  bool get isEn {
    if (lang == AppLang.en) return true;
    if (lang == AppLang.ar) return false;
    // تلقائي: العربية إذا كانت ضمن لغات الجهاز، وإلا الإنكليزية
    final locales = PlatformDispatcher.instance.locales;
    if (locales.isEmpty) return false;
    return !const ['ar', 'ku', 'ckb'].contains(locales.first.languageCode);
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      lang = AppLang.values.firstWhere((m) => m.name == v, orElse: () => AppLang.system);
    } catch (_) {}
    L.en = isEn;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> set(AppLang m) async {
    if (m == lang) return;
    lang = m;
    L.en = isEn;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, m.name);
    } catch (_) {}
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (lang == AppLang.system && L.en != isEn) {
      L.en = isEn;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
