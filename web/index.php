<?php
declare(strict_types=1);

/*
 * Ghani Group Rental — Front controller
 *   /api/v1/*   → REST API (JSON)
 *   /admin      → لوحة التحكم
 *   /*          → موقع الويب
 */

require __DIR__ . '/app/bootstrap.php';

use App\HttpError;
use App\Request;
use App\Response;
use App\Security;

Security::forceHttps();
$req = new Request();

// ---------------- API ----------------
if (str_starts_with($req->path, '/api/')) {
    Security::headers(false);
    try {
        Security::cors($req);
        if (!preg_match('#^/api/v1(/.*)?$#', $req->path, $m)) throw new HttpError(404, 'not_found', 'إصدار API غير معروف');
        $path = $m[1] ?? '/';

        // حد عام لكل IP، وحد أعلى لطلبات الكتابة
        Security::throttle('api', 'ip:' . $req->ip());
        if ($req->method !== 'GET') Security::throttle('write', 'w:' . $req->ip());

        if (($_SERVER['CONTENT_LENGTH'] ?? 0) > 25 * 1024 * 1024) throw new HttpError(413, 'too_large', 'حجم الطلب كبير');

        // ترقية القاعدة تلقائياً بعد رفع نسخة جديدة (مرة واحدة فقط)
        App\Migrator::ensure();

        $router = require __DIR__ . '/app/routes.php';
        if ($path === '/' ) Response::json(['name' => 'Ghani Group Rental API', 'version' => 'v1', 'endpoints' => $router->list()]);
        $router->dispatch($req, $path);
    } catch (HttpError $e) {
        Response::error($e->status, $e->errorCode, $e->getMessage(), $e->details);
    } catch (PDOException $e) {
        App\Log::error('DB: ' . $e->getMessage());
        Response::error(503, 'db_unavailable', 'الخدمة غير متاحة مؤقتاً');
    }
    exit;
}

// ---------------- Web / Admin (SPA shells) ----------------
Security::headers(true);
header('Cache-Control: no-cache');
$base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/') . '/';

// ---------------- صفحات عامة مطلوبة لمتاجر التطبيقات ----------------
$pages = ['/privacy' => 'سياسة الخصوصية', '/terms' => 'شروط الاستخدام', '/delete-account' => 'حذف الحساب', '/support' => 'الدعم'];
if (isset($pages[$req->path])) {
    $s = [];
    try { $s = App\Catalog::settings(); } catch (Throwable) { /* القاعدة غير متاحة: نعرض الصفحة بدون بيانات الشركة */ }
    $e = fn($v) => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
    $host = parse_url((string)App\Config::get('app.url', ''), PHP_URL_HOST) ?: ($_SERVER['HTTP_HOST'] ?? '');
    $vars = [
        '{{BASE}}' => $e($base), '{{TITLE}}' => $e($pages[$req->path]),
        '{{COMPANY}}' => $e($s['company_name'] ?? 'Ghani Group'), '{{COMPANY_AR}}' => $e($s['company_name_ar'] ?? ($s['company_name'] ?? 'Ghani Group')),
        '{{EMAIL}}' => $e($s['email'] ?? ''), '{{PHONE}}' => $e($s['phone'] ?? ''), '{{PHONE_RAW}}' => $e(preg_replace('/[^\d+]/', '', $s['phone'] ?? '')),
        '{{WHATSAPP}}' => $e($s['whatsapp'] ?? ''), '{{ADDRESS}}' => $e($s['address'] ?? ''), '{{DOMAIN}}' => $e($host), '{{YEAR}}' => date('Y'),
    ];
    $content = strtr(file_get_contents(__DIR__ . '/assets/pages' . $req->path . '.html'), $vars);
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: public, max-age=600');
    echo strtr(str_replace('{{CONTENT}}', $content, file_get_contents(__DIR__ . '/assets/pages/_layout.html')), $vars);
    exit;
}

$isAdmin = $req->path === '/admin' || str_starts_with($req->path, '/admin/');
$file = __DIR__ . ($isAdmin ? '/assets/admin.html' : '/assets/web.html');
$html = file_get_contents($file);
header('Content-Type: text/html; charset=utf-8');
echo str_replace('{{BASE}}', htmlspecialchars($base, ENT_QUOTES), $html);
