import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'session.dart';

/// الإشعارات داخل التطبيق:
///  - الإعلانية (للجميع) + تحديثات الطلبات (للمسجّل، وللضيف عبر رقم الطلب والهاتف المحفوظين على الجهاز)
///  - تُحدَّث عند فتح التطبيق، وعند العودة إليه، وكل دقيقة أثناء استخدامه
///  - الإشعار الجديد يظهر كتنبيه منزلق أعلى الشاشة (انظر widgets/heads_up.dart)
class NotificationsState extends ChangeNotifier with WidgetsBindingObserver {
  final ApiClient api;
  final SessionState session;
  NotificationsState(this.api, this.session);

  static const _kSeen = 'gg_notif_seen';
  static const _kTrack = 'gg_track';
  static const _kCache = 'gg_notif_cache';

  List<AppNotification> items = [];
  int lastSeen = 0;
  int _maxKnown = -1; // -1 = لم يتم التحميل بعد (لا نعرض تنبيهات لأول تحميل)
  bool loading = false;
  final List<Map<String, String>> _track = [];
  Timer? _timer;
  int? _userId;
  final _incoming = StreamController<AppNotification>.broadcast();

  Stream<AppNotification> get incoming => _incoming.stream;

  /// طلبات الضيف المتابَعة (للتسجيل في الإشعارات الفورية)
  List<Map<String, String>> get track => List.unmodifiable(_track);
  VoidCallback? onTrackChanged;
  int get unread => items.where((n) => n.id > lastSeen).length;

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final p = await SharedPreferences.getInstance();
      lastSeen = p.getInt(_kSeen) ?? 0;
      final t = p.getString(_kTrack);
      if (t != null) {
        for (final e in (jsonDecode(t) as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          _track.add({'ref': '${m['ref']}', 'phone': '${m['phone']}'});
        }
      }
      final c = p.getString(_kCache);
      if (c != null) {
        items = (jsonDecode(c) as List).map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (items.isNotEmpty) _maxKnown = items.first.id;
      }
    } catch (_) {}
    notifyListeners();
    _userId = session.user?.id;
    session.addListener(_onSession);
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void _onSession() {
    final id = session.user?.id;
    if (id != _userId) {
      _userId = id;
      refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// يُستدعى بعد إرسال طلب جديد حتى يصل الضيف إشعار تغيّر حالته
  Future<void> addTrack(String ref, String phone) async {
    _track.removeWhere((t) => t['ref'] == ref);
    _track.insert(0, {'ref': ref, 'phone': phone});
    if (_track.length > 20) _track.removeRange(20, _track.length);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kTrack, jsonEncode(_track));
    } catch (_) {}
    onTrackChanged?.call();
    refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    try {
      final r = _track.isEmpty ? await api.get('/notifications') : await api.post('/notifications/feed', {'track': _track});
      final list = r.list.map(AppNotification.fromJson).toList();
      final firstLoad = _maxKnown < 0;
      final fresh = firstLoad ? <AppNotification>[] : list.where((n) => n.id > _maxKnown && n.id > lastSeen).toList();
      items = list;
      if (list.isNotEmpty && list.first.id > _maxKnown) _maxKnown = list.first.id;
      if (_maxKnown < 0) _maxKnown = 0;
      // أحدث إشعار جديد فقط كتنبيه منزلق (لتجنب سيل تنبيهات)
      if (fresh.isNotEmpty) _incoming.add(fresh.first);
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_kCache, jsonEncode(list.take(40).map((e) => e.toJson()).toList()));
      } catch (_) {}
      notifyListeners();
    } catch (_) {
      // بدون إنترنت: نبقي آخر نسخة محفوظة
    } finally {
      loading = false;
    }
  }

  Future<void> markAllRead() async {
    if (items.isEmpty) return;
    final top = items.map((e) => e.id).reduce((a, b) => a > b ? a : b);
    if (top <= lastSeen) return;
    lastSeen = top;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSeen, lastSeen);
    } catch (_) {}
  }

  /// رقم هاتف الضيف المحفوظ لطلب معيّن (لفتح صفحة التتبع مباشرة)
  String? phoneFor(String ref) {
    for (final t in _track) {
      if (t['ref'] == ref) return t['phone'];
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    session.removeListener(_onSession);
    WidgetsBinding.instance.removeObserver(this);
    _incoming.close();
    super.dispose();
  }
}
