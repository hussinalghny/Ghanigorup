<?php
declare(strict_types=1);

namespace App\Controllers;

use App\Auth;
use App\Cache;
use App\Catalog;
use App\Config;
use App\DB;
use App\HttpError;
use App\Importer;
use App\Notify;
use App\Request;
use App\Response;
use App\Security;
use App\Upload;
use App\Validator;

/** واجهات لوحة التحكم — admin / staff / storekeeper حسب الصلاحية (Auth::can) */
final class AdminController
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

    /** أمين المخزن لا يرى الأسعار */
    private function stripPrices(array $o): array
    {
        if (!Auth::can($this->u, 'orders.price')) unset($o['quote_amount'], $o['daily_rate']);
        return $o;
    }

    private function adminOnly(): void
    {
        if ($this->u['role'] !== 'admin') throw new HttpError(403, 'forbidden', 'هذا الإجراء للمدير فقط');
    }

    private function id(Request $r): int
    {
        $id = (int)($r->params['id'] ?? 0);
        if ($id <= 0) throw new HttpError(404, 'not_found', 'غير موجود');
        return $id;
    }

    // ---------------- Dashboard ----------------

    public function stats(Request $r): void
    {
        $v = Cache::version('admin_stats') . Cache::version('catalog');
        $data = Cache::remember("admin_stats:$v", 60, function () {
            $by = [];
            foreach (DB::all('SELECT status, COUNT(*) n FROM orders GROUP BY status') as $x) $by[$x['status']] = (int)$x['n'];
            $daily = DB::all(
                "SELECT DATE(created_at) d, COUNT(*) n FROM orders WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY) GROUP BY DATE(created_at) ORDER BY d"
            );
            $map = array_column($daily, 'n', 'd');
            $series = [];
            for ($i = 29; $i >= 0; $i--) { $d = date('Y-m-d', strtotime("-$i day")); $series[] = ['date' => $d, 'orders' => (int)($map[$d] ?? 0)]; }
            return [
                'orders_by_status' => $by,
                'orders_total' => array_sum($by),
                'orders_30d' => $series,
                'equipment_items' => (int)DB::val('SELECT COUNT(*) FROM equipment WHERE is_active = 1'),
                'equipment_units' => (int)DB::val('SELECT COALESCE(SUM(qty_total),0) FROM equipment WHERE is_active = 1'),
                'customers' => (int)DB::val("SELECT COUNT(*) FROM users WHERE role = 'customer'"),
                'out_now' => (int)DB::val("SELECT COALESCE(SUM(oi.qty),0) FROM order_items oi JOIN orders o ON o.id = oi.order_id WHERE o.status = 'out'"),
                'top_equipment' => DB::all(
                    'SELECT e.id, e.name, e.brand, e.image, SUM(oi.qty) AS units, COUNT(DISTINCT oi.order_id) AS orders
                       FROM order_items oi JOIN equipment e ON e.id = oi.equipment_id JOIN orders o ON o.id = oi.order_id
                      WHERE o.status <> \'cancelled\' GROUP BY e.id ORDER BY units DESC LIMIT 6'
                ),
                'upcoming' => DB::all(
                    "SELECT id, ref, contact_name, project, start_date, end_date, status FROM orders
                      WHERE status IN ('confirmed','quoted','pending') AND start_date >= CURDATE() ORDER BY start_date LIMIT 8"
                ),
            ];
        });
        foreach ($data['top_equipment'] as &$t) $t['image'] = Catalog::url($t['image']);
        Response::json($data + ['system' => ['cache' => Cache::driver(), 'replicas' => count(Config::get('db.replicas', []) ?: []), 'php' => PHP_VERSION, 'version' => APP_VERSION]]);
    }

    // ---------------- Orders ----------------

    public function orders(Request $r): void
    {
        $this->need('orders.view');
        $page = $r->int('page', 1, 1, 10000);
        $per = $r->int('per_page', 25, 5, 100);
        $where = ['1=1'];
        $p = [];
        if (($s = $r->str('status')) !== '' && in_array($s, ['pending', 'quoted', 'confirmed', 'out', 'returned', 'cancelled'], true)) { $where[] = 'status = ?'; $p[] = $s; }
        if (($q = $r->str('q', '', 80)) !== '') {
            $like = '%' . addcslashes($q, '%_\\') . '%';
            $where[] = '(ref LIKE ? OR contact_name LIKE ? OR phone LIKE ? OR project LIKE ?)';
            array_push($p, $like, $like, $like, $like);
        }
        $w = implode(' AND ', $where);
        $total = (int)DB::val("SELECT COUNT(*) FROM orders WHERE $w", $p);
        $rows = DB::all("SELECT o.*, (SELECT SUM(qty) FROM order_items WHERE order_id = o.id) AS units FROM orders o WHERE $w ORDER BY o.id DESC LIMIT $per OFFSET " . (($page - 1) * $per), $p);
        Response::json(array_map(fn($o) => $this->stripPrices(OrderController::present($o, false, true) + ['units' => (int)$o['units']]), $rows), 200, ['page' => $page, 'per_page' => $per, 'total' => $total, 'pages' => (int)ceil($total / $per)]);
    }

    public function order(Request $r): void
    {
        $this->need('orders.view');
        $o = DB::oneW('SELECT * FROM orders WHERE id = ?', [$this->id($r)]);
        if (!$o) throw new HttpError(404, 'not_found', 'الطلب غير موجود');
        $out = OrderController::present($o, true, true);
        $items = array_map(fn($i) => ['equipment_id' => $i['equipment_id'], 'qty' => $i['qty']], $out['items']);
        $out['shortages'] = in_array($o['status'], ['pending', 'quoted', 'confirmed'], true)
            ? Catalog::shortages($items, $o['start_date'], $o['end_date'], (int)$o['id']) : [];
        $out['handovers'] = HandoverController::listFor((int)$o['id']);
        Response::json($this->stripPrices($out));
    }

    public function updateOrder(Request $r): void
    {
        $this->need('orders.edit');
        $id = $this->id($r);
        $o = DB::oneW('SELECT * FROM orders WHERE id = ?', [$id]);
        if (!$o) throw new HttpError(404, 'not_found', 'الطلب غير موجود');
        $d = Validator::check($r->input(), [
            'status' => 'in:pending,quoted,confirmed,out,returned,cancelled',
            'quote_amount' => 'nullable|num|min:0|max:999999999',
            'admin_notes' => 'nullable|string|max:5000',
            'start_date' => 'date', 'end_date' => 'date',
            'force' => 'bool',
        ], true);
        $force = !empty($d['force']);
        unset($d['force']);

        $from = $d['start_date'] ?? $o['start_date'];
        $to = $d['end_date'] ?? $o['end_date'];
        if ($to < $from) throw new HttpError(422, 'validation', 'تاريخ الإرجاع قبل الاستلام');

        // عند التأكيد أو التسليم: تأكد أن المخزون يكفي (على السيرفر الرئيسي، داخل معاملة)
        DB::tx(function () use ($d, $o, $from, $to, $force, $id) {
            $newStatus = $d['status'] ?? $o['status'];
            if (in_array($newStatus, ['confirmed', 'out'], true) && !$force) {
                $items = DB::allW('SELECT equipment_id, qty FROM order_items WHERE order_id = ?', [$id]);
                DB::allW('SELECT id FROM equipment WHERE id IN (' . DB::in(array_column($items, 'equipment_id')) . ') FOR UPDATE', array_column($items, 'equipment_id'));
                $short = Catalog::shortages($items, $from, $to, $id);
                if ($short) throw new HttpError(409, 'shortage', 'الكمية غير متوفرة لبعض المعدات في هذه الفترة', ['shortages' => $short]);
            }
            if ($d) DB::update('orders', $d, 'id = :id', ['id' => $id]);
        });

        Cache::bump('orders');
        Cache::bump('admin_stats');
        Auth::audit('order.update', 'order', $id, $d);
        if (isset($d['status']) && $d['status'] !== $o['status']) {
            $extra = ($d['status'] === 'quoted' && isset($d['quote_amount'])) || ($d['status'] === 'quoted' && $o['quote_amount'] !== null)
                ? 'المبلغ: ' . number_format((float)($d['quote_amount'] ?? $o['quote_amount'])) . ' ' . (Catalog::setting('currency') ?: 'IQD') : null;
            Notify::orderStatus($o, $d['status'], $extra);
        }
        $this->order($r);
    }

    // ---------------- Equipment ----------------

    public function equipment(Request $r): void
    {
        $where = ['1=1'];
        $p = [];
        if (($b = $r->str('brand', '', 80)) !== '') { $where[] = 'e.brand = ?'; $p[] = $b; }
        if (($c = $r->str('category')) !== '') { $where[] = 'c.slug = ?'; $p[] = $c; }
        if (($q = $r->str('q', '', 80)) !== '') { $like = '%' . addcslashes($q, '%_\\') . '%'; $where[] = '(e.name LIKE ? OR e.brand LIKE ?)'; array_push($p, $like, $like); }
        if ($r->str('active') !== '') { $where[] = 'e.is_active = ?'; $p[] = (int)$r->str('active'); }
        $rows = DB::all(Catalog::EQ_SELECT . ' WHERE ' . implode(' AND ', $where) . ' ORDER BY c.sort, e.sort, e.id LIMIT 1000', $p);
        Response::json(array_map(fn($x) => $this->stripPrices(Catalog::equipment($x, true) + [
            'is_active' => (bool)$x['is_active'], 'daily_rate' => $x['daily_rate'] !== null ? (float)$x['daily_rate'] : null,
            'sort' => (int)$x['sort'], 'category_id' => (int)$x['category_id'], 'image_path' => $x['image'],
        ]), $rows));
    }

    private const EQ_RULES = [
        'category_id' => 'required|int|min:1',
        'brand' => 'required|string|max:80',
        'name' => 'required|string|max:150',
        'slug' => 'slug',
        'description' => 'nullable|string|max:5000',
        'specs' => 'nullable|array|max:30',
        'qty_total' => 'required|int|min:0|max:9999',
        'daily_rate' => 'nullable|num|min:0',
        'is_featured' => 'bool', 'is_new' => 'bool', 'is_active' => 'bool',
        'sort' => 'int',
    ];

    private function eqData(array $d): array
    {
        if (array_key_exists('specs', $d)) {
            $clean = [];
            foreach ((array)$d['specs'] as $k => $v) {
                $k = Security::cleanText((string)$k, 60);
                if ($k !== '' && is_scalar($v)) $clean[$k] = Security::cleanText((string)$v, 200);
            }
            $d['specs'] = $clean ? json_encode($clean, JSON_UNESCAPED_UNICODE) : null;
        }
        if (!Auth::can($this->u, 'orders.price')) unset($d['daily_rate']);
        if (isset($d['brand'])) {
            // ماركة جديدة تُضاف تلقائياً لقائمة الماركات
            DB::exec('INSERT IGNORE INTO brands (name, slug) VALUES (?, ?)', [$d['brand'], Validator::slugify($d['brand']) . '-' . bin2hex(random_bytes(2))]);
        }
        if (isset($d['category_id']) && !DB::oneW('SELECT id FROM categories WHERE id = ?', [$d['category_id']])) {
            throw new HttpError(422, 'validation', 'القسم غير موجود', ['category_id' => 'غير موجود']);
        }
        return $d;
    }

    private function uniqueSlug(string $base, ?int $except = null): string
    {
        $slug = $base;
        $i = 2;
        while ($row = DB::oneW('SELECT id FROM equipment WHERE slug = ?', [$slug])) {
            if ($except && (int)$row['id'] === $except) break;
            $slug = $base . '-' . $i++;
        }
        return $slug;
    }

    public function createEquipment(Request $r): void
    {
        $this->need('equipment.edit');
        $d = $this->eqData(Validator::check($r->input(), self::EQ_RULES));
        $d['slug'] = $this->uniqueSlug($d['slug'] ?? Validator::slugify($d['brand'] . ' ' . $d['name']));
        $id = DB::insert('equipment', $d);
        Cache::bump('catalog');
        Auth::audit('equipment.create', 'equipment', $id, ['name' => $d['name']]);
        $r->params['id'] = (string)$id;
        $this->one($r, 201);
    }

    public function updateEquipment(Request $r): void
    {
        $id = $this->id($r);
        if (!DB::oneW('SELECT id FROM equipment WHERE id = ?', [$id])) throw new HttpError(404, 'not_found', 'غير موجود');
        $this->need('equipment.edit');
        $d = $this->eqData(Validator::check($r->input(), self::EQ_RULES, true));
        if (isset($d['slug'])) $d['slug'] = $this->uniqueSlug($d['slug'], $id);
        if ($d) DB::update('equipment', $d, 'id = :id', ['id' => $id]);
        Cache::bump('catalog');
        Auth::audit('equipment.update', 'equipment', $id, array_keys($d));
        $this->one($r);
    }

    public function showEquipment(Request $r): void
    {
        if (!DB::oneW('SELECT id FROM equipment WHERE id = ?', [$this->id($r)])) throw new HttpError(404, 'not_found', 'غير موجود');
        $this->one($r);
    }

    private function one(Request $r, int $status = 200): void
    {
        $x = DB::oneW(Catalog::EQ_SELECT . ' WHERE e.id = ?', [$this->id($r)]);
        $out = Catalog::equipment($x, true) + ['is_active' => (bool)$x['is_active'], 'daily_rate' => $x['daily_rate'] !== null ? (float)$x['daily_rate'] : null, 'sort' => (int)$x['sort'], 'category_id' => (int)$x['category_id']];
        $out['gallery'] = array_map(fn($g) => ['id' => (int)$g['id'], 'url' => Catalog::url($g['path'])], DB::allW('SELECT id, path FROM equipment_images WHERE equipment_id = ? ORDER BY sort, id', [$x['id']]));
        Response::json($this->stripPrices($out), $status);
    }

    public function deleteEquipment(Request $r): void
    {
        $this->adminOnly();
        $id = $this->id($r);
        $used = (int)DB::val('SELECT COUNT(*) FROM order_items WHERE equipment_id = ?', [$id]);
        if ($used) {
            // لها طلبات سابقة: نخفيها بدل حذفها للحفاظ على السجلات
            DB::update('equipment', ['is_active' => 0], 'id = :id', ['id' => $id]);
            $msg = 'archived';
        } else {
            $row = DB::oneW('SELECT image FROM equipment WHERE id = ?', [$id]);
            foreach (DB::allW('SELECT path FROM equipment_images WHERE equipment_id = ?', [$id]) as $g) Upload::remove($g['path']);
            DB::exec('DELETE FROM equipment WHERE id = ?', [$id]);
            Upload::remove($row['image'] ?? null);
            $msg = 'deleted';
        }
        Cache::bump('catalog');
        Auth::audit('equipment.delete', 'equipment', $id, ['result' => $msg]);
        Response::json(['result' => $msg]);
    }

    public function uploadImage(Request $r): void
    {
        $this->need('equipment.edit');
        $id = $this->id($r);
        $row = DB::oneW('SELECT id, image FROM equipment WHERE id = ?', [$id]);
        if (!$row) throw new HttpError(404, 'not_found', 'غير موجود');
        Security::throttle('upload', 'up:' . $this->u['id'], 60, 600);
        $path = Upload::image($_FILES['image'] ?? []);
        if (($_POST['gallery'] ?? '') === '1') {
            DB::insert('equipment_images', ['equipment_id' => $id, 'path' => $path, 'sort' => (int)DB::val('SELECT COUNT(*) FROM equipment_images WHERE equipment_id = ?', [$id])]);
        } else {
            DB::update('equipment', ['image' => $path], 'id = :id', ['id' => $id]);
            if ($row['image'] && !DB::oneW('SELECT id FROM categories WHERE image = ? UNION SELECT id FROM kits WHERE image = ?', [$row['image'], $row['image']])) {
                Upload::remove($row['image']);
            }
        }
        Cache::bump('catalog');
        Auth::audit('equipment.image', 'equipment', $id);
        $this->one($r);
    }

    public function deleteGalleryImage(Request $r): void
    {
        $this->need('equipment.edit');
        $img = DB::oneW('SELECT * FROM equipment_images WHERE id = ?', [(int)$r->params['img']]);
        if ($img) { DB::exec('DELETE FROM equipment_images WHERE id = ?', [$img['id']]); Upload::remove($img['path']); }
        Cache::bump('catalog');
        $r->params['id'] = (string)($img['equipment_id'] ?? 0);
        $this->one($r);
    }

    // ---------------- Categories ----------------

    public function categories(Request $r): void
    {
        Response::json(array_map(fn($c) => [
            'id' => (int)$c['id'], 'slug' => $c['slug'], 'name_ar' => $c['name_ar'], 'name_en' => $c['name_en'],
            'image' => Catalog::url($c['image']), 'sort' => (int)$c['sort'], 'is_active' => (bool)$c['is_active'], 'count' => (int)$c['n'],
        ], DB::all('SELECT c.*, (SELECT COUNT(*) FROM equipment e WHERE e.category_id = c.id) n FROM categories c ORDER BY sort, id')));
    }

    public function saveCategory(Request $r): void
    {
        $this->need('catalog.edit');
        $id = (int)($r->params['id'] ?? 0);
        $d = Validator::check($r->input(), [
            'name_ar' => 'required|string|max:100', 'name_en' => 'required|string|max:100',
            'slug' => 'slug', 'sort' => 'int', 'is_active' => 'bool',
        ], $id > 0);
        if ($id) {
            DB::update('categories', $d, 'id = :id', ['id' => $id]);
        } else {
            $d['slug'] ??= Validator::slugify($d['name_en']);
            if (DB::oneW('SELECT id FROM categories WHERE slug = ?', [$d['slug']])) throw new HttpError(409, 'exists', 'المعرّف مستخدم');
            $id = DB::insert('categories', $d);
        }
        Cache::bump('catalog');
        Auth::audit('category.save', 'category', $id, $d);
        $this->categories($r);
    }

    public function deleteCategory(Request $r): void
    {
        $this->adminOnly();
        $id = $this->id($r);
        if (DB::val('SELECT COUNT(*) FROM equipment WHERE category_id = ?', [$id])) {
            throw new HttpError(409, 'conflict', 'لا يمكن حذف قسم يحتوي معدات — انقل المعدات أولاً أو عطّل القسم');
        }
        DB::exec('DELETE FROM categories WHERE id = ?', [$id]);
        Cache::bump('catalog');
        Auth::audit('category.delete', 'category', $id);
        $this->categories($r);
    }

    // ---------------- Kits ----------------

    public function kits(Request $r): void
    {
        $kits = DB::all('SELECT * FROM kits ORDER BY sort, id');
        foreach ($kits as &$k) {
            $k = ['id' => (int)$k['id'], 'slug' => $k['slug'], 'name_ar' => $k['name_ar'], 'name_en' => $k['name_en'], 'image' => Catalog::url($k['image']), 'sort' => (int)$k['sort'], 'is_active' => (bool)$k['is_active'],
                  'items' => array_map(fn($i) => ['equipment_id' => (int)$i['equipment_id'], 'qty' => (int)$i['qty'], 'name' => $i['name']], DB::all('SELECT ki.equipment_id, ki.qty, e.name FROM kit_items ki JOIN equipment e ON e.id = ki.equipment_id WHERE ki.kit_id = ?', [$k['id']]))];
        }
        Response::json($kits);
    }

    public function saveKit(Request $r): void
    {
        $this->need('catalog.edit');
        $id = (int)($r->params['id'] ?? 0);
        $d = Validator::check($r->input(), [
            'name_ar' => 'required|string|max:120', 'name_en' => 'required|string|max:120',
            'sort' => 'int', 'is_active' => 'bool', 'items' => 'array|max:50',
        ], $id > 0);
        $items = $d['items'] ?? null;
        unset($d['items']);
        DB::tx(function () use (&$id, $d, $items) {
            if ($id) { if ($d) DB::update('kits', $d, 'id = :id', ['id' => $id]); }
            else $id = DB::insert('kits', $d + ['slug' => Validator::slugify($d['name_en']) . '-' . bin2hex(random_bytes(2))]);
            if ($items !== null) {
                DB::exec('DELETE FROM kit_items WHERE kit_id = ?', [$id]);
                $first = null;
                foreach ($items as $it) {
                    $eid = (int)($it['equipment_id'] ?? 0);
                    $eq = DB::oneW('SELECT id, image FROM equipment WHERE id = ?', [$eid]);
                    if (!$eq) continue;
                    $first ??= $eq['image'];
                    DB::exec('INSERT IGNORE INTO kit_items (kit_id, equipment_id, qty) VALUES (?,?,?)', [$id, $eid, max(1, (int)($it['qty'] ?? 1))]);
                }
                if ($first && !DB::val('SELECT image FROM kits WHERE id = ?', [$id])) DB::update('kits', ['image' => $first], 'id = :id', ['id' => $id]);
            }
        });
        Cache::bump('catalog');
        Auth::audit('kit.save', 'kit', $id);
        $this->kits($r);
    }

    public function deleteKit(Request $r): void
    {
        $this->need('catalog.edit');
        $id = $this->id($r);
        DB::exec('DELETE FROM kits WHERE id = ?', [$id]);
        Cache::bump('catalog');
        Auth::audit('kit.delete', 'kit', $id);
        $this->kits($r);
    }

    // ---------------- Users ----------------

    private const ROLES = 'customer,staff,storekeeper,technician,admin';

    /** قائمة الموظفين والفنيين لاختيارهم في محضر التسليم */
    public function staffList(Request $r): void
    {
        $this->need('handover');
        Response::json(array_map(fn($u) => ['id' => (int)$u['id'], 'name' => $u['name'], 'role' => $u['role'], 'phone' => $u['phone']], DB::all(
            "SELECT id, name, role, phone FROM users WHERE role IN ('technician','storekeeper','staff','admin') AND status = 'active' ORDER BY FIELD(role,'technician','storekeeper','staff','admin'), name"
        )));
    }

    public function users(Request $r): void
    {
        $this->adminOnly();
        $where = ['1=1'];
        $p = [];
        if (($q = $r->str('q', '', 80)) !== '') { $like = '%' . addcslashes($q, '%_\\') . '%'; $where[] = '(u.name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)'; array_push($p, $like, $like, $like); }
        if (($role = $r->str('role')) !== '') { $where[] = 'u.role = ?'; $p[] = $role; }
        $rows = DB::all('SELECT u.id, u.name, u.email, u.phone, u.company, u.role, u.status, u.last_login_at, u.created_at,
                                (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS orders
                           FROM users u WHERE ' . implode(' AND ', $where) . ' ORDER BY u.id DESC LIMIT 500', $p);
        Response::json($rows);
    }

    public function createUser(Request $r): void
    {
        $this->adminOnly();
        $d = Validator::check($r->input(), [
            'name' => 'required|string|max:120', 'email' => 'required|email', 'phone' => 'phone',
            'role' => 'required|in:' . self::ROLES, 'password' => 'required|string|min:8|max:200',
        ]);
        if (!Security::passwordStrong($d['password'])) throw new HttpError(422, 'validation', 'كلمة المرور ضعيفة', ['password' => 'ضعيفة']);
        if (DB::oneW('SELECT id FROM users WHERE email = ?', [$d['email']])) throw new HttpError(409, 'exists', 'البريد مسجل مسبقاً');
        $d['password_hash'] = Security::hashPassword($d['password']);
        unset($d['password']);
        $id = DB::insert('users', $d);
        Auth::audit('user.create', 'user', $id, ['role' => $d['role']]);
        $this->users($r);
    }

    public function updateUser(Request $r): void
    {
        $this->adminOnly();
        $id = $this->id($r);
        $d = Validator::check($r->input(), ['role' => 'in:' . self::ROLES, 'status' => 'in:active,disabled', 'password' => 'string|min:8|max:200', 'name' => 'string|min:2|max:120', 'phone' => 'phone'], true);
        if ($id === (int)$this->u['id'] && (($d['role'] ?? 'admin') !== 'admin' || ($d['status'] ?? 'active') !== 'active')) {
            throw new HttpError(409, 'conflict', 'لا يمكنك تعطيل حسابك أو تخفيض صلاحيتك');
        }
        if (isset($d['password'])) {
            if (!Security::passwordStrong($d['password'])) throw new HttpError(422, 'validation', 'كلمة المرور ضعيفة');
            $d['password_hash'] = Security::hashPassword($d['password']);
            unset($d['password']);
        }
        if ($d) DB::update('users', $d, 'id = :id', ['id' => $id]);
        if (isset($d['status']) || isset($d['role']) || isset($d['password_hash'])) Auth::revokeAll($id);
        Auth::audit('user.update', 'user', $id, array_keys($d));
        $this->users($r);
    }

    // ---------------- Settings / Import / System ----------------

    public const SETTING_KEYS = ['company_name', 'company_name_ar', 'address', 'phone', 'whatsapp', 'email', 'website', 'instagram', 'facebook', 'show_prices', 'currency', 'notify_email',
        'app_min_version_ios', 'app_min_version_android', 'app_latest_version', 'app_store_url', 'play_store_url', 'maintenance_message',
        'home_title', 'home_subtitle', 'welcome_enabled', 'welcome_title', 'welcome_body', 'welcome_button', 'welcome_link', 'welcome_frequency'];
    public const SETTING_IMAGES = ['hero_image', 'welcome_image'];

    public function settings(Request $r): void
    {
        $s = Catalog::settings();
        $out = [];
        foreach (self::SETTING_KEYS as $k) $out[$k] = $s[$k] ?? '';
        foreach (self::SETTING_IMAGES as $k) $out[$k] = Catalog::url($s[$k] ?? null);
        $out['welcome_version'] = $s['welcome_version'] ?? '1';
        Response::json($out);
    }

    public function saveSettings(Request $r): void
    {
        $this->adminOnly();
        $in = $r->input();
        $welcomeChanged = false;
        $old = Catalog::settings();
        foreach (self::SETTING_KEYS as $k) {
            if (!array_key_exists($k, $in)) continue;
            $v = Security::cleanText((string)$in[$k], $k === 'welcome_body' ? 1000 : 500);
            if (str_starts_with($k, 'welcome_') && ($old[$k] ?? '') !== $v) $welcomeChanged = true;
            DB::exec('INSERT INTO settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', [$k, $v]);
        }
        // أي تعديل على رسالة الترحيب يجعلها تظهر من جديد لكل المستخدمين (في وضع "مرة واحدة")
        if ($welcomeChanged || !empty($in['welcome_reshow'])) {
            DB::exec("INSERT INTO settings (k, v) VALUES ('welcome_version', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)", [(string)time()]);
        }
        Cache::bump('settings');
        Cache::bump('catalog');
        Auth::audit('settings.update', 'settings', null, array_keys(array_intersect_key($in, array_flip(self::SETTING_KEYS))));
        $this->settings($r);
    }

    public function import(Request $r): void
    {
        $this->adminOnly();
        @set_time_limit(600);
        $f = $_FILES['file'] ?? null;
        if (!$f || $f['error'] !== UPLOAD_ERR_OK || $f['size'] > 20 * 1024 * 1024 || !is_uploaded_file($f['tmp_name'])) {
            throw new HttpError(422, 'upload', 'ارفع ملف JSON أو CSV (حتى 20MB)');
        }
        $raw = file_get_contents($f['tmp_name']);
        $ext = strtolower(pathinfo($f['name'], PATHINFO_EXTENSION));
        $data = $ext === 'csv' ? Importer::fromCsv($raw) : json_decode($raw, true);
        if (!is_array($data)) throw new HttpError(422, 'validation', 'صيغة الملف غير صحيحة');
        if (array_is_list($data)) $data = ['equipment' => $data];
        $report = (new Importer())->run($data);
        Auth::audit('import', 'equipment', null, array_diff_key($report, ['errors' => 1]));
        Response::json($report);
    }

    public function export(Request $r): void
    {
        $this->adminOnly();
        $cats = DB::all('SELECT slug, name_ar, name_en, sort FROM categories ORDER BY sort');
        $eq = array_map(fn($e) => [
            'category' => $e['cat_slug'], 'slug' => $e['slug'], 'brand' => $e['brand'], 'name' => $e['name'], 'qty' => (int)$e['qty_total'],
            'image' => Catalog::url($e['image']), 'description' => $e['description'], 'specs' => json_decode($e['specs'] ?? 'null', true),
            'featured' => (bool)$e['is_featured'], 'is_new' => (bool)$e['is_new'], 'daily_rate' => $e['daily_rate'],
        ], DB::all(Catalog::EQ_SELECT . ' ORDER BY c.sort, e.sort, e.id'));
        header('Content-Disposition: attachment; filename="ghani-equipment-' . date('Ymd') . '.json"');
        Response::json(['categories' => $cats, 'equipment' => $eq]);
    }

    public function audit(Request $r): void
    {
        $this->adminOnly();
        Response::json(DB::all('SELECT a.*, u.name AS user_name FROM audit_log a LEFT JOIN users u ON u.id = a.user_id ORDER BY a.id DESC LIMIT 300'));
    }

    public function clearCache(Request $r): void
    {
        $this->adminOnly();
        Cache::flush();
        Auth::audit('cache.flush');
        Response::json(['flushed' => true]);
    }

    public function system(Request $r): void
    {
        $this->adminOnly();
        $replicas = [];
        foreach (Config::get('db.replicas', []) ?: [] as $rep) {
            $t = microtime(true);
            try {
                $pdo = DB::connect(array_merge(Config::get('db.primary'), $rep));
                $lag = null;
                try { $st = $pdo->query('SHOW SLAVE STATUS')->fetch(); $lag = $st['Seconds_Behind_Master'] ?? null; } catch (\Throwable) {}
                $replicas[] = ['host' => $rep['host'], 'ok' => true, 'ms' => round((microtime(true) - $t) * 1000, 1), 'lag_seconds' => $lag];
            } catch (\Throwable $e) {
                $replicas[] = ['host' => $rep['host'], 'ok' => false, 'error' => 'unreachable'];
            }
        }
        Response::json([
            'version' => APP_VERSION, 'php' => PHP_VERSION, 'cache_driver' => Cache::driver(),
            'db_version' => DB::val('SELECT VERSION()'), 'primary' => Config::get('db.primary.host'),
            'replicas' => $replicas, 'opcache' => function_exists('opcache_get_status') && @opcache_get_status(false) ? true : false,
            'https' => Security::isHttps(),
            'tables' => DB::all('SELECT table_name AS name, table_rows AS `rows`, ROUND((data_length+index_length)/1024) AS kb FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY name'),
        ]);
    }
}
