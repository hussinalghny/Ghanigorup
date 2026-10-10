import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../screens/item_screen.dart';
import '../state/cart.dart';
import 'common.dart';

void openItem(BuildContext context, Equipment e) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemScreen(slug: e.slug, preview: e)));
}

/// بطاقة معدة (شبكة)
class EquipmentCard extends StatelessWidget {
  final Equipment item;
  final double imageHeight;
  const EquipmentCard(this.item, {super.key, this.imageHeight = 130});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final inCart = cart.has(item.slug);
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => openItem(context, item),
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
                        child: NetImage(item.image),
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
                        child: const Text('جديد', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
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
                  textAlign: TextAlign.right,
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
                          const TextSpan(text: 'في الأسطول '),
                          TextSpan(text: '${item.qtyTotal}', style: const TextStyle(color: C.ink, fontWeight: FontWeight.w600)),
                        ]),
                        style: Txt.small,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: inCart ? 'إزالة من الطلب' : 'أضف للطلب',
                      child: Material(
                        color: inCart ? C.ink : C.soft,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            final on = context.read<CartState>().toggle(item);
                            showToast(context, on ? '${item.name} أضيفت للطلب' : 'أزيلت من الطلب');
                          },
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(inCart ? Icons.check_rounded : Icons.add_rounded, size: 19, color: inCart ? Colors.white : C.ink),
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
    );
  }
}

/// شبكة معدات بعمودين داخل CustomScrollView
class EquipmentSliverGrid extends StatelessWidget {
  final List<Equipment> items;
  const EquipmentSliverGrid(this.items, {super.key});

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
        delegate: SliverChildBuilderDelegate((_, i) => EquipmentCard(items[i]), childCount: items.length),
      ),
    );
  }
}

/// صف أفقي من البطاقات
class EquipmentRow extends StatelessWidget {
  final List<Equipment> items;
  const EquipmentRow(this.items, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 262,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 172, child: EquipmentCard(items[i])),
        ),
      );
}
