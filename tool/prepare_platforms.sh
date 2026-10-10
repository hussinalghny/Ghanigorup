#!/usr/bin/env bash
# يجهّز مجلدات android/ و ios/ بكل إعدادات Ghani Group.
# يُستخدم في Codemagic ومحلياً بنفس الطريقة:   bash tool/prepare_platforms.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Flutter $(flutter --version | head -1)"

# 1) توليد الملفات الناقصة فقط (لا يستبدل أي ملف موجود)
flutter create --org online.ghanigroup --project-name ghani_group --platforms=android,ios --no-pub .

# 2) إعدادات المتاجر (Bundle/Package ID، SDK، التوقيع، الصلاحيات، Info.plist)
python3 tool/patch_platforms.py

# 3) الحزم + الأيقونات + شاشة البداية
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create

# 4) مشروع Xcode (على macOS فقط)
if [[ "$(uname)" == "Darwin" ]]; then
  ruby tool/patch_xcode.rb
fi

echo "✓ platforms ready"
