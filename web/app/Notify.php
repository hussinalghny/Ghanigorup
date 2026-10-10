<?php
declare(strict_types=1);

namespace App;

/** إنشاء الإشعارات (إعلانية للجميع، أو خاصة بطلب عند تغيّر حالته) */
final class Notify
{
    public const ORDER_TEXT = [
        'pending' => ['استلمنا طلبك', 'طلبك %s قيد المراجعة، سنرد عليك قريباً.'],
        'quoted' => ['عرض السعر جاهز', 'أرسلنا عرض السعر لطلبك %s — راجعه وتواصل معنا للتأكيد.'],
        'confirmed' => ['تم تأكيد الحجز ✓', 'حجزك %s مؤكد. المعدات محجوزة لك في التواريخ المطلوبة.'],
        'out' => ['تم تسليم المعدات', 'استلمت معدات الطلب %s. نتمنى لك تصويراً موفقاً 🎬'],
        'returned' => ['تم إرجاع المعدات', 'استلمنا معدات الطلب %s. شكراً لتعاملك مع Ghani Group.'],
        'cancelled' => ['تم إلغاء الطلب', 'تم إلغاء الطلب %s. تواصل معنا إذا كان هذا غير متوقع.'],
    ];

    /** إشعار تغيّر حالة الطلب — يصل لصاحب الحساب، وللضيف عبر رقم الطلب والهاتف */
    public static function orderStatus(array $order, string $status, ?string $extra = null): void
    {
        if (!isset(self::ORDER_TEXT[$status])) return;
        [$title, $body] = self::ORDER_TEXT[$status];
        $body = sprintf($body, $order['ref']);
        if ($extra) $body .= ' ' . $extra;
        try {
            $nid = DB::insert('notifications', [
                'user_id' => $order['user_id'] ?: null,
                'order_id' => (int)$order['id'],
                'type' => 'order',
                'title' => $title,
                'body' => mb_substr($body, 0, 1000),
                'link_type' => 'order',
                'link_value' => $order['ref'],
                'created_by' => Auth::user()['id'] ?? null,
            ]);
            Cache::bump('notifications');
            // إشعار فوري للهاتف (إذا كان Firebase مُعدّاً)
            Push::later(static function () use ($order, $title, $body, $nid) {
                Push::toDevices(Push::orderDevices($order), $title, $body, null, [
                    'id' => $nid, 'type' => 'order', 'link_type' => 'order', 'link_value' => $order['ref'],
                ]);
            });
        } catch (\Throwable $e) {
            Log::error('notify: ' . $e->getMessage());
        }
    }

    public static function present(array $n): array
    {
        return [
            'id' => (int)$n['id'],
            'type' => $n['type'],
            'title' => $n['title'],
            'body' => $n['body'],
            'image' => Catalog::url($n['image'] ?? null),
            'link_type' => $n['link_type'],
            'link_value' => $n['link_value'],
            'order_ref' => $n['order_ref'] ?? null,
            'created_at' => $n['created_at'],
        ];
    }
}
