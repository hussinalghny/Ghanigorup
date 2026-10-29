import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/cart.dart';
import '../state/notifications.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import 'item_screen.dart';
import 'track_screen.dart';
import '../core/i18n.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _project = TextEditingController();
  final _location = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  Map<String, dynamic> _errors = {};
  bool _sending = false;
  int? _prefilledFor;

  @override
  void dispose() {
    for (final c in [_project, _location, _name, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(AppUser? u) {
    if (u == null || _prefilledFor == u.id) return;
    _prefilledFor = u.id;
    if (_name.text.isEmpty) _name.text = u.name;
    if (_phone.text.isEmpty) _phone.text = u.phone ?? '';
    if (_email.text.isEmpty) _email.text = u.email;
  }

  Future<void> _pickDate(bool start) async {
    final cart = context.read<CartState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DateTime.tryParse((start ? cart.startDate : cart.endDate) ?? '') ??
        (start ? today : (DateTime.tryParse(cart.startDate ?? '') ?? today));
    final first = start ? today : (DateTime.tryParse(cart.startDate ?? '') ?? today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: today.add(const Duration(days: 365)),
      helpText: start ? tr('تاريخ الاستلام', 'Pickup date') : tr('تاريخ الإرجاع', 'Return date'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: C.ink)),
        child: child!,
      ),
    );
    if (picked == null) return;
    final v = fmtYmd(picked);
    if (start) {
      final end = cart.endDate;
      cart.setDates(v, end == null || end.compareTo(v) < 0 ? v : end);
    } else {
      cart.setDates(cart.startDate ?? v, v);
    }
  }

  Future<void> _submit() async {
    final cart = context.read<CartState>();
    final app = context.read<AppState>();
    final api = context.read<ApiClient>();
    final notifs = context.read<NotificationsState>();
    if (cart.startDate == null) {
      setState(() => _errors = {'start_date': tr('اختر التاريخ', 'Pick a date')});
      showToast(context, tr('اختر تاريخ الاستلام', 'Pick a pickup date'));
      return;
    }
    setState(() {
      _sending = true;
      _errors = {};
    });
    try {
      final r = await api.post('/orders', {
        'contact_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (_project.text.trim().isNotEmpty) 'project': _project.text.trim(),
        if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'start_date': cart.startDate,
        'end_date': cart.endDate ?? cart.startDate,
        'technician': cart.technician,
        'delivery': cart.delivery,
        'items': [for (final i in cart.items) {'slug': i.slug, 'qty': i.qty}],
      });
      final o = RentalOrder.fromJson(r.map);
      // ليصل إشعار تغيّر حالة الطلب حتى بدون حساب
      notifs.addTrack(o.ref, o.phone);
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('gg_last_ref', o.ref);
        await p.setString('gg_last_phone', o.phone);
      } catch (_) {}
      cart.clear();
      _project.clear();
      _location.clear();
      _notes.clear();
      if (!mounted) return;
      _showSuccess(o, app.whatsapp);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.details);
      showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSuccess(RentalOrder o, String whatsapp) {
    final lines = o.items.map((i) => '- ${i.brand} ${i.name} ×${i.qty}').join('\n');
    final text = tr('طلب عرض سعر ${o.ref}\n${o.project != null ? 'المشروع: ${o.project}\n' : ''}${fmtDay(o.startDate)} ← ${fmtDay(o.endDate)}\n$lines', 'Quote request ${o.ref}\n${o.project != null ? 'Project: ${o.project}\n' : ''}${fmtDay(o.startDate)} → ${fmtDay(o.endDate)}\n$lines');
    final loggedIn = context.read<SessionState>().loggedIn;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 5, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(5))),
              const SizedBox(height: 22),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(color: C.okBg, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, color: C.ok, size: 38),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('وصل طلبك', 'Request received'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: tr('رقم الطلب ', 'Order number ')),
                  TextSpan(text: o.ref, style: TextStyle(color: C.ink, fontWeight: FontWeight.w600)),
                  TextSpan(text: tr('\nسيراجع قسم التأجير التوفر ويرسل لك عرض السعر.', '\nThe rental desk will check availability and send you a quote.')),
                ]),
                style: Txt.muted,
                textAlign: TextAlign.center,
              ),
              if (o.warnings.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    tr('تنبيه: بعض المعدات محجوزة جزئياً في هذه الفترة وسيتواصل معك الفريق لاقتراح بديل:\n${o.warnings.map((w) => '• ${w.name} — المتاح ${w.available} من ${w.requested}').join('\n')}', 'Note: some items are partly booked in this period. The team will contact you with an alternative:\n${o.warnings.map((w) => '• ${w.name} — ${w.available} of ${w.requested} available').join('\n')}'),
                    style: TextStyle(color: C.warn, fontSize: 12.5, height: 1.7),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              AppButton(tr('متابعة عبر واتساب', 'Continue on WhatsApp'), icon: Icons.chat_rounded, onPressed: () => openLink(ctx, whatsappUrl(whatsapp, text))),
              const SizedBox(height: 10),
              AppButton.light(
                loggedIn ? tr('طلباتي', 'My orders') : tr('تتبع الطلب', 'Track order'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (loggedIn) {
                    context.read<AppState>().goTab(3);
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackScreen(initialRef: o.ref, initialPhone: o.phone)));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final user = context.watch<SessionState>().user;
    if (user != null && _prefilledFor != user.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prefill(user);
      });
    }

    if (cart.isEmpty) {
      return SafeArea(
        child: ListView(
          children: [
            Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 0), child: Text(tr('الطلب', 'Order'), style: Txt.title)),
            EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: tr('طلبك فارغ', 'Your order is empty'),
              message: tr('أضف معدات أو باقة جاهزة\nونرسل لك عرض السعر.', 'Add gear or a ready kit\nand we will send you a quote.'),
              action: tr('تصفّح المعدات', 'Browse gear'),
              onAction: () => context.read<AppState>().openBrowse(),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text(tr('الطلب', 'Order'), style: Txt.title),
            const SizedBox(height: 14),
            for (var k = 0; k < cart.items.length; k++) Reveal(key: ValueKey(cart.items[k].slug), index: k, child: _line(cart.items[k], cart)),
            Row(children: [
              Text(tr('${cart.count} قطعة', '${cart.count} pcs'), style: Txt.muted),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text(tr('إفراغ الطلب؟', 'Clear the order?')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('إلغاء', 'Cancel'))),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('إفراغ', 'Clear'), style: TextStyle(color: C.red))),
                      ],
                    ),
                  );
                  if (ok == true) cart.clear();
                },
                child: Text(tr('إفراغ الطلب', 'Clear order'), style: TextStyle(color: C.muted)),
              ),
            ]),
            SectionHeader(tr('تفاصيل التصوير', 'Shoot details'), padding: EdgeInsets.only(top: 18, bottom: 12)),
            FormCard(children: [
              Row(children: [
                Expanded(child: _dateField(tr('تاريخ الاستلام', 'Pickup date'), cart.startDate, () => _pickDate(true), _errors['start_date']?.toString())),
                const SizedBox(width: 16),
                Expanded(child: _dateField(tr('تاريخ الإرجاع', 'Return date'), cart.endDate, () => _pickDate(false), _errors['end_date']?.toString())),
              ]),
              LabeledField(label: tr('اسم المشروع', 'Project name'), controller: _project, hint: tr('مثلاً: إعلان حملة الشتاء', 'e.g. Winter campaign ad'), maxLength: 150, error: _errors['project']?.toString()),
              LabeledField(label: tr('موقع التصوير', 'Shoot location'), controller: _location, hint: tr('بغداد — المنصور', 'Baghdad — Al-Mansour'), maxLength: 190, last: true, error: _errors['location']?.toString()),
            ]),
            const SizedBox(height: 12),
            FormCard(children: [
              ToggleRow(title: tr('فني / مشغّل مع المعدات', 'Technician / operator with the gear'), value: cart.technician, onChanged: cart.setTechnician),
              ToggleRow(title: tr('توصيل إلى الموقع', 'Delivery to location'), value: cart.delivery, onChanged: cart.setDelivery, divider: false),
            ]),
            SectionHeader(tr('بيانات التواصل', 'Contact details'), padding: EdgeInsets.only(top: 26, bottom: 12)),
            AutofillGroup(
              child: FormCard(children: [
                LabeledField(label: tr('الاسم', 'Name'), controller: _name, autofill: const [AutofillHints.name], maxLength: 120, error: _errors['contact_name']?.toString()),
                LabeledField(
                    label: tr('رقم الهاتف', 'Phone number'),
                    controller: _phone,
                    keyboard: TextInputType.phone,
                    ltr: true,
                    hint: '07xx xxx xxxx',
                    autofill: const [AutofillHints.telephoneNumber],
                    error: _errors['phone']?.toString()),
                LabeledField(
                    label: tr('البريد (اختياري)', 'Email (optional)'),
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                    ltr: true,
                    autofill: const [AutofillHints.email],
                    error: _errors['email']?.toString()),
                LabeledField(label: tr('ملاحظات', 'Notes'), controller: _notes, maxLines: 3, maxLength: 2000, last: true),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Text(tr('التسعير', 'Pricing'), style: Txt.muted),
              const Spacer(),
              Text(tr('عرض سعر رسمي من قسم التأجير', 'Official quote from the rental desk'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 16),
            AppButton.red(tr('إرسال طلب عرض السعر', 'Send quote request'), loading: _sending, onPressed: _submit),
          ],
        ),
      ),
    );
  }

  Widget _line(CartItem i, CartState cart) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemScreen(slug: i.slug))),
            child: Container(
              width: 70,
              height: 70,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16)),
              child: NetImage(i.image),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(i.brand, style: Txt.small),
              ],
            ),
          ),
          QtyStepper(
            compact: true,
            bg: C.bg,
            value: i.qty,
            onInc: () {
              if (i.qty >= i.max) {
                showToast(context, tr('الحد الأقصى في الأسطول: ${i.max}', 'Fleet maximum: ${i.max}'));
                return;
              }
              cart.setQty(i.slug, i.qty + 1);
            },
            onDec: () => cart.setQty(i.slug, i.qty - 1),
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, String? value, VoidCallback onTap, String? error) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error == null ? label : '$label — $error', style: TextStyle(fontSize: 11.5, color: error == null ? C.muted : C.red)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(value == null ? tr('اختر', 'Select') : fmtDay(value),
                    style: TextStyle(fontSize: 15, color: value == null ? C.muted : C.ink)),
              ),
              Icon(Icons.calendar_today_rounded, size: 16, color: C.muted),
            ]),
          ],
        ),
      ),
    );
  }
}
