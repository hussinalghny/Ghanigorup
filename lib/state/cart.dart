import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

class CartItem {
  final int id;
  final String slug, name, brand;
  final String? image;
  final int max;
  int qty;

  CartItem({required this.id, required this.slug, required this.name, required this.brand, this.image, required this.max, required this.qty});

  Map<String, dynamic> toJson() => {'id': id, 'slug': slug, 'name': name, 'brand': brand, 'image': image, 'max': max, 'qty': qty};

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        slug: '${j['slug']}',
        name: '${j['name']}',
        brand: '${j['brand']}',
        image: j['image'] as String?,
        max: (j['max'] as num?)?.toInt() ?? 1,
        qty: (j['qty'] as num?)?.toInt() ?? 1,
      );
}

/// سلة الطلب — محفوظة على الجهاز
class CartState extends ChangeNotifier {
  static const _key = 'gg_cart_v1';
  final Map<String, CartItem> _items = {};
  String? startDate, endDate;
  bool technician = false, delivery = false;

  List<CartItem> get items => _items.values.toList();
  bool get isEmpty => _items.isEmpty;
  int get count => _items.values.fold(0, (a, b) => a + b.qty);
  int qtyOf(String slug) => _items[slug]?.qty ?? 0;
  bool has(String slug) => _items.containsKey(slug);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final e in (j['items'] as List? ?? const [])) {
        final it = CartItem.fromJson(Map<String, dynamic>.from(e as Map));
        _items[it.slug] = it;
      }
      startDate = j['start'] as String?;
      endDate = j['end'] as String?;
      technician = j['technician'] == true;
      delivery = j['delivery'] == true;
      // تواريخ قديمة تُحذف
      final today = fmtYmd(DateTime.now());
      if (startDate != null && startDate!.compareTo(today) < 0) {
        startDate = null;
        endDate = null;
      }
    } catch (_) {
      _items.clear();
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode({
        'items': _items.values.map((e) => e.toJson()).toList(),
        'start': startDate,
        'end': endDate,
        'technician': technician,
        'delivery': delivery,
      }));
    } catch (_) {}
  }

  void add(Equipment e, [int qty = 1]) {
    final max = e.qtyTotal < 1 ? 1 : e.qtyTotal;
    final int q = qty < 1 ? 1 : (qty > max ? max : qty);
    _items[e.slug] = CartItem(id: e.id, slug: e.slug, name: e.name, brand: e.brand, image: e.image, max: max, qty: q);
    _save();
  }

  /// يضيف أو يزيل — يرجع true إذا أصبحت المعدة في السلة
  bool toggle(Equipment e) {
    if (has(e.slug)) {
      _items.remove(e.slug);
      _save();
      return false;
    }
    add(e, 1);
    return true;
  }

  void setQty(String slug, int qty) {
    final it = _items[slug];
    if (it == null) return;
    if (qty <= 0) {
      _items.remove(slug);
    } else {
      it.qty = qty > it.max ? it.max : qty;
    }
    _save();
  }

  void setDates(String? start, String? end) {
    startDate = start;
    endDate = end;
    _save();
  }

  void setTechnician(bool v) {
    technician = v;
    _save();
  }

  void setDelivery(bool v) {
    delivery = v;
    _save();
  }

  void clear() {
    _items.clear();
    startDate = null;
    endDate = null;
    technician = false;
    delivery = false;
    _save();
  }
}
