<?php
declare(strict_types=1);

namespace App\Controllers;

use App\Auth;
use App\DB;
use App\HttpError;
use App\Request;
use App\Response;
use App\Security;

/**
 * تسجيل أجهزة التطبيق للإشعارات الفورية (FCM token).
 * POST /devices  {"token":"…","platform":"ios|android","app_version":"1.2.0","track":[{"ref":"GG-…","phone":"07…"}],"promo":true}
 *   promo: موافقة المستخدم على الإشعارات الإعلانية — إذا لم يُرسل يبقى الاختيار السابق (الافتراضي: لا)
 *   إشعارات الطلبات تصل دائماً لصاحب الطلب لأنها جزء من الخدمة
 * DELETE /devices {"token":"…"}
 */
final class DeviceController
{
    public function register(Request $r): void
    {
        Security::throttle('write', 'dev:' . $r->ip(), 30, 600);
        $in = $r->input();
        $token = trim((string)($in['token'] ?? ''));
        if (!preg_match('/^[A-Za-z0-9_\-:.]{20,500}$/', $token)) throw new HttpError(422, 'validation', 'رمز الجهاز غير صالح');
        $platform = in_array($in['platform'] ?? '', ['ios', 'android', 'web'], true) ? $in['platform'] : 'android';
        $ver = mb_substr(preg_replace('/[^0-9.+]/', '', (string)($in['app_version'] ?? '')), 0, 20);
        $u = Auth::user();
        $hash = hash('sha256', $token);
        $promo = array_key_exists('promo', $in) && $in['promo'] !== null ? (filter_var($in['promo'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0) : null;

        DB::exec(
            'INSERT INTO device_tokens (token, token_hash, platform, user_id, promo, app_version, last_seen) VALUES (?, ?, ?, ?, ?, ?, NOW())
             ON DUPLICATE KEY UPDATE platform = VALUES(platform), user_id = VALUES(user_id), app_version = VALUES(app_version), last_seen = NOW(),
                                     promo = IF(? IS NULL, promo, VALUES(promo))',
            [$token, $hash, $platform, $u['id'] ?? null, $promo ?? 0, $ver ?: null, $promo]
        );
        $id = (int)DB::val('SELECT id FROM device_tokens WHERE token_hash = ?', [$hash]);

        // طلبات الضيف: نربطها بالجهاز فقط بعد التحقق من رقم الطلب والهاتف
        $linked = 0;
        $track = $in['track'] ?? [];
        if (is_array($track)) {
            foreach (array_slice($track, 0, 20) as $t) {
                if (!is_array($t)) continue;
                $ref = strtoupper(trim((string)($t['ref'] ?? '')));
                $phone = preg_replace('/\D/', '', (string)($t['phone'] ?? ''));
                if (!preg_match('/^GG-[A-Z0-9]{4,10}$/', $ref) || strlen($phone) < 6) continue;
                $o = DB::oneW('SELECT id, phone FROM orders WHERE ref = ?', [$ref]);
                if ($o && hash_equals(preg_replace('/\D/', '', $o['phone']), $phone)) {
                    $linked += DB::exec('INSERT IGNORE INTO device_orders (device_id, order_id) VALUES (?, ?)', [$id, $o['id']]);
                }
            }
        }
        // تنظيف دوري للأجهزة غير النشطة منذ 9 أشهر
        if (random_int(1, 200) === 1) DB::exec('DELETE FROM device_tokens WHERE last_seen < DATE_SUB(NOW(), INTERVAL 270 DAY)');

        header('Cache-Control: no-store');
        Response::json(['registered' => true, 'orders_linked' => $linked, 'promo' => (bool)DB::val('SELECT promo FROM device_tokens WHERE id = ?', [$id])]);
    }

    public function remove(Request $r): void
    {
        $token = trim((string)($r->input()['token'] ?? ''));
        if ($token !== '') DB::exec('DELETE FROM device_tokens WHERE token_hash = ?', [hash('sha256', $token)]);
        Response::json(['removed' => true]);
    }
}
