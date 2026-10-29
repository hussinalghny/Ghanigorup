<?php
declare(strict_types=1);

namespace App;

final class HttpError extends \RuntimeException
{
    public function __construct(
        public readonly int $status,
        public readonly string $errorCode,
        string $message,
        public readonly array $details = []
    ) {
        parent::__construct($message, $status);
    }
}

final class Request
{
    public string $method;
    public string $path;
    public array $query;
    public array $params = [];
    private ?array $json = null;

    public function __construct()
    {
        $this->method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        if ($this->method === 'POST' && isset($_SERVER['HTTP_X_HTTP_METHOD_OVERRIDE'])) {
            $o = strtoupper($_SERVER['HTTP_X_HTTP_METHOD_OVERRIDE']);
            if (in_array($o, ['PUT', 'PATCH', 'DELETE'], true)) $this->method = $o;
        }
        $uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        $base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
        if ($base !== '' && str_starts_with($uri, $base)) $uri = substr($uri, strlen($base));
        $this->path = '/' . trim(rawurldecode($uri), '/');
        $this->query = $_GET;
    }

    public function ip(): string
    {
        $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
        // نثق بـ X-Forwarded-For فقط إذا كان الطلب قادماً من بروكسي/موزع أحمال معرّف في الإعدادات
        $trusted = Config::get('security.trusted_proxies', []) ?: [];
        if ($trusted && in_array($ip, $trusted, true) && !empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
            $parts = array_map('trim', explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']));
            $cand = $parts[0];
            if (filter_var($cand, FILTER_VALIDATE_IP)) return $cand;
        }
        return $ip;
    }

    public function header(string $name): ?string
    {
        $k = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
        return $_SERVER[$k] ?? null;
    }

    public function input(): array
    {
        if ($this->json !== null) return $this->json;
        $ct = $_SERVER['CONTENT_TYPE'] ?? '';
        if (str_contains($ct, 'application/json')) {
            $raw = file_get_contents('php://input', false, null, 0, 2_000_000) ?: '';
            if ($raw === '') return $this->json = [];
            $d = json_decode($raw, true, 32);
            if (!is_array($d)) throw new HttpError(400, 'bad_json', 'صيغة JSON غير صحيحة');
            return $this->json = $d;
        }
        return $this->json = $_POST;
    }

    public function get(string $k, mixed $d = null): mixed
    {
        return $this->input()[$k] ?? $this->query[$k] ?? $d;
    }

    public function int(string $k, int $d = 0, int $min = PHP_INT_MIN, int $max = PHP_INT_MAX): int
    {
        $v = $this->query[$k] ?? null;
        $v = is_numeric($v) ? (int)$v : $d;
        return max($min, min($max, $v));
    }

    public function str(string $k, string $d = '', int $max = 200): string
    {
        $v = $this->query[$k] ?? $d;
        return is_string($v) ? mb_substr(trim($v), 0, $max) : $d;
    }
}

final class Response
{
    public const ORIGIN = '{{ORIGIN}}';

    /** عنوان الموقع كما طلبه العميل الحالي: scheme://host/base */
    public static function origin(): string
    {
        $host = $_SERVER['HTTP_HOST'] ?? '';
        if (!preg_match('/^[a-z0-9.\-]+(:\d{1,5})?$/i', $host)) {
            return rtrim((string)Config::get('app.url', ''), '/');
        }
        $https = Security::isHttps()
            || strtolower($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https'
            || str_contains($_SERVER['HTTP_CF_VISITOR'] ?? '', 'https')
            || (($_SERVER['HTTP_X_FORWARDED_SSL'] ?? '') === 'on')
            || str_starts_with((string)Config::get('app.url', ''), 'https://');
        $base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
        return ($https ? 'https' : 'http') . '://' . strtolower($host) . $base;
    }

    private static function encode(array $body): string
    {
        $json = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        return str_replace(self::ORIGIN, self::origin(), (string)$json);
    }

    public static function json(mixed $data, int $status = 200, array $meta = []): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Response-Time: ' . round((microtime(true) - APP_START) * 1000, 1) . 'ms');
        $body = ['ok' => $status < 400, 'data' => $data];
        if ($meta) $body['meta'] = $meta;
        echo self::encode($body);
        exit;
    }

    /** استجابة قابلة للكاش في المتصفح والـ CDN مع ETag ودعم 304 */
    public static function cached(mixed $data, int $maxAge = 60, array $meta = []): never
    {
        $body = self::encode(['ok' => true, 'data' => $data] + ($meta ? ['meta' => $meta] : []));
        $etag = '"' . substr(sha1($body), 0, 20) . '"';
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: public, max-age=' . $maxAge . ', stale-while-revalidate=' . ($maxAge * 5));
        header('ETag: ' . $etag);
        header('Vary: Accept-Encoding, Authorization');
        if (trim($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
            http_response_code(304);
            exit;
        }
        echo $body;
        exit;
    }

    public static function error(int $status, string $code, string $message, array $details = []): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        if (I18n::wantsEn()) {
            $message = I18n::t($message);
            $details = I18n::details($details);
        }
        $e = ['code' => $code, 'message' => $message];
        if ($details) $e['details'] = $details;
        echo json_encode(['ok' => false, 'error' => $e], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}
