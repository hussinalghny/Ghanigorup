// مولَّد تلقائياً بواسطة tool/firebase_setup.py — لا تعدّله يدوياً.
// بدون ملفات Firebase تبقى القيم فارغة ويعمل التطبيق بالإشعارات الداخلية فقط.
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static const bool android = false;
  static const bool ios = false;

  static bool get enabled => Platform.isIOS ? ios : (Platform.isAndroid && android);

  static FirebaseOptions? get options {
    if (Platform.isIOS) return null;
    if (Platform.isAndroid) return null;
    return null;
  }
}
