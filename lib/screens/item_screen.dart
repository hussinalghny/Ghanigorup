import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/cart.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/equipment_card.dart';

class ItemScreen extends StatefulWidget {
  final String slug;
  final Equipment? preview;
  final String? heroTag;
  const ItemScreen({super.key, required this.slug, this.preview, this.heroTag});

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  Equipment? _item;
  List<DayAvailability> _days = [];
  Object? _error;
  bool _loading = true;
  int _qty = 1;
  List<int> _sel = [];
  String? _mainImage;

  @override
  void initState() {
    super.initState();
    _item = widget.preview;
    _mainImage = widget.preview?.image;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final cart = context.read<CartState>();
    try {
      final res = await Future.wait([
        api.get('/equipment/${widget.slug}'),
        api.get('/equipment/${widget.slug}/availability', {'days': 21}),
      ]);
      final item = Equipment.fromJson(res[0].map);
      final days = (res[1].map['days'] as List? ?? const [])
          .map((e) => DayAvailability.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _item = item;
        _days = days;
        _mainImage ??= item.image;
        _qty = cart.qtyOf(item.slug) > 0 ? cart.qtyOf(item.slug) : 1;
        // استعادة التواريخ المختارة سابقاً في السلة
        if (cart.startDate != null) {
          final a = days.indexWhere((d) => d.ymd == cart.startDate);
          final b = days.indexWhere((d) => d.ymd == (cart.endDate ?? cart.startDate));
          if (a >= 0 && b >= a && !days.sublist(a, b + 1).any((d) => d.available <= 0)) _sel = [a, b];
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _maxFree {
    final it = _item;
    if (it == null) return 1;
    if (_sel.isEmpty || _days.isEmpty) return it.qtyTotal;
    final end = _sel.length > 1 ? _sel[1] : _sel[0];
    return _days.sublist(_sel[0], end + 1).map((d) => d.available).reduce((a, b) => a < b ? a : b);
  }

  int get _selDays => _sel.isEmpty ? 0 : (_sel.length > 1 ? _sel[1] - _sel[0] + 1 : 1);

  void _pick(int i) {
    if (_days[i].available <= 0) return;
    setState(() {
      if (_sel.length != 1) {
        _sel = [i];
      } else {
        final lo = _sel[0] < i ? _sel[0] : i;
        final hi = _sel[0] < i ? i : _sel[0];
        if (_days.sublist(lo, hi + 1).any((d) => d.available <= 0)) {
          showToast(context, 'يوجد يوم محجوز ضمن المدة');
          _sel = [i];
        } else {
          _sel = [lo, hi];
        }
      }
      if (_qty > _maxFree) _qty = _maxFree < 1 ? 1 : _maxFree;
    });
  }

  Future<void> _toggleFav() async {
    final s = context.read<SessionState>();
    if (!s.loggedIn) {
      showToast(context, 'سجّل الدخول من "حسابي" لحفظ المفضلة');
      return;
    }
    try {
      final on = await s.toggleFavorite(widget.slug);
      if (mounted) showToast(context, on ? 'أضيفت إلى المفضلة' : 'أزيلت من المفضلة');
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  void _add() {
    final it = _item;
    if (it == null) return;
    final cart = context.read<CartState>();
    if (_sel.isNotEmpty) {
      cart.setDates(_days[_sel[0]].ymd, _days[_sel.length > 1 ? _sel[1] : _sel[0]].ymd);
    }
    cart.add(it, _qty);
    showToast(context, '${it.name} أضيفت للطلب');
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    final top = MediaQuery.paddingOf(context).top;
    final fav = context.select<SessionState, bool>((s) => s.favorites.contains(widget.slug));
    return Scaffold(
      body: it == null
          ? (_error != null
              ? SafeArea(child: ErrorView(_error!, onRetry: _load))
              : Center(child: CircularProgressIndicator(color: C.ink)))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _gallery(it, top, fav)),
                SliverToBoxAdapter(child: Reveal(delay: const Duration(milliseconds: 120), child: _info(it))),
                if (it.specs.isNotEmpty) SliverToBoxAdapter(child: Reveal(delay: const Duration(milliseconds: 200), child: _specs(it))),
                SliverToBoxAdapter(child: Reveal(delay: const Duration(milliseconds: 280), child: _calendar())),
                SliverToBoxAdapter(child: Reveal(delay: const Duration(milliseconds: 340), child: _options())),
                if (it.related.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader('من نفس القسم')),
                  SliverToBoxAdapter(child: EquipmentRow(it.related, heroPrefix: 'rel-${widget.slug}')),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 130)),
              ],
            ),
      bottomNavigationBar: it == null ? null : _dock(it),
    );
  }

  Widget _gallery(Equipment it, double top, bool fav) {
    final images = <String>[if (it.image != null) it.image!, ...it.gallery];
    return Container(
      height: 360 + top,
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(bottom: Radius.circular(40))),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 50, 40, 50),
              child: widget.heroTag != null && (_mainImage == null || _mainImage == widget.preview?.image)
                  ? Hero(tag: widget.heroTag!, child: NetImage(_mainImage ?? it.image))
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: NetImage(_mainImage ?? it.image, key: ValueKey(_mainImage ?? it.image)),
                    ),
            ),
          ),
          PositionedDirectional(
            top: 10,
            start: 20,
            child: _circleBtn(Icons.arrow_back_rounded, 'رجوع', () => Navigator.of(context).maybePop()),
          ),
          PositionedDirectional(
            top: 10,
            end: 20,
            child: _circleBtn(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, 'المفضلة', _toggleFav, color: fav ? C.red : C.ink),
          ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final src in images)
                    GestureDetector(
                      onTap: () => setState(() => _mainImage = src),
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: C.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: src == _mainImage ? C.ink : Colors.transparent, width: 2),
                        ),
                        child: NetImage(src),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) => Material(
        color: C.bg,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => ScaleTransition(scale: Tween<double>(begin: .4, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.elasticOut)), child: c),
            child: Icon(icon, key: ValueKey(icon), color: color ?? C.ink, size: 20),
          ),
        ),
      );

  Widget _info(Equipment it) {
    final freeToday = _days.isNotEmpty ? _days.first.available : it.qtyTotal;
    final ok = freeToday > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${it.brand}${it.categoryAr.isNotEmpty ? ' · ${it.categoryAr}' : ''}', style: Txt.muted),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: Text(it.name,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600, height: 1.2)),
          ),
          const SizedBox(height: 12),
          if (!_loading || _days.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: ok ? C.okBg : C.warnBg, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: ok ? C.ok : C.warn, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(ok ? 'متوفر اليوم $freeToday من ${it.qtyTotal}' : 'محجوز اليوم — اختر أياماً أخرى',
                    style: TextStyle(fontSize: 12, color: ok ? C.ok : C.warn, fontWeight: FontWeight.w500)),
              ]),
            ),
          if (it.description != null) ...[
            const SizedBox(height: 14),
            Text(it.description!, style: TextStyle(color: C.muted, fontSize: 14.5, height: 1.85)),
          ],
        ],
      ),
    );
  }

  Widget _specs(Equipment it) {
    final entries = it.specs.entries.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 70),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(entries[i].key, style: Txt.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(entries[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendar() {
    final n = _selDays;
    String label = 'اختر يوم الاستلام ثم الإرجاع';
    if (n > 0) {
      label = '$n يوم · ${fmtDay(_days[_sel[0]].ymd)}${n > 1 ? ' ← ${fmtDay(_days[_sel[1]].ymd)}' : ''}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
          child: Row(children: [
            Text('أيام الحجز', style: Txt.section),
            const Spacer(),
            Flexible(child: Text(label, style: Txt.muted, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        SizedBox(
          height: 82,
          child: _days.isEmpty
              ? ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: List.generate(6, (_) => const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Skeleton(width: 60, height: 78, radius: 20))),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _days.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final d = _days[i];
                    final booked = d.available <= 0;
                    final sel = _sel.contains(i);
                    final mid = _sel.length == 2 && i > _sel[0] && i < _sel[1];
                    final bg = sel ? C.ink : (mid ? C.midSel : C.surface);
                    final fg = sel ? C.onInk : C.ink;
                    return Opacity(
                      opacity: booked ? .35 : 1,
                      child: Material(
                        color: bg,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: booked ? null : () => _pick(i),
                          child: SizedBox(
                            width: 60,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(weekdaysAr[d.date.weekday - 1], style: TextStyle(fontSize: 10, color: sel ? C.inkMuted : C.muted)),
                                const SizedBox(height: 2),
                                Text('${d.date.day}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: fg,
                                      decoration: booked ? TextDecoration.lineThrough : null,
                                    )),
                                Text(booked ? 'محجوز' : '${d.available} متاح',
                                    style: TextStyle(fontSize: 9.5, color: sel ? C.inkMuted : C.muted)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _options() {
    final cart = context.watch<CartState>();
    return FormCard(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      children: [
        ToggleRow(title: 'فني / مشغّل مع المعدة', subtitle: 'يُضاف إلى طلبك', value: cart.technician, onChanged: cart.setTechnician),
        ToggleRow(title: 'توصيل إلى الموقع', subtitle: 'داخل بغداد', value: cart.delivery, onChanged: cart.setDelivery, divider: false),
      ],
    );
  }

  Widget _dock(Equipment it) {
    final inCart = context.select<CartState, bool>((c) => c.has(it.slug));
    final n = _selDays;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.bg.withAlpha(0), C.bg], stops: [0, .3]),
      ),
      child: Row(
        children: [
          QtyStepper(
            value: _qty,
            onInc: () {
              final m = _maxFree;
              if (_qty >= m) {
                showToast(context, 'أقصى كمية متاحة: $m');
                return;
              }
              setState(() => _qty++);
            },
            onDec: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              inCart ? 'تحديث الطلب' : 'أضف للطلب',
              trailing: n > 0 ? '· $n يوم' : null,
              onPressed: it.qtyTotal > 0 ? _add : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// يُستخدم من خارج الشاشة لمعرفة رقم واتساب الشركة
String companyWhatsapp(BuildContext context) => context.read<AppState>().whatsapp;
