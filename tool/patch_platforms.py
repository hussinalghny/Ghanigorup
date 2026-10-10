#!/usr/bin/env python3
"""
يطبّق إعدادات Ghani Group على مجلدات android/ و ios/ التي يولّدها `flutter create`.
آمن للتشغيل أكثر من مرة (idempotent). يُشغَّل تلقائياً من tool/prepare_platforms.sh

  - Android: applicationId، minSdk 24، targetSdk/compileSdk 36 (متطلب Google Play 2026)،
             توقيع الإصدار من Codemagic أو key.properties، صلاحية الإنترنت، منع النسخ الاحتياطي،
             اسم التطبيق، queries لروابط واتساب والاتصال.
  - iOS:     اسم العرض، عدم استخدام تشفير غير معفى، اتجاه عمودي، اللغات.
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "online.ghanigroup.app"
APP_NAME = "Ghani Group"
TARGET_SDK = 36
MIN_SDK = 24
MARK = "// ghani-patched"


def fail(msg: str) -> None:
    print(f"[patch] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def sub_once(pattern: str, repl, text: str, what: str, required: bool = True) -> str:
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n == 0 and required:
        fail(f"لم أجد السطر المطلوب لتعديل: {what}")
    return new


# ---------------------------------------------------------------- Android
def patch_gradle() -> None:
    kts = ROOT / "android/app/build.gradle.kts"
    groovy = ROOT / "android/app/build.gradle"
    path = kts if kts.exists() else groovy
    if not path.exists():
        fail("android/app/build.gradle(.kts) غير موجود — شغّل flutter create أولاً")
    s = path.read_text(encoding="utf-8")
    if MARK in s:
        print(f"[patch] {path.name} already patched")
        return
    is_kts = path.suffix == ".kts"

    s = sub_once(r'applicationId\s*=?\s*"[^"]*"', f'applicationId = "{APP_ID}"', s, "applicationId")
    s = sub_once(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", f"minSdk = {MIN_SDK}", s, "minSdk")
    s = sub_once(r"targetSdk(Version)?\s*=?\s*flutter\.targetSdkVersion", f"targetSdk = {TARGET_SDK}", s, "targetSdk")
    if is_kts:
        s = sub_once(r"compileSdk\s*=\s*flutter\.compileSdkVersion", f"compileSdk = maxOf({TARGET_SDK}, flutter.compileSdkVersion)", s, "compileSdk")
    else:
        s = sub_once(r"compileSdk(Version)?\s*=?\s*flutter\.compileSdkVersion", f"compileSdk = Math.max({TARGET_SDK}, flutter.compileSdkVersion)", s, "compileSdk")

    if is_kts:
        imports = f"{MARK}\nimport java.io.FileInputStream\nimport java.util.Properties\n\n"
        keystore = '''

// توقيع الإصدار: Codemagic يضبط CM_KEYSTORE_* تلقائياً، ومحلياً يُقرأ android/key.properties
val releaseKeystore: Map<String, String?> = run {
    val env = System.getenv("CM_KEYSTORE_PATH")
    if (env != null) {
        mapOf(
            "storeFile" to env,
            "storePassword" to System.getenv("CM_KEYSTORE_PASSWORD"),
            "keyAlias" to System.getenv("CM_KEY_ALIAS"),
            "keyPassword" to System.getenv("CM_KEY_PASSWORD"),
        )
    } else {
        val f = rootProject.file("key.properties")
        if (f.exists()) {
            val p = Properties()
            p.load(FileInputStream(f))
            mapOf(
                "storeFile" to p.getProperty("storeFile"),
                "storePassword" to p.getProperty("storePassword"),
                "keyAlias" to p.getProperty("keyAlias"),
                "keyPassword" to p.getProperty("keyPassword"),
            )
        } else emptyMap()
    }
}
'''
        signing = '''    signingConfigs {
        create("release") {
            if (releaseKeystore["storeFile"] != null) {
                storeFile = file(releaseKeystore["storeFile"]!!)
                storePassword = releaseKeystore["storePassword"]
                keyAlias = releaseKeystore["keyAlias"]
                keyPassword = releaseKeystore["keyPassword"]
            }
        }
    }

    buildTypes {'''
        use = ('signingConfig = if (releaseKeystore["storeFile"] != null) '
               'signingConfigs.getByName("release") else signingConfigs.getByName("debug")')
        # الـ imports أول الملف، و plugins {} يجب أن يبقى أول تعليمة، لذلك نضع التعريفات بعده
        s = imports + s
        s = sub_once(r"^(plugins \{[\s\S]*?\n\})", lambda m: m.group(1) + keystore, s, "plugins block")
        s = sub_once(r"^    buildTypes \{", signing, s, "buildTypes")
        s = sub_once(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', use, s, "release signingConfig")
    else:
        header = f'''{MARK}
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {{ keystorePropertiesFile.withInputStream {{ keystoreProperties.load(it) }} }}
def ksPath = System.getenv("CM_KEYSTORE_PATH") ?: keystoreProperties["storeFile"]

'''
        signing = '''    signingConfigs {
        release {
            if (ksPath != null) {
                storeFile file(ksPath)
                storePassword System.getenv("CM_KEYSTORE_PASSWORD") ?: keystoreProperties["storePassword"]
                keyAlias System.getenv("CM_KEY_ALIAS") ?: keystoreProperties["keyAlias"]
                keyPassword System.getenv("CM_KEY_PASSWORD") ?: keystoreProperties["keyPassword"]
            }
        }
    }

    buildTypes {'''
        # في groovy يجب أن تأتي plugins {} أولاً، لذلك نضع التعريفات بعدها
        s = sub_once(r"^(plugins \{[\s\S]*?\n\})", r"\1\n\n" + header.replace("\\", "\\\\"), s, "plugins block")
        s = sub_once(r"^    buildTypes \{", signing, s, "buildTypes")
        s = sub_once(r"signingConfig\s*=?\s*signingConfigs\.debug", "signingConfig = ksPath != null ? signingConfigs.release : signingConfigs.debug", s, "release signingConfig")

    path.write_text(s, encoding="utf-8")
    print(f"[patch] {path.relative_to(ROOT)} ✓")


def patch_manifest() -> None:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not path.exists():
        fail("AndroidManifest.xml غير موجود")
    s = path.read_text(encoding="utf-8")
    if "ghani-patched" in s:
        print("[patch] AndroidManifest already patched")
        return

    s = sub_once(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', s, "android:label")
    extra = []
    for attr, val in [("android:allowBackup", "false"), ("android:fullBackupContent", "false"),
                      ("android:usesCleartextTraffic", "false"), ("android:enableOnBackInvokedCallback", "true")]:
        if attr not in s:
            extra.append(f'{attr}="{val}"')
    if extra:
        s = s.replace(f'android:label="{APP_NAME}"', f'android:label="{APP_NAME}"\n        ' + "\n        ".join(extra), 1)

    if "android.permission.INTERNET" not in s:
        s = sub_once(r"(<manifest[^>]*>)", r'\1\n    <!-- ghani-patched -->\n    <uses-permission android:name="android.permission.INTERNET"/>', s, "<manifest>")
    else:
        s = sub_once(r"(<manifest[^>]*>)", r"\1\n    <!-- ghani-patched -->", s, "<manifest>")

    intents = '''        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
'''
    if "<queries>" in s:
        s = s.replace("    </queries>", intents + "    </queries>", 1)
    else:
        s = s.replace("</manifest>", "    <queries>\n" + intents + "    </queries>\n</manifest>", 1)

    path.write_text(s, encoding="utf-8")
    print("[patch] AndroidManifest.xml ✓")


def patch_gradle_properties() -> None:
    path = ROOT / "android/gradle.properties"
    if not path.exists():
        return
    s = path.read_text(encoding="utf-8")
    if "android.suppressUnsupportedCompileSdk" not in s:
        s = s.rstrip() + f"\nandroid.suppressUnsupportedCompileSdk={TARGET_SDK}\n"
        path.write_text(s, encoding="utf-8")
        print("[patch] gradle.properties ✓")


# ---------------------------------------------------------------- iOS
def patch_info_plist() -> None:
    path = ROOT / "ios/Runner/Info.plist"
    if not path.exists():
        print("[patch] ios/Runner/Info.plist غير موجود — تخطي iOS")
        return
    with path.open("rb") as f:
        p = plistlib.load(f)
    p["CFBundleDisplayName"] = APP_NAME
    p["CFBundleLocalizations"] = ["ar", "en"]
    p["ITSAppUsesNonExemptEncryption"] = False          # HTTPS فقط ← معفى من قيود التصدير
    p["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
    p.pop("UISupportedInterfaceOrientations~ipad", None)
    p["LSApplicationQueriesSchemes"] = ["https", "tel", "whatsapp"]
    p["UIViewControllerBasedStatusBarAppearance"] = True
    with path.open("wb") as f:
        plistlib.dump(p, f)
    print("[patch] ios/Runner/Info.plist ✓")


if __name__ == "__main__":
    patch_gradle()
    patch_manifest()
    patch_gradle_properties()
    patch_info_plist()
    print("[patch] done")
