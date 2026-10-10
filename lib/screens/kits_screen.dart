import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/cart.dart';
import '../widgets/common.dart';
import '../widgets/equipment_card.dart';

class KitsScreen extends StatefulWidget {
  const KitsScreen({super.key});

  @override
  State<KitsScreen> createState() => _KitsScreenState();
}

class _KitsScreenState extends State<KitsScreen> {
  late Future<List<Kit>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Kit>> _load() async {
    final r = await context.read<ApiClient>().get('/kits');
    return r.list.map(Kit.fromJson).toList();
  }

  void _addKit(Kit k) {
    final c = context.read<CartState>();
    for (final e in k.items) {
      if (!c.has(e.slug)) c.add(e, e.kitQty);
    }
    showToast(context, '${k.nameAr} أضيفت للطلب');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('باقات جاهزة', style: TextStyle(fontWeight: FontWeight.w600))),
      body: FutureBuilder<List<Kit>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(snap.error!, onRetry: () => setState(() {
                _future = _load();
              }));
          if (!snap.hasData) return Center(child: CircularProgressIndicator(color: C.ink));
          final kits = snap.data!;
          return ListView(
            padding: EdgeInsets.only(bottom: 30 + MediaQuery.paddingOf(context).bottom),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text('مجموعات معدات مجرّبة لأنواع التصوير الأكثر طلباً. أضف الباقة كاملة ثم عدّل الكميات من صفحة الطلب.', style: Txt.muted),
              ),
              for (final k in kits) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k.nameAr, style: Txt.section),
                            Text('${k.nameEn} · ${k.items.length} قطع', style: Txt.small),
                          ],
                        ),
                      ),
                      AppButton('أضف الباقة', onPressed: () => _addKit(k), expand: false, height: 42),
                    ],
                  ),
                ),
                EquipmentRow(k.items, heroPrefix: 'kit-${k.slug}'),
              ],
            ],
          );
        },
      ),
    );
  }
}
