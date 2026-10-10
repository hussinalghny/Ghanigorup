import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/cart.dart';
import '../widgets/common.dart';
import '../widgets/equipment_card.dart';
import 'kits_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  final List<GearCategory> cats;
  final List<Equipment> featured, fresh;
  final List<Kit> kits;
  _HomeData(this.cats, this.featured, this.fresh, this.kits);
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load({bool force = false}) async {
    final api = context.read<ApiClient>();
    final app = context.read<AppState>();
    final results = await Future.wait([
      app.loadCategories(force: force),
      api.get('/equipment', {'featured': 1, 'per_page': 8}),
      api.get('/equipment', {'new': 1, 'per_page': 8}),
      api.get('/kits'),
    ]);
    return _HomeData(
      results[0] as List<GearCategory>,
      (results[1] as ApiResponse).list.map(Equipment.fromJson).toList(),
      (results[2] as ApiResponse).list.map(Equipment.fromJson).toList(),
      (results[3] as ApiResponse).list.map(Kit.fromJson).toList(),
    );
  }

  Future<void> _refresh() async {
    final f = _load(force: true);
    setState(() {
      _future = f;
    });
    await f.catchError((_) => _HomeData(const [], const [], const [], const []));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: C.ink,
        onRefresh: _refresh,
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snap) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header(context)),
                if (snap.hasError)
                  SliverToBoxAdapter(child: ErrorView(snap.error!, onRetry: _refresh))
                else if (!snap.hasData)
                  SliverToBoxAdapter(child: _skeleton())
                else ..._content(context, snap.data!, app),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/mark.png', width: 30, height: 30),
              const SizedBox(width: 10),
              const Text('Ghani Group', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              Material(
                color: C.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'حسابي',
                  onPressed: () => context.read<AppState>().goTab(3),
                  icon: const Icon(Icons.person_outline_rounded, color: C.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text.rich(
            TextSpan(children: [
              TextSpan(text: 'ماذا ستصوّر\n'),
              TextSpan(text: 'هذا الأسبوع؟', style: TextStyle(color: C.muted, fontWeight: FontWeight.w300)),
            ]),
            style: Txt.h1,
          ),
          const SizedBox(height: 18),
          Semantics(
            button: true,
            label: 'بحث',
            child: GestureDetector(
              onTap: () => context.read<AppState>().openBrowse(focus: true),
              child: Container(
                height: 54,
                padding: const EdgeInsetsDirectional.only(start: 18, end: 7),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: C.muted, size: 21),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('ابحث عن كاميرا، عدسة، إضاءة…', style: TextStyle(color: C.muted, fontSize: 14))),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Column(
          children: [
            Row(children: List.generate(4, (_) => const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Skeleton(height: 86))))),
            const SizedBox(height: 22),
            const Skeleton(height: 200, radius: 28),
            const SizedBox(height: 22),
            Row(children: const [Expanded(child: Skeleton(height: 250)), SizedBox(width: 12), Expanded(child: Skeleton(height: 250))]),
          ],
        ),
      );

  List<Widget> _content(BuildContext context, _HomeData d, AppState app) {
    final hero = app.settings['hero_image'];
    return [
      SliverToBoxAdapter(child: SectionHeader('الأقسام', action: 'عرض الكل', onAction: () => app.openBrowse())),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: d.cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final c = d.cats[i];
              return GestureDetector(
                onTap: () => app.openBrowse(category: c.slug),
                child: SizedBox(
                  width: 86,
                  child: Column(
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24)),
                        child: NetImage(c.image),
                      ),
                      const SizedBox(height: 7),
                      Text(c.nameAr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      Text('${c.count} معدة', style: const TextStyle(fontSize: 10.5, color: C.muted)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KitsScreen())),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                height: 200,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: C.ink),
                    if (hero != null && hero.isNotEmpty) NetImage(hero, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xC0000000), Color(0x00000000)],
                          stops: [0, .65],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: 20,
                      end: 20,
                      bottom: 18,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('GHANI GROUP · FILM PRODUCTION', style: TextStyle(color: Colors.white70, fontSize: 10.5, letterSpacing: .5)),
                                SizedBox(height: 4),
                                Text('أسطول وطاقم فني\nمن التحضير حتى التسليم',
                                    style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, height: 1.4)),
                              ],
                            ),
                          ),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_forward_rounded, color: C.ink, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (d.featured.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader('الأكثر طلباً', action: 'عرض الكل', onAction: () => app.openBrowse())),
        EquipmentSliverGrid(d.featured),
      ],
      if (d.kits.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader('باقات جاهزة', action: 'كل الباقات', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KitsScreen()))),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: d.kits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => KitCard(d.kits[i]),
            ),
          ),
        ),
      ],
      if (d.fresh.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader('وصل حديثاً', action: 'الإضاءة', onAction: () => app.openBrowse(category: 'light'))),
        EquipmentSliverGrid(d.fresh),
      ],
    ];
  }
}

/// بطاقة باقة (أفقية)
class KitCard extends StatelessWidget {
  final Kit kit;
  const KitCard(this.kit, {super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final added = kit.items.isNotEmpty && kit.items.every((e) => cart.has(e.slug));
    return Container(
      width: 290,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(26)),
      child: Row(
        children: [
          SizedBox(width: 84, height: 84, child: NetImage(kit.image)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(kit.nameAr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${kit.items.length} قطع · ${kit.nameEn}', style: Txt.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    final c = context.read<CartState>();
                    for (final e in kit.items) {
                      if (!c.has(e.slug)) c.add(e, e.kitQty);
                    }
                    showToast(context, '${kit.nameAr} أضيفت للطلب');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: added ? C.soft : C.ink, borderRadius: BorderRadius.circular(20)),
                    child: Text(added ? 'مضافة' : 'أضف الباقة',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: added ? C.ink : Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
