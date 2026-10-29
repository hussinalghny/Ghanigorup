import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../core/i18n.dart';

/// شاشة الإقلاع: تحميل الإعدادات + فحص التحديث الإجباري ووضع الصيانة
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<void> _boot;

  @override
  void initState() {
    super.initState();
    _boot = context.read<AppState>().bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _boot,
      builder: (context, snap) {
        Widget page;
        if (snap.connectionState != ConnectionState.done) {
          page = const _BrandSplash(key: ValueKey('splash'));
        } else {
          final cfg = context.read<AppState>().config;
          if (cfg.forceUpdate) {
            page = _GateScreen.update(storeUrl: cfg.storeUrl);
          } else if (cfg.maintenance != null) {
            page = _GateScreen.maintenance(
              message: cfg.maintenance!,
              onRetry: () => setState(() {
                _boot = context.read<AppState>().bootstrap();
              }),
            );
          } else {
            page = const Shell(key: ValueKey('shell'));
          }
        }
        // انتقال ناعم من شاشة البداية إلى التطبيق
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 550),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween<double>(begin: 1.04, end: 1).animate(a), child: child),
          ),
          child: page,
        );
      },
    );
  }
}

/// نفس شاشة البداية الأصلية (لون الشعار + الشعار بنفس الحجم والمكان) حتى لا يحدث وميض
class _BrandSplash extends StatelessWidget {
  const _BrandSplash({super.key});

  static const bg = Color(0xFFEF2B4B);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            Center(
              // نفس حجم الشعار في شاشة البداية الأصلية (220) ثم "نبضة" خفيفة
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.scale(scale: .96 + .04 * v, child: child),
                child: Image.asset('assets/images/logo_full.png', width: 220, filterQuality: FilterQuality.high),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 48,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                builder: (_, v, child) => Opacity(opacity: v, child: child),
                child: const Center(
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      );
}

class _GateScreen extends StatelessWidget {
  final String title, message, button;
  final VoidCallback? onPressed;
  final String? url;

  const _GateScreen({required this.title, required this.message, required this.button, this.onPressed, this.url});

  factory _GateScreen.update({required String storeUrl}) => _GateScreen(
        title: tr('يتوفر إصدار جديد', 'A new version is available'),
        message: tr('حدّث التطبيق للاستمرار — الإصدار الحالي لم يعد مدعوماً.', 'Update the app to continue — this version is no longer supported.'),
        button: tr('تحديث الآن', 'Update now'),
        url: storeUrl,
      );

  factory _GateScreen.maintenance({required String message, required VoidCallback onRetry}) => _GateScreen(
        title: tr('صيانة مؤقتة', 'Temporary maintenance'),
        message: message,
        button: tr('إعادة المحاولة', 'Try again'),
        onPressed: onRetry,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(28)),
                  padding: const EdgeInsets.all(16),
                  child: Image.asset('assets/images/mark.png'),
                ),
                const SizedBox(height: 24),
                Text(title, style: Txt.title, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(message, style: Txt.muted, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                AppButton(
                  button,
                  onPressed: onPressed ?? (url != null && url!.isNotEmpty ? () => openLink(context, url!) : null),
                ),
              ],
            ),
          ),
        ),
      );
}
