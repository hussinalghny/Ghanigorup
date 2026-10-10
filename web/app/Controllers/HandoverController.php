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

/**
 * محاضر تسليم وإرجاع المعدات مع التوقيع الإلكتروني:
 *  - تسليم (checkout): العميل يوقّع باستلام القطع، يُسجَّل الموظف المسؤول والفني المرافق → حالة الطلب "مُسلَّم"
 *  - إرجاع (return): يوقّع المُرجِع، تُسجَّل حالة كل قطعة (سليمة/متضررة/ناقصة) → حالة الطلب "مُرجَع"
 * صور التواقيع تُحفظ في storage/ (غير متاحة للعامة) وتُعرض فقط عبر API للوحة التحكم.
 */
final class HandoverController
{
    private array $u;

    public function __construct()
    {
        $this->u = Auth::require(Auth::PANEL_ROLES);
        if (!Auth::can($this->u, 'handover')) throw new HttpError(403, 'forbidden', 'لا تملك صلاحية التسليم والإرجاع');
        header('Cache-Control: no-store');
    }

    public static function listFor(int $orderId): array
    {
        return array_map([self::class, 'present'], DB::allW('SELECT * FROM order_handovers WHERE order_id = ? ORDER BY id', [$orderId]));
    }

    public static function present(array $h): array
    {
        return [
            'id' => (int)$h['id'], 'type' => $h['type'],
            'employee_id' => $h['employee_id'] ? (int)$h['employee_id'] : null, 'employee_name' => $h['employee_name'],
            'technician_id' => $h['technician_id'] ? (int)$h['technician_id'] : null, 'technician_name' => $h['technician_name'],
            'receiver_name' => $h['receiver_name'], 'receiver_phone' => $h['receiver_phone'],
            'items' => json_decode($h['items'], true) ?: [], 'notes' => $h['notes'],
            'has_employee_signature' => (bool)$h['employee_signature'],
            'created_at' => $h['created_at'],
        ];
    }

    /** POST /admin/orders/{id}/handover */
    public function create(Request $r): void
    {
        $orderId = (int)($r->params['id'] ?? 0);
        $o = DB::oneW('SELECT * FROM orders WHERE id = ?', [$orderId]);
        if (!$o) throw new HttpError(404, 'not_found', 'الطلب غير موجود');
        Security::throttle('upload', 'ho:' . $this->u['id'], 30, 600);

        $in = $r->input();
        $d = Validator::check($in, [
            'type' => 'required|in:checkout,return',
            'receiver_name' => 'required|string|min:2|max:120',
            'receiver_phone' => 'phone',
            'employee_id' => 'int|min:1',
            'technician_id' => 'int|min:1',
            'technician_name' => 'string|max:120',
            'notes' => 'string|max:3000',
            'items' => 'required|array|min:1|max:200',
        ]);

        if ($d['type'] === 'checkout' && !in_array($o['status'], ['pending', 'quoted', 'confirmed'], true)) {
            throw new HttpError(409, 'conflict', $o['status'] === 'out' ? 'تم تسليم هذا الطلب مسبقاً' : 'لا يمكن تسليم طلب بهذه الحالة');
        }
        if ($d['type'] === 'return' && $o['status'] !== 'out') {
            throw new HttpError(409, 'conflict', 'الإرجاع متاح فقط لطلب مُسلَّم للعميل');
        }

        // الموظف المسؤول: المختار أو المستخدم الحالي
        $emp = $this->u;
        if (!empty($d['employee_id']) && (int)$d['employee_id'] !== (int)$this->u['id']) {
            $emp = DB::oneW("SELECT id, name FROM users WHERE id = ? AND role IN ('admin','staff','storekeeper') AND status = 'active'", [$d['employee_id']]);
            if (!$emp) throw new HttpError(422, 'validation', 'الموظف غير موجود', ['employee_id' => 'غير موجود']);
        }
        $techName = $d['technician_name'] ?? null;
        $techId = null;
        if (!empty($d['technician_id'])) {
            $t = DB::oneW("SELECT id, name FROM users WHERE id = ? AND role IN ('technician','storekeeper','staff','admin')", [$d['technician_id']]);
            if (!$t) throw new HttpError(422, 'validation', 'الفني غير موجود', ['technician_id' => 'غير موجود']);
            $techId = (int)$t['id'];
            $techName = $t['name'];
        }

        // البنود: تُطابق مع بنود الطلب الفعلية (لا نثق بالأسماء القادمة من المتصفح)
        $orderItems = [];
        foreach (DB::allW('SELECT oi.equipment_id, oi.qty, e.name, e.brand FROM order_items oi JOIN equipment e ON e.id = oi.equipment_id WHERE oi.order_id = ?', [$orderId]) as $it) {
            $orderItems[(int)$it['equipment_id']] = $it;
        }
        $items = [];
        $issues = 0;
        foreach ($d['items'] as $it) {
            if (!is_array($it)) continue;
            $eid = (int)($it['equipment_id'] ?? 0);
            if (!isset($orderItems[$eid])) continue;
            $base = $orderItems[$eid];
            $qty = max(0, min((int)$base['qty'], (int)($it['qty'] ?? $base['qty'])));
            $cond = in_array($it['condition'] ?? 'ok', ['ok', 'damaged', 'missing'], true) ? ($it['condition'] ?? 'ok') : 'ok';
            if ($cond !== 'ok' || $qty < (int)$base['qty']) $issues++;
            $items[] = [
                'equipment_id' => $eid, 'name' => $base['name'], 'brand' => $base['brand'],
                'ordered' => (int)$base['qty'], 'qty' => $qty, 'condition' => $cond,
                'note' => Security::cleanText((string)($it['note'] ?? ''), 300),
            ];
        }
        if (!$items) throw new HttpError(422, 'validation', 'اختر القطع المسلَّمة', ['items' => 'فارغة']);

        // تسليم طلب غير مؤكد: نتحقق من توفر الكميات أولاً
        if ($d['type'] === 'checkout' && $o['status'] !== 'confirmed' && empty($in['force'])) {
            $short = Catalog::shortages(array_map(fn($i) => ['equipment_id' => $i['equipment_id'], 'qty' => $i['qty']], $items), $o['start_date'], $o['end_date'], (int)$o['id']);
            if ($short) throw new HttpError(409, 'shortage', 'الكمية غير متوفرة لبعض المعدات في هذه الفترة', ['shortages' => $short]);
        }

        // التواقيع
        $sig =Upload::signature((string)($in['signature'] ?? ''));
        $empSig = !empty($in['employee_signature']) ? Upload::signature((string)$in['employee_signature']) : null;

        $newStatus = $d['type'] === 'checkout' ? 'out' : 'returned';
        $id = DB::tx(function () use ($d, $o, $emp, $techId, $techName, $items, $sig, $empSig, $r, $newStatus) {
            $id = DB::insert('order_handovers', [
                'order_id' => (int)$o['id'], 'type' => $d['type'],
                'employee_id' => (int)$emp['id'], 'employee_name' => $emp['name'],
                'technician_id' => $techId, 'technician_name' => $techName,
                'receiver_name' => $d['receiver_name'], 'receiver_phone' => $d['receiver_phone'] ?? null,
                'items' => json_encode($items, JSON_UNESCAPED_UNICODE), 'notes' => $d['notes'] ?? null,
                'signature' => $sig, 'employee_signature' => $empSig,
                'ip' => $r->ip(), 'created_by' => (int)$this->u['id'],
            ]);
            $upd = ['status' => $newStatus];
            if ($d['type'] === 'checkout' && $techId === null && $techName) $upd['technician'] = 1;
            DB::update('orders', $upd, 'id = :id', ['id' => (int)$o['id']]);
            return $id;
        });

        Cache::bump('orders');
        Cache::bump('admin_stats');
        Auth::audit('order.' . $d['type'], 'order', (int)$o['id'], ['handover' => $id, 'issues' => $issues]);
        Notify::orderStatus($o, $newStatus, $d['type'] === 'checkout' && $techName ? 'الفني المرافق: ' . $techName . '.' : null);

        $h = DB::oneW('SELECT * FROM order_handovers WHERE id = ?', [$id]);
        Response::json(self::present($h), 201);
    }

    /** GET /admin/handovers/{id}/signature?who=customer|employee — صورة التوقيع (للمخوّلين فقط) */
    public function signature(Request $r): void
    {
        $h = DB::one('SELECT signature, employee_signature FROM order_handovers WHERE id = ?', [(int)($r->params['id'] ?? 0)]);
        $rel = $h ? ($r->str('who') === 'employee' ? $h['employee_signature'] : $h['signature']) : null;
        if (!$rel || !preg_match('#^signatures/\d{4}/\d{2}/[a-f0-9]{32}\.png$#', $rel)) throw new HttpError(404, 'not_found', 'غير موجود');
        $file = ROOT . '/storage/' . $rel;
        if (!is_file($file)) throw new HttpError(404, 'not_found', 'الملف غير موجود');
        header('Content-Type: image/png');
        header('Content-Length: ' . filesize($file));
        header('Cache-Control: private, max-age=3600');
        header("Content-Security-Policy: default-src 'none'");
        readfile($file);
        exit;
    }

    /** GET /admin/handovers — سجل التسليم والإرجاع */
    public function index(Request $r): void
    {
        $where = ['1=1'];
        $p = [];
        if (in_array($t = $r->str('type'), ['checkout', 'return'], true)) { $where[] = 'h.type = ?'; $p[] = $t; }
        $rows = DB::all('SELECT h.*, o.ref, o.project, o.contact_name FROM order_handovers h JOIN orders o ON o.id = h.order_id WHERE '
            . implode(' AND ', $where) . ' ORDER BY h.id DESC LIMIT 300', $p);
        Response::json(array_map(fn($h) => self::present($h) + ['order_id' => (int)$h['order_id'], 'ref' => $h['ref'], 'project' => $h['project'], 'contact_name' => $h['contact_name']], $rows));
    }

    /** أوامر قادمة لأمين المخزن: ما يجب تسليمه اليوم/قريباً وما يجب استلامه */
    public function board(Request $r): void
    {
        $sel = 'SELECT o.id, o.ref, o.contact_name, o.phone, o.project, o.start_date, o.end_date, o.status, o.technician,
                       (SELECT SUM(qty) FROM order_items WHERE order_id = o.id) AS units FROM orders o';
        $fmt = fn($rows) => array_map(fn($o) => $o + ['units' => (int)$o['units'], 'days_left' => (int)floor((strtotime($o['status'] === 'out' ? $o['end_date'] : $o['start_date']) - strtotime(date('Y-m-d'))) / 86400)], $rows);
        Response::json([
            'to_checkout' => $fmt(DB::all("$sel WHERE o.status IN ('confirmed','quoted','pending') AND o.start_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY) ORDER BY FIELD(o.status,'confirmed','quoted','pending'), o.start_date LIMIT 50")),
            'to_return' => $fmt(DB::all("$sel WHERE o.status = 'out' ORDER BY o.end_date LIMIT 100")),
            'today' => date('Y-m-d'),
        ]);
    }
}
