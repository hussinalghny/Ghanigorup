import 'package:flutter/material.dart';

import 'theme.dart';
import 'i18n.dart';

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

  /// الاسم بلغة الواجهة
  String get name => L.en && nameEn.isNotEmpty ? nameEn : nameAr;
}

class Equipment {
  final int id;
  final String slug, brand, name;
  final String? image;
  final int qtyTotal;
  final bool isNew, isFeatured;
  final String categorySlug, categoryAr, categoryEn;
  final String? description;
  final Map<String, String> specs;
  final List<String> gallery;
  final List<Equipment> related;
  final int kitQty;
  final double? dailyRate;

  String get categoryName => L.en && categoryEn.isNotEmpty ? categoryEn : categoryAr;

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
    this.categoryEn = '',
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
      categoryEn: _str(cat['name_en']),
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

  /// الاسم بلغة الواجهة
  String get name => L.en && nameEn.isNotEmpty ? nameEn : nameAr;
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

  bool get isStaff => role == 'admin' || role == 'staff' || role == 'storekeeper';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _int(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
        role: _str(j['role']),
        phone: _strN(j['phone']),
        company: _strN(j['company']),
      );
}

/// رابط داخلي/خارجي لبنر أو إشعار
class AppLink {
  final String type, value;
  const AppLink(this.type, this.value);
  bool get isNone => type == 'none' || type.isEmpty;
}

/// بنر إعلاني في الصفحة الرئيسية
class PromoBanner {
  final int id;
  final String? title, subtitle, image, buttonText;
  final AppLink link;
  PromoBanner({required this.id, this.title, this.subtitle, this.image, this.buttonText, required this.link});

  factory PromoBanner.fromJson(Map<String, dynamic> j) => PromoBanner(
        id: _int(j['id']),
        title: _strN(j['title']),
        subtitle: _strN(j['subtitle']),
        image: _strN(j['image']),
        buttonText: _strN(j['button_text']),
        link: AppLink(_str(j['link_type']), _str(j['link_value'])),
      );
}

/// ماركة / علامة تجارية
class Brand {
  final String name, slug;
  final String? logo;
  final int count;
  Brand({required this.name, required this.slug, this.logo, this.count = 0});

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(
        name: _str(j['name'] ?? j['brand']),
        slug: _str(j['slug']),
        logo: _strN(j['logo']),
        count: _int(j['count']),
      );
}

/// إشعار (إعلاني أو تحديث طلب)
class AppNotification {
  final int id;
  final String type, title;
  final String? body, image, orderRef;
  final AppLink link;
  final DateTime createdAt;
  AppNotification({required this.id, required this.type, required this.title, this.body, this.image, this.orderRef, required this.link, required this.createdAt});

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: _int(j['id']),
        type: _str(j['type']),
        title: _str(j['title']),
        body: _strN(j['body']),
        image: _strN(j['image']),
        orderRef: _strN(j['order_ref']),
        link: AppLink(_str(j['link_type']), _str(j['link_value'])),
        createdAt: DateTime.tryParse(_str(j['created_at']).replaceFirst(' ', 'T')) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'title': title, 'body': body, 'image': image, 'order_ref': orderRef,
        'link_type': link.type, 'link_value': link.value, 'created_at': createdAt.toIso8601String(),
      };
}

/// رسالة الترحيب عند فتح التطبيق (تُدار من لوحة التحكم)
class WelcomeMessage {
  final String id, title, body, button, link, frequency;
  final String? image;
  WelcomeMessage({required this.id, required this.title, required this.body, required this.button, required this.link, required this.frequency, this.image});

  factory WelcomeMessage.fromJson(Map<String, dynamic> j) => WelcomeMessage(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        button: _str(j['button']).isEmpty ? tr('متابعة', 'Continue') : _str(j['button']),
        link: _str(j['link']),
        frequency: _str(j['frequency']).isEmpty ? 'once' : _str(j['frequency']),
        image: _strN(j['image']),
      );
}

String timeAgo(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return tr('الآن', 'Just now');
  if (m < 60) return tr('قبل $m دقيقة', '${m}m ago');
  final h = m ~/ 60;
  if (h < 24) return tr('قبل $h ساعة', '${h}h ago');
  final days = h ~/ 24;
  if (days < 30) return tr('قبل $days يوم', '${days}d ago');
  return '${d.day} ${monthsAr[d.month - 1]}';
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
        return OrderStatus(tr('بانتظار المراجعة', 'Under review'), C.warn, C.warnBg, .15);
      case 'quoted':
        return OrderStatus(tr('تم إرسال عرض السعر', 'Quote sent'), C.onInk, C.ink, .35);
      case 'confirmed':
        return OrderStatus(tr('مؤكد', 'Confirmed'), C.ok, C.okBg, .6);
      case 'out':
        return OrderStatus(tr('تم الاستلام', 'Picked up'), C.ok, C.okBg, .85);
      case 'returned':
        return OrderStatus(tr('مكتمل', 'Completed'), C.muted, C.soft, 1);
      case 'cancelled':
        return OrderStatus(tr('ملغي', 'Cancelled'), C.red, C.redBg, 1);
      default:
        return OrderStatus(s, C.muted, C.soft, 0);
    }
  }
}

// ---------- تواريخ ----------
const _monthsAr = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
const _weekdaysAr = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']; // DateTime.weekday: 1 = Monday
const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
List<String> get monthsAr => L.en ? _monthsEn : _monthsAr;
List<String> get weekdaysAr => L.en ? _weekdaysEn : _weekdaysAr;

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
