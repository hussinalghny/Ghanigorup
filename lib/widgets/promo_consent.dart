import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';
import '../core/i18n.dart';

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
            Text(tr('توصلك العروض؟', 'Get our offers?'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(tr('نرسل لك إشعار عند وجود خصومات أو معدات جديدة. إشعارات طلباتك توصل دائماً، وتگدر تغيّر هذا الاختيار من حسابي.', 'We will notify you about discounts and new gear. Order notifications always arrive, and you can change this anytime from Account.'),
                textAlign: TextAlign.center, style: Txt.muted),
            const SizedBox(height: 20),
            AppButton(tr('نعم، أرسلوا لي العروض', 'Yes, send me offers'), onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            AppButton.light(tr('لا شكراً', 'No thanks'), onPressed: () => Navigator.pop(ctx, false)),
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
          title: tr('إشعارات العروض', 'Offer notifications'),
          subtitle: tr('خصومات ومعدات جديدة — إشعارات الطلبات توصل دائماً', 'Discounts and new gear — order notifications always arrive'),
          value: _on,
          divider: false,
          onChanged: (v) {
            setState(() => _on = v);
            widget.write(v);
          },
        ),
      ]);
}
