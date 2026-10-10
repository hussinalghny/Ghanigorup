import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/equipment_card.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _cat = '';
  String _brand = '';
  String _sort = 'default';
  int _page = 1, _pages = 1, _total = 0, _nonce = -1;
  bool _loading = true;
  Object? _error;
  final List<Equipment> _items = [];

  static const _sorts = {'default': 'الأبرز', 'name': 'الاسم', 'brand': 'الماركة', 'newest': 'الأحدث'};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600 && !_loading && _page < _pages) {
        _page++;
        _load();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = Provider.of<AppState>(context);
    if (app.browseNonce != _nonce) {
      final first = _nonce == -1;
      _nonce = app.browseNonce;
      if (!first || app.browseNonce > 0) {
        final cat = app.browseCategory, brand = app.browseBrand, query = app.browseQuery, focus = app.browseFocus;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _cat = cat;
          _brand = brand;
          _search.text = query;
          _load(reset: true);
          if (focus) _focus.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _items.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<ApiClient>().get('/equipment', {
        'category': _cat,
        'brand': _brand,
        'q': _search.text.trim(),
        'sort': _sort,
        'page': _page,
        'per_page': 20,
      });
      if (!mounted) return;
      setState(() {
        _items.addAll(r.list.map(Equipment.fromJson));
        _pages = (r.meta['pages'] as num?)?.toInt() ?? 1;
        _total = (r.meta['total'] as num?)?.toInt() ?? _items.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = context.watch<AppState>().categories;
    final total = cats.fold<int>(0, (a, c) => a + c.count);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: C.ink,
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تصفّح المعدات', style: Txt.title),
                    const SizedBox(height: 14),
                    Container(
                      height: 54,
                      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
                      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: C.muted, size: 21),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _search,
                              focusNode: _focus,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'ALEXA، SkyPanel، Dolly…',
                                hintStyle: TextStyle(color: C.muted, fontSize: 14),
                                isDense: true,
                              ),
                              onChanged: (_) {
                                _debounce?.cancel();
                                _debounce = Timer(const Duration(milliseconds: 350), () => _load(reset: true));
                              },
                              onSubmitted: (_) => _load(reset: true),
                            ),
                          ),
                          if (_search.text.isNotEmpty)
                            IconButton(
                              tooltip: 'مسح',
                              icon: Icon(Icons.close_rounded, size: 18, color: C.muted),
                              onPressed: () {
                                _search.clear();
                                _load(reset: true);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    _pill('', 'الكل', total),
                    for (final c in cats) _pill(c.slug, c.nameAr, c.count),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(_loading && _items.isEmpty ? '' : '$_total معدة', key: ValueKey('$_total$_loading'), style: Txt.muted),
                        ),
                        if (_brand.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Reveal(
                              key: ValueKey(_brand),
                              scale: true,
                              offset: Offset.zero,
                              child: Pressable(
                                onTap: () {
                                  setState(() => _brand = '');
                                  _load(reset: true);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(20)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Flexible(child: Text(_brand, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: TextStyle(color: C.onInk, fontSize: 12.5, fontWeight: FontWeight.w600))),
                                    const SizedBox(width: 6),
                                    Icon(Icons.close_rounded, size: 15, color: C.onInk),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                    PopupMenuButton<String>(
                      initialValue: _sort,
                      tooltip: 'الترتيب',
                      onSelected: (v) {
                        _sort = v;
                        _load(reset: true);
                      },
                      itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_sorts[_sort]!, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more_rounded, size: 18),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null && _items.isEmpty)
              SliverToBoxAdapter(child: ErrorView(_error!, onRetry: () => _load(reset: true)))
            else if (_items.isEmpty && _loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 262),
                  delegate: SliverChildBuilderDelegate((_, __) => const Skeleton(height: 262), childCount: 4),
                ),
              )
            else if (_items.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(icon: Icons.search_off_rounded, title: 'لا توجد نتائج', message: 'جرّب كلمة بحث أخرى أو قسماً آخر.'),
              )
            else
              EquipmentSliverGrid(_items),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _loading && _items.isNotEmpty
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink))
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String slug, String label, int count) {
    final on = _cat == slug;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Pressable(
        scale: .93,
        onTap: () {
          setState(() => _cat = slug);
          _load(reset: true);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? C.ink : C.surface, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? C.onInk : C.ink)),
              const SizedBox(width: 7),
              Text('$count', style: TextStyle(fontSize: 11, color: on ? C.inkMuted : C.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
