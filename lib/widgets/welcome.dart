import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';
import '../core/i18n.dart';

/// يعرض رسالة الترحيب حسب إعداد التكرار (مرة واحدة / يومياً / كل فتح)
Future<void> maybeShowWelcome(BuildContext context, WelcomeMessage? w) async {
  if (w == null || w.title.isEmpty) return;
  final now = DateTime.now();
  final today = '${now.year}-${now.month}-${now.day}';
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('gg_welcome');
    final seen = raw == null ? const <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (w.frequency == 'once' && seen['id'] == w.id) return;
    if (w.frequency == 'daily' && seen['id'] == w.id && seen['day'] == today) return;
    await p.setString('gg_welcome', jsonEncode({'id': w.id, 'day': today}));
  } catch (_) {}
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('إغلاق', 'Close'),
    barrierColor: Colors.black.withAlpha(110),
    transitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (ctx, _, __) => _WelcomeCard(w),
    transitionBuilder: (ctx, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween<double>(begin: .86, end: 1).animate(c), child: child),
      );
    },
  );
}

class _WelcomeCard extends StatelessWidget {
  final WelcomeMessage w;
  const _WelcomeCard(this.w);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: C.surface,
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (w.image != null)
                  Stack(children: [
                    AspectRatio(aspectRatio: 3 / 2, child: NetImage(w.image, fit: BoxFit.cover)),
                    PositionedDirectional(top: 12, end: 12, child: _close(context, onImage: true)),
                  ])
                else
                  Align(alignment: AlignmentDirectional.centerEnd, child: Padding(padding: const EdgeInsets.all(12), child: _close(context))),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, w.image != null ? 22 : 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Reveal(delay: const Duration(milliseconds: 150), child: Text(w.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.4))),
                      if (w.body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Reveal(delay: const Duration(milliseconds: 230), child: Text(w.body, textAlign: TextAlign.center, style: Txt.muted.copyWith(fontSize: 14, height: 1.8))),
                      ],
                      const SizedBox(height: 22),
                      Reveal(
                        delay: const Duration(milliseconds: 310),
                        child: AppButton(w.button, onPressed: () {
                          Navigator.of(context).pop();
                          if (w.link.startsWith('http')) openLink(context, w.link);
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _close(BuildContext context, {bool onImage = false}) => Material(
        color: onImage ? Colors.black.withAlpha(90) : C.soft,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tr('إغلاق', 'Close'),
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded, size: 18, color: onImage ? Colors.white : C.ink),
        ),
      );
}
