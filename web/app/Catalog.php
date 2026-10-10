<?php
declare(strict_types=1);

namespace App;

/** منطق مشترك للكتالوج: الإعدادات، تهيئة السجلات للإخراج، وحساب التوفر */
final class Catalog
{
    public const BOOKED_STATUSES = ['confirmed', 'out'];

    public static function settings(): array
    {
        $v = Cache::version('settings');
        return Cache::remember("settings:$v", 3600, function () {
            $out = [];
            foreach (DB::all('SELECT k, v FROM settings') as $r) $out[$r['k']] = $r['v'];
            return $out;
        });
    }

    public static function setting(string $k, ?string $d = null): ?string
    {
        return self::settings()[$k] ?? $d;
    }

    public static function url(?string $rel): ?string
    {
        if (!$rel) return null;
        if (preg_match('#^https?://#', $rel)) return $rel;
        // يُستبدل عند الإرسال بعنوان الموقع كما فتحه الزائر فعلاً (https/http، www أو بدونها)
        // حتى لا تُحجب الصور بسبب اختلاف الدومين أو البروتوكول عن المكتوب وقت التنصيب
        return Response::ORIGIN . '/' . ltrim($rel, '/');
    }

    public static function equipment(array $r, bool $full = false): array
    {
        $out = [
            'id' => (int)$r['id'],
            'slug' => $r['slug'],
            'brand' => $r['brand'],
            'name' => $r['name'],
            'category' => [
                'slug' => $r['cat_slug'] ?? null,
                'name_ar' => $r['cat_ar'] ?? null,
                'name_en' => $r['cat_en'] ?? null,
            ],
            'qty_total' => (int)$r['qty_total'],
            'image' => self::url($r['image']),
            'is_new' => (bool)$r['is_new'],
            'is_featured' => (bool)$r['is_featured'],
        ];
        if (self::setting('show_prices') === '1' && $r['daily_rate'] !== null) {
            $out['daily_rate'] = (float)$r['daily_rate'];
        }
        if ($full) {
            $out['description'] = $r['description'];
            $out['specs'] = $r['specs'] ? (json_decode($r['specs'], true) ?: (object)[]) : (object)[];
        }
        return $out;
    }

    public const EQ_SELECT = 'SELECT e.*, c.slug AS cat_slug, c.name_ar AS cat_ar, c.name_en AS cat_en
                                FROM equipment e JOIN categories c ON c.id = e.category_id';

    /**
     * التوفر اليومي لمعدة: الكمية الكلية ناقص المحجوز بطلبات مؤكدة/مُسلّمة تتقاطع مع اليوم.
     * @return array<string,int> date => booked qty
     */
    public static function bookedByDay(int $equipmentId, string $from, string $to, bool $primary = false, ?int $excludeOrder = null): array
    {
        $sql = 'SELECT o.start_date, o.end_date, oi.qty
                  FROM order_items oi JOIN orders o ON o.id = oi.order_id
                 WHERE oi.equipment_id = ? AND o.status IN (' . DB::in(self::BOOKED_STATUSES) . ')
                   AND o.start_date <= ? AND o.end_date >= ?' . ($excludeOrder ? ' AND o.id <> ?' : '');
        $params = array_merge([$equipmentId], self::BOOKED_STATUSES, [$to, $from]);
        if ($excludeOrder) $params[] = $excludeOrder;
        $rows = $primary ? DB::allW($sql, $params) : DB::all($sql, $params);

        $days = [];
        for ($d = strtotime($from); $d <= strtotime($to); $d += 86400) $days[date('Y-m-d', $d)] = 0;
        foreach ($rows as $r) {
            foreach ($days as $day => $_) {
                if ($day >= $r['start_date'] && $day <= $r['end_date']) $days[$day] += (int)$r['qty'];
            }
        }
        return $days;
    }

    /** يتحقق من توفر كل البنود لمدة الطلب، ويُرجع قائمة النواقص */
    public static function shortages(array $items, string $from, string $to, ?int $excludeOrder = null): array
    {
        $short = [];
        foreach ($items as $it) {
            $eq = DB::oneW('SELECT id, name, qty_total FROM equipment WHERE id = ?', [$it['equipment_id']]);
            if (!$eq) continue;
            $peak = max(self::bookedByDay((int)$eq['id'], $from, $to, true, $excludeOrder) ?: [0]);
            $free = (int)$eq['qty_total'] - $peak;
            if ($it['qty'] > $free) $short[] = ['equipment_id' => (int)$eq['id'], 'name' => $eq['name'], 'requested' => (int)$it['qty'], 'available' => max(0, $free)];
        }
        return $short;
    }
}
