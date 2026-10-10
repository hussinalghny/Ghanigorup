import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/models.dart';

/// حالة تسجيل الدخول والمفضلة
class SessionState extends ChangeNotifier {
  final ApiClient api;
  AppUser? user;
  final Set<String> favorites = {};
  bool restoring = true;

  SessionState(this.api) {
    api.onUnauthorized = () {
      user = null;
      favorites.clear();
      notifyListeners();
    };
  }

  bool get loggedIn => user != null;

  Future<void> restore() async {
    if (api.hasToken) {
      try {
        final r = await api.get('/auth/me');
        user = r.data == null ? null : AppUser.fromJson(r.map);
        if (user == null) await api.setToken(null);
        await loadFavorites(notify: false);
      } catch (_) {
        // بدون إنترنت: نبقي التوكن ونحاول لاحقاً
      }
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> _afterAuth(ApiResponse r) async {
    final m = r.map;
    if (m['token'] != null) await api.setToken('${m['token']}');
    user = AppUser.fromJson(Map<String, dynamic>.from(m['user'] as Map));
    await loadFavorites(notify: false);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await _afterAuth(await api.post('/auth/login', {'email': email.trim(), 'password': password}));
  }

  Future<void> register({required String name, required String email, required String phone, String? company, required String password}) async {
    await _afterAuth(await api.post('/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      if (company != null && company.trim().isNotEmpty) 'company': company.trim(),
      'password': password,
    }));
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    await api.setToken(null);
    user = null;
    favorites.clear();
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, String> data) async {
    final r = await api.patch('/auth/me', data);
    user = AppUser.fromJson(r.map);
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async {
    final r = await api.post('/auth/password', {'current': current, 'new': next});
    final t = r.map['token'];
    if (t != null) await api.setToken('$t');
  }

  /// حذف الحساب نهائياً (متطلب Apple و Google)
  Future<void> deleteAccount(String password) async {
    await api.delete('/auth/me', {'password': password});
    await api.setToken(null);
    user = null;
    favorites.clear();
    notifyListeners();
  }

  Future<void> loadFavorites({bool notify = true}) async {
    favorites.clear();
    if (!api.hasToken) return;
    try {
      final r = await api.get('/me/favorites');
      for (final e in r.list) {
        favorites.add('${e['slug']}');
      }
    } catch (_) {}
    if (notify) notifyListeners();
  }

  Future<bool> toggleFavorite(String slug) async {
    final on = !favorites.contains(slug);
    if (on) {
      await api.post('/me/favorites/$slug');
      favorites.add(slug);
    } else {
      await api.delete('/me/favorites/$slug');
      favorites.remove(slug);
    }
    notifyListeners();
    return on;
  }
}
