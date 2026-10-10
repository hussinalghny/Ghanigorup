import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/cart.dart';
import '../core/api.dart';
import '../state/notifications.dart';
import '../state/push.dart';
import '../state/session.dart';
import '../widgets/heads_up.dart';
import '../widgets/links.dart';
import '../widgets/motion.dart';
import '../widgets/welcome.dart';
import 'account_screen.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'order_screen.dart';

/// الهيكل الرئيسي: 4 تبويبات + شريط سفلي بأسلوب التصميم المعتمد
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'تصفّح'),
    (Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'الطلب'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
  ];

  StreamSubscription<AppNotification>? _sub;

  @override
  void initState() {
    super.initState();
    final notifs = context.read<NotificationsState>();
    _sub = notifs.incoming.listen((n) {
      if (!mounted) return;
      showHeadsUp(context, n, onTap: () {
        notifs.markAllRead();
        openAppLink(context, n.link);
      });
    });
    notifs.start();
    // الإشعارات الفورية (Firebase) — لا تعمل إلا إذا أُضيفت ملفات Firebase وقت البناء
    final push = PushService(
      api: context.read<ApiClient>(),
      session: context.read<SessionState>(),
      notifications: notifs,
      openLink: (link) {
        final c = appNavigator.currentContext;
        if (c != null) openAppLink(c, link);
      },
    );
    Future.delayed(const Duration(milliseconds: 1500), push.start);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) maybeShowWelcome(context, context.read<AppState>().config.welcome);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final count = context.select<CartState, int>((c) => c.count);
    return PopScope(
      canPop: app.tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.read<AppState>().goTab(0);
      },
      child: Scaffold(
        body: _FadeIndexedStack(
          index: app.tab,
          children: const [HomeScreen(), BrowseScreen(), OrderScreen(), AccountScreen()],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: C.shadow, blurRadius: 30, offset: const Offset(0, -10))],
          ),
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _NavItem(
                  icon: app.tab == i ? _tabs[i].$2 : _tabs[i].$1,
                  label: _tabs[i].$3,
                  active: app.tab == i,
                  badge: i == 2 ? count : 0,
                  onTap: () {
                    if (app.tab != i) HapticFeedback.selectionClick();
                    context.read<AppState>().goTab(i);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مثل IndexedStack لكن مع انتقال ناعم بين التبويبات، ويُبقي حالة كل تبويب
class _FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _FadeIndexedStack({required this.index, required this.children});

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);

  @override
  void didUpdateWidget(_FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: HeroMode(
                enabled: i == widget.index,
                // نفس البنية دائماً حتى لا تضيع حالة التبويب عند التبديل
                child: FadeTransition(
                  opacity: i == widget.index ? a : const AlwaysStoppedAnimation(1.0),
                  child: SlideTransition(
                    position: i == widget.index
                        ? Tween<Offset>(begin: const Offset(0, .015), end: Offset.zero).animate(a)
                        : const AlwaysStoppedAnimation(Offset.zero),
                    child: widget.children[i],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: active ? C.ink : Colors.transparent, borderRadius: BorderRadius.circular(23)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: AnimatedCount(badge, style: const TextStyle(fontSize: 10)),
                backgroundColor: C.red,
                child: AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  child: Icon(icon, size: 22, color: active ? C.onInk : C.muted),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: active
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(label, style: TextStyle(color: C.onInk, fontSize: 13, fontWeight: FontWeight.w500)),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
