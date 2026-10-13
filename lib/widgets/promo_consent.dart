import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';

/// طلب موافقة صريحة على إشعارات العروض (Apple 4.5.4) — يُعرض مرة واحدة
Future<bool?> askPromoConsent(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: C.redBg, borderRadius: BorderRadius.circular(22)),
              child: Icon(Icons.local_offer_rounded, color: C.red, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('توصلك العروض؟', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('نرسل لك إشعار عند وجود خصومات أو معدات جديدة. إشعارات طلباتك توصل دائماً، وتگدر تغيّر هذا الاختيار من حسابي.',
                textAlign: TextAlign.center, style: Txt.muted),
            const SizedBox(height: 20),
            AppButton('نعم، أرسلوا لي العروض', onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            AppButton.light('لا شكراً', onPressed: () => Navigator.pop(ctx, false)),
          ],
        ),
      ),
    ),
  );
}

/// مفتاح إشعارات العروض في صفحة الحساب
class PromoToggle extends StatefulWidget {
  final Future<bool?> Function() read;
  final Future<void> Function(bool) write;
  const PromoToggle({super.key, required this.read, required this.write});

  @override
  State<PromoToggle> createState() => _PromoToggleState();
}

class _PromoToggleState extends State<PromoToggle> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    widget.read().then((v) {
      if (mounted) setState(() => _on = v ?? false);
    });
  }

  @override
  Widget build(BuildContext context) => FormCard(children: [
        ToggleRow(
          title: 'إشعارات العروض',
          subtitle: 'خصومات ومعدات جديدة — إشعارات الطلبات توصل دائماً',
          value: _on,
          divider: false,
          onChanged: (v) {
            setState(() => _on = v);
            widget.write(v);
          },
        ),
      ]);
}
