import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api.dart';
import '../core/firebase_options.dart';
import '../core/models.dart';
import 'notifications.dart';
import 'session.dart';

/// الإشعارات الفورية (Firebase Cloud Messaging):
///  - يطلب الإذن، يسجّل رمز الجهاز في السيرفر (مع الحساب أو طلبات الضيف)، ويشترك في موضوع "all" للإعلانات
///  - التطبيق مفتوح: نحدّث صندوق الإشعارات فيظهر التنبيه المنزلق الخاص بالتطبيق
///  - الضغط على إشعار والتطبيق بالخلفية/مغلق: يفتح الصفحة المرتبطة (طلب، ماركة، معدة…)
/// إذا لم تُضف ملفات Firebase (FirebaseConfig.enabled = false) لا يفعل شيئاً.
class PushService {
  final ApiClient api;
  final SessionState session;
  final NotificationsState notifications;
  final void Function(AppLink link) openLink;
  PushService({required this.api, required this.session, required this.notifications, required this.openLink});

  bool _started = false;
  String? _token;
  int? _userId;
  String _version = '';

  static bool get available => FirebaseConfig.enabled && FirebaseConfig.options != null;

  Future<void> start() async {
    if (_started || !available) return;
    _started = true;
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      final m = FirebaseMessaging.instance;
      try {
        _version = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}

      // التطبيق مفتوح: لا نعرض إشعار النظام (iOS) — التنبيه المنزلق داخل التطبيق يكفي
      await m.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((_) => notifications.refresh());
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
      final initial = await m.getInitialMessage();
      if (initial != null) {
        // التطبيق فُتح بالضغط على إشعار: ننتظر اكتمال الواجهة
        Future.delayed(const Duration(milliseconds: 900), () => _handleTap(initial));
      }

      final perm = await m.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;

      try {
        await m.subscribeToTopic('all');
      } catch (e) {
        debugPrint('push topic: $e');
      }
      _token = await _getToken(m);
      m.onTokenRefresh.listen((t) {
        _token = t;
        register();
      });
      _userId = session.user?.id;
      session.addListener(() {
        if (session.user?.id != _userId) {
          _userId = session.user?.id;
          register();
        }
      });
      notifications.onTrackChanged = register;
      await register();
    } catch (e) {
      // مثلاً: توقيع بدون صلاحية Push على iOS — نكمل بالإشعارات الداخلية
      debugPrint('push disabled: $e');
    }
  }

  Future<String?> _getToken(FirebaseMessaging m) async {
    if (Platform.isIOS) {
      // على iOS يجب أن يصل رمز APNs أولاً
      for (var i = 0; i < 10; i++) {
        if (await m.getAPNSToken() != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    try {
      return await m.getToken();
    } catch (e) {
      debugPrint('push token: $e');
      return null;
    }
  }

  Future<void> register() async {
    final t = _token;
    if (t == null) return;
    try {
      await api.post('/devices', {
        'token': t,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app_version': _version,
        'track': notifications.track,
      });
    } catch (e) {
      debugPrint('push register: $e');
    }
  }

  void _handleTap(RemoteMessage msg) {
    final d = msg.data;
    notifications.refresh();
    final type = '${d['link_type'] ?? ''}';
    if (type.isEmpty || type == 'none') return;
    WidgetsBinding.instance.addPostFrameCallback((_) => openLink(AppLink(type, '${d['link_value'] ?? ''}')));
    WidgetsBinding.instance.scheduleFrame();
  }
}
