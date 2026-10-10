import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/cart.dart';
import 'account_screen.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'order_screen.dart';

/// الهيكل الرئيسي: 4 تبويبات + شريط سفلي بأسلوب التصميم المعتمد
class Shell extends StatelessWidget {
  const Shell({super.key});

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'تصفّح'),
    (Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'الطلب'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
  ];

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
        body: IndexedStack(
          index: app.tab,
          children: const [HomeScreen(), BrowseScreen(), OrderScreen(), AccountScreen()],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 30, offset: Offset(0, -10))],
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
                  onTap: () => context.read<AppState>().goTab(i),
                ),
            ],
          ),
        ),
      ),
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
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: active ? C.ink : Colors.transparent, borderRadius: BorderRadius.circular(23)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge', style: const TextStyle(fontSize: 10)),
                backgroundColor: C.red,
                child: Icon(icon, size: 22, color: active ? Colors.white : C.muted),
              ),
              if (active) ...[
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
