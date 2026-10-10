import 'package:flutter_test/flutter_test.dart';
import 'package:ghani_group/core/models.dart';
import 'package:ghani_group/state/cart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final alexa = Equipment.fromJson({
    'id': 1,
    'slug': 'arri-alexa-mini',
    'brand': 'ARRI',
    'name': 'ALEXA Mini',
    'category': {'slug': 'cam', 'name_ar': 'كاميرات', 'name_en': 'Cameras'},
    'qty_total': 2,
    'image': 'https://ghanigroup.online/uploads/a.jpg',
    'is_new': false,
    'is_featured': true,
    'specs': {'الدقة': '3.4K'},
  });

  test('Equipment parses API json', () {
    expect(alexa.slug, 'arri-alexa-mini');
    expect(alexa.categoryAr, 'كاميرات');
    expect(alexa.specs['الدقة'], '3.4K');
    expect(alexa.qtyTotal, 2);
  });

  test('Order parses status and warnings', () {
    final o = RentalOrder.fromJson({
      'id': 5,
      'ref': 'GG-ABC123',
      'status': 'quoted',
      'contact_name': 'Ahmed',
      'phone': '07700000000',
      'start_date': '2026-10-12',
      'end_date': '2026-10-14',
      'created_at': '2026-10-10 10:00:00',
      'days': 3,
      'quote_amount': 750000,
      'items': [
        {'equipment_id': 1, 'qty': 2, 'slug': 'x', 'brand': 'ARRI', 'name': 'ALEXA Mini'}
      ],
      'availability_warnings': [
        {'name': 'ALEXA Mini', 'requested': 2, 'available': 1}
      ],
    });
    expect(o.units, 2);
    expect(o.cancellable, isTrue);
    expect(o.warnings.single.available, 1);
    expect(fmtNumber(o.quoteAmount!), '750,000');
    expect(OrderStatus.of('confirmed').label, 'مؤكد');
  });

  test('Cart respects fleet quantity and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartState();
    await cart.load();
    expect(cart.toggle(alexa), isTrue);
    cart.setQty(alexa.slug, 5);
    expect(cart.qtyOf(alexa.slug), 2, reason: 'لا تتجاوز الكمية الموجودة في الأسطول');
    cart.setDates('2099-01-01', '2099-01-03');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final again = CartState();
    await again.load();
    expect(again.count, 2);
    expect(again.startDate, '2099-01-01');
    expect(again.toggle(alexa), isFalse);
  });

  test('Date helpers', () {
    expect(fmtYmd(DateTime(2026, 3, 7)), '2026-03-07');
    expect(fmtDay('2026-10-12'), '12 تشرين الأول');
  });
}
