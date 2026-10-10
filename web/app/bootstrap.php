<?php
declare(strict_types=1);

/*
 * Ghani Group Rental — bootstrap
 * يحمّل الإعدادات، الـ autoloader، معالجة الأخطاء والمنطقة الزمنية.
 */

define('ROOT', dirname(__DIR__));
define('APP_START', microtime(true));
define('APP_VERSION', '1.2.1');

spl_autoload_register(static function (string $class): void {
    if (strncmp($class, 'App\\', 4) !== 0) return;
    $file = ROOT . '/app/' . str_replace('\\', '/', substr($class, 4)) . '.php';
    if (is_file($file)) require $file;
});

require ROOT . '/app/Http.php';

use App\Config;
use App\Log;

if (!is_file(ROOT . '/config/config.php')) {
    // لم يتم التنصيب بعد
    if (PHP_SAPI !== 'cli') {
        header('Location: ' . rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/'), '/') . '/install/');
    }
    exit;
}

Config::load(ROOT . '/config/config.php');
date_default_timezone_set(Config::get('app.timezone', 'Asia/Baghdad'));

$debug = Config::get('app.env') === 'development';
ini_set('display_errors', $debug ? '1' : '0');
error_reporting(E_ALL);

set_error_handler(static function (int $no, string $str, string $file, int $line): bool {
    if (!(error_reporting() & $no)) return false;
    throw new ErrorException($str, 0, $no, $file, $line);
});

set_exception_handler(static function (Throwable $e) use ($debug): void {
    Log::error($e->getMessage(), ['file' => $e->getFile(), 'line' => $e->getLine()]);
    if (!headers_sent()) {
        http_response_code(500);
        header('Content-Type: application/json; charset=utf-8');
    }
    echo json_encode([
        'ok' => false,
        'error' => ['code' => 'server_error', 'message' => $debug ? $e->getMessage() : 'حدث خطأ غير متوقع'],
    ], JSON_UNESCAPED_UNICODE);
});
