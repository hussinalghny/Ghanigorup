# Ghani Group Rental — API v1

الرابط الأساسي: `https://your-domain.com/api/v1`
كل الاستجابات JSON بهذا الشكل:

```json
{ "ok": true,  "data": { ... }, "meta": { "page": 1, "total": 72 } }
{ "ok": false, "error": { "code": "validation", "message": "...", "details": { "phone": "رقم هاتف غير صالح" } } }
```

## المصادقة

| العميل | الطريقة |
|---|---|
| تطبيق موبايل / أي عميل خارجي | `Authorization: Bearer <token>` — التوكن يرجع من `/auth/login` أو `/auth/register` |
| موقع الويب ولوحة التحكم | أرسل `X-Client: web` عند الدخول ← كوكي `gg_t` (HttpOnly) + كوكي `gg_csrf`. كل طلب غير GET يجب أن يحمل `X-CSRF-Token` بنفس قيمة `gg_csrf` |

صلاحية التوكن 30 يوم (قابلة للتغيير في الإعدادات)، وحد أقصى 10 جلسات لكل مستخدم.

## حدود الطلبات (Rate limits)

| المجموعة | الافتراضي |
|---|---|
| كل الـ API لكل IP | 300 طلب / دقيقة |
| طلبات الكتابة لكل IP | 60 / دقيقة |
| تسجيل الدخول والتسجيل | 10 / 5 دقائق لكل IP + 20 / 15 دقيقة لكل حساب |
| إنشاء الطلبات | 8 / 10 دقائق لكل IP |

عند التجاوز: `429` مع `Retry-After`. الترويسات `X-RateLimit-Limit` و `X-RateLimit-Remaining` ترجع مع كل طلب.
الحساب يُقفل 15 دقيقة بعد 5 محاولات دخول خاطئة.

## الكاش

الواجهات العامة ترجع `ETag` و `Cache-Control`. أرسل `If-None-Match` لتحصل على `304` بدون جسم (يوفّر البيانات في تطبيق الموبايل).

---

## عام

| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/health` | حالة الخدمة والقاعدة والكاش (لموزّع الأحمال) |
| GET | `/settings` | بيانات الشركة: الاسم، الهاتف، واتساب، العنوان، صورة الواجهة |
| GET | `/categories` | الأقسام مع عدد المعدات |
| GET | `/brands` | الماركات وعدد المعدات |
| GET | `/equipment` | قائمة المعدات — `category`, `q`, `brand`, `featured=1`, `new=1`, `sort=default\|name\|brand\|newest`, `page`, `per_page` (حد أقصى 60) |
| GET | `/equipment/{slug}` | تفاصيل معدة + المواصفات + صور إضافية + معدات مشابهة |
| GET | `/equipment/{slug}/availability` | التوفر اليومي — `from=YYYY-MM-DD`, `days` (1–60) |
| GET | `/kits` | الباقات الجاهزة ومحتواها |
| GET | `/app/config` | لتطبيق الموبايل — `platform=ios\|android`, `version` ← إجبار التحديث، رسالة الصيانة، روابط الخصوصية والشروط والدعم وحذف الحساب |

### إنشاء طلب عرض سعر — `POST /orders`
يعمل للزائر أو المستخدم المسجّل (الاسم والهاتف اختياريان للمسجّل).

```json
{
  "contact_name": "أحمد", "phone": "07701234567", "email": "a@x.iq",
  "project": "إعلان", "location": "بغداد",
  "start_date": "2026-10-20", "end_date": "2026-10-22",
  "technician": true, "delivery": false, "notes": "...",
  "items": [ { "slug": "arri-alexa-mini", "qty": 2 }, { "equipment_id": 18, "qty": 1 } ]
}
```
الاستجابة `201` تحتوي `ref` (مثل `GG-7K2QXP`) و `availability_warnings` إن كانت بعض المعدات محجوزة.

`GET /orders/track?ref=GG-XXXXXX&phone=07...` — تتبع طلب بدون حساب.

## الحساب

| الطريقة | المسار | الجسم |
|---|---|---|
| POST | `/auth/register` | `name, email, phone, password, company?` |
| POST | `/auth/login` | `email, password` |
| POST | `/auth/logout` | — |
| GET | `/auth/me` | المستخدم الحالي أو `null` |
| PATCH | `/auth/me` | `name?, phone?, company?` |
| POST | `/auth/password` | `current, new` — يُنهي كل الجلسات الأخرى |
| DELETE | `/auth/me` | `password` — حذف الحساب نهائياً (متطلب Apple 5.1.1v) |
| POST | `/auth/delete-account` | `email, password` — حذف الحساب من صفحة الويب `/delete-account` (متطلب Google Play) |
| GET | `/me/orders` | طلباتي |
| GET | `/me/orders/{ref}` | طلب واحد |
| POST | `/me/orders/{ref}/cancel` | إلغاء (فقط بحالة pending أو quoted) |
| GET | `/me/favorites` | المفضلة |
| POST / DELETE | `/me/favorites/{slug}` | إضافة / إزالة |

## لوحة التحكم (admin / staff)

| الطريقة | المسار | ملاحظة |
|---|---|---|
| GET | `/admin/stats` | أرقام لوحة المعلومات |
| GET | `/admin/system` | حالة السيرفرات وسيرفرات القراءة والجداول — admin |
| GET | `/admin/orders` | `status`, `q`, `page` |
| GET | `/admin/orders/{id}` | مع `shortages` (تعارضات التوفر) |
| PATCH | `/admin/orders/{id}` | `status, quote_amount, admin_notes, start_date, end_date, force` — التأكيد يرفض (409) إذا الكمية غير كافية إلا مع `force: true` |
| GET / POST | `/admin/equipment` | قائمة / إضافة |
| GET / PATCH / DELETE | `/admin/equipment/{id}` | الحذف يُخفي المعدة إذا لها طلبات سابقة |
| POST | `/admin/equipment/{id}/image` | multipart: `image` (+ `gallery=1` لصورة إضافية) |
| DELETE | `/admin/gallery/{imageId}` | حذف صورة إضافية |
| GET / POST / PATCH / DELETE | `/admin/categories[/{id}]` | |
| GET / POST / PATCH / DELETE | `/admin/kits[/{id}]` | `items: [{equipment_id, qty}]` |
| GET / POST / PATCH | `/admin/users[/{id}]` | admin فقط |
| GET / PUT | `/admin/settings` | |
| POST | `/admin/import` | multipart `file` (JSON أو CSV) |
| GET | `/admin/export` | كل المعدات JSON |
| GET | `/admin/audit` | سجل العمليات |
| POST | `/admin/cache/clear` | |

## حالات الطلب

`pending` جديد ← `quoted` أُرسل عرض السعر ← `confirmed` مؤكد (يحجز المخزون) ← `out` عند العميل ← `returned` مكتمل. أو `cancelled`.
المخزون المحجوز في التقويم = الطلبات بحالة `confirmed` أو `out` فقط.
