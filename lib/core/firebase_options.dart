// مولَّد تلقائياً بواسطة tool/firebase_setup.py — لا تعدّله يدوياً.
// بدون ملفات Firebase تبقى القيم فارغة ويعمل التطبيق بالإشعارات الداخلية فقط.
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static const bool android = true;
  static const bool ios = false;

  static bool get enabled => Platform.isIOS ? ios : (Platform.isAndroid && android);

  static FirebaseOptions? get options {
    if (Platform.isIOS) return null;
    if (Platform.isAndroid) return const FirebaseOptions(
        apiKey: "AIzaSyBtO6jrGsH8-KKGq9k3C7Ov-65PERBIPWk",
        appId: "1:947801280089:android:663defbeb9ec441aea2b48",
        messagingSenderId: "947801280089",
        projectId: "ghani-app-a5a0f",
        storageBucket: "ghani-app-a5a0f.firebasestorage.app",
      );
    return null;
  }
}
