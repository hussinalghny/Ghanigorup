import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/notifications.dart';
import '../widgets/common.dart';
import '../widgets/links.dart';
import '../core/i18n.dart';

/// صندوق الإشعارات: العروض وتحديثات الطلبات
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final int _seenBefore;

  @override
  void initState() {
    super.initState();
    final n = context.read<NotificationsState>();
    _seenBefore = n.lastSeen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      n.refresh();
      n.markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<NotificationsState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr('الإشعارات', 'Notifications'), style: TextStyle(fontWeight: FontWeight.w600))),
      body: RefreshIndicator(
        color: C.ink,
        onRefresh: n.refresh,
        child: n.items.isEmpty
            ? ListView(children: [
                Reveal(
                  child: EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: n.loading ? tr('جاري التحميل…', 'Loading…') : tr('لا توجد إشعارات', 'No notifications'),
                    message: tr('العروض الجديدة وتحديثات طلباتك ستظهر هنا.', 'New offers and updates on your orders will appear here.'),
                  ),
                ),
              ])
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 30 + MediaQuery.paddingOf(context).bottom),
                itemCount: n.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => Reveal(index: i, child: NotificationTile(n.items[i], unread: n.items[i].id > _seenBefore)),
              ),
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  final AppNotification n;
  final bool unread;
  final VoidCallback? onTap;
  final bool compact;
  const NotificationTile(this.n, {super.key, this.unread = false, this.onTap, this.compact = false});

  static IconData iconOf(String type) => switch (type) {
        'order' => Icons.local_shipping_rounded,
        'info' => Icons.campaign_rounded,
        _ => Icons.local_offer_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final isOrder = n.type == 'order';
    return Pressable(
      onTap: onTap ?? () => openAppLink(context, n.link),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: unread ? C.ink : Colors.transparent, width: 1.5),
          boxShadow: compact ? [BoxShadow(color: C.shadow, blurRadius: 30, offset: const Offset(0, 10))] : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: isOrder ? C.okBg : C.soft, borderRadius: BorderRadius.circular(14)),
              child: Icon(iconOf(n.type), size: 20, color: isOrder ? C.ok : C.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(n.title, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
                    if (unread && !compact) Container(width: 8, height: 8, decoration: BoxDecoration(color: C.red, shape: BoxShape.circle)),
                  ]),
                  if (n.body != null) ...[
                    const SizedBox(height: 3),
                    Text(n.body!, maxLines: compact ? 2 : 5, overflow: TextOverflow.ellipsis, style: Txt.muted),
                  ],
                  if (n.image != null && !compact) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(aspectRatio: 2, child: NetImage(n.image, fit: BoxFit.cover)),
                    ),
                  ],
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    Text(timeAgo(n.createdAt), style: Txt.small),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
