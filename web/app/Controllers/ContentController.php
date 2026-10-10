<?php
declare(strict_types=1);

namespace App\Controllers;

use App\Auth;
use App\Cache;
use App\Catalog;
use App\DB;
use App\HttpError;
use App\Notify;
use App\Request;
use App\Response;
use App\Security;
use App\Upload;
use App\Validator;

/** لوحة التحكم: البنرات الإعلانية، الماركات، الإشعارات، صور الإعدادات */
final class ContentController
{
    private array $u;

    public function __construct()
    {
        $this->u = Auth::require(Auth::PANEL_ROLES);
        header('Cache-Control: no-store');
    }

    private function need(string $perm): void
    {
        if (!Auth::can($this->u, $perm)) throw new HttpError(403, 'forbidden', 'لا تملك صلاحية لهذا الإجراء');
    }

    private function id(Request $r): int
    {
        $id = (int)($r->params['id'] ?? 0);
        if ($id <= 0) throw new HttpError(404, 'not_found', 'غير موجود');
        return $id;
    }

    private const LINK_TYPES = 'none,url,category,equipment,brand,kits';

    private static function checkLink(array &$d): void
    {
        $t = $d['link_type'] ?? null;
        $v = trim((string)($d['link_value'] ?? ''));
        if ($t === 'url' && $v !== '' && !preg_match('#^https?://#i', $v)) {
            throw new HttpError(422, 'validation', 'الرابط يجب أن يبدأ بـ https://', ['link_value' => 'رابط غير صالح']);
        }
        if ($t === 'none' || $t === 'kits') $d['link_value'] = null;
    }

    // ======================= البنرات =======================

    public static function presentBanner(array $b, bool $admin = false): array
    {
        $out = [
            'id' => (int)$b['id'], 'title' => $b['title'], 'subtitle' => $b['subtitle'], 'image' => Catalog::url($b['image']),
            'link_type' => $b['link_type'], 'link_value' => $b['link_value'], 'button_text' => $b['button_text'],
        ];
        if ($admin) $out += ['sort' => (int)$b['sort'], 'is_active' => (bool)$b['is_active'], 'starts_at' => $b['starts_at'], 'ends_at' => $b['ends_at']];
        return $out;
    }

    public function banners(Request $r): void
    {
        $this->need('banners');
        Response::json(array_map(fn($b) => self::presentBanner($b, true), DB::all('SELECT * FROM banners ORDER BY sort, id')));
    }

    public function saveBanner(Request $r): void
    {
        $this->need('banners');
        $id = (int)($r->params['id'] ?? 0);
        $d = Validator::check($r->input(), [
            'title' => 'nullable|string|max:120', 'subtitle' => 'nullable|string|max:200', 'button_text' => 'nullable|string|max:40',
            'link_type' => 'in:' . self::LINK_TYPES, 'link_value' => 'nullable|string|max:255',
            'sort' => 'int', 'is_active' => 'bool', 'starts_at' => 'nullable|date', 'ends_at' => 'nullable|date',
        ], true);
        self::checkLink($d);
        if ($id) {
            if (!DB::oneW('SELECT id FROM banners WHERE id = ?', [$id])) throw new HttpError(404, 'not_found', 'غير موجود');
            if ($d) DB::update('banners', $d, 'id = :id', ['id' => $id]);
        } else {
            $d['sort'] ??= (int)DB::val('SELECT COALESCE(MAX(sort),0)+1 FROM banners');
            $id = DB::insert('banners', $d);
        }
        Cache::bump('banners');
        Auth::audit('banner.save', 'banner', $id);
        Response::json(self::presentBanner(DB::oneW('SELECT * FROM banners WHERE id = ?', [$id]), true), 200);
    }

    public function bannerImage(Request $r): void
    {
        $this->need('banners');
        $id = $this->id($r);
        $b = DB::oneW('SELECT * FROM banners WHERE id = ?', [$id]);
        if (!$b) throw new HttpError(404, 'not_found', 'غير موجود');
        Security::throttle('upload', 'up:' . $this->u['id'], 60, 600);
        $path = Upload::image($_FILES['image'] ?? [], 1800, 'media');
        DB::update('banners', ['image' => $path], 'id = :id', ['id' => $id]);
        Upload::remove($b['image']);
        Cache::bump('banners');
        Response::json(self::presentBanner(DB::oneW('SELECT * FROM banners WHERE id = ?', [$id]), true));
    }

    public function deleteBanner(Request $r): void
    {
        $this->need('banners');
        $id = $this->id($r);
        $b = DB::oneW('SELECT image FROM banners WHERE id = ?', [$id]);
        DB::exec('DELETE FROM banners WHERE id = ?', [$id]);
        if ($b) Upload::remove($b['image']);
        Cache::bump('banners');
        Auth::audit('banner.delete', 'banner', $id);
        Response::json(['deleted' => true]);
    }

    public function sortBanners(Request $r): void
    {
        $this->need('banners');
        $ids = (array)($r->input()['ids'] ?? []);
        foreach (array_values($ids) as $i => $id) DB::exec('UPDATE banners SET sort = ? WHERE id = ?', [$i + 1, (int)$id]);
        Cache::bump('banners');
        Response::json(['sorted' => count($ids)]);
    }

    // ======================= الماركات =======================

    public static function presentBrand(array $b, bool $admin = false): array
    {
        $out = ['id' => (int)$b['id'], 'name' => $b['name'], 'brand' => $b['name'], 'slug' => $b['slug'], 'logo' => Catalog::url($b['logo']), 'count' => (int)($b['n'] ?? 0), 'is_featured' => (bool)$b['is_featured']];
        if ($admin) $out += ['sort' => (int)$b['sort'], 'is_active' => (bool)$b['is_active']];
        return $out;
    }

    public function brands(Request $r): void
    {
        Response::json(array_map(fn($b) => self::presentBrand($b, true), DB::all(
            'SELECT b.*, (SELECT COUNT(*) FROM equipment e WHERE e.brand = b.name) n FROM brands b ORDER BY b.sort, b.name'
        )));
    }

    public function saveBrand(Request $r): void
    {
        $this->need('brands');
        $id = (int)($r->params['id'] ?? 0);
        $d = Validator::check($r->input(), ['name' => 'required|string|min:1|max:80', 'sort' => 'int', 'is_active' => 'bool', 'is_featured' => 'bool'], $id > 0);
        DB::tx(function () use (&$id, $d) {
            $dup = isset($d['name']) ? DB::oneW('SELECT id FROM brands WHERE name = ?', [$d['name']]) : null;
            if ($dup && (int)$dup['id'] !== $id) throw new HttpError(409, 'exists', 'الماركة موجودة مسبقاً');
            if ($id) {
                $old = DB::oneW('SELECT name FROM brands WHERE id = ?', [$id]);
                if (!$old) throw new HttpError(404, 'not_found', 'غير موجود');
                if ($d) DB::update('brands', $d, 'id = :id', ['id' => $id]);
                // إعادة تسمية الماركة تنعكس على المعدات
                if (isset($d['name']) && $d['name'] !== $old['name']) DB::exec('UPDATE equipment SET brand = ? WHERE brand = ?', [$d['name'], $old['name']]);
            } else {
                $d['slug'] = Validator::slugify($d['name']);
                if (DB::oneW('SELECT id FROM brands WHERE slug = ?', [$d['slug']])) $d['slug'] .= '-' . bin2hex(random_bytes(2));
                $id = DB::insert('brands', $d);
            }
        });
        Cache::bump('catalog');
        Auth::audit('brand.save', 'brand', $id);
        $this->brands($r);
    }

    public function brandLogo(Request $r): void
    {
        $this->need('brands');
        $id = $this->id($r);
        $b = DB::oneW('SELECT * FROM brands WHERE id = ?', [$id]);
        if (!$b) throw new HttpError(404, 'not_found', 'غير موجود');
        Security::throttle('upload', 'up:' . $this->u['id'], 60, 600);
        $path = Upload::image($_FILES['image'] ?? [], 600, 'media', true);
        DB::update('brands', ['logo' => $path], 'id = :id', ['id' => $id]);
        Upload::remove($b['logo']);
        Cache::bump('catalog');
        $this->brands($r);
    }

    public function deleteBrand(Request $r): void
    {
        $this->need('brands');
        $id = $this->id($r);
        $b = DB::oneW('SELECT * FROM brands WHERE id = ?', [$id]);
        if ($b && DB::val('SELECT COUNT(*) FROM equipment WHERE brand = ?', [$b['name']])) {
            throw new HttpError(409, 'conflict', 'هذه الماركة مستخدمة في معدات — أخفِها بدل الحذف');
        }
        DB::exec('DELETE FROM brands WHERE id = ?', [$id]);
        if ($b) Upload::remove($b['logo']);
        Cache::bump('catalog');
        $this->brands($r);
    }

    /** إضافة أي ماركة موجودة في المعدات وغير موجودة في القائمة */
    public function syncBrands(Request $r): void
    {
        $this->need('brands');
        $n = 0;
        foreach (DB::allW("SELECT DISTINCT brand FROM equipment WHERE brand <> '' AND brand NOT IN (SELECT name FROM brands)") as $row) {
            $slug = Validator::slugify($row['brand']);
            if (DB::oneW('SELECT id FROM brands WHERE slug = ?', [$slug])) $slug .= '-' . bin2hex(random_bytes(2));
            $n += DB::exec('INSERT IGNORE INTO brands (name, slug, sort) VALUES (?, ?, 500)', [$row['brand'], $slug]);
        }
        Cache::bump('catalog');
        Auth::audit('brand.sync', 'brand', null, ['added' => $n]);
        $this->brands($r);
    }

    // ======================= الإشعارات =======================

    public function notifications(Request $r): void
    {
        $this->need('notifications');
        $type = $r->str('type');
        $where = in_array($type, ['promo', 'order', 'info'], true) ? 'WHERE n.type = ?' : '';
        $rows = DB::all("SELECT n.*, o.ref AS order_ref, u.name AS user_name, c.name AS by_name FROM notifications n
            LEFT JOIN orders o ON o.id = n.order_id LEFT JOIN users u ON u.id = n.user_id LEFT JOIN users c ON c.id = n.created_by
            $where ORDER BY n.id DESC LIMIT 200", $where ? [$type] : []);
        Response::json(array_map(fn($n) => Notify::present($n) + ['user_name' => $n['user_name'], 'by_name' => $n['by_name'], 'broadcast' => $n['user_id'] === null && $n['order_id'] === null], $rows));
    }

    public function sendNotification(Request $r): void
    {
        $this->need('notifications');
        Security::throttle('write', 'ntf:' . $this->u['id'], 30, 3600);
        $in = $_POST ?: $r->input();
        $d = Validator::check($in, [
            'title' => 'required|string|min:2|max:150', 'body' => 'nullable|string|max:1000',
            'type' => 'in:promo,info', 'link_type' => 'in:' . self::LINK_TYPES, 'link_value' => 'nullable|string|max:255',
            'user_id' => 'int|min:1',
        ]);
        self::checkLink($d);
        if (!empty($d['user_id']) && !DB::oneW('SELECT id FROM users WHERE id = ?', [$d['user_id']])) {
            throw new HttpError(422, 'validation', 'المستخدم غير موجود', ['user_id' => 'غير موجود']);
        }
        if (!empty($_FILES['image']['name'])) $d['image'] = Upload::image($_FILES['image'], 1400, 'media');
        $d['type'] ??= 'promo';
        $d['link_type'] ??= 'none';
        $d['created_by'] = (int)$this->u['id'];
        $id = DB::insert('notifications', $d);
        Cache::bump('notifications');
        Auth::audit('notification.send', 'notification', $id, ['title' => $d['title']]);
        $n = DB::oneW('SELECT * FROM notifications WHERE id = ?', [$id]);
        Response::json(Notify::present($n), 201);
    }

    public function deleteNotification(Request $r): void
    {
        $this->need('notifications');
        $id = $this->id($r);
        $n = DB::oneW('SELECT image FROM notifications WHERE id = ?', [$id]);
        DB::exec('DELETE FROM notifications WHERE id = ?', [$id]);
        if ($n) Upload::remove($n['image']);
        Cache::bump('notifications');
        Response::json(['deleted' => true]);
    }

    // ======================= صور الإعدادات =======================

    /** POST /admin/settings/image  (key = hero_image | welcome_image) — أو remove=1 للحذف */
    public function settingImage(Request $r): void
    {
        if ($this->u['role'] !== 'admin') throw new HttpError(403, 'forbidden', 'هذا الإجراء للمدير فقط');
        $key = (string)($_POST['key'] ?? '');
        if (!in_array($key, AdminController::SETTING_IMAGES, true)) throw new HttpError(422, 'validation', 'مفتاح غير معروف');
        $old = Catalog::setting($key);
        $path = ($_POST['remove'] ?? '') === '1' ? null : Upload::image($_FILES['image'] ?? [], 1800, 'media');
        DB::exec('INSERT INTO settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', [$key, $path]);
        if ($old && str_starts_with($old, 'uploads/media/')) Upload::remove($old);
        if ($key === 'welcome_image') DB::exec("INSERT INTO settings (k, v) VALUES ('welcome_version', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)", [(string)time()]);
        Cache::bump('settings');
        Cache::bump('catalog');
        Auth::audit('settings.image', 'settings', null, ['key' => $key]);
        Response::json(['key' => $key, 'url' => Catalog::url($path)]);
    }
}
