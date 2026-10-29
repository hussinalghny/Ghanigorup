import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/cart.dart';
import '../state/notifications.dart';
import '../state/theme_state.dart';
import '../widgets/common.dart';
import '../widgets/equipment_card.dart';
import '../widgets/links.dart';
import 'kits_screen.dart';
import 'notifications_screen.dart';
import '../core/i18n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  final List<GearCategory> cats;
  final List<Equipment> featured, fresh;
  final List<Kit> kits;
  final List<PromoBanner> banners;
  final List<Brand> brands;
  _HomeData(this.cats, this.featured, this.fresh, this.kits, this.banners, this.brands);
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
    // البنرات والماركات اختيارية: فشلها لا يوقف الصفحة
    Future<ApiResponse?> opt(Future<ApiResponse> f) => f.then<ApiResponse?>((v) => v).catchError((_) => null);
    final results = await Future.wait([
      app.loadCategories(force: force),
      api.get('/equipment', {'featured': 1, 'per_page': 8}),
      api.get('/equipment', {'new': 1, 'per_page': 8}),
      api.get('/kits'),
      opt(api.get('/banners')),
      opt(api.get('/brands', {'featured': 1})),
    ]);
    return _HomeData(
      results[0] as List<GearCategory>,
      (results[1] as ApiResponse).list.map(Equipment.fromJson).toList(),
      (results[2] as ApiResponse).list.map(Equipment.fromJson).toList(),
      (results[3] as ApiResponse).list.map(Kit.fromJson).toList(),
      (results[4] as ApiResponse?)?.list.map(PromoBanner.fromJson).where((b) => b.image != null).toList() ?? const [],
      (results[5] as ApiResponse?)?.list.map(Brand.fromJson).toList() ?? const [],
    );
  }

  Future<void> _refresh() async {
    final f = _load(force: true);
    setState(() {
      _future = f;
    });
    context.read<NotificationsState>().refresh();
    await f.catchError((_) => _HomeData(const [], const [], const [], const [], const [], const []));
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
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: _header(context, app)),
                if (snap.hasError)
                  SliverToBoxAdapter(child: ErrorView(snap.error!, onRetry: _refresh))
                else if (!snap.hasData)
                  SliverToBoxAdapter(child: _skeleton())
                else
                  ..._content(context, snap.data!, app),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppState app) {
    final unread = context.select<NotificationsState, int>((n) => n.unread);
    final theme = context.watch<ThemeState>();
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
              Builder(builder: (btnCtx) {
                return _RoundIcon(
                  tooltip: theme.isDark ? tr('الوضع الفاتح', 'Light mode') : tr('الوضع الداكن', 'Dark mode'),
                  icon: theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  onTap: () {
                    final box = btnCtx.findRenderObject() as RenderBox?;
                    final from = box == null ? null : box.localToGlobal(box.size.center(Offset.zero));
                    theme.set(theme.isDark ? AppThemeMode.light : AppThemeMode.dark, from: from);
                  },
                );
              }),
              const SizedBox(width: 8),
              _RoundIcon(
                tooltip: tr('الإشعارات', 'Notifications'),
                icon: unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                badge: unread,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Reveal(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: app.homeTitle),
                if (app.homeSubtitle.isNotEmpty) ...[
                  const TextSpan(text: '\n'),
                  TextSpan(text: app.homeSubtitle, style: TextStyle(color: C.muted, fontWeight: FontWeight.w300)),
                ],
              ]),
              style: Txt.h1,
            ),
          ),
          const SizedBox(height: 18),
          Reveal(
            index: 1,
            child: Semantics(
              button: true,
              label: tr('بحث', 'Search'),
              child: Pressable(
                scale: .98,
                onTap: () => context.read<AppState>().openBrowse(focus: true),
                child: Container(
                  height: 54,
                  padding: const EdgeInsetsDirectional.only(start: 18, end: 7),
                  decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: C.muted, size: 21),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tr('ابحث عن كاميرا، عدسة، إضاءة…', 'Search cameras, lenses, lights…'), style: TextStyle(color: C.muted, fontSize: 14))),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.tune_rounded, color: C.onInk, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Column(
          children: [
            const Skeleton(height: 190, radius: 28),
            const SizedBox(height: 22),
            Row(children: List.generate(4, (_) => const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Skeleton(height: 86))))),
            const SizedBox(height: 22),
            const Row(children: [Expanded(child: Skeleton(height: 250)), SizedBox(width: 12), Expanded(child: Skeleton(height: 250))]),
          ],
        ),
      );

  List<Widget> _content(BuildContext context, _HomeData d, AppState app) {
    final hero = app.settings['hero_image'];
    final kitsCard = _KitsHero(hero: hero);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Reveal(index: 2, child: d.banners.isEmpty ? Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: kitsCard) : _BannerCarousel(d.banners)),
        ),
      ),
      SliverToBoxAdapter(child: SectionHeader(tr('الأقسام', 'Categories'), action: tr('عرض الكل', 'See all'), onAction: () => app.openBrowse())),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: d.cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final c = d.cats[i];
              return Reveal(
                index: i,
                offset: const Offset(24, 0),
                child: Pressable(
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
                        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        Text(tr('${c.count} معدة', '${c.count} items'), style: TextStyle(fontSize: 10.5, color: C.muted)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      if (d.brands.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(tr('الماركات', 'Brands'), action: tr('الكل', 'All'), onAction: () => app.openBrowse())),
        SliverToBoxAdapter(child: _BrandsRow(d.brands)),
      ],
      if (d.banners.isNotEmpty)
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: Reveal(child: kitsCard))),
      if (d.featured.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(tr('الأكثر طلباً', 'Most requested'), action: tr('عرض الكل', 'See all'), onAction: () => app.openBrowse())),
        EquipmentSliverGrid(d.featured, heroPrefix: 'feat'),
      ],
      if (d.kits.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(tr('باقات جاهزة', 'Ready kits'), action: tr('كل الباقات', 'All kits'), onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KitsScreen()))),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: d.kits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => Reveal(index: i, offset: const Offset(30, 0), child: KitCard(d.kits[i])),
            ),
          ),
        ),
      ],
      if (d.fresh.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(tr('وصل حديثاً', 'New arrivals'), action: tr('الإضاءة', 'Lighting'), onAction: () => app.openBrowse(category: 'light'))),
        EquipmentSliverGrid(d.fresh, heroPrefix: 'new'),
      ],
    ];
  }
}

/// زر دائري في رأس الصفحة مع شارة عدد
class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: .9,
      child: Material(
        color: C.surface,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Badge(
            isLabelVisible: badge > 0,
            backgroundColor: C.red,
            label: AnimatedCount(badge > 9 ? 9 : badge, style: const TextStyle(fontSize: 10, color: Colors.white)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (c, a) => RotationTransition(
                turns: Tween<double>(begin: -.25, end: 0).animate(a),
                child: ScaleTransition(scale: a, child: c),
              ),
              child: Icon(icon, key: ValueKey(icon), color: C.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// شرائح البنرات الإعلانية: تمرير تلقائي + حركة parallax للصورة + مؤشر نقاط متحرك
class _BannerCarousel extends StatefulWidget {
  final List<PromoBanner> banners;
  const _BannerCarousel(this.banners);

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  late final PageController _pc = PageController(viewportFraction: .9);
  Timer? _timer;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pc.addListener(() => setState(() => _page = _pc.page ?? 0));
    _auto();
  }

  void _auto() {
    _timer?.cancel();
    if (widget.banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pc.hasClients) return;
      final next = ((_pc.page ?? 0).round() + 1) % widget.banners.length;
      _pc.animateToPage(next, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banners;
    return Column(
      children: [
        SizedBox(
          height: 196,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) _auto();
              return false;
            },
            child: PageView.builder(
              controller: _pc,
              itemCount: b.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (_, i) {
                final delta = (_page - i);
                final shrink = delta.abs() * .06;
                final scale = 1 - (shrink > .06 ? .06 : shrink);
                return Transform.scale(
                  scale: scale,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Pressable(
                      scale: .98,
                      onTap: () => openAppLink(context, b[i].link),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: C.ink),
                            // parallax: الصورة تتحرك أبطأ من البطاقة
                            Transform.translate(
                              offset: Offset(delta * 40, 0),
                              child: Transform.scale(scale: 1.15, child: NetImage(b[i].image, fit: BoxFit.cover)),
                            ),
                            if (b[i].title != null || b[i].subtitle != null || b[i].buttonText != null) ...[
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Color(0xB0000000), Color(0x00000000)],
                                    stops: [0, .7],
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                start: 20,
                                end: 16,
                                bottom: 18,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (b[i].subtitle != null)
                                            Text(b[i].subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          if (b[i].title != null)
                                            Text(b[i].title!,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, height: 1.35)),
                                        ],
                                      ),
                                    ),
                                    if (b[i].buttonText != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                                        child: Text(b[i].buttonText!, style: const TextStyle(color: Color(0xFF141414), fontSize: 12.5, fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (b.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < b.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page.round() == i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(color: _page.round() == i ? C.ink : C.line, borderRadius: BorderRadius.circular(7)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// شريط الماركات بشعاراتها
class _BrandsRow extends StatelessWidget {
  final List<Brand> brands;
  const _BrandsRow(this.brands);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: brands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final b = brands[i];
          return Reveal(
            index: i,
            offset: const Offset(24, 0),
            child: Pressable(
              onTap: () => context.read<AppState>().openBrowse(brand: b.name),
              child: Container(
                width: 124,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 38,
                      child: b.logo != null
                          ? (C.dark
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: C.imageWell, borderRadius: BorderRadius.circular(10)),
                                  child: NetImage(b.logo, well: false),
                                )
                              : NetImage(b.logo, well: false))
                          : Center(
                              child: Text(b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: .3)),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(tr('${b.count} معدة', '${b.count} items'), style: Txt.small),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// بطاقة الأسطول والباقات
class _KitsHero extends StatelessWidget {
  final String? hero;
  const _KitsHero({this.hero});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: .98,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KitsScreen())),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF141414)),
              if (hero != null && hero!.isNotEmpty) NetImage(hero, fit: BoxFit.cover),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('GHANI GROUP · FILM PRODUCTION', style: TextStyle(color: Colors.white70, fontSize: 10.5, letterSpacing: .5)),
                          SizedBox(height: 4),
                          Text(tr('أسطول وطاقم فني\nمن التحضير حتى التسليم', 'Fleet and crew\nfrom prep to wrap'), style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, height: 1.4)),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF141414), size: 20),
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
                Text(kit.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(tr('${kit.items.length} قطع · ${kit.nameEn}', '${kit.items.length} pcs'), style: Txt.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Pressable(
                  scale: .92,
                  haptic: true,
                  onTap: () {
                    final c = context.read<CartState>();
                    for (final e in kit.items) {
                      if (!c.has(e.slug)) c.add(e, e.kitQty);
                    }
                    showToast(context, tr('${kit.nameAr} أضيفت للطلب', '${kit.name} added to your order'));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: added ? C.soft : C.ink, borderRadius: BorderRadius.circular(20)),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(added ? tr('مضافة ✓', 'Added ✓') : tr('أضف الباقة', 'Add kit'),
                          key: ValueKey(added), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: added ? C.ink : C.onInk)),
                    ),
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
