#!/usr/bin/env python3
"""
ربط التطبيق بـ Firebase للإشعارات الفورية — يعمل تلقائياً من tool/prepare_platforms.sh

مصدر الإعدادات (أحدهما يكفي لكل منصة):
  1) ملفات في المستودع:          firebase/google-services.json   و   firebase/GoogleService-Info.plist
  2) أو متغيرات بيئة سرية في CI:  FIREBASE_ANDROID_JSON           و   FIREBASE_IOS_PLIST
     (محتوى الملف كما هو أو بصيغة base64 — يُفضَّل هذا لأن المستودع عام)

ماذا يفعل:
  - يولّد lib/core/firebase_options.dart (بدونه يعمل التطبيق بلا إشعارات فورية)
  - Android: موارد Firebase (بدل إضافة google-services لـ Gradle)، أيقونة الإشعار، اللون، صلاحية الإشعارات
  - iOS: ملف Runner.entitlements (aps-environment) + UIBackgroundModes=remote-notification
آمن للتشغيل أكثر من مرة.
"""
import base64
import json
import os
import plistlib
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "online.ghanigroup.app"
FB = ROOT / "firebase"
OUT = ROOT / "lib/core/firebase_options.dart"


def log(m: str) -> None:
    print(f"[firebase] {m}")


def from_env(name: str, target: Path) -> None:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return
    data = raw.encode()
    if not raw.startswith(("{", "<")):
        try:
            data = base64.b64decode(raw, validate=True)
        except Exception:
            log(f"⚠ {name} ليس ملفاً صالحاً ولا base64 — تم تجاهله")
            return
    FB.mkdir(exist_ok=True)
    target.write_bytes(data)
    log(f"{target.name} ← من المتغير {name}")


def android_options():
    f = FB / "google-services.json"
    if not f.exists():
        return None
    j = json.loads(f.read_text(encoding="utf-8"))
    pi = j.get("project_info", {})
    for c in j.get("client", []):
        info = c.get("client_info", {})
        if info.get("android_client_info", {}).get("package_name") == APP_ID:
            keys = c.get("api_key") or [{}]
            return {
                "apiKey": keys[0].get("current_key", ""),
                "appId": info.get("mobilesdk_app_id", ""),
                "messagingSenderId": str(pi.get("project_number", "")),
                "projectId": pi.get("project_id", ""),
                "storageBucket": pi.get("storage_bucket", ""),
            }
    sys.exit(f"[firebase] ERROR: google-services.json لا يحتوي تطبيق Android بالمعرّف {APP_ID} — أضفه في Firebase بنفس المعرّف")


def ios_options():
    f = FB / "GoogleService-Info.plist"
    if not f.exists():
        return None
    p = plistlib.loads(f.read_bytes())
    if p.get("BUNDLE_ID") != APP_ID:
        sys.exit(f"[firebase] ERROR: GoogleService-Info.plist لمعرّف {p.get('BUNDLE_ID')} وليس {APP_ID}")
    return {
        "apiKey": p.get("API_KEY", ""),
        "appId": p.get("GOOGLE_APP_ID", ""),
        "messagingSenderId": str(p.get("GCM_SENDER_ID", "")),
        "projectId": p.get("PROJECT_ID", ""),
        "storageBucket": p.get("STORAGE_BUCKET", ""),
        "iosBundleId": APP_ID,
    }


def dart_options(o) -> str:
    if not o:
        return "null"
    fields = ",\n        ".join(f"{k}: {json.dumps(v)}" for k, v in o.items() if v)
    return f"const FirebaseOptions(\n        {fields},\n      )"


def write_dart(a, i) -> None:
    OUT.write_text(f"""// مولَّد تلقائياً بواسطة tool/firebase_setup.py — لا تعدّله يدوياً.
// بدون ملفات Firebase تبقى القيم فارغة ويعمل التطبيق بالإشعارات الداخلية فقط.
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {{
  static const bool android = {'true' if a else 'false'};
  static const bool ios = {'true' if i else 'false'};

  static bool get enabled => Platform.isIOS ? ios : (Platform.isAndroid && android);

  static FirebaseOptions? get options {{
    if (Platform.isIOS) return {dart_options(i)};
    if (Platform.isAndroid) return {dart_options(a)};
    return null;
  }}
}}
""", encoding="utf-8")
    log(f"lib/core/firebase_options.dart ✓ (Android: {'نعم' if a else 'لا'}، iOS: {'نعم' if i else 'لا'})")


def patch_android(a) -> None:
    res = ROOT / "android/app/src/main/res"
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        return
    # أيقونة الإشعار (بيضاء شفافة) لكل الكثافات
    for d in ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]:
        src = ROOT / f"brand/notification/ic_notification-{d}.png"
        if src.exists():
            (res / f"drawable-{d}").mkdir(parents=True, exist_ok=True)
            shutil.copy(src, res / f"drawable-{d}/ic_notification.png")
    values = res / "values/firebase_values.xml"
    values.parent.mkdir(parents=True, exist_ok=True)
    strings = ""
    if a:
        # نفس الموارد التي تولّدها إضافة google-services: تسمح لـ Firebase بالعمل حتى عندما يفتح النظام التطبيق لاستقبال إشعار
        strings = "\n".join(f'    <string name="{k}" translatable="false">{v}</string>' for k, v in [
            ("google_app_id", a["appId"]), ("gcm_defaultSenderId", a["messagingSenderId"]),
            ("google_api_key", a["apiKey"]), ("google_crash_reporting_api_key", a["apiKey"]),
            ("project_id", a["projectId"]), ("google_storage_bucket", a["storageBucket"]),
        ] if v)
    values.write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="notification_color">#B82619</color>
{strings}
</resources>
""", encoding="utf-8")

    s = manifest.read_text(encoding="utf-8")
    if "android.permission.POST_NOTIFICATIONS" not in s:
        s = re.sub(r"(<manifest[^>]*>)", r'\1\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>', s, count=1)
    if "default_notification_icon" not in s:
        meta = ('\n        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_notification"/>'
                '\n        <meta-data android:name="com.google.firebase.messaging.default_notification_color" android:resource="@color/notification_color"/>')
        s = re.sub(r"(<application[^>]*>)", r"\1" + meta, s, count=1)
    manifest.write_text(s, encoding="utf-8")
    log("Android ✓")


def patch_ios(i) -> None:
    plist = ROOT / "ios/Runner/Info.plist"
    if not plist.exists():
        return
    ent = ROOT / "ios/Runner/Runner.entitlements"
    with plist.open("rb") as f:
        p = plistlib.load(f)
    modes = [m for m in p.get("UIBackgroundModes", []) if m != "remote-notification"]
    if i:
        modes.append("remote-notification")
        with ent.open("wb") as f:
            plistlib.dump({"aps-environment": "production"}, f)
    elif ent.exists():
        ent.unlink()
    if modes:
        p["UIBackgroundModes"] = modes
    else:
        p.pop("UIBackgroundModes", None)
    with plist.open("wb") as f:
        plistlib.dump(p, f)
    log(f"iOS ✓ {'(Push entitlement)' if i else ''}")


if __name__ == "__main__":
    from_env("FIREBASE_ANDROID_JSON", FB / "google-services.json")
    from_env("FIREBASE_IOS_PLIST", FB / "GoogleService-Info.plist")
    a, i = android_options(), ios_options()
    write_dart(a, i)
    patch_android(a)
    patch_ios(i)
    if not a and not i:
        log("لا توجد ملفات Firebase — التطبيق سيعمل بالإشعارات الداخلية فقط (انظر docs/FIREBASE.md)")
