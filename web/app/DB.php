<?php
declare(strict_types=1);

namespace App;

use PDO;
use PDOException;
use PDOStatement;

/**
 * طبقة قاعدة البيانات مع توزيع الأحمال:
 *  - كل عمليات الكتابة تذهب إلى السيرفر الرئيسي (primary).
 *  - القراءات توزَّع عشوائياً على سيرفرات القراءة (replicas) إن وُجدت.
 *  - السيرفر المعطّل يُستبعد 30 ثانية (circuit breaker) ويُستخدم الرئيسي بدله.
 *  - بعد أي كتابة: نفس الطلب + نفس العميل لعدة ثوانٍ يقرأ من الرئيسي (sticky)
 *    حتى لا يرى بيانات قديمة بسبب تأخر النسخ (replication lag).
 */
final class DB
{
    private static ?PDO $primary = null;
    private static ?PDO $replica = null;
    private static bool $wrote = false;
    private static int $queries = 0;

    public static function connect(array $c, bool $persistent = false): PDO
    {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            $c['host'],
            (int)($c['port'] ?? 3306),
            $c['name']
        );
        $pdo = new PDO($dsn, $c['user'], $c['pass'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_STRINGIFY_FETCHES => false,
            PDO::ATTR_PERSISTENT => $persistent,
            PDO::ATTR_TIMEOUT => 3,
        ]);
        $pdo->exec("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci, time_zone = '+03:00', sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO'");
        return $pdo;
    }

    public static function primary(): PDO
    {
        return self::$primary ??= self::connect(Config::get('db.primary'), (bool)Config::get('db.persistent', false));
    }

    public static function replica(): PDO
    {
        if (self::$wrote || self::isSticky()) return self::primary();
        if (self::$replica) return self::$replica;

        $replicas = Config::get('db.replicas', []) ?: [];
        shuffle($replicas);
        foreach ($replicas as $r) {
            $key = 'db_down:' . md5(($r['host'] ?? '') . ':' . ($r['port'] ?? 3306));
            if (Cache::get($key)) continue;
            try {
                return self::$replica = self::connect(array_merge(Config::get('db.primary'), $r), (bool)Config::get('db.persistent', false));
            } catch (PDOException $e) {
                Cache::set($key, 1, 30);
                Log::warn('Replica unavailable, skipped for 30s', ['host' => $r['host'] ?? '?']);
            }
        }
        return self::$replica = self::primary();
    }

    private static function isSticky(): bool
    {
        return isset($_COOKIE['gg_stk']) && (int)$_COOKIE['gg_stk'] > time();
    }

    private static function markWrite(): void
    {
        if (self::$wrote) return;
        self::$wrote = true;
        $sec = (int)Config::get('db.sticky_seconds', 5);
        if ($sec > 0 && PHP_SAPI !== 'cli' && !headers_sent() && Config::get('db.replicas')) {
            setcookie('gg_stk', (string)(time() + $sec), [
                'expires' => time() + $sec, 'path' => '/', 'httponly' => true,
                'samesite' => 'Lax', 'secure' => Security::isHttps(),
            ]);
        }
    }

    // ---------- helpers ----------

    public static function run(string $sql, array $params = [], bool $write = false): PDOStatement
    {
        $pdo = $write ? self::primary() : self::replica();
        if ($write) self::markWrite();
        self::$queries++;
        $st = $pdo->prepare($sql);
        foreach ($params as $k => $v) {
            $name = is_int($k) ? $k + 1 : ':' . ltrim((string)$k, ':');
            $type = is_int($v) ? PDO::PARAM_INT : (is_bool($v) ? PDO::PARAM_BOOL : ($v === null ? PDO::PARAM_NULL : PDO::PARAM_STR));
            $st->bindValue($name, $v, $type);
        }
        $st->execute();
        return $st;
    }

    public static function all(string $sql, array $p = []): array { return self::run($sql, $p)->fetchAll(); }
    public static function one(string $sql, array $p = []): ?array { $r = self::run($sql, $p)->fetch(); return $r ?: null; }
    public static function val(string $sql, array $p = []): mixed { $r = self::run($sql, $p)->fetchColumn(); return $r === false ? null : $r; }

    /** قراءة من الرئيسي مباشرة (للعمليات الحساسة مثل التحقق من المخزون أثناء الحجز) */
    public static function oneW(string $sql, array $p = []): ?array { $r = self::run($sql, $p, true)->fetch(); return $r ?: null; }
    public static function allW(string $sql, array $p = []): array { return self::run($sql, $p, true)->fetchAll(); }

    public static function exec(string $sql, array $p = []): int { return self::run($sql, $p, true)->rowCount(); }

    public static function insert(string $table, array $data): int
    {
        self::assertIdent($table);
        $cols = array_keys($data);
        array_walk($cols, [self::class, 'assertIdent']);
        $sql = sprintf(
            'INSERT INTO `%s` (`%s`) VALUES (%s)',
            $table,
            implode('`,`', $cols),
            implode(',', array_map(fn($c) => ':' . $c, $cols))
        );
        self::run($sql, $data, true);
        return (int)self::primary()->lastInsertId();
    }

    public static function update(string $table, array $data, string $where, array $whereParams = []): int
    {
        self::assertIdent($table);
        $set = [];
        $params = [];
        foreach ($data as $c => $v) {
            self::assertIdent($c);
            $set[] = "`$c` = :s_$c";
            $params["s_$c"] = $v;
        }
        return self::exec("UPDATE `$table` SET " . implode(', ', $set) . " WHERE $where", $params + $whereParams);
    }

    public static function tx(callable $fn): mixed
    {
        $pdo = self::primary();
        self::markWrite();
        $pdo->beginTransaction();
        try {
            $r = $fn();
            $pdo->commit();
            return $r;
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $e;
        }
    }

    public static function assertIdent(string $s): void
    {
        if (!preg_match('/^[a-z_][a-z0-9_]{0,63}$/i', $s)) {
            throw new \InvalidArgumentException('Invalid SQL identifier');
        }
    }

    public static function queryCount(): int { return self::$queries; }

    /** IN (?,?,?) placeholder helper */
    public static function in(array $values): string
    {
        return implode(',', array_fill(0, max(1, count($values)), '?'));
    }
}
