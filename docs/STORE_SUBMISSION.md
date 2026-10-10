# دليل الرفع على App Store و Google Play — Ghani Group

| | iOS | Android |
|---|---|---|
| المعرّف | `online.ghanigroup.app` | `online.ghanigroup.app` |
| الاسم في المتجر | Ghani Group | Ghani Group |
| أقل نظام | iOS 15 (iPhone فقط) | Android 7.0 (API 24) |
| SDK البناء | Xcode 26 / iOS 26 SDK | targetSdk 36 (Android 16) |
| السيرفر | `https://ghanigroup.online/api/v1` | نفسه |

---

## 0) قبل كل شيء — السيرفر

1. ارفع سكربت الموقع على `ghanigroup.online` مع شهادة SSL فعالة (HTTPS إلزامي).
2. أثناء التنصيب ضع رابط الموقع: `https://ghanigroup.online`.
3. تأكد أن هذه الروابط تفتح (المتاجر تطلبها):
   - `https://ghanigroup.online/privacy` — سياسة الخصوصية
   - `https://ghanigroup.online/terms` — شروط الاستخدام
   - `https://ghanigroup.online/support` — الدعم
   - `https://ghanigroup.online/delete-account` — حذف الحساب (مطلوب لـ Google Play)
4. من لوحة التحكم ▸ المستخدمون: أنشئ **حساب تجريبي للمراجعين** (دور عميل)، مثلاً:
   `review@ghanigroup.online` / `Review2026x` — ستحتاجه في الخطوتين 2 و 3.
5. من لوحة التحكم ▸ الإعدادات: بعد النشر ضع روابط المتجرين، وأقل إصدار مسموح (لإجبار التحديث مستقبلاً).

---

## 1) Codemagic (البناء والرفع الآلي)

1. ارفع مجلد التطبيق إلى مستودع GitHub / GitLab / Bitbucket خاص، وأضفه في Codemagic.
2. Codemagic سيقرأ `codemagic.yaml` تلقائياً. فيه 3 مسارات:
   - `checks` — فحص الكود والاختبارات مع كل Push.
   - `ios-release` — بناء IPA ورفعه إلى TestFlight.
   - `android-release` — بناء AAB ورفعه إلى Google Play (Internal testing).
3. يبدأ البناء عند إنشاء Tag يبدأ بـ `v` (مثل `v1.0.0`)، أو يدوياً من زر **Start new build**.

### IPA بدون توقيع (بدون حساب Apple)
مسار `ios-unsigned` في Codemagic (أو GitHub Actions ▸ Build apps) يبني IPA غير موقّع تقدر توقّعه بشهادتك. لا يحتاج أي إعداد.

### إعداد iOS في Codemagic (للرفع على App Store)
0. سجّل الـ Bundle ID: developer.apple.com ▸ Certificates, IDs & Profiles ▸ Identifiers ▸ ➕ ▸ App IDs ▸ App ▸
   Description `Ghani Group` ▸ Bundle ID (Explicit) `online.ghanigroup.app` ▸ Register.
   (بدونه يظهر الخطأ: *No matching profiles found for bundle identifier "online.ghanigroup.app"*)
1. App Store Connect ▸ Users and Access ▸ Integrations ▸ **App Store Connect API** ▸ أنشئ مفتاحاً بصلاحية **App Manager**، ونزّل ملف `.p8`.
2. Codemagic ▸ Team settings ▸ Integrations ▸ **Developer Portal** ▸ Add key، وسمّه بالضبط: `GhaniGroup ASC`.
3. في `codemagic.yaml` ضع قيمة `APP_STORE_APPLE_ID` (رقم التطبيق من App Store Connect ▸ App Information ▸ Apple ID).
4. أنشئ مفتاحاً خاصاً للشهادة مرة واحدة (على أي جهاز فيه OpenSSL):
   ```bash
   ssh-keygen -t rsa -b 2048 -m PEM -f ghani_cert_key -q -N ""
   ```
   Codemagic ▸ Environment variables ▸ مجموعة باسم `ios_signing` ▸ متغير `CERTIFICATE_PRIVATE_KEY` = محتوى ملف `ghani_cert_key` كاملاً (Secure). احتفظ بالملف — نفس المفتاح يُستخدم لكل البناءات.
5. عند أول بناء `ios-release` يُنشئ Codemagic شهادة التوزيع وملف Provisioning تلقائياً، ولا تحتاج Mac.

### إعداد Android في Codemagic
1. أنشئ مفتاح الرفع (Upload key) مرة واحدة واحفظه في مكان آمن:
   ```bash
   keytool -genkey -v -keystore ghani-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ghani
   ```
2. Codemagic ▸ Team settings ▸ Code signing identities ▸ **Android keystores** ▸ ارفع الملف وسمّه: `ghani_upload_keystore`.
3. Google Play Console ▸ Setup ▸ API access ▸ أنشئ **Service account** وأعطه صلاحية Release، ونزّل JSON.
4. Codemagic ▸ Environment variables ▸ مجموعة باسم `google_play` ▸ متغير `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` = محتوى ملف JSON (Secure).

---

## 2) App Store Connect

### إنشاء التطبيق
- My Apps ▸ ➕ New App ▸ iOS ▸ الاسم `Ghani Group` ▸ اللغة الأساسية **Arabic** ▸ Bundle ID `online.ghanigroup.app` ▸ SKU `ghanigroup-ios`.
- (سجّل الـ Bundle ID أولاً في developer.apple.com ▸ Identifiers إذا لم يظهر.)

### App Information
- Category: **Business** (ثانوي: Photo & Video)
- Content Rights: لا يحتوي محتوى طرف ثالث يتطلب حقوقاً.
- Age Rating: أجب **None** على كل الأسئلة ← النتيجة 4+.
- Privacy Policy URL: `https://ghanigroup.online/privacy`

### App Privacy (ملصق الخصوصية) — أجب هكذا
"Do you or your third-party partners collect data from this app?" ← **Yes**

| نوع البيانات | مرتبطة بالمستخدم | للتتبع | الغرض |
|---|---|---|---|
| Contact Info ▸ Name | Yes | No | App Functionality |
| Contact Info ▸ Email Address | Yes | No | App Functionality |
| Contact Info ▸ Phone Number | Yes | No | App Functionality |
| Purchases ▸ Purchase History (طلبات الحجز) | Yes | No | App Functionality |
| User Content ▸ Other User Content (ملاحظات الطلب) | Yes | No | App Functionality |

لا شيء غير ذلك (لا موقع، لا معرفات إعلانية، لا تحليلات). هذا مطابق لملف `ios/Runner/PrivacyInfo.xcprivacy`.

### نسخة 1.0 — الصفحة
- لقطات الشاشة: iPhone 6.9" (1320×2868) — في مجلد `store/screenshots/ios/` (استبدلها بلقطات من TestFlight إذا تغيّر شيء في الواجهة).
- النصوص: من `docs/STORE_LISTING.md`.
- Support URL: `https://ghanigroup.online/support` · Marketing URL: `https://ghanigroup.online`
- Copyright: `2026 Al-Ghani Group for TV, Cinema Production & Media Services`

### App Review Information (مهم جداً)
- Sign-in required: **Yes** — Username/Password: حساب المراجعين من الخطوة 0.
- Notes (انسخها كما هي):
```
Ghani Group is a professional film-equipment rental house in Baghdad, Iraq.
The app lets production companies browse our real equipment fleet, check daily availability,
and send a rental quote request. No payments are made in the app — pricing and payment
are handled directly with our rental team after the request.

- Browsing and sending a quote request work without an account.
- An account (optional) stores order history and favorites.
- Account deletion: Account tab → "الحساب" (Profile) → "حذف الحساب" (Delete account).
- The UI is in Arabic (right-to-left).
Demo account is provided above.
```

### إرسال للمراجعة
بعد نجاح بناء `ios-release` يظهر البناء في TestFlight. جرّبه، ثم من صفحة الإصدار اختر البناء ▸ **Add for Review**.

---

## 3) Google Play Console

### إنشاء التطبيق
- Create app ▸ الاسم `Ghani Group` ▸ اللغة الافتراضية **Arabic – ar** ▸ App ▸ Free.
- ⚠️ **أول AAB يُرفع يدوياً**: شغّل `android-release` في Codemagic، نزّل ملف `.aab` من Artifacts، وارفعه في Testing ▸ Internal testing ▸ Create release. بعدها Codemagic يرفع تلقائياً.
- فعّل **Play App Signing** (افتراضي) — Google تحتفظ بمفتاح التوقيع، وأنت تحتفظ بمفتاح الرفع فقط.

### App content (كلها إلزامية)
| البند | الإجابة |
|---|---|
| Privacy policy | `https://ghanigroup.online/privacy` |
| App access | All or some functionality is restricted ▸ أضف حساب المراجعين + نفس الملاحظات أعلاه |
| Ads | No, my app does not contain ads |
| Content rating | أجب على الاستبيان (فئة Utility/Productivity، كل الإجابات No) ← Everyone / PEGI 3 |
| Target audience | 18 وأكبر |
| News app | No |
| Data safety | انظر الجدول أدناه |
| Government app | No |
| Financial features | None |
| Health | No |

### Data safety — أجب هكذا
- Does your app collect or share user data? **Yes** · Is all data encrypted in transit? **Yes** · Can users request deletion? **Yes** (رابط: `https://ghanigroup.online/delete-account`)

| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Personal info ▸ Name | Yes | No | Yes (الحساب اختياري) | App functionality, Account management |
| Personal info ▸ Email address | Yes | No | Yes | App functionality, Account management |
| Personal info ▸ Phone number | Yes | No | No (لإرسال الطلب) | App functionality |
| Financial info ▸ Purchase history | Yes | No | No | App functionality |
| Messages ▸ Other in-app messages (ملاحظات الطلب) | Yes | No | Yes | App functionality |
| Device or other IDs (رمز الإشعارات — فقط إذا فعّلت Firebase) | Yes | No | No | App functionality |

### Store listing
- النصوص من `docs/STORE_LISTING.md`.
- App icon 512×512: `store/play/icon-512.png` · Feature graphic 1024×500: `store/play/feature-graphic.png`
- Phone screenshots: `store/screenshots/android/`
- Category: **Business** · Email: `info@alghani-group.com` · Website: `https://ghanigroup.online`

### ⚠️ حسابات المطوّرين الشخصية الجديدة
إذا كان حساب Google Play Console **شخصياً** وتم إنشاؤه بعد نوفمبر 2023، تشترط Google **اختباراً مغلقاً (Closed testing) بـ 12 مختبراً لمدة 14 يوماً** قبل السماح بالنشر للعامة. حسابات الشركات (Organization) معفاة — يُفضّل فتح الحساب باسم الشركة مع D-U-N-S.

---

## الإشعارات الفورية
إعداد Firebase خطوة بخطوة في `docs/FIREBASE.md`.

## 4) الإصدارات القادمة
1. غيّر `version:` في `pubspec.yaml` (مثلاً `1.1.0+1`) — رقم البناء يزيد تلقائياً.
2. `git tag v1.1.0 && git push --tags` ← Codemagic يبني ويرفع للمتجرين.
3. لإجبار المستخدمين القدامى على التحديث: لوحة التحكم ▸ الإعدادات ▸ "أقل إصدار مسموح".
4. وضع صيانة طارئ: لوحة التحكم ▸ الإعدادات ▸ "رسالة صيانة" — يظهر في التطبيق فوراً بدون تحديث.

## قائمة التحقق قبل الإرسال
- [ ] الموقع يعمل على HTTPS وصفحات privacy / terms / support / delete-account تفتح
- [ ] حساب المراجعين يعمل ويحتوي طلباً تجريبياً واحداً على الأقل
- [ ] بناء TestFlight مُجرَّب على جهاز حقيقي: تصفح، طلب، دخول، حذف حساب
- [ ] لقطات الشاشة مطابقة للتطبيق الفعلي
- [ ] ملصق الخصوصية (Apple) و Data safety (Google) مطابقان للجداول أعلاه
- [ ] رقم واتساب الشركة صحيح في لوحة التحكم ▸ الإعدادات
