<?php
declare(strict_types=1);

namespace App\Controllers;

use App\Auth;
use App\Cache;
use App\Catalog;
use App\DB;
use App\HttpError;
use App\Request;
use App\Response;
use App\Security;
use App\Validator;

/** طلبات عرض السعر/الحجز + حساب العميل (طلباتي، المفضلة) */
final class OrderController
{
    public static function present(array $o, bool $withItems = true, bool $admin = false): array
    {
        $out = [
            'id' => (int)$o['id'], 'ref' => $o['ref'], 'status' => $o['status'],
            'contact_name' => $o['contact_name'], 'phone' => $o['phone'], 'email' => $o['email'],
            'project' => $o['project'], 'location' => $o['location'],
            'start_date' => $o['start_date'], 'end_date' => $o['end_date'],
            'days' => (int)((strtotime($o['end_date']) - strtotime($o['start_date'])) / 86400) + 1,
            'technician' => (bool)$o['technician'], 'delivery' => (bool)$o['delivery'],
            'notes' => $o['notes'],
            'quote_amount' => $o['quote_amount'] !== null ? (float)$o['quote_amount'] : null,
            'created_at' => $o['created_at'],
        ];
        if ($admin) {
            $out['admin_notes'] = $o['admin_notes'];
            $out['user_id'] = $o['user_id'] ? (int)$o['user_id'] : null;
            $out['ip'] = $o['ip'];
            $out['updated_at'] = $o['updated_at'];
        }
        if ($withItems) {
            $out['items'] = array_map(fn($i) => [
                'equipment_id' => (int)$i['equipment_id'], 'slug' => $i['slug'], 'brand' => $i['brand'],
                'name' => $i['name'], 'image' => Catalog::url($i['image']), 'qty' => (int)$i['qty'],
            ], DB::all(
                'SELECT oi.equipment_id, oi.qty, e.slug, e.brand, e.name, e.image
                   FROM order_items oi JOIN equipment e ON e.id = oi.equipment_id WHERE oi.order_id = ? ORDER BY oi.id',
                [$o['id']]
            ));
        }
        return $out;
    }

    private function newRef(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        do {
            $ref = 'GG-';
            for ($i = 0; $i < 6; $i++) $ref .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        } while (DB::oneW('SELECT id FROM orders WHERE ref = ?', [$ref]));
        return $ref;
    }

    public function create(Request $r): void
    {
        Security::throttle('orders', 'ord:' . $r->ip());
        $in = $r->input();
        if (!empty($in['website'])) throw new HttpError(422, 'validation', 'طلب غير صالح'); // honeypot ضد البوتات

        $u = Auth::user();
        $d = Validator::check($in, [
            'contact_name' => ($u ? '' : 'required|') . 'string|min:2|max:120',
            'phone' => ($u ? '' : 'required|') . 'phone',
            'email' => 'email|max:190',
            'project' => 'string|max:150',
            'location' => 'string|max:190',
            'start_date' => 'required|date',
            'end_date' => 'required|date',
            'technician' => 'bool',
            'delivery' => 'bool',
            'notes' => 'string|max:2000',
            'items' => 'required|array|min:1|max:80',
        ]);
        $today = date('Y-m-d');
        if ($d['start_date'] < $today) throw new HttpError(422, 'validation', 'تاريخ الاستلام لا يمكن أن يكون في الماضي', ['start_date' => 'في الماضي']);
        if ($d['end_date'] < $d['start_date']) throw new HttpError(422, 'validation', 'تاريخ الإرجاع قبل تاريخ الاستلام', ['end_date' => 'قبل الاستلام']);
        if ((strtotime($d['end_date']) - strtotime($d['start_date'])) / 86400 > 120) throw new HttpError(422, 'validation', 'أقصى مدة 120 يوم');

        // توحيد البنود ودمج المكرر
        $items = [];
        foreach ($d['items'] as $it) {
            if (!is_array($it)) continue;
            $qty = max(1, min(999, (int)($it['qty'] ?? 1)));
            $eq = isset($it['equipment_id'])
                ? DB::oneW('SELECT id, qty_total FROM equipment WHERE id = ? AND is_active = 1', [(int)$it['equipment_id']])
                : DB::oneW('SELECT id, qty_total FROM equipment WHERE slug = ? AND is_active = 1', [(string)($it['slug'] ?? '')]);
            if (!$eq) throw new HttpError(422, 'validation', 'معدة غير موجودة في الطلب');
            $id = (int)$eq['id'];
            $items[$id] = ['equipment_id' => $id, 'qty' => min((int)$eq['qty_total'], ($items[$id]['qty'] ?? 0) + $qty)];
        }
        if (!$items) throw new HttpError(422, 'validation', 'الطلب فارغ');

        $order = DB::tx(function () use ($d, $u, $items, $r) {
            $id = DB::insert('orders', [
                'ref' => $this->newRef(),
                'user_id' => $u['id'] ?? null,
                'contact_name' => $d['contact_name'] ?? $u['name'],
                'phone' => $d['phone'] ?? $u['phone'] ?? '',
                'email' => $d['email'] ?? $u['email'] ?? null,
                'project' => $d['project'] ?? null,
                'location' => $d['location'] ?? null,
                'start_date' => $d['start_date'],
                'end_date' => $d['end_date'],
                'technician' => $d['technician'] ?? 0,
                'delivery' => $d['delivery'] ?? 0,
                'notes' => $d['notes'] ?? null,
                'ip' => $r->ip(),
            ]);
            foreach ($items as $it) DB::insert('order_items', ['order_id' => $id] + $it);
            return DB::oneW('SELECT * FROM orders WHERE id = ?', [$id]);
        });
        Cache::bump('admin_stats');

        $out = self::present($order);
        $out['availability_warnings'] = Catalog::shortages(array_values($items), $d['start_date'], $d['end_date']);
        Response::json($out, 201);
    }

    /** تتبع طلب بدون حساب: رقم الطلب + رقم الهاتف */
    public function track(Request $r): void
    {
        Security::throttle('auth', 'track:' . $r->ip(), 20, 600);
        $ref = strtoupper($r->str('ref', '', 16));
        $phone = preg_replace('/[^\d+]/', '', $r->str('phone', '', 20));
        $o = DB::oneW('SELECT * FROM orders WHERE ref = ?', [$ref]);
        if (!$o || !hash_equals(preg_replace('/[^\d]/', '', $o['phone']), preg_replace('/[^\d]/', '', $phone))) {
            throw new HttpError(404, 'not_found', 'لم يتم العثور على الطلب');
        }
        header('Cache-Control: no-store');
        Response::json(self::present($o));
    }

    public function mine(Request $r): void
    {
        $u = Auth::require();
        header('Cache-Control: no-store');
        $rows = DB::all('SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC LIMIT 100', [$u['id']]);
        Response::json(array_map(fn($o) => self::present($o), $rows));
    }

    public function mineOne(Request $r): void
    {
        $u = Auth::require();
        $o = DB::one('SELECT * FROM orders WHERE ref = ? AND user_id = ?', [$r->params['ref'], $u['id']]);
        if (!$o) throw new HttpError(404, 'not_found', 'الطلب غير موجود');
        header('Cache-Control: no-store');
        Response::json(self::present($o));
    }

    public function cancel(Request $r): void
    {
        $u = Auth::require();
        $o = DB::oneW('SELECT * FROM orders WHERE ref = ? AND user_id = ?', [$r->params['ref'], $u['id']]);
        if (!$o) throw new HttpError(404, 'not_found', 'الطلب غير موجود');
        if (!in_array($o['status'], ['pending', 'quoted'], true)) throw new HttpError(409, 'conflict', 'لا يمكن إلغاء الطلب في حالته الحالية');
        DB::update('orders', ['status' => 'cancelled'], 'id = :id', ['id' => $o['id']]);
        Cache::bump('admin_stats');
        Response::json(self::present(DB::oneW('SELECT * FROM orders WHERE id = ?', [$o['id']])));
    }

    public function favorites(Request $r): void
    {
        $u = Auth::require();
        header('Cache-Control: no-store');
        $rows = DB::all(Catalog::EQ_SELECT . ' JOIN favorites f ON f.equipment_id = e.id WHERE f.user_id = ? AND e.is_active = 1 ORDER BY f.created_at DESC', [$u['id']]);
        Response::json(array_map(fn($x) => Catalog::equipment($x), $rows));
    }

    public function favAdd(Request $r): void
    {
        $u = Auth::require();
        $eq = DB::one('SELECT id FROM equipment WHERE slug = ?', [$r->params['slug']]);
        if (!$eq) throw new HttpError(404, 'not_found', 'المعدة غير موجودة');
        DB::exec('INSERT IGNORE INTO favorites (user_id, equipment_id) VALUES (?, ?)', [$u['id'], $eq['id']]);
        Response::json(['favorite' => true]);
    }

    public function favRemove(Request $r): void
    {
        $u = Auth::require();
        DB::exec('DELETE f FROM favorites f JOIN equipment e ON e.id = f.equipment_id WHERE f.user_id = ? AND e.slug = ?', [$u['id'], $r->params['slug']]);
        Response::json(['favorite' => false]);
    }
}
