import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../screens/item_screen.dart';
import '../state/cart.dart';
import 'common.dart';
import '../core/i18n.dart';

void openItem(BuildContext context, Equipment e, {String? heroTag}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemScreen(slug: e.slug, preview: e, heroTag: heroTag)));
}

/// بطاقة معدة (شبكة)
class EquipmentCard extends StatelessWidget {
  final Equipment item;
  final double imageHeight;
  final String heroPrefix;
  const EquipmentCard(this.item, {super.key, this.imageHeight = 130, this.heroPrefix = 'eq'});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final inCart = cart.has(item.slug);
    final tag = '$heroPrefix-${item.slug}';
    return Pressable(
      scale: .97,
      child: Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => openItem(context, item, heroTag: tag),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: imageHeight,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Hero(tag: tag, child: NetImage(item.image)),
                        ),
                      ),
                    ),
                    if (item.isNew)
                      PositionedDirectional(
                        top: 6,
                        start: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(20)),
                          child: Text(tr('جديد', 'New'), style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(item.brand, style: Txt.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    textAlign: L.en ? TextAlign.left : TextAlign.right,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: tr('في الأسطول ', 'In fleet ')),
                            TextSpan(text: '${item.qtyTotal}', style: TextStyle(color: C.ink, fontWeight: FontWeight.w600)),
                          ]),
                          style: Txt.small,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: inCart ? tr('إزالة من الطلب', 'Remove from order') : tr('أضف للطلب', 'Add to order'),
                        child: Pressable(
                          scale: .85,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final on = context.read<CartState>().toggle(item);
                            showToast(context, on ? tr('${item.name} أضيفت للطلب', '${item.name} added to your order') : tr('أزيلت من الطلب', 'Removed from order'));
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: inCart ? C.ink : C.soft, borderRadius: BorderRadius.circular(inCart ? 19 : 12)),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (c, a) => RotationTransition(
                                turns: Tween<double>(begin: -.25, end: 0).animate(a),
                                child: ScaleTransition(scale: a, child: c),
                              ),
                              child: Icon(inCart ? Icons.check_rounded : Icons.add_rounded,
                                  key: ValueKey(inCart), size: 19, color: inCart ? C.onInk : C.ink),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شبكة معدات بعمودين داخل CustomScrollView — تظهر البطاقات بشكل متتابع
class EquipmentSliverGrid extends StatelessWidget {
  final List<Equipment> items;
  final String heroPrefix;
  const EquipmentSliverGrid(this.items, {super.key, this.heroPrefix = 'grid'});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 900 ? 4 : (w >= 600 ? 3 : 2);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 262,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => Reveal(
            key: ValueKey('$heroPrefix-${items[i].slug}'),
            index: i % (cols * 3),
            scale: true,
            child: EquipmentCard(items[i], heroPrefix: heroPrefix),
          ),
          childCount: items.length,
        ),
      ),
    );
  }
}

/// صف أفقي من البطاقات
class EquipmentRow extends StatelessWidget {
  final List<Equipment> items;
  final String heroPrefix;
  const EquipmentRow(this.items, {super.key, this.heroPrefix = 'row'});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 262,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => Reveal(
            index: i,
            offset: const Offset(30, 0),
            child: SizedBox(width: 172, child: EquipmentCard(items[i], heroPrefix: heroPrefix)),
          ),
        ),
      );
}
