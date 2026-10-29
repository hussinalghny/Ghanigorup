import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/notifications.dart';
import '../state/push.dart';
import '../widgets/promo_consent.dart';
import '../state/session.dart';
import '../state/theme_state.dart';
import '../widgets/common.dart';
import '../widgets/equipment_card.dart';
import 'notifications_screen.dart';
import 'track_screen.dart';
import '../core/i18n.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionState>();
    if (s.restoring) return Center(child: CircularProgressIndicator(color: C.ink));
    return SafeArea(bottom: false, child: s.loggedIn ? const _Profile() : const _AuthView());
  }
}

// ======================= تسجيل الدخول / حساب جديد =======================

class _AuthView extends StatefulWidget {
  const _AuthView();

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  bool _register = false;
  bool _busy = false;
  Map<String, dynamic> _errors = {};
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _company, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final s = context.read<SessionState>();
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      if (_register) {
        await s.register(name: _name.text, email: _email.text, phone: _phone.text, company: _company.text, password: _password.text);
      } else {
        await s.login(_email.text, _password.text);
      }
      _password.clear();
      if (mounted) showToast(context, tr('أهلاً ${s.user?.name ?? ''}', 'Welcome ${s.user?.name ?? ''}'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.details);
      showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? err(String k) => _errors[k]?.toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text(_register ? tr('حساب جديد', 'Sign up') : tr('تسجيل الدخول', 'Sign in'), style: Txt.title),
        const SizedBox(height: 6),
        Text(tr('الحساب اختياري — يمكنك التصفح وإرسال طلب بدون حساب. الحساب يحفظ طلباتك ومفضلتك.', 'An account is optional — you can browse and send a request without one. An account keeps your orders and favorites.'), style: Txt.muted),
        const SizedBox(height: 16),
        _Segmented(
          labels: [tr('دخول', 'Sign in'), tr('حساب جديد', 'Sign up')],
          index: _register ? 1 : 0,
          onChanged: (i) => setState(() {
            _register = i == 1;
            _errors = {};
          }),
        ),
        const SizedBox(height: 14),
        AutofillGroup(
          child: FormCard(children: [
            if (_register) ...[
              LabeledField(label: tr('الاسم', 'Name'), controller: _name, autofill: const [AutofillHints.name], error: err('name')),
              LabeledField(label: tr('رقم الهاتف', 'Phone number'), controller: _phone, keyboard: TextInputType.phone, ltr: true, autofill: const [AutofillHints.telephoneNumber], error: err('phone')),
              LabeledField(label: tr('الشركة (اختياري)', 'Company (optional)'), controller: _company, autofill: const [AutofillHints.organizationName], error: err('company')),
            ],
            LabeledField(label: tr('البريد الإلكتروني', 'Email'), controller: _email, keyboard: TextInputType.emailAddress, ltr: true, autofill: const [AutofillHints.email], error: err('email')),
            LabeledField(
              label: tr('كلمة المرور', 'Password'),
              controller: _password,
              obscure: true,
              ltr: true,
              last: true,
              autofill: [_register ? AutofillHints.newPassword : AutofillHints.password],
              error: err('password'),
              action: TextInputAction.done,
            ),
          ]),
        ),
        if (_register)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(tr('8 أحرف على الأقل وتحتوي حروفاً وأرقاماً.', 'At least 8 characters, with letters and numbers.'), style: Txt.small),
          ),
        const SizedBox(height: 16),
        AppButton(_register ? tr('إنشاء الحساب', 'Create account') : tr('دخول', 'Sign in'), loading: _busy, onPressed: _submit),
        if (_register)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: tr('بإنشاء حساب فإنك توافق على ', 'By creating an account you agree to the ')),
                WidgetSpan(child: _LinkText(tr('شروط الاستخدام', 'Terms of Use'), AppConfig.termsUrl)),
                TextSpan(text: tr(' و', ' and ')),
                WidgetSpan(child: _LinkText(tr('سياسة الخصوصية', 'Privacy Policy'), AppConfig.privacyUrl)),
              ]),
              style: Txt.small,
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 26),
        _MenuCard(items: [
          _MenuItem(Icons.local_shipping_outlined, tr('تتبع طلب برقم الطلب', 'Track an order by number'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrackScreen()))),
        ]),
        const SizedBox(height: 12),
        const _InfoSection(),
      ],
    );
  }
}

// ======================= الحساب =======================

class _Profile extends StatefulWidget {
  const _Profile();

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  int _tab = 0;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionState>().user!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Text(tr('حسابي', 'Account'), style: Txt.title),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(26)),
          child: Row(children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: C.onInk,
              child: Text(u.name.trim().isEmpty ? '?' : u.name.trim().substring(0, 1),
                  style: TextStyle(color: C.ink, fontWeight: FontWeight.w600, fontSize: 18)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.name, style: TextStyle(color: C.onInk, fontSize: 17, fontWeight: FontWeight.w600)),
                Text(u.email, textDirection: TextDirection.ltr, style: TextStyle(color: C.inkMuted, fontSize: 12.5)),
              ]),
            ),
            OutlinedButton(
              onPressed: () => context.read<SessionState>().logout(),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.inkMuted,
                side: BorderSide(color: C.inkLine),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(tr('خروج', 'Sign out'), style: TextStyle(fontSize: 12.5)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _Segmented(labels: [tr('طلباتي', 'My orders'), tr('المفضلة', 'Favorites'), tr('الحساب', 'Profile')], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        const SizedBox(height: 14),
        if (_tab == 0) _OrdersList(key: ValueKey('orders$_reload'), onChanged: () => setState(() => _reload++)),
        if (_tab == 1) const _Favorites(),
        if (_tab == 2) const _Settings(),
      ],
    );
  }
}

class _OrdersList extends StatefulWidget {
  final VoidCallback onChanged;
  const _OrdersList({super.key, required this.onChanged});

  @override
  State<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<_OrdersList> {
  late Future<List<RentalOrder>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RentalOrder>> _load() async {
    final r = await context.read<ApiClient>().get('/me/orders');
    return r.list.map(RentalOrder.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RentalOrder>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(snap.error!, onRetry: () => setState(() {
                _future = _load();
              }));
        if (!snap.hasData) return const Skeleton(height: 120);
        if (snap.data!.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: tr('لا توجد طلبات بعد', 'No orders yet'),
            message: tr('طلباتك وعروض الأسعار ستظهر هنا.', 'Your orders and quotes will appear here.'),
            action: tr('تصفّح المعدات', 'Browse gear'),
            onAction: () => context.read<AppState>().openBrowse(),
          );
        }
        return Column(children: [
          for (var i = 0; i < snap.data!.length; i++) Reveal(index: i, child: OrderCard(snap.data![i], onCancelled: widget.onChanged)),
        ]);
      },
    );
  }
}

/// بطاقة طلب مع الحالة وشريط التقدم
class OrderCard extends StatelessWidget {
  final RentalOrder order;
  final bool showCancel;
  final VoidCallback? onCancelled;
  const OrderCard(this.order, {super.key, this.showCancel = true, this.onCancelled});

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('إلغاء هذا الطلب؟', 'Cancel this order?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('رجوع', 'Back'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('إلغاء الطلب', 'Cancel order'), style: TextStyle(color: C.red))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<ApiClient>().post('/me/orders/${order.ref}/cancel');
      if (context.mounted) showToast(context, tr('تم إلغاء الطلب', 'Order cancelled'));
      onCancelled?.call();
    } catch (e) {
      if (context.mounted) showToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = OrderStatus.of(order.status);
    final currency = context.select<AppState, String>((a) => a.currency);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16)),
            child: NetImage(order.items.isNotEmpty ? order.items.first.image : null),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(order.project ?? tr('طلب ${order.ref}', 'Order ${order.ref}'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  StatusChip(order.status),
                ]),
                const SizedBox(height: 4),
                Text(tr('${order.ref} · ${fmtDay(order.startDate)} – ${fmtDay(order.endDate)} · ${order.units} قطعة', '${order.ref} · ${fmtDay(order.startDate)} – ${fmtDay(order.endDate)} · ${order.units} pcs'), style: Txt.small),
                if (order.quoteAmount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: tr('عرض السعر: ', 'Quote: ')),
                      TextSpan(text: '${fmtNumber(order.quoteAmount!)} $currency', style: TextStyle(color: C.ink, fontWeight: FontWeight.w600)),
                    ]), style: Txt.small),
                  ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: st.progress,
                    minHeight: 5,
                    backgroundColor: C.soft,
                    color: order.status == 'cancelled' ? C.red : C.ink,
                  ),
                ),
                if (showCancel && order.cancellable)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => _cancel(context),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 34)),
                      child: Text(tr('إلغاء الطلب', 'Cancel order'), style: TextStyle(color: C.muted, fontSize: 12)),
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

class _Favorites extends StatefulWidget {
  const _Favorites();

  @override
  State<_Favorites> createState() => _FavoritesState();
}

class _FavoritesState extends State<_Favorites> {
  late Future<List<Equipment>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Equipment>> _load() async {
    final r = await context.read<ApiClient>().get('/me/favorites');
    return r.list.map(Equipment.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Equipment>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(snap.error!, onRetry: () => setState(() {
                _future = _load();
              }));
        if (!snap.hasData) return const Skeleton(height: 200);
        final items = snap.data!;
        if (items.isEmpty) {
          return EmptyState(icon: Icons.favorite_border_rounded, title: tr('لا توجد مفضلة', 'No favorites yet'), message: tr('اضغط ♡ في صفحة أي معدة لحفظها هنا.', 'Tap ♡ on any item to save it here.'));
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 262),
          itemBuilder: (_, i) => EquipmentCard(items[i]),
        );
      },
    );
  }
}

class _Settings extends StatefulWidget {
  const _Settings();

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late final TextEditingController _name, _phone, _company;
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _savingProfile = false, _savingPw = false;
  Map<String, dynamic> _errors = {};

  @override
  void initState() {
    super.initState();
    final u = context.read<SessionState>().user!;
    _name = TextEditingController(text: u.name);
    _phone = TextEditingController(text: u.phone ?? '');
    _company = TextEditingController(text: u.company ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _company, _current, _next]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() {
      _savingProfile = true;
      _errors = {};
    });
    try {
      await context.read<SessionState>().updateProfile({'name': _name.text.trim(), 'phone': _phone.text.trim(), 'company': _company.text.trim()});
      if (mounted) showToast(context, tr('تم الحفظ', 'Saved'));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errors = e.details);
        showToast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    setState(() {
      _savingPw = true;
      _errors = {};
    });
    try {
      await context.read<SessionState>().changePassword(_current.text, _next.text);
      _current.clear();
      _next.clear();
      if (mounted) showToast(context, tr('تم تغيير كلمة المرور', 'Password changed'));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errors = e.details);
        showToast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  /// حذف الحساب — مطلوب من Apple (Guideline 5.1.1(v)) و Google Play
  Future<void> _deleteAccount() async {
    final pw = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('حذف الحساب نهائياً', 'Delete account permanently')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('سيتم حذف بيانات حسابك (الاسم، البريد، الهاتف، الشركة) والمفضلة فوراً، ولا يمكن التراجع. سجلات الطلبات السابقة تبقى لدى الشركة كسجل تجاري بدون ربطها بحسابك.', "Your account data (name, email, phone, company) and favorites will be deleted immediately. This can't be undone. Past order records stay with the company as business records, no longer linked to your account."),
              style: TextStyle(fontSize: 13.5, height: 1.7),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pw,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('كلمة المرور للتأكيد', 'Password to confirm'), border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('إلغاء', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('حذف الحساب', 'Delete account'), style: TextStyle(color: C.red))),
        ],
      ),
    );
    final password = pw.text; // لا نتخلص من المتحكم هنا لأن الحوار ما زال يُغلق بحركة
    if (confirmed != true || !mounted) return;
    try {
      await context.read<SessionState>().deleteAccount(password);
      if (mounted) showToast(context, tr('تم حذف حسابك نهائياً', 'Your account has been deleted'));
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    String? err(String k) => _errors[k]?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormCard(children: [
          LabeledField(label: tr('الاسم', 'Name'), controller: _name, error: err('name')),
          LabeledField(label: tr('الهاتف', 'Phone'), controller: _phone, keyboard: TextInputType.phone, ltr: true, error: err('phone')),
          LabeledField(label: tr('الشركة', 'Company'), controller: _company, last: true, error: err('company')),
        ]),
        const SizedBox(height: 12),
        AppButton(tr('حفظ', 'Save'), loading: _savingProfile, onPressed: _saveProfile),
        SectionHeader(tr('تغيير كلمة المرور', 'Change password'), padding: EdgeInsets.only(top: 28, bottom: 12)),
        FormCard(children: [
          LabeledField(label: tr('كلمة المرور الحالية', 'Current password'), controller: _current, obscure: true, ltr: true, error: err('current')),
          LabeledField(label: tr('كلمة المرور الجديدة', 'New password'), controller: _next, obscure: true, ltr: true, last: true, error: err('new')),
        ]),
        const SizedBox(height: 12),
        AppButton.light(tr('تغيير كلمة المرور', 'Change password'), loading: _savingPw, onPressed: _savePassword),
        const SizedBox(height: 26),
        const _InfoSection(),
        const SizedBox(height: 12),
        _MenuCard(items: [
          _MenuItem(Icons.delete_outline_rounded, tr('حذف الحساب', 'Delete account'), _deleteAccount, color: C.red),
        ]),
      ],
    );
  }
}

// ======================= مشترك =======================

/// روابط الخصوصية والشروط والدعم والتواصل + رقم الإصدار (مطلوبة للمتاجر)
class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unread = context.select<NotificationsState, int>((n) => n.unread);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AppearanceCard(),
        const SizedBox(height: 12),
        const _LanguageCard(),
        const SizedBox(height: 12),
        if (PushService.available) ...[
          PromoToggle(read: PushService.promoConsent, write: (v) async => PushService.instance?.setPromo(v)),
          const SizedBox(height: 12),
        ],
        _MenuCard(items: [
          _MenuItem(Icons.notifications_none_rounded, unread > 0 ? tr('الإشعارات ($unread جديد)', 'Notifications ($unread new)') : tr('الإشعارات', 'Notifications'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(26)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('قسم التأجير', 'Rental desk'), style: TextStyle(color: C.onInk, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if ((app.settings['address'] ?? '').isNotEmpty)
                Text(app.settings['address']!, style: TextStyle(color: C.inkMuted, fontSize: 12.5, height: 1.8)),
              Text(app.phone, textDirection: TextDirection.ltr, style: TextStyle(color: C.inkMuted, fontSize: 12.5)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: AppButton(tr('واتساب', 'WhatsApp'),
                      color: C.onInk, fg: C.ink, height: 44, onPressed: () => openLink(context, whatsappUrl(app.whatsapp, tr('مرحباً Ghani Group', 'Hello Ghani Group')))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(tr('اتصال', 'Call'),
                      color: C.ink2, height: 44, onPressed: () => openLink(context, 'tel:${app.phone.replaceAll(RegExp(r'[^0-9+]'), '')}')),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MenuCard(items: [
          _MenuItem(Icons.privacy_tip_outlined, tr('سياسة الخصوصية', 'Privacy Policy'), () => openLink(context, AppConfig.privacyUrl, inApp: true)),
          _MenuItem(Icons.description_outlined, tr('شروط الاستخدام', 'Terms of Use'), () => openLink(context, AppConfig.termsUrl, inApp: true)),
          _MenuItem(Icons.support_agent_rounded, tr('الدعم', 'Support'), () => openLink(context, AppConfig.supportUrl, inApp: true)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(tr('Ghani Group · الإصدار ${app.version} (${app.build})', 'Ghani Group · Version ${app.version} (${app.build})'), textAlign: TextAlign.center, style: Txt.small),
        ),
      ],
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  _MenuItem(this.icon, this.label, this.onTap, {this.color});
}

class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            InkWell(
              onTap: items[i].onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(border: i == items.length - 1 ? null : Border(bottom: BorderSide(color: C.line))),
                child: Row(children: [
                  Icon(items[i].icon, size: 20, color: items[i].color ?? C.ink),
                  const SizedBox(width: 12),
                  Expanded(child: Text(items[i].label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: items[i].color ?? C.ink))),
                  Icon(Icons.chevron_left_rounded, color: C.line),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const _Segmented({required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: i == index ? C.ink : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(labels[i], style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: i == index ? C.onInk : C.muted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// المظهر: تلقائي (حسب النظام) / فاتح / داكن
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeState>();
    final opts = [
      (AppThemeMode.system, Icons.brightness_auto_rounded, tr('تلقائي', 'Auto')),
      (AppThemeMode.light, Icons.light_mode_rounded, tr('فاتح', 'Light')),
      (AppThemeMode.dark, Icons.dark_mode_rounded, tr('داكن', 'Dark')),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('المظهر', 'Appearance'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final o in opts)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Builder(builder: (bctx) {
                      final on = t.mode == o.$1;
                      return Pressable(
                        scale: .94,
                        onTap: () {
                          final box = bctx.findRenderObject() as RenderBox?;
                          t.set(o.$1, from: box?.localToGlobal(box.size.center(Offset.zero)));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: on ? C.ink : C.bg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(children: [
                            AnimatedScale(
                              scale: on ? 1.12 : 1,
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.elasticOut,
                              child: Icon(o.$2, size: 22, color: on ? C.onInk : C.muted),
                            ),
                            const SizedBox(height: 6),
                            Text(o.$3, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: on ? C.onInk : C.ink)),
                          ]),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// اللغة: تلقائي (حسب لغة الجهاز) / العربية / English
class _LanguageCard extends StatelessWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LangState>();
    final opts = [
      (AppLang.system, Icons.language_rounded, tr('تلقائي', 'Auto')),
      (AppLang.ar, Icons.translate_rounded, 'العربية'),
      (AppLang.en, Icons.translate_rounded, 'English'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('اللغة', 'Language'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final o in opts)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Pressable(
                      scale: .94,
                      onTap: () => l.set(o.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: l.lang == o.$1 ? C.ink : C.bg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(children: [
                          Icon(o.$2, size: 22, color: l.lang == o.$1 ? C.onInk : C.muted),
                          const SizedBox(height: 6),
                          Text(o.$3, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: l.lang == o.$1 ? C.onInk : C.ink)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  final String text, url;
  const _LinkText(this.text, this.url);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openLink(context, url, inApp: true),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: C.ink, decoration: TextDecoration.underline)),
      );
}
