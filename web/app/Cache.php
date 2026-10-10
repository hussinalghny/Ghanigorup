<?php
declare(strict_types=1);

namespace App;

/**
 * كاش موحّد يختار أفضل محرك متوفر تلقائياً:
 *   Redis (مشترك بين عدة سيرفرات ويب)  →  APCu (ذاكرة السيرفر)  →  ملفات (احتياطي)
 * يدعم "إصدارات" للمجموعات (tags) حتى نلغي كاش الكتالوج كله بخطوة واحدة.
 */
final class Cache
{
    private static ?string $driver = null;
    private static ?\Redis $redis = null;
    private static array $local = [];

    public static function driver(): string
    {
        if (self::$driver) return self::$driver;
        $want = (string)Config::get('cache.driver', 'auto');

        if (in_array($want, ['auto', 'redis'], true) && extension_loaded('redis') && Config::get('cache.redis.host')) {
            try {
                $r = new \Redis();
                $r->connect((string)Config::get('cache.redis.host'), (int)Config::get('cache.redis.port', 6379), 1.0);
                if ($pw = Config::get('cache.redis.password')) $r->auth($pw);
                if ($db = (int)Config::get('cache.redis.db', 0)) $r->select($db);
                self::$redis = $r;
                return self::$driver = 'redis';
            } catch (\Throwable $e) {
                Log::warn('Redis unavailable, falling back', ['e' => $e->getMessage()]);
            }
        }
        if (in_array($want, ['auto', 'apcu'], true) && function_exists('apcu_enabled') && apcu_enabled()) {
            return self::$driver = 'apcu';
        }
        return self::$driver = 'file';
    }

    private static function k(string $key): string
    {
        return (string)Config::get('cache.prefix', 'gg:') . APP_VERSION . ':' . $key;
    }

    private static function path(string $key): string
    {
        $h = sha1($key);
        return ROOT . '/storage/cache/' . substr($h, 0, 2) . '/' . $h . '.cache';
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        $k = self::k($key);
        if (array_key_exists($k, self::$local)) return self::$local[$k];

        switch (self::driver()) {
            case 'redis':
                $v = self::$redis->get($k);
                return $v === false ? $default : unserialize($v, ['allowed_classes' => false]);
            case 'apcu':
                $v = apcu_fetch($k, $ok);
                return $ok ? $v : $default;
            default:
                $f = self::path($k);
                if (!is_file($f)) return $default;
                $raw = @file_get_contents($f);
                if ($raw === false || strlen($raw) < 10) return $default;
                $exp = (int)substr($raw, 0, 10);
                if ($exp !== 0 && $exp < time()) { @unlink($f); return $default; }
                return unserialize(substr($raw, 10), ['allowed_classes' => false]);
        }
    }

    public static function set(string $key, mixed $value, int $ttl = 300): void
    {
        $k = self::k($key);
        self::$local[$k] = $value;
        switch (self::driver()) {
            case 'redis':
                $ttl > 0 ? self::$redis->setex($k, $ttl, serialize($value)) : self::$redis->set($k, serialize($value));
                return;
            case 'apcu':
                apcu_store($k, $value, $ttl);
                return;
            default:
                $f = self::path($k);
                if (!is_dir(dirname($f))) @mkdir(dirname($f), 0750, true);
                $tmp = $f . '.' . bin2hex(random_bytes(4));
                file_put_contents($tmp, sprintf('%010d', $ttl > 0 ? time() + $ttl : 0) . serialize($value), LOCK_EX);
                @rename($tmp, $f);
        }
    }

    public static function delete(string $key): void
    {
        $k = self::k($key);
        unset(self::$local[$k]);
        match (self::driver()) {
            'redis' => self::$redis->del($k),
            'apcu' => apcu_delete($k),
            default => @unlink(self::path($k)),
        };
    }

    public static function remember(string $key, int $ttl, callable $fn): mixed
    {
        $miss = new \stdClass();
        $v = self::get($key, $miss);
        if ($v !== $miss) return $v;
        $v = $fn();
        self::set($key, $v, $ttl);
        return $v;
    }

    /** عدّاد ذري خلال نافذة زمنية — يُستخدم لتحديد معدل الطلبات */
    public static function hit(string $key, int $window): int
    {
        $k = self::k($key);
        switch (self::driver()) {
            case 'redis':
                $n = self::$redis->incr($k);
                if ($n === 1) self::$redis->expire($k, $window);
                return (int)$n;
            case 'apcu':
                apcu_add($k, 0, $window);
                return (int)apcu_inc($k);
            default:
                $f = self::path($k);
                if (!is_dir(dirname($f))) @mkdir(dirname($f), 0750, true);
                $fh = fopen($f, 'c+');
                if (!$fh) return 0;
                flock($fh, LOCK_EX);
                $raw = stream_get_contents($fh);
                $exp = (int)substr($raw ?: '0', 0, 10);
                $n = ($raw && $exp >= time()) ? (int)unserialize(substr($raw, 10)) : 0;
                if (!$raw || $exp < time()) $exp = time() + $window;
                $n++;
                ftruncate($fh, 0);
                rewind($fh);
                fwrite($fh, sprintf('%010d', $exp) . serialize($n));
                fflush($fh);
                flock($fh, LOCK_UN);
                fclose($fh);
                return $n;
        }
    }

    /** إصدار مجموعة: تغييره يُبطل كل المفاتيح المرتبطة به */
    public static function version(string $tag): int
    {
        $v = self::get('ver:' . $tag);
        if (!$v) { $v = time(); self::set('ver:' . $tag, $v, 0); }
        return (int)$v;
    }

    public static function bump(string $tag): void
    {
        self::set('ver:' . $tag, (int)(microtime(true) * 1000), 0);
    }

    public static function flush(): void
    {
        self::$local = [];
        switch (self::driver()) {
            case 'redis':
                $it = null;
                while ($keys = self::$redis->scan($it, self::k('*'), 500)) self::$redis->del($keys);
                return;
            case 'apcu':
                apcu_clear_cache();
                return;
            default:
                $dir = ROOT . '/storage/cache';
                foreach (glob($dir . '/*/*.cache') ?: [] as $f) @unlink($f);
        }
    }
}
