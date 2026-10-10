# تفعيل الإشعارات الفورية (Firebase) — Ghani Group

المشروع جاهز بالكامل. بقي فقط أن تنشئ مشروع Firebase وتضع ملفاته. بدون Firebase يعمل التطبيق بالإشعارات الداخلية فقط
(تظهر عند فتح التطبيق). بعد التفعيل تصل الإشعارات للهاتف **حتى والتطبيق مغلق**:
- الإشعارات الإعلانية من لوحة التحكم ← الإشعارات (لكل المستخدمين)
- تغيّر حالة الطلب (عرض سعر، تأكيد، تسليم، إرجاع…) لصاحب الطلب — حتى لو طلب بدون حساب
- الضغط على الإشعار يفتح الصفحة المرتبطة (الطلب، الماركة، المعدة…)

المعرّف في كل مكان: `online.ghanigroup.app`

---

## 1) إنشاء المشروع (مرة واحدة)
1. ادخل https://console.firebase.google.com ← **Add project** ← الاسم `Ghani Group` (Google Analytics غير ضروري).
2. **أضف تطبيق Android**: أيقونة Android ← Package name: `online.ghanigroup.app` ← Register ← نزّل **google-services.json**. (تخطَّ باقي الخطوات في الصفحة)
3. **أضف تطبيق iOS**: أيقونة Apple ← Bundle ID: `online.ghanigroup.app` ← Register ← نزّل **GoogleService-Info.plist**. (تخطَّ باقي الخطوات)

## 2) مفتاح Apple للإشعارات (لـ iPhone فقط)
1. https://developer.apple.com/account ← Certificates, IDs & Profiles ← **Keys** ← ➕ ← اسم `Ghani Push` ← فعّل **Apple Push Notifications service (APNs)** ← Continue ← Register ← نزّل ملف `.p8` واحفظ **Key ID**.
2. نفس الموقع ← **Identifiers** ← `online.ghanigroup.app` ← فعّل **Push Notifications** ← Save.
3. Firebase ← ⚙️ Project settings ← **Cloud Messaging** ← Apple app configuration ← **APNs Authentication Key** ← Upload: ملف `.p8` + Key ID + **Team ID** (يظهر أعلى يمين حساب Apple Developer).

## 3) ربط التطبيق (وقت البناء)
المستودع على GitHub **عام**، لذلك لا ترفع الملفين داخله — ضعهما كأسرار:

GitHub ← المستودع ← **Settings ← Secrets and variables ← Actions ← New repository secret**
| الاسم | القيمة |
|---|---|
| `FIREBASE_ANDROID_JSON` | افتح `google-services.json` بأي محرر نصوص، انسخ كل المحتوى والصقه |
| `FIREBASE_IOS_PLIST` | افتح `GoogleService-Info.plist` بمحرر نصوص، انسخ كل المحتوى والصقه |

ثم أعد البناء: تبويب **Actions ← Build apps ← Run workflow**. الرابط المباشر للـ IPA/APK في Releases يتحدّث تلقائياً.

**Codemagic** (للرفع على المتاجر): أضف نفس المتغيرين (Secure) إلى مجموعة `ios_signing` ومجموعة `google_play`.

> بديل (مستودع خاص فقط): ضع الملفين في مجلد `firebase/` داخل المشروع بنفس الاسمين.

## 4) ربط السيرفر (لإرسال الإشعارات)
1. Firebase ← ⚙️ Project settings ← **Service accounts** ← **Generate new private key** ← ينزل ملف JSON.
2. لوحة التحكم ← **الإعدادات** ← بطاقة **الإشعارات الفورية — Firebase** ← **رفع ملف الخدمة (JSON)**.
3. اضغط **اختبار الاتصال** — إذا كنت مسجّل دخول بالتطبيق بنفس حساب المدير تصلك رسالة تجربة على هاتفك.

السيرفر يحتاج إضافتي PHP: `openssl` و `curl` (موجودتان في أغلب الاستضافات). الملف يُحفظ في `storage/firebase/` وغير متاح للعامة.

---

## ملاحظات
- **Android**: يعمل مباشرة بعد إعادة البناء. أول فتح للتطبيق يطلب إذن الإشعارات (Android 13+).
- **iPhone**: الإشعارات الفورية تحتاج توقيعاً يتضمن صلاحية Push (`aps-environment`):
  - نسخة **TestFlight / App Store** من Codemagic: تعمل (بعد الخطوة 2).
  - **التوقيع الشخصي** (ESign / Feather / Sideloadly…): يعمل فقط إذا كانت شهادتك وملف الـ Provisioning يدعمان Push، وأغلب شهادات التوقيع الخارجي لا تدعمها. في هذه الحالة يبقى التطبيق يعمل بالإشعارات الداخلية.
- أقل إصدار iOS أصبح **15.0** (متطلب Firebase).
- الأجهزة المسجّلة تظهر في بطاقة Firebase بالإعدادات، والأجهزة التي حذفت التطبيق تُحذف تلقائياً.
