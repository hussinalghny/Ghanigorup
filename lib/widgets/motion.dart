import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// تصغير خفيف عند الضغط (إحساس زر حقيقي) + اهتزاز لمسي خفيف
class Pressable extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;
  final VoidCallback? onTap;
  final bool haptic;
  const Pressable({super.key, required this.child, this.enabled = true, this.scale = .96, this.onTap, this.haptic = false});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap == null || !widget.enabled
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 260),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// ظهور متدرج: انزلاق + تلاشي، بتأخير حسب ترتيب العنصر (للقوائم والشبكات)
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final bool scale;
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = const Offset(0, 24),
    this.scale = false,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    // حد أقصى للتأخير حتى لا تتأخر العناصر البعيدة في القوائم الطويلة
    final idx = widget.index < 0 ? 0 : (widget.index > 10 ? 10 : widget.index);
    final ms = widget.delay.inMilliseconds + idx * 55;
    if (ms <= 0 || MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first).disableAnimations) {
      _c.forward();
    } else {
      _t = Timer(Duration(milliseconds: ms), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (_, child) {
        final v = _a.value;
        Widget w = Transform.translate(offset: Offset(widget.offset.dx * (1 - v), widget.offset.dy * (1 - v)), child: child);
        if (widget.scale) w = Transform.scale(scale: .92 + .08 * v, child: w);
        return Opacity(opacity: v, child: w);
      },
    );
  }
}

/// وميض متحرك لعناصر التحميل (Skeleton)
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = C.soft;
    final hi = C.dark ? const Color(0xFF34343A) : const Color(0xFFF8F6F2);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = _c.value * 3 - 1; // من -1 إلى 2
          return LinearGradient(
            begin: Alignment(x - 1, -.3),
            end: Alignment(x + 1, .3),
            colors: [base, hi, base],
            stops: const [.35, .5, .65],
          ).createShader(r);
        },
        child: child,
      ),
    );
  }
}

/// رقم يتغير بحركة (عدّاد)
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  const AnimatedCount(this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (c, a) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .6), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: c),
        ),
        child: Text('$value', key: ValueKey(value), style: style),
      );
}

/// انتقال ناعم بين محتوى التحميل والمحتوى الفعلي
class FadeSwitch extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const FadeSwitch({super.key, required this.child, this.duration = const Duration(milliseconds: 350)});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: c),
        ),
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
        child: child,
      );
}
