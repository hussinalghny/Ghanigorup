import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/i18n.dart';

class RemoteConfig {
  final bool forceUpdate, updateAvailable;
  final String storeUrl;
  final String? maintenance;
  final WelcomeMessage? welcome;
  final String homeTitle, homeSubtitle;
  RemoteConfig({
    this.forceUpdate = false,
    this.updateAvailable = false,
    this.storeUrl = '',
    this.maintenance,
    this.welcome,
    this.homeTitle = '',
    this.homeSubtitle = '',
  });
}

/// بيانات عامة مشتركة + التنقل بين التبويبات
class AppState extends ChangeNotifier {
  final ApiClient api;
  AppState(this.api);

  Map<String, String> settings = {};
  List<GearCategory> categories = [];
  RemoteConfig config = RemoteConfig();
  String version = '1.0.0';
  String build = '1';

  // ---- التبويبات ----
  int tab = 0;
  String browseCategory = '';
  String browseBrand = '';
  String browseQuery = '';
  bool browseFocus = false;
  int browseNonce = 0;

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  void openBrowse({String category = '', String brand = '', String query = '', bool focus = false}) {
    browseCategory = category;
    browseBrand = brand;
    browseQuery = query;
    browseFocus = focus;
    browseNonce++;
    tab = 1;
    notifyListeners();
  }

  String get whatsapp => (settings['whatsapp'] ?? '').isNotEmpty ? settings['whatsapp']! : AppConfig.fallbackWhatsapp;
  String get phone => (settings['phone'] ?? '').isNotEmpty ? settings['phone']! : AppConfig.fallbackPhone;
  // عناوين الرئيسية من لوحة التحكم عربية — بالإنكليزية نعرض عنواناً ثابتاً
  String get homeTitle => L.en ? 'What are you shooting' : _homeTitleAr;
  String get homeSubtitle => L.en ? 'this week?' : _homeSubtitleAr;
  String get _homeTitleAr => config.homeTitle.isNotEmpty ? config.homeTitle : ((settings['home_title'] ?? '').isNotEmpty ? settings['home_title']! : 'ماذا ستصوّر');
  String get _homeSubtitleAr => config.homeTitle.isNotEmpty ? config.homeSubtitle : (settings['home_subtitle'] ?? 'هذا الأسبوع؟');

  String get currency => (settings['currency'] ?? '').isNotEmpty ? settings['currency']! : 'IQD';

  /// يُستدعى عند الإقلاع: نسخة التطبيق + الإعدادات + فحص التحديث الإجباري
  Future<void> bootstrap() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}
    await Future.wait<void>([
      loadSettings(),
      _loadConfig(),
      loadCategories().then((_) {}, onError: (_) {}),
    ]);
  }

  Future<void> _loadConfig() async {
    try {
      final r = await api.get('/app/config', {'platform': Platform.isIOS ? 'ios' : 'android', 'version': version});
      final m = r.map;
      final home = m['home'] is Map ? Map<String, dynamic>.from(m['home'] as Map) : const <String, dynamic>{};
      config = RemoteConfig(
        forceUpdate: m['force_update'] == true,
        updateAvailable: m['update_available'] == true,
        storeUrl: '${m['store_url'] ?? ''}',
        maintenance: m['maintenance'] == null ? null : '${m['maintenance']}',
        welcome: m['welcome'] is Map ? WelcomeMessage.fromJson(Map<String, dynamic>.from(m['welcome'] as Map)) : null,
        homeTitle: '${home['title'] ?? ''}',
        homeSubtitle: '${home['subtitle'] ?? ''}',
      );
    } catch (_) {
      config = RemoteConfig();
    }
  }

  Future<void> loadSettings() async {
    try {
      final r = await api.get('/settings');
      settings = r.map.map((k, v) => MapEntry(k, v == null ? '' : '$v'));
      notifyListeners();
    } catch (_) {}
  }

  Future<List<GearCategory>> loadCategories({bool force = false}) async {
    if (categories.isNotEmpty && !force) return categories;
    final r = await api.get('/categories');
    categories = r.list.map(GearCategory.fromJson).toList();
    notifyListeners();
    return categories;
  }
}
