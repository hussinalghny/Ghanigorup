<?php
declare(strict_types=1);

namespace App;

final class Security
{
    public static function isHttps(): bool
    {
        return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['SERVER_PORT'] ?? '') === '443')
            || (Config::get('security.trusted_proxies') && ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    }

    /** ترويسات أمان لكل استجابة */
    public static function headers(bool $html = false): void
    {
        header_remove('X-Powered-By');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: strict-origin-when-cross-origin');
        header('Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()');
        header('Cross-Origin-Opener-Policy: same-origin');
        if (self::isHttps()) header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
        if ($html) {
            header("Content-Security-Policy: default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
        } else {
            header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");
        }
    }

    public static function forceHttps(): void
    {
        if (Config::get('security.force_https') && !self::isHttps() && PHP_SAPI !== 'cli') {
            header('Location: https://' . ($_SERVER['HTTP_HOST'] ?? '') . ($_SERVER['REQUEST_URI'] ?? '/'), true, 301);
            exit;
        }
    }

    /** CORS: يسمح فقط بالمصادر المعرّفة في الإعدادات (لتطبيقات الموبايل/المواقع الأخرى) */
    public static function cors(Request $req): void
    {
        $origin = $req->header('Origin');
        $allowed = Config::get('security.cors_origins', []) ?: [];
        if ($origin && (in_array('*', $allowed, true) || in_array($origin, $allowed, true))) {
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Vary: Origin');
            header('Access-Control-Allow-Headers: Authorization, Content-Type, X-CSRF-Token');
            header('Access-Control-Allow-Methods: GET, POST, PATCH, PUT, DELETE, OPTIONS');
            header('Access-Control-Max-Age: 600');
        }
        if ($req->method === 'OPTIONS') {
            http_response_code(204);
            exit;
        }
    }

    /**
     * تحديد معدل الطلبات (Rate limiting) — يحمي من الهجمات والـ brute force والضغط.
     * @param string $bucket اسم المجموعة (api, auth, orders ...)
     */
    public static function throttle(string $bucket, string $id, ?int $limit = null, ?int $window = null): void
    {
        [$defLimit, $defWindow] = Config::get("security.rate.$bucket", [120, 60]);
        $limit ??= (int)$defLimit;
        $window ??= (int)$defWindow;
        $n = Cache::hit("rl:$bucket:" . sha1($id), $window);
        header("X-RateLimit-Limit: $limit");
        header('X-RateLimit-Remaining: ' . max(0, $limit - $n));
        if ($n > $limit) {
            header('Retry-After: ' . $window);
            if ($n === $limit + 1) Log::warn('Rate limit exceeded', ['bucket' => $bucket]);
            throw new HttpError(429, 'too_many_requests', 'طلبات كثيرة، حاول بعد قليل');
        }
    }

    public static function randomToken(int $bytes = 32): string
    {
        return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '=');
    }

    public static function hashToken(string $t): string
    {
        return hash_hmac('sha256', $t, (string)Config::get('app.key'));
    }

    public static function hashPassword(string $p): string
    {
        return defined('PASSWORD_ARGON2ID')
            ? password_hash($p, PASSWORD_ARGON2ID)
            : password_hash($p, PASSWORD_BCRYPT, ['cost' => 12]);
    }

    public static function passwordStrong(string $p): bool
    {
        return mb_strlen($p) >= 8 && preg_match('/[A-Za-z\x{0600}-\x{06FF}]/u', $p) && preg_match('/\d/', $p);
    }

    public static function cleanText(?string $s, int $max = 1000): string
    {
        $s = (string)$s;
        $s = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $s) ?? '';
        return mb_substr(trim($s), 0, $max);
    }
}
