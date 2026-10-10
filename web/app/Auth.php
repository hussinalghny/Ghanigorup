<?php
declare(strict_types=1);

namespace App;

/**
 * المصادقة:
 *  - تطبيقات الموبايل / أي عميل API:  Authorization: Bearer <token>
 *  - موقع الويب ولوحة التحكم: كوكي HttpOnly (gg_t) + حماية CSRF (double submit: كوكي gg_csrf + ترويسة X-CSRF-Token)
 *  التوكن لا يُخزَّن في القاعدة إلا كـ HMAC-SHA256، فتسريب القاعدة لا يكشف الجلسات.
 */
final class Auth
{
    private static array|false|null $user = null;
    private static bool $viaCookie = false;

    public static function user(): ?array
    {
        if (self::$user !== null) return self::$user ?: null;

        $token = null;
        $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
        if (preg_match('/^Bearer\s+([A-Za-z0-9_\-]{20,100})$/', $h, $m)) {
            $token = $m[1];
        } elseif (!empty($_COOKIE['gg_t']) && preg_match('/^[A-Za-z0-9_\-]{20,100}$/', $_COOKIE['gg_t'])) {
            $token = $_COOKIE['gg_t'];
            self::$viaCookie = true;
        }
        if (!$token) return (self::$user = false) ?: null;

        $hash = Security::hashToken($token);
        $row = Cache::remember('tok:' . $hash, 60, fn() => DB::one(
            'SELECT t.id AS token_id, t.expires_at, u.id, u.name, u.email, u.phone, u.company, u.role, u.status
               FROM api_tokens t JOIN users u ON u.id = t.user_id
              WHERE t.token_hash = ? LIMIT 1',
            [$hash]
        ) ?: []);

        if (!$row || strtotime($row['expires_at']) < time() || $row['status'] !== 'active') {
            return (self::$user = false) ?: null;
        }

        // CSRF للطلبات المعتمدة على الكوكي
        if (self::$viaCookie && !in_array($_SERVER['REQUEST_METHOD'] ?? 'GET', ['GET', 'HEAD', 'OPTIONS'], true)) {
            $hdr = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
            $ck = $_COOKIE['gg_csrf'] ?? '';
            if ($hdr === '' || $ck === '' || !hash_equals($ck, $hdr)) {
                throw new HttpError(419, 'csrf', 'انتهت صلاحية الجلسة، أعد تحميل الصفحة');
            }
        }

        // تحديث آخر استخدام مرة كل 5 دقائق فقط لتخفيف الكتابة على القاعدة
        if (!Cache::get('tok_touch:' . $row['token_id'])) {
            Cache::set('tok_touch:' . $row['token_id'], 1, 300);
            DB::exec('UPDATE api_tokens SET last_used_at = NOW() WHERE id = ?', [$row['token_id']]);
        }

        unset($row['expires_at']);
        return self::$user = $row;
    }

    public static function require(array $roles = []): array
    {
        $u = self::user();
        if (!$u) throw new HttpError(401, 'unauthenticated', 'يجب تسجيل الدخول');
        if ($roles && !in_array($u['role'], $roles, true)) {
            throw new HttpError(403, 'forbidden', 'لا تملك صلاحية لهذا الإجراء');
        }
        return $u;
    }

    /** الأدوار التي تدخل لوحة التحكم */
    public const PANEL_ROLES = ['admin', 'staff', 'storekeeper'];

    /**
     * صلاحيات الأدوار:
     *  admin       — كل شيء
     *  staff       — الطلبات والأسعار، الكتالوج، البنرات، الماركات، الإشعارات، التسليم والإرجاع
     *  storekeeper — أمين المخزن: عرض الطلبات، التسليم والإرجاع بالتوقيع، كميات المعدات — بدون أسعار
     */
    private const PERMS = [
        'staff' => ['dashboard', 'orders.view', 'orders.edit', 'orders.price', 'handover', 'equipment.edit', 'catalog.edit', 'banners', 'brands', 'notifications'],
        'storekeeper' => ['dashboard', 'orders.view', 'handover', 'equipment.edit'],
    ];

    public static function can(?array $u, string $perm): bool
    {
        if (!$u) return false;
        if ($u['role'] === 'admin') return true;
        return in_array($perm, self::PERMS[$u['role']] ?? [], true);
    }

    public static function perms(array $u): array
    {
        if ($u['role'] === 'admin') return ['*'];
        return self::PERMS[$u['role']] ?? [];
    }

    public static function issue(int $userId, Request $req, bool $cookie): string
    {
        $token = Security::randomToken(32);
        $days = (int)Config::get('security.token_ttl_days', 30);
        DB::insert('api_tokens', [
            'user_id' => $userId,
            'token_hash' => Security::hashToken($token),
            'ip' => $req->ip(),
            'user_agent' => mb_substr($req->header('User-Agent') ?? '', 0, 250),
            'expires_at' => date('Y-m-d H:i:s', time() + $days * 86400),
        ]);
        // حد أقصى 10 جلسات فعالة لكل مستخدم
        DB::exec(
            'DELETE FROM api_tokens WHERE user_id = ? AND id NOT IN (
                SELECT id FROM (SELECT id FROM api_tokens WHERE user_id = ? ORDER BY id DESC LIMIT 10) x)',
            [$userId, $userId]
        );
        // تنظيف الجلسات المنتهية بشكل دوري (1% من عمليات الدخول)
        if (random_int(1, 100) === 1) DB::exec('DELETE FROM api_tokens WHERE expires_at < NOW()');
        if ($cookie) self::setCookies($token, $days);
        return $token;
    }

    public static function setCookies(string $token, int $days): void
    {
        $opt = ['expires' => time() + $days * 86400, 'path' => '/', 'secure' => Security::isHttps(), 'samesite' => 'Strict'];
        setcookie('gg_t', $token, $opt + ['httponly' => true]);
        setcookie('gg_csrf', Security::randomToken(18), $opt + ['httponly' => false]);
    }

    public static function revokeCurrent(): void
    {
        $u = self::user();
        if ($u) {
            DB::exec('DELETE FROM api_tokens WHERE id = ?', [$u['token_id']]);
            $tok = $_COOKIE['gg_t'] ?? '';
            if ($tok) Cache::delete('tok:' . Security::hashToken($tok));
        }
        $opt = ['expires' => time() - 3600, 'path' => '/', 'secure' => Security::isHttps(), 'samesite' => 'Strict'];
        setcookie('gg_t', '', $opt + ['httponly' => true]);
        setcookie('gg_csrf', '', $opt);
    }

    public static function revokeAll(int $userId): void
    {
        foreach (DB::allW('SELECT token_hash FROM api_tokens WHERE user_id = ?', [$userId]) as $t) {
            Cache::delete('tok:' . $t['token_hash']);
        }
        DB::exec('DELETE FROM api_tokens WHERE user_id = ?', [$userId]);
    }

    public static function audit(string $action, string $entity = '', ?int $entityId = null, array $meta = []): void
    {
        $u = self::user();
        DB::insert('audit_log', [
            'user_id' => $u['id'] ?? null,
            'action' => $action,
            'entity' => $entity,
            'entity_id' => $entityId,
            'meta' => $meta ? json_encode($meta, JSON_UNESCAPED_UNICODE) : null,
            'ip' => $_SERVER['REMOTE_ADDR'] ?? '',
        ]);
    }
}
