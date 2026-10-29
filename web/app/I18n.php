<?php
declare(strict_types=1);

namespace App;

/**
 * ترجمة رسائل الأخطاء للتطبيق عند اختيار English (Accept-Language: en).
 * لوحة التحكم والموقع يبقون بالعربي — الترجمة تُطبَّق فقط على ردود الأخطاء.
 */
final class I18n
{
    private const EN = [
        'مطلوب' => 'Required',
        'نص غير صالح' => 'Invalid text',
        'رقم صحيح مطلوب' => 'A whole number is required',
        'رقم مطلوب' => 'A number is required',
        'بريد غير صالح' => 'Invalid email',
        'رقم هاتف غير صالح' => 'Invalid phone number',
        'تاريخ غير صالح (YYYY-MM-DD)' => 'Invalid date (YYYY-MM-DD)',
        'معرّف غير صالح' => 'Invalid identifier',
        'قيمة غير مسموحة' => 'Value not allowed',
        'قائمة مطلوبة' => 'A list is required',
        'تحقق من البيانات المدخلة' => 'Please check the entered details',
        'الخدمة غير متاحة مؤقتاً' => 'Service temporarily unavailable',
        'أقصى مدة 120 يوم' => 'Maximum period is 120 days',
        'البريد أو كلمة المرور غير صحيحة' => 'Incorrect email or password',
        'البريد مسجل مسبقاً' => 'This email is already registered',
        'الحساب معطّل' => 'This account is disabled',
        'الطريقة غير مسموحة' => 'Method not allowed',
        'الطلب غير موجود' => 'Order not found',
        'الطلب فارغ' => 'The order is empty',
        'المسار غير موجود' => 'Not found',
        'المعدة غير موجودة' => 'Item not found',
        'القسم غير موجود' => 'Category not found',
        'الكمية غير متوفرة لبعض المعدات في هذه الفترة' => 'Some items are not available in this quantity for this period',
        'تاريخ الإرجاع قبل الاستلام' => 'Return date is before pickup',
        'تاريخ الإرجاع قبل تاريخ الاستلام' => 'Return date is before the pickup date',
        'تاريخ الاستلام لا يمكن أن يكون في الماضي' => 'Pickup date can\'t be in the past',
        'رمز الجهاز غير صالح' => 'Invalid device token',
        'طلب غير صالح' => 'Invalid request',
        'طلبات كثيرة، حاول بعد قليل' => 'Too many requests, try again shortly',
        'غير موجود' => 'Not found',
        'كلمة المرور الحالية غير صحيحة' => 'Current password is incorrect',
        'كلمة المرور ضعيفة' => 'Password is too weak',
        'كلمة المرور غير صحيحة' => 'Incorrect password',
        'لا يمكن إلغاء الطلب في حالته الحالية' => 'This order can\'t be cancelled in its current status',
        'لم يتم العثور على الطلب' => 'Order not found',
        'يجب تسجيل الدخول' => 'Please sign in',
        'لا تملك صلاحية لهذا الإجراء' => 'You don\'t have permission for this action',
        'انتهت صلاحية الجلسة، أعد تحميل الصفحة' => 'Session expired, please reload',
    ];

    /** بادئات لرسائل فيها أرقام متغيرة */
    private const PREFIX = [
        'الحد الأقصى ' => 'Maximum ',
        'الحد الأدنى ' => 'Minimum ',
        'الحساب مقفل مؤقتاً بسبب محاولات خاطئة، حاول بعد ' => 'Account temporarily locked after failed attempts, try again in ',
    ];

    public static function wantsEn(): bool
    {
        return str_starts_with(strtolower(trim((string)($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? ''))), 'en');
    }

    public static function t(string $ar): string
    {
        if (isset(self::EN[$ar])) return self::EN[$ar];
        foreach (self::PREFIX as $p => $en) {
            if (str_starts_with($ar, $p)) {
                return $en . str_replace([' حرف', ' دقيقة', ' ثانية'], [' characters', ' min', ' sec'], substr($ar, strlen($p)));
            }
        }
        return $ar;
    }

    public static function details(array $d): array
    {
        foreach ($d as $k => $v) $d[$k] = is_string($v) ? self::t($v) : (is_array($v) ? self::details($v) : $v);
        return $d;
    }
}
