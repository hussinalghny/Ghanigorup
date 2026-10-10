import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'motion.dart';

export 'motion.dart';

/// صورة من الشبكة مع كاش ومكان مؤقت وظهور تدريجي.
/// في الوضع الداكن تُعرض صور المنتجات (BoxFit.contain) داخل خلفية فاتحة لأن صورها بخلفية بيضاء.
class NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width, height;
  final bool well;
  const NetImage(this.url, {super.key, this.fit = BoxFit.contain, this.width, this.height, this.well = true});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return SizedBox(width: width, height: height, child: Icon(Icons.videocam_outlined, color: C.line, size: 34));
    }
    final img = CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 320),
      fadeInCurve: Curves.easeOut,
      placeholder: (_, __) => SizedBox(width: width, height: height),
      errorWidget: (_, __, ___) => SizedBox(
        width: width,
        height: height,
        child: Icon(Icons.broken_image_outlined, color: C.line, size: 30),
      ),
    );
    if (C.dark && well && fit == BoxFit.contain) {
      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: C.imageWell, borderRadius: BorderRadius.circular(14)),
        child: img,
      );
    }
    return img;
  }
}

/// زر أساسي بأسلوب التصميم
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? color, fgColor;
  final bool loading, expand;
  final double height;
  final IconData? icon;
  final String? trailing;
  final int _variant; // 0 أساسي، 1 أحمر، 2 فاتح

  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.color,
    Color? fg,
    this.loading = false,
    this.expand = true,
    this.height = 56,
    this.icon,
    this.trailing,
  })  : fgColor = fg,
        _variant = 0;

  const AppButton.red(this.label, {super.key, this.onPressed, this.loading = false, this.expand = true, this.height = 56, this.icon, this.trailing})
      : color = null,
        fgColor = null,
        _variant = 1;

  const AppButton.light(this.label, {super.key, this.onPressed, this.loading = false, this.expand = true, this.height = 56, this.icon, this.trailing})
      : color = null,
        fgColor = null,
        _variant = 2;

  Color get bgColor => color ?? (_variant == 1 ? C.red : (_variant == 2 ? C.soft : C.ink));
  Color get fg => fgColor ?? (_variant == 1 ? Colors.white : (_variant == 2 ? C.ink : C.onInk));

  Widget _label() => Text(label,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: height < 48 ? 13.5 : 15));

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
              // Flexible فقط عندما يكون العرض محدداً، وإلا يفشل التخطيط داخل Row
              if (expand)
                Flexible(child: _label())
              else
                _label(),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(trailing!, style: TextStyle(color: fg.withAlpha(160), fontSize: 12)),
              ],
            ],
          );
    return Pressable(
      enabled: !disabled,
      child: AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled && !loading ? .45 : 1,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(height < 48 ? 14 : 18),
        child: InkWell(
          borderRadius: BorderRadius.circular(height < 48 ? 14 : 18),
          onTap: disabled ? null : onPressed,
          child: Container(
            height: height,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(loading), child: child)),
          ),
        ),
      ),
    ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(20, 30, 20, 14)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: Txt.section)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(action!, style: Txt.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// شريحة حالة الطلب
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = OrderStatus.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label, style: TextStyle(color: s.fg, fontSize: 11.5, fontWeight: FontWeight.w500)),
    );
  }
}

/// زر + / − للكمية
class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback onInc, onDec;
  final bool compact;
  final Color? bg;
  const QtyStepper({super.key, required this.value, required this.onInc, required this.onDec, this.compact = false, this.bg});

  @override
  Widget build(BuildContext context) {
    final h = compact ? 40.0 : 56.0;
    Widget btn(String t, VoidCallback f, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: f,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: compact ? 32 : 40, height: h, child: Center(child: Text(t, style: TextStyle(fontSize: compact ? 17 : 21)))),
          ),
        );
    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: bg ?? C.surface, borderRadius: BorderRadius.circular(compact ? 14 : 18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn('+', onInc, 'زيادة'),
          SizedBox(
            width: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
              child: Text('$value', key: ValueKey(value), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          btn('−', onDec, 'إنقاص'),
        ],
      ),
    );
  }
}

/// مفتاح تشغيل بأسلوب التصميم
class ToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool divider;
  const ToggleRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.divider = true});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: divider ? Border(bottom: BorderSide(color: C.line)) : null),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (subtitle != null) Text(subtitle!, style: Txt.small),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged, activeTrackColor: C.ink, inactiveTrackColor: C.soft),
          ],
        ),
      ),
    );
  }
}

/// بطاقة بيضاء تحتوي حقولاً
class FormCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  const FormCard({super.key, required this.children, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24)),
        child: Column(children: children),
      );
}

/// حقل نص بأسلوب "تسمية فوق القيمة"
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint, error;
  final TextInputType? keyboard;
  final bool obscure, last, ltr;
  final int maxLines;
  final int? maxLength;
  final Iterable<String>? autofill;
  final TextInputAction? action;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.keyboard,
    this.obscure = false,
    this.last = false,
    this.ltr = false,
    this.maxLines = 1,
    this.maxLength,
    this.autofill,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: C.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error == null ? label : '$label — $error',
              style: TextStyle(fontSize: 11.5, color: error == null ? C.muted : C.red)),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            obscureText: obscure,
            maxLines: obscure ? 1 : maxLines,
            maxLength: maxLength,
            autofillHints: autofill,
            textInputAction: action,
            textDirection: ltr ? TextDirection.ltr : null,
            textAlign: TextAlign.start,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              hintText: hint,
              hintStyle: TextStyle(color: C.line, fontSize: 15),
              contentPadding: const EdgeInsets.only(top: 6, bottom: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;
  const EmptyState({super.key, required this.title, required this.message, this.action, this.onAction, this.icon = Icons.inventory_2_outlined});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(28)),
              child: Icon(icon, size: 36, color: C.muted),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: Txt.muted, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 22),
              AppButton(action!, onPressed: onAction, expand: false, height: 48),
            ],
          ],
        ),
      );
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView(this.error, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'تعذر التحميل',
        message: '$error',
        action: 'إعادة المحاولة',
        onAction: onRetry,
      );
}

class Skeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton({super.key, required this.height, this.width, this.radius = 24});

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(color: C.soft, borderRadius: BorderRadius.circular(radius)),
        ),
      );
}

void showToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2200)));
}

/// فتح رابط خارجي (واتساب، اتصال، صفحة سياسة)
Future<void> openLink(BuildContext context, String url, {bool inApp = false}) async {
  final uri = Uri.parse(url);
  bool ok = false;
  try {
    ok = await launchUrl(uri, mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) showToast(context, 'تعذر فتح الرابط');
}

String whatsappUrl(String number, String text) =>
    'https://wa.me/${number.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(text)}';
