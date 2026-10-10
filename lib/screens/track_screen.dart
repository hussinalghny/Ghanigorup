import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';

/// تتبع طلب بدون حساب: رقم الطلب + رقم الهاتف
class TrackScreen extends StatefulWidget {
  final String? initialRef, initialPhone;
  const TrackScreen({super.key, this.initialRef, this.initialPhone});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final _ref = TextEditingController();
  final _phone = TextEditingController();
  RentalOrder? _order;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ref.text = widget.initialRef ?? '';
    _phone.text = widget.initialPhone ?? '';
    if (widget.initialRef == null) {
      SharedPreferences.getInstance().then((p) {
        if (!mounted) return;
        setState(() {
          _ref.text = p.getString('gg_last_ref') ?? '';
          _phone.text = p.getString('gg_last_phone') ?? '';
        });
      }).catchError((_) {});
    } else if (widget.initialPhone != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _go());
    }
  }

  @override
  void dispose() {
    _ref.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<ApiClient>().get('/orders/track', {'ref': _ref.text.trim().toUpperCase(), 'phone': _phone.text.trim()});
      if (mounted) setState(() => _order = RentalOrder.fromJson(r.map));
    } catch (e) {
      if (mounted) {
        setState(() {
          _order = null;
          _error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع طلب', style: TextStyle(fontWeight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          const Text('أدخل رقم الطلب ورقم الهاتف المستخدم في الطلب.', style: Txt.muted),
          const SizedBox(height: 16),
          FormCard(children: [
            LabeledField(label: 'رقم الطلب', controller: _ref, hint: 'GG-XXXXXX', ltr: true),
            LabeledField(label: 'رقم الهاتف', controller: _phone, keyboard: TextInputType.phone, ltr: true, last: true),
          ]),
          const SizedBox(height: 14),
          AppButton('عرض الحالة', loading: _loading, onPressed: _go),
          const SizedBox(height: 20),
          if (_error != null) EmptyState(icon: Icons.search_off_rounded, title: 'لم يتم العثور على الطلب', message: _error!),
          if (_order != null) ...[
            OrderCard(_order!, showCancel: false),
            FormCard(children: [
              for (var i = 0; i < _order!.items.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: i == _order!.items.length - 1 ? null : const Border(bottom: BorderSide(color: C.line))),
                  child: Row(children: [
                    Expanded(
                      child: Text('${_order!.items[i].brand} ${_order!.items[i].name}', textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: 10),
                    Text('×${_order!.items[i].qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
