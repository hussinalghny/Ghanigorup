import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../screens/notifications_screen.dart';

OverlayEntry? _current;

/// تنبيه منزلق أعلى الشاشة عند وصول إشعار جديد أثناء استخدام التطبيق
void showHeadsUp(BuildContext context, AppNotification n, {required VoidCallback onTap}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.remove();
  _current = null;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _HeadsUp(
      n: n,
      onTap: onTap,
      onDone: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
  HapticFeedback.lightImpact();
}

class _HeadsUp extends StatefulWidget {
  final AppNotification n;
  final VoidCallback onTap, onDone;
  const _HeadsUp({required this.n, required this.onTap, required this.onDone});

  @override
  State<_HeadsUp> createState() => _HeadsUpState();
}

class _HeadsUpState extends State<_HeadsUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), reverseDuration: const Duration(milliseconds: 260));
  Timer? _t;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _t = Timer(const Duration(milliseconds: 4800), _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _t?.cancel();
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final slide = Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic));
    return Positioned(
      top: top + 8,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: _c,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < -100) _close();
              },
              child: NotificationTile(
                widget.n,
                compact: true,
                onTap: () {
                  _close();
                  widget.onTap();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
