<?php
declare(strict_types=1);

namespace App;

final class Log
{
    public static function write(string $level, string $msg, array $ctx = []): void
    {
        $dir = ROOT . '/storage/logs';
        if (!is_dir($dir)) @mkdir($dir, 0750, true);
        $line = sprintf(
            "[%s] %s: %s %s | ip=%s uri=%s\n",
            date('Y-m-d H:i:s'),
            strtoupper($level),
            str_replace(["\n", "\r"], ' ', $msg),
            $ctx ? json_encode($ctx, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : '',
            $_SERVER['REMOTE_ADDR'] ?? 'cli',
            substr($_SERVER['REQUEST_URI'] ?? '', 0, 200)
        );
        @file_put_contents($dir . '/app-' . date('Y-m-d') . '.log', $line, FILE_APPEND | LOCK_EX);
    }

    public static function error(string $m, array $c = []): void { self::write('error', $m, $c); }
    public static function warn(string $m, array $c = []): void { self::write('warning', $m, $c); }
    public static function info(string $m, array $c = []): void { self::write('info', $m, $c); }
}
