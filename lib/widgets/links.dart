import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../screens/item_screen.dart';
import '../screens/kits_screen.dart';
import '../screens/track_screen.dart';
import '../state/app_state.dart';
import '../state/notifications.dart';
import '../state/session.dart';
import 'common.dart';

/// فتح رابط بنر أو إشعار: قسم، ماركة، معدة، الباقات، طلب، أو رابط خارجي
void openAppLink(BuildContext context, AppLink link) {
  final app = context.read<AppState>();
  final nav = Navigator.of(context);
  switch (link.type) {
    case 'category':
      nav.popUntil((r) => r.isFirst);
      app.openBrowse(category: link.value);
      break;
    case 'brand':
      nav.popUntil((r) => r.isFirst);
      app.openBrowse(brand: link.value);
      break;
    case 'equipment':
      if (link.value.isNotEmpty) nav.push(MaterialPageRoute(builder: (_) => ItemScreen(slug: link.value)));
      break;
    case 'kits':
      nav.push(MaterialPageRoute(builder: (_) => const KitsScreen()));
      break;
    case 'order':
      if (context.read<SessionState>().loggedIn) {
        nav.popUntil((r) => r.isFirst);
        app.goTab(3);
      } else {
        final phone = context.read<NotificationsState>().phoneFor(link.value);
        nav.push(MaterialPageRoute(builder: (_) => TrackScreen(initialRef: link.value, initialPhone: phone)));
      }
      break;
    case 'url':
      if (link.value.startsWith('http')) openLink(context, link.value);
      break;
  }
}
