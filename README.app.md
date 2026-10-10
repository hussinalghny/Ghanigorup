# Ghani Group — تطبيق iOS و Android

تطبيق Flutter أصلي (Native) لتأجير معدات التصوير السينمائي، متصل بـ API موقع `ghanigroup.online`.
التصميم مطابق للتصميم المعتمد (Studio) والهوية: شعار GH، أحمر Ghani Group، خط Alexandria.

## الشاشات
- **الرئيسية**: الأقسام، بانر، الأكثر طلباً، الباقات الجاهزة، وصل حديثاً.
- **تصفّح**: بحث فوري، فلترة بالأقسام، ترتيب، تحميل تدريجي.
- **المعدة**: الصور، المواصفات، تقويم التوفر 21 يوماً (الأيام المحجوزة معطّلة)، الكمية حسب المتاح، المفضلة.
- **الباقات**: إضافة باقة كاملة بضغطة.
- **الطلب**: السلة، التواريخ، فني/توصيل، بيانات التواصل، إرسال طلب عرض السعر، متابعة بواتساب.
- **حسابي**: دخول / حساب جديد (اختياري)، طلباتي وحالتها، المفضلة، تعديل البيانات، تغيير كلمة المرور، **حذف الحساب**، الخصوصية والشروط والدعم.
- **تتبع طلب** برقم الطلب والهاتف بدون حساب.
- **تحديث إجباري** و**وضع صيانة** من لوحة التحكم بدون رفع إصدار جديد.

## متطلبات المتاجر المُطبّقة
| المتطلب | الحالة |
|---|---|
| Apple 5.1.1(v) حذف الحساب داخل التطبيق | ✓ حسابي ▸ الحساب ▸ حذف الحساب |
| Google Play: رابط ويب لحذف الحساب | ✓ `/delete-account` |
| سياسة خصوصية داخل التطبيق وفي المتجر | ✓ |
| Privacy Manifest (PrivacyInfo.xcprivacy) | ✓ |
| التصفح بدون إجبار على التسجيل (Apple 5.1.1) | ✓ |
| لا مشتريات داخلية (عرض سعر فقط) | ✓ |
| Export compliance (`ITSAppUsesNonExemptEncryption = NO`) | ✓ |
| Xcode 26 / iOS 26 SDK | ✓ Codemagic `xcode: latest` |
| Google Play targetSdk 36 | ✓ |
| Edge-to-edge + Predictive back (Android 15/16) | ✓ |
| صلاحيات: الإنترنت فقط | ✓ |
| تخزين التوكن مشفّراً (Keychain / EncryptedSharedPreferences) | ✓ |
| HTTPS فقط، منع cleartext، منع النسخ الاحتياطي للبيانات | ✓ |

## التشغيل محلياً
```bash
flutter --version            # 3.24 أو أحدث (stable)
bash tool/prepare_platforms.sh   # يولّد android/ و ios/ ويطبّق كل الإعدادات والأيقونات
flutter run
# سيرفر آخر للتجربة:
flutter run --dart-define=SITE_URL=https://staging.ghanigroup.online
```

## البناء والرفع
كله عبر **Codemagic** — الملف `codemagic.yaml` جاهز. الخطوات الكاملة لإعداد المفاتيح والمتاجر وإجابات الاستبيانات:
**`docs/STORE_SUBMISSION.md`** · نصوص المتجر: **`docs/STORE_LISTING.md`**

## الهيكل
```
lib/
  core/      config (الدومين) · api (الاتصال + التوكن الآمن) · models · theme
  state/     app_state (الإعدادات والتبويبات) · cart (السلة محفوظة) · session (الحساب والمفضلة)
  screens/   startup · shell · home · browse · item · kits · order · account · track
  widgets/   common · equipment_card
assets/      الخطوط (Alexandria عربي+لاتيني) والشعار
brand/       مصادر الأيقونة وشاشة البداية (تُولَّد منها كل المقاسات تلقائياً)
store/       أيقونة Play، Feature graphic، لقطات الشاشة
tool/        prepare_platforms.sh · patch_platforms.py · patch_xcode.rb
ios/Runner/PrivacyInfo.xcprivacy
codemagic.yaml
```

مجلدا `android/` و `ios/` يُولَّدان تلقائياً بأحدث قالب Flutter ثم تُطبَّق عليهما الإعدادات، فيبقى المشروع متوافقاً مع أي إصدار Flutter جديد بدون صيانة يدوية.
