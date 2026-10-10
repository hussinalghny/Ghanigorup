<?php
declare(strict_types=1);

namespace App;

/**
 * الإشعارات الفورية عبر Firebase Cloud Messaging (HTTP v1).
 *  - المفتاح: ملف حساب الخدمة (service account JSON) يُرفع من لوحة التحكم ← الإعدادات،
 *    ويُحفظ في storage/firebase/ (غير متاح للعامة).
 *  - المصادقة: JWT موقّع بـ RS256 ← access token من Google (يُخزَّن في الكاش ~55 دقيقة).
 *  - الإعلانات تُرسل لموضوع "all" (كل التطبيقات مشتركة فيه)، وتحديثات الطلبات لأجهزة صاحب الطلب.
 * إذا لم يُضبط Firebase تبقى الإشعارات داخل التطبيق تعمل كما هي.
 */
final class Push
{
    public const TOPIC = 'all';
    private const DIR = '/storage/firebase';
    private const FILE = '/storage/firebase/service-account.json';

    public static function configured(): bool
    {
        return is_file(ROOT . self::FILE) && function_exists('openssl_sign') && function_exists('curl_init');
    }

    /** @return array{project_id:string,client_email:string,private_key:string,token_uri:string}|null */
    public static function credentials(): ?array
    {
        if (!is_file(ROOT . self::FILE)) return null;
        $j = json_decode((string)file_get_contents(ROOT . self::FILE), true);
        return is_array($j) && !empty($j['private_key']) ? $j : null;
    }

    /** يتحقق من ملف حساب الخدمة ويحفظه */
    public static function saveCredentials(string $json): array
    {
        $j = json_decode($json, true);
        if (!is_array($j) || ($j['type'] ?? '') !== 'service_account' || empty($j['project_id']) || empty($j['client_email']) || empty($j['private_key'])) {
            throw new HttpError(422, 'validation', 'الملف ليس ملف حساب خدمة من Firebase (Service account JSON)');
        }
        if (!openssl_pkey_get_private($j['private_key'])) throw new HttpError(422, 'validation', 'المفتاح الخاص داخل الملف غير صالح');
        $keep = array_intersect_key($j, array_flip(['type', 'project_id', 'private_key_id', 'private_key', 'client_email', 'client_id', 'token_uri']));
        $keep['token_uri'] = $keep['token_uri'] ?? 'https://oauth2.googleapis.com/token';
        if (!is_dir(ROOT . self::DIR)) mkdir(ROOT . self::DIR, 0750, true);
        @file_put_contents(ROOT . self::DIR . '/.htaccess', "Require all denied\n");
        file_put_contents(ROOT . self::FILE, json_encode($keep, JSON_UNESCAPED_SLASHES), LOCK_EX);
        @chmod(ROOT . self::FILE, 0600);
        Cache::delete('fcm_access_token');
        return ['project_id' => $keep['project_id'], 'client_email' => $keep['client_email']];
    }

    public static function removeCredentials(): void
    {
        @unlink(ROOT . self::FILE);
        Cache::delete('fcm_access_token');
    }

    private static function b64(string $s): string
    {
        return rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
    }

    /** JWT موقّع بالمفتاح الخاص لحساب الخدمة (للاختبار أيضاً) */
    public static function jwt(array $c, ?int $now = null): string
    {
        $now ??= time();
        $head = self::b64(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
        $claims = self::b64(json_encode([
            'iss' => $c['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => $c['token_uri'] ?? 'https://oauth2.googleapis.com/token',
            'iat' => $now,
            'exp' => $now + 3600,
        ]));
        $sig = '';
        if (!openssl_sign("$head.$claims", $sig, $c['private_key'], OPENSSL_ALGO_SHA256)) {
            throw new \RuntimeException('تعذر توقيع JWT');
        }
        return "$head.$claims." . self::b64($sig);
    }

    public static function accessToken(bool $fresh = false): string
    {
        if (!$fresh && ($t = Cache::get('fcm_access_token'))) return (string)$t;
        $c = self::credentials();
        if (!$c) throw new \RuntimeException('Firebase غير مُعدّ');
        [$code, $body] = self::http('POST', $c['token_uri'] ?? 'https://oauth2.googleapis.com/token', [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => self::jwt($c),
        ], null, true);
        $j = json_decode($body, true);
        if ($code !== 200 || empty($j['access_token'])) {
            throw new \RuntimeException('رفضت Google المفتاح: ' . ($j['error_description'] ?? $j['error'] ?? "HTTP $code"));
        }
        Cache::set('fcm_access_token', $j['access_token'], max(60, (int)($j['expires_in'] ?? 3600) - 300));
        return $j['access_token'];
    }

    /** @return array{0:int,1:string} */
    private static function http(string $method, string $url, array $payload, ?string $bearer, bool $form = false): array
    {
        $ch = curl_init($url);
        $headers = $form ? ['Content-Type: application/x-www-form-urlencoded'] : ['Content-Type: application/json; charset=utf-8'];
        if ($bearer) $headers[] = 'Authorization: Bearer ' . $bearer;
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_POSTFIELDS => $form ? http_build_query($payload) : json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 4,
            CURLOPT_TIMEOUT => 8,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
        ]);
        $body = (string)curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        if ($body === '' && curl_errno($ch)) $body = json_encode(['error' => curl_error($ch)]);
        curl_close($ch);
        return [$code, $body];
    }

    /** يبني رسالة FCM بإشعار ظاهر + بيانات للتنقل عند الضغط */
    private static function message(array $target, string $title, ?string $body, ?string $image, array $data): array
    {
        $data = array_map('strval', array_filter($data, fn($v) => $v !== null && $v !== ''));
        $n = ['title' => mb_substr($title, 0, 150)];
        if ($body) $n['body'] = mb_substr($body, 0, 1000);
        if ($image && str_starts_with($image, 'https://')) $n['image'] = $image;
        return $target + [
            'notification' => $n,
            'data' => (object)$data,
            'android' => [
                'priority' => 'HIGH',
                'notification' => ['color' => '#B82619', 'sound' => 'default', 'icon' => 'ic_notification'],
            ],
            'apns' => [
                'headers' => ['apns-priority' => '10'],
                'payload' => ['aps' => ['sound' => 'default', 'mutable-content' => 1]],
            ] + ($n['image'] ?? null ? ['fcm_options' => ['image' => $n['image']]] : []),
        ];
    }

    private static function send(array $message): array
    {
        $c = self::credentials();
        $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($c['project_id']) . '/messages:send';
        [$code, $body] = self::http('POST', $url, ['message' => $message], self::accessToken());
        if ($code === 401) [$code, $body] = self::http('POST', $url, ['message' => $message], self::accessToken(true));
        return [$code, $body];
    }

    private static array $jobs = [];

    /**
     * تأجيل الإرسال لما بعد إرجاع الاستجابة — لوحة التحكم لا تنتظر خوادم Google.
     * (على PHP-FPM يُغلق الاتصال فوراً؛ على mod_php يُرسل في نهاية نفس الطلب)
     */
    public static function later(callable $job): void
    {
        if (!self::configured()) return;
        if (!self::$jobs) {
            register_shutdown_function(static function () {
                if (function_exists('fastcgi_finish_request')) @fastcgi_finish_request();
                @set_time_limit(60);
                foreach (self::$jobs as $j) {
                    try { $j(); } catch (\Throwable $e) { Log::error('FCM job: ' . $e->getMessage()); }
                }
            });
        }
        self::$jobs[] = $job;
    }

    /** إشعار لكل المستخدمين (موضوع all) */
    public static function broadcast(string $title, ?string $body, ?string $image = null, array $data = []): bool
    {
        if (!self::configured()) return false;
        try {
            [$code, $resp] = self::send(self::message(['topic' => self::TOPIC], $title, $body, $image, $data));
            if ($code !== 200) Log::warn('FCM topic failed', ['code' => $code, 'body' => mb_substr($resp, 0, 300)]);
            return $code === 200;
        } catch (\Throwable $e) {
            Log::error('FCM: ' . $e->getMessage());
            return false;
        }
    }

    /** إشعار لأجهزة محددة؛ الرموز المنتهية تُحذف تلقائياً. @return int عدد المرسَل بنجاح */
    public static function toDevices(array $devices, string $title, ?string $body, ?string $image = null, array $data = []): int
    {
        if (!self::configured() || !$devices) return 0;
        $ok = 0;
        try {
            foreach (array_slice($devices, 0, 50) as $d) {
                [$code, $resp] = self::send(self::message(['token' => $d['token']], $title, $body, $image, $data));
                if ($code === 200) { $ok++; continue; }
                // UNREGISTERED / INVALID_ARGUMENT للرمز ← الجهاز حذف التطبيق
                if ($code === 404 || ($code === 400 && str_contains($resp, 'registration token'))) {
                    DB::exec('DELETE FROM device_tokens WHERE id = ?', [$d['id']]);
                } else {
                    Log::warn('FCM token failed', ['code' => $code, 'body' => mb_substr($resp, 0, 300)]);
                }
            }
        } catch (\Throwable $e) {
            Log::error('FCM: ' . $e->getMessage());
        }
        return $ok;
    }

    /** أجهزة صاحب الطلب: حسابه المسجّل + أي جهاز ضيف يتابع الطلب */
    public static function orderDevices(array $order): array
    {
        return DB::allW(
            'SELECT DISTINCT d.id, d.token FROM device_tokens d
               LEFT JOIN device_orders x ON x.device_id = d.id AND x.order_id = ?
              WHERE (d.user_id IS NOT NULL AND d.user_id = ?) OR x.order_id IS NOT NULL
              ORDER BY d.id DESC LIMIT 20',
            [(int)$order['id'], (int)($order['user_id'] ?? 0)]
        );
    }

    public static function userDevices(int $userId): array
    {
        return DB::allW('SELECT id, token FROM device_tokens WHERE user_id = ? ORDER BY id DESC LIMIT 20', [$userId]);
    }
}
