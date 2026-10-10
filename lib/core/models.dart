import 'package:flutter/material.dart';

import 'theme.dart';

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
String _str(dynamic v) => v == null ? '' : '$v';
String? _strN(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';

class GearCategory {
  final String slug, nameAr, nameEn;
  final String? image;
  final int count;

  GearCategory({required this.slug, required this.nameAr, required this.nameEn, this.image, this.count = 0});

  factory GearCategory.fromJson(Map<String, dynamic> j) => GearCategory(
        slug: _str(j['slug']),
        nameAr: _str(j['name_ar']),
        nameEn: _str(j['name_en']),
        image: _strN(j['image']),
        count: _int(j['count']),
      );
}

class Equipment {
  final int id;
  final String slug, brand, name;
  final String? image;
  final int qtyTotal;
  final bool isNew, isFeatured;
  final String categorySlug, categoryAr;
  final String? description;
  final Map<String, String> specs;
  final List<String> gallery;
  final List<Equipment> related;
  final int kitQty;
  final double? dailyRate;

  Equipment({
    required this.id,
    required this.slug,
    required this.brand,
    required this.name,
    this.image,
    this.qtyTotal = 1,
    this.isNew = false,
    this.isFeatured = false,
    this.categorySlug = '',
    this.categoryAr = '',
    this.description,
    this.specs = const {},
    this.gallery = const [],
    this.related = const [],
    this.kitQty = 1,
    this.dailyRate,
  });

  factory Equipment.fromJson(Map<String, dynamic> j) {
    final cat = j['category'] is Map ? Map<String, dynamic>.from(j['category'] as Map) : <String, dynamic>{};
    final specs = <String, String>{};
    if (j['specs'] is Map) {
      (j['specs'] as Map).forEach((k, v) => specs['$k'] = '$v');
    }
    return Equipment(
      id: _int(j['id']),
      slug: _str(j['slug']),
      brand: _str(j['brand']),
      name: _str(j['name']),
      image: _strN(j['image']),
      qtyTotal: _int(j['qty_total']),
      isNew: j['is_new'] == true,
      isFeatured: j['is_featured'] == true,
      categorySlug: _str(cat['slug']),
      categoryAr: _str(cat['name_ar']),
      description: _strN(j['description']),
      specs: specs,
      gallery: (j['gallery'] as List? ?? const []).map((e) => '$e').toList(),
      related: (j['related'] as List? ?? const [])
          .map((e) => Equipment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      kitQty: j['qty'] == null ? 1 : _int(j['qty']),
      dailyRate: j['daily_rate'] is num ? (j['daily_rate'] as num).toDouble() : null,
    );
  }
}

class Kit {
  final String slug, nameAr, nameEn;
  final String? image;
  final List<Equipment> items;

  Kit({required this.slug, required this.nameAr, required this.nameEn, this.image, this.items = const []});

  factory Kit.fromJson(Map<String, dynamic> j) => Kit(
        slug: _str(j['slug']),
        nameAr: _str(j['name_ar']),
        nameEn: _str(j['name_en']),
        image: _strN(j['image']),
        items: (j['items'] as List? ?? const [])
            .map((e) => Equipment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class DayAvailability {
  final DateTime date;
  final int available, booked;

  DayAvailability(this.date, this.available, this.booked);

  String get ymd => fmtYmd(date);

  factory DayAvailability.fromJson(Map<String, dynamic> j) =>
      DayAvailability(DateTime.parse(_str(j['date'])), _int(j['available']), _int(j['booked']));
}

class OrderItem {
  final int equipmentId, qty;
  final String slug, brand, name;
  final String? image;

  OrderItem({required this.equipmentId, required this.qty, required this.slug, required this.brand, required this.name, this.image});

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        equipmentId: _int(j['equipment_id']),
        qty: _int(j['qty']),
        slug: _str(j['slug']),
        brand: _str(j['brand']),
        name: _str(j['name']),
        image: _strN(j['image']),
      );
}

class AvailabilityWarning {
  final String name;
  final int requested, available;
  AvailabilityWarning(this.name, this.requested, this.available);
}

class RentalOrder {
  final int id;
  final String ref, status, contactName, phone;
  final String? project, location;
  final String startDate, endDate, createdAt;
  final int days;
  final double? quoteAmount;
  final List<OrderItem> items;
  final List<AvailabilityWarning> warnings;

  RentalOrder({
    required this.id,
    required this.ref,
    required this.status,
    required this.contactName,
    required this.phone,
    this.project,
    this.location,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.days,
    this.quoteAmount,
    this.items = const [],
    this.warnings = const [],
  });

  int get units => items.fold(0, (a, b) => a + b.qty);
  bool get cancellable => status == 'pending' || status == 'quoted';

  factory RentalOrder.fromJson(Map<String, dynamic> j) => RentalOrder(
        id: _int(j['id']),
        ref: _str(j['ref']),
        status: _str(j['status']),
        contactName: _str(j['contact_name']),
        phone: _str(j['phone']),
        project: _strN(j['project']),
        location: _strN(j['location']),
        startDate: _str(j['start_date']),
        endDate: _str(j['end_date']),
        createdAt: _str(j['created_at']),
        days: _int(j['days']),
        quoteAmount: j['quote_amount'] is num ? (j['quote_amount'] as num).toDouble() : null,
        items: (j['items'] as List? ?? const [])
            .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        warnings: (j['availability_warnings'] as List? ?? const []).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return AvailabilityWarning(_str(m['name']), _int(m['requested']), _int(m['available']));
        }).toList(),
      );
}

class AppUser {
  final int id;
  final String name, email, role;
  final String? phone, company;

  AppUser({required this.id, required this.name, required this.email, required this.role, this.phone, this.company});

  bool get isStaff => role == 'admin' || role == 'staff';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _int(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
        role: _str(j['role']),
        phone: _strN(j['phone']),
        company: _strN(j['company']),
      );
}

/// حالة الطلب: النص واللون ونسبة التقدم
class OrderStatus {
  final String label;
  final Color fg, bg;
  final double progress;
  const OrderStatus(this.label, this.fg, this.bg, this.progress);

  static OrderStatus of(String s) {
    switch (s) {
      case 'pending':
        return const OrderStatus('بانتظار المراجعة', C.warn, C.warnBg, .15);
      case 'quoted':
        return const OrderStatus('تم إرسال عرض السعر', Colors.white, C.ink, .35);
      case 'confirmed':
        return const OrderStatus('مؤكد', C.ok, C.okBg, .6);
      case 'out':
        return const OrderStatus('تم الاستلام', C.ok, C.okBg, .85);
      case 'returned':
        return const OrderStatus('مكتمل', C.muted, C.soft, 1);
      case 'cancelled':
        return const OrderStatus('ملغي', C.red, C.redBg, 1);
      default:
        return OrderStatus(s, C.muted, C.soft, 0);
    }
  }
}

// ---------- تواريخ ----------
const monthsAr = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
const weekdaysAr = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']; // DateTime.weekday: 1 = Monday

String fmtYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmtDay(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${d.day} ${monthsAr[d.month - 1]}';
}

String fmtNumber(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
