<?php
declare(strict_types=1);

namespace App\Controllers;

use App\Auth;
use App\Cache;
use App\Catalog;
use App\Config;
use App\DB;
use App\HttpError;
use App\Notify;
use App\Request;
use App\Response;

/** واجهات عامة للقراءة — كلها مُكاشة (cache) ومُوزعة على سيرفرات القراءة */
final class PublicController
{
    public function health(Request $r): void
    {
        $db = 'ok';
        try { DB::val('SELECT 1'); } catch (\Throwable) { $db = 'down'; }
        Response::json(['status' => $db === 'ok' ? 'ok' : 'degraded', 'db' => $db, 'cache' => Cache::driver(), 'version' => APP_VERSION, 'time' => date('c')], $db === 'ok' ? 200 : 503);
    }

    public function settings(Request $r): void
    {
        $s = Catalog::settings();
        $public = ['company_name', 'company_name_ar', 'address', 'phone', 'whatsapp', 'email', 'website', 'show_prices', 'currency', 'instagram', 'facebook', 'home_title', 'home_subtitle'];
        $out = array_intersect_key($s, array_flip($public));
        $out['hero_image'] = Catalog::url($s['hero_image'] ?? null);
        $out['welcome'] = self::welcome($s);
        Response::cached($out, 120);
    }

    /** رسالة الترحيب التي تظهر عند فتح التطبيق/الموقع — تُدار من لوحة التحكم */
    public static function welcome(array $s): ?array
    {
        if (($s['welcome_enabled'] ?? '0') !== '1' || trim($s['welcome_title'] ?? '') === '') return null;
        return [
            'id' => (string)($s['welcome_version'] ?? '1'),
            'title' => $s['welcome_title'] ?? '',
            'body' => $s['welcome_body'] ?? '',
            'image' => Catalog::url($s['welcome_image'] ?? null),
            'button' => ($s['welcome_button'] ?? '') !== '' ? $s['welcome_button'] : 'متابعة',
            'link' => $s['welcome_link'] ?? '',
            'frequency' => in_array($s['welcome_frequency'] ?? 'once', ['once', 'always', 'daily'], true) ? $s['welcome_frequency'] : 'once',
        ];
    }

    /** البنرات الإعلانية الفعّالة (ضمن تاريخ العرض إن وُجد) */
    public function banners(Request $r): void
    {
        $v = Cache::version('banners');
        $today = date('Y-m-d');
        $data = Cache::remember("banners:$v:$today", 600, fn() => array_map(
            fn($b) => ContentController::presentBanner($b),
            DB::all('SELECT * FROM banners WHERE is_active = 1 AND image IS NOT NULL AND (starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at >= ?) ORDER BY sort, id LIMIT 12', [$today, $today])
        ));
        Response::cached($data, 120);
    }

    /**
     * الإشعارات: الإعلانية للجميع + إشعارات طلبات المستخدم المسجّل.
     * الضيف (بدون حساب) يرسل رقم الطلب والهاتف لطلباته فيستلم إشعارات تغيّر حالتها.
     * GET /notifications   أو   POST /notifications/feed  {"track":[{"ref":"GG-XXXX","phone":"07..."}]}
     */
    public function notifications(Request $r): void
    {
        $u = Auth::user();
        $after = max(0, (int)($r->get('after') ?? 0));
        $orderIds = [];
        $track = $r->method === 'POST' ? ($r->input()['track'] ?? []) : [];
        if (is_array($track) && $track) {
            foreach (array_slice($track, 0, 20) as $t) {
                if (!is_array($t)) continue;
                $ref = strtoupper(trim((string)($t['ref'] ?? '')));
                $phone = preg_replace('/\D/', '', (string)($t['phone'] ?? ''));
                if (!preg_match('/^GG-[A-Z0-9]{4,10}$/', $ref) || strlen($phone) < 6) continue;
                $o = DB::one('SELECT id, phone FROM orders WHERE ref = ?', [$ref]);
                if ($o && hash_equals(preg_replace('/\D/', '', $o['phone']), $phone)) $orderIds[] = (int)$o['id'];
            }
        }
        $cond = ['(n.user_id IS NULL AND n.order_id IS NULL)'];
        $p = [];
        if ($u) { $cond[] = 'n.user_id = ?'; $p[] = $u['id']; }
        if ($orderIds) { $cond[] = 'n.order_id IN (' . DB::in($orderIds) . ')'; array_push($p, ...$orderIds); }
        $p[] = $after;
        $rows = DB::all('SELECT n.*, o.ref AS order_ref FROM notifications n LEFT JOIN orders o ON o.id = n.order_id
            WHERE (' . implode(' OR ', $cond) . ') AND n.id > ? AND n.created_at >= DATE_SUB(NOW(), INTERVAL 120 DAY)
            ORDER BY n.id DESC LIMIT 60', $p);
        header('Cache-Control: no-store');
        Response::json(array_map([Notify::class, 'present'], $rows), 200, ['latest_id' => $rows ? (int)$rows[0]['id'] : $after]);
    }

    /**
     * إعدادات تطبيق الموبايل: إجبار التحديث، الصيانة، روابط السياسات.
     * GET /app/config?platform=ios|android&version=1.0.0
     */
    public function appConfig(Request $r): void
    {
        $s = Catalog::settings();
        $base = Response::origin();
        $platform = $r->str('platform', '', 10) === 'ios' ? 'ios' : 'android';
        $current = $r->str('version', '0.0.0', 20);
        $min = $s['app_min_version_' . $platform] ?? '1.0.0';
        $latest = $s['app_latest_version'] ?? $min;
        header('Cache-Control: public, max-age=60');
        Response::json([
            'min_version' => $min,
            'latest_version' => $latest,
            'force_update' => version_compare($current, $min, '<'),
            'update_available' => version_compare($current, $latest, '<'),
            'store_url' => $platform === 'ios' ? ($s['app_store_url'] ?? '') : ($s['play_store_url'] ?? ''),
            'maintenance' => ($s['maintenance_message'] ?? '') !== '' ? $s['maintenance_message'] : null,
            'links' => [
                'privacy' => $base . '/privacy', 'terms' => $base . '/terms',
                'delete_account' => $base . '/delete-account', 'support' => $base . '/support',
            ],
            'contact' => ['phone' => $s['phone'] ?? '', 'whatsapp' => $s['whatsapp'] ?? '', 'email' => $s['email'] ?? '', 'address' => $s['address'] ?? ''],
            'welcome' => self::welcome($s),
            'home' => ['title' => $s['home_title'] ?? '', 'subtitle' => $s['home_subtitle'] ?? ''],
        ]);
    }

    public function categories(Request $r): void
    {
        $v = Cache::version('catalog');
        $data = Cache::remember("cats:$v", 600, fn() => array_map(fn($c) => [
            'slug' => $c['slug'],
            'name_ar' => $c['name_ar'],
            'name_en' => $c['name_en'],
            'image' => Catalog::url($c['image']),
            'count' => (int)$c['n'],
        ], DB::all(
            'SELECT c.*, (SELECT COUNT(*) FROM equipment e WHERE e.category_id = c.id AND e.is_active = 1) AS n
               FROM categories c WHERE c.is_active = 1 ORDER BY c.sort, c.id'
        )));
        Response::cached($data, 120);
    }

    public function equipment(Request $r): void
    {
        $page = $r->int('page', 1, 1, 1000);
        $per = $r->int('per_page', 24, 1, 60);
        $q = $r->str('q', '', 80);
        $cat = $r->str('category', '', 60);
        $brand = $r->str('brand', '', 80);
        $sortKey = $r->str('sort', 'default', 20);
        $sorts = ['default' => 'e.is_featured DESC, e.sort, e.id', 'name' => 'e.name', 'newest' => 'e.id DESC', 'brand' => 'e.brand, e.name'];
        $order = $sorts[$sortKey] ?? $sorts['default'];

        $where = ['e.is_active = 1', 'c.is_active = 1'];
        $p = [];
        if ($cat !== '') { $where[] = 'c.slug = ?'; $p[] = $cat; }
        if ($brand !== '') { $where[] = 'e.brand = ?'; $p[] = $brand; }
        if ($r->str('featured') === '1') $where[] = 'e.is_featured = 1';
        if ($r->str('new') === '1') $where[] = 'e.is_new = 1';
        if ($q !== '') {
            $like = '%' . addcslashes($q, '%_\\') . '%';
            $where[] = '(e.name LIKE ? OR e.brand LIKE ? OR e.description LIKE ?)';
            array_push($p, $like, $like, $like);
        }
        $w = implode(' AND ', $where);
        $key = 'eq:' . Cache::version('catalog') . ':' . md5(json_encode([$w, $p, $order, $page, $per]));

        [$rows, $total] = Cache::remember($key, 300, function () use ($w, $p, $order, $page, $per) {
            $total = (int)DB::val("SELECT COUNT(*) FROM equipment e JOIN categories c ON c.id = e.category_id WHERE $w", $p);
            $rows = DB::all(Catalog::EQ_SELECT . " WHERE $w ORDER BY $order LIMIT " . (int)$per . ' OFFSET ' . (int)(($page - 1) * $per), $p);
            return [array_map(fn($x) => Catalog::equipment($x), $rows), $total];
        });

        Response::cached($rows, 60, ['page' => $page, 'per_page' => $per, 'total' => $total, 'pages' => (int)ceil($total / $per)]);
    }

    public function show(Request $r): void
    {
        $slug = $r->params['slug'];
        $key = 'eq1:' . Cache::version('catalog') . ':' . $slug;
        $data = Cache::remember($key, 600, function () use ($slug) {
            $row = DB::one(Catalog::EQ_SELECT . ' WHERE e.slug = ? AND e.is_active = 1', [$slug]);
            if (!$row) return null;
            $out = Catalog::equipment($row, true);
            $out['gallery'] = array_map(fn($g) => Catalog::url($g['path']), DB::all('SELECT path FROM equipment_images WHERE equipment_id = ? ORDER BY sort', [$row['id']]));
            $out['related'] = array_map(fn($x) => Catalog::equipment($x), DB::all(
                Catalog::EQ_SELECT . ' WHERE e.category_id = ? AND e.id <> ? AND e.is_active = 1 ORDER BY e.is_featured DESC, RAND() LIMIT 6',
                [$row['category_id'], $row['id']]
            ));
            return $out;
        });
        if (!$data) throw new HttpError(404, 'not_found', 'المعدة غير موجودة');
        Response::cached($data, 120);
    }

    public function availability(Request $r): void
    {
        $eq = DB::one('SELECT id, qty_total FROM equipment WHERE slug = ? AND is_active = 1', [$r->params['slug']]);
        if (!$eq) throw new HttpError(404, 'not_found', 'المعدة غير موجودة');
        $from = $r->str('from', date('Y-m-d'), 10);
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $from) || $from < date('Y-m-d')) $from = date('Y-m-d');
        $days = $r->int('days', 14, 1, 60);
        $to = date('Y-m-d', strtotime($from) + ($days - 1) * 86400);
        $key = 'av:' . Cache::version('orders') . ':' . $eq['id'] . ":$from:$days";
        $data = Cache::remember($key, 120, function () use ($eq, $from, $to) {
            $out = [];
            foreach (Catalog::bookedByDay((int)$eq['id'], $from, $to) as $d => $b) {
                $out[] = ['date' => $d, 'booked' => $b, 'available' => max(0, (int)$eq['qty_total'] - $b)];
            }
            return $out;
        });
        Response::cached(['qty_total' => (int)$eq['qty_total'], 'days' => $data], 60);
    }

    public function kits(Request $r): void
    {
        $v = Cache::version('catalog');
        $data = Cache::remember("kits:$v", 600, function () {
            $kits = DB::all('SELECT * FROM kits WHERE is_active = 1 ORDER BY sort, id');
            foreach ($kits as &$k) {
                $items = DB::all(str_replace('SELECT e.*', 'SELECT e.*, ki.qty', Catalog::EQ_SELECT) . ' JOIN kit_items ki ON ki.equipment_id = e.id WHERE ki.kit_id = ? AND e.is_active = 1', [$k['id']]);
                $k = [
                    'slug' => $k['slug'], 'name_ar' => $k['name_ar'], 'name_en' => $k['name_en'], 'image' => Catalog::url($k['image']),
                    'items' => array_map(fn($x) => Catalog::equipment($x) + ['qty' => (int)$x['qty']], $items),
                ];
            }
            return $kits;
        });
        Response::cached($data, 120);
    }

    /** الماركات الفعّالة مع شعاراتها وعدد معداتها (featured=1 للواجهة الرئيسية فقط) */
    public function brands(Request $r): void
    {
        $v = Cache::version('catalog');
        $featured = $r->str('featured') === '1';
        $data = Cache::remember("brands2:$v:" . (int)$featured, 600, fn() => array_map(
            fn($b) => ContentController::presentBrand($b),
            DB::all('SELECT b.*, COUNT(e.id) AS n FROM brands b JOIN equipment e ON e.brand = b.name AND e.is_active = 1
                      WHERE b.is_active = 1' . ($featured ? ' AND b.is_featured = 1' : '') . '
                      GROUP BY b.id ORDER BY b.sort, n DESC, b.name')
        ));
        Response::cached($data, 300);
    }
}
