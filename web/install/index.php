<?php
declare(strict_types=1);

/*
 * Ghani Group Rental — معالج التنصيب
 *  1) فحص المتطلبات   2) ربط قاعدة البيانات (+ سيرفرات قراءة اختيارية)
 *  3) إعدادات الموقع والمدير   4) إنشاء الجداول + ترحيل كل بيانات الكتالوج والصور + كتابة الإعدادات + قفل المعالج
 */

define('ROOT', dirname(__DIR__));
define('APP_START', microtime(true));
define('APP_VERSION', '1.2.3');
define('LOCK', ROOT . '/config/install.lock');
define('SCHEMA_VERSION', '2026_10_001');

spl_autoload_register(static function (string $c): void {
    if (strncmp($c, 'App\\', 4) !== 0) return;
    $f = ROOT . '/app/' . str_replace('\\', '/', substr($c, 4)) . '.php';
    if (is_file($f)) require $f;
});
require ROOT . '/app/Http.php';

use App\Config;
use App\DB;
use App\Importer;
use App\Security;

header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self' 'unsafe-inline'; img-src 'self' data:");

session_name('gg_install');
session_start(['cookie_httponly' => true, 'cookie_samesite' => 'Strict']);
$_SESSION['csrf'] ??= bin2hex(random_bytes(16));

$locked = is_file(LOCK);
$action = $_GET['action'] ?? '';

function out(array $d, int $code = 200): never
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($d, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function requirements(): array
{
    $w = fn($p) => is_dir(ROOT . $p) && is_writable(ROOT . $p);
    return [
        ['PHP 8.1 أو أحدث', version_compare(PHP_VERSION, '8.1.0', '>='), PHP_VERSION, true],
        ['PDO MySQL', extension_loaded('pdo_mysql'), '', true],
        ['GD (معالجة الصور)', extension_loaded('gd'), '', true],
        ['mbstring', extension_loaded('mbstring'), '', true],
        ['JSON', extension_loaded('json'), '', true],
        ['cURL (استيراد صور من روابط)', extension_loaded('curl'), '', false],
        ['OPcache (أداء)', extension_loaded('Zend OPcache'), '', false],
        ['APCu أو Redis (كاش سريع)', extension_loaded('apcu') || extension_loaded('redis'), extension_loaded('redis') ? 'redis' : (extension_loaded('apcu') ? 'apcu' : 'file cache'), false],
        ['مجلد config قابل للكتابة', $w('/config'), '/config', true],
        ['مجلد storage قابل للكتابة', $w('/storage') && $w('/storage/cache') && $w('/storage/logs'), '/storage', true],
        ['مجلد uploads قابل للكتابة', $w('/uploads') && $w('/uploads/equipment'), '/uploads', true],
        ['ملفات البيانات والصور', is_file(__DIR__ . '/seed/data.json') && is_dir(__DIR__ . '/seed/images'), 'install/seed', true],
    ];
}

function dbCfg(array $in): array
{
    return [
        'host' => trim((string)($in['db_host'] ?? 'localhost')) ?: 'localhost',
        'port' => (int)($in['db_port'] ?? 3306) ?: 3306,
        'name' => trim((string)($in['db_name'] ?? '')),
        'user' => trim((string)($in['db_user'] ?? '')),
        'pass' => (string)($in['db_pass'] ?? ''),
    ];
}

function replicas(string $txt): array
{
    $out = [];
    foreach (preg_split('/\r\n|\n/', $txt) as $line) {
        $line = trim($line);
        if ($line === '') continue;
        // الصيغ: host   |  host:port   |  user:pass@host:port
        $r = [];
        if (str_contains($line, '@')) {
            [$cred, $line] = explode('@', $line, 2);
            [$r['user'], $r['pass']] = array_pad(explode(':', $cred, 2), 2, '');
        }
        [$r['host'], $port] = array_pad(explode(':', $line, 2), 2, '3306');
        $r['port'] = (int)$port ?: 3306;
        if (preg_match('/^[\w.\-]+$/', $r['host'])) $out[] = $r;
    }
    return $out;
}

function ensureDb(array $c, array $in): void
{
    if (!preg_match('/^[\w\-]{1,64}$/', $c['name'])) throw new RuntimeException('اسم قاعدة البيانات غير صالح');
    if (empty($in['create_db'])) return;
    $pdo = new PDO("mysql:host={$c['host']};port={$c['port']};charset=utf8mb4", $c['user'], $c['pass'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 5]);
    $pdo->exec("CREATE DATABASE IF NOT EXISTS `{$c['name']}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
}

if ($action !== '') {
    if ($locked) out(['ok' => false, 'error' => 'تم التنصيب مسبقاً. احذف config/install.lock لإعادة التنصيب.'], 403);
    $in = json_decode(file_get_contents('php://input') ?: '[]', true) ?: [];
    if (!hash_equals($_SESSION['csrf'], (string)($in['csrf'] ?? ''))) out(['ok' => false, 'error' => 'انتهت الجلسة، حدّث الصفحة'], 419);

    if ($action === 'test') {
        $c = dbCfg($in);
        try {
            ensureDb($c, $in);
            $pdo = DB::connect($c);
            $ver = $pdo->query('SELECT VERSION()')->fetchColumn();
            $tables = (int)$pdo->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()')->fetchColumn();
            $reps = [];
            foreach (replicas((string)($in['replicas'] ?? '')) as $r) {
                try { DB::connect(array_merge($c, $r)); $reps[] = [$r['host'], true]; }
                catch (Throwable $e) { $reps[] = [$r['host'], false]; }
            }
            out(['ok' => true, 'version' => $ver, 'tables' => $tables, 'replicas' => $reps]);
        } catch (Throwable $e) {
            out(['ok' => false, 'error' => 'تعذر الاتصال: ' . preg_replace('/\s+/', ' ', $e->getMessage())]);
        }
    }

    if ($action === 'install') {
        @set_time_limit(600);
        foreach (requirements() as $r) if ($r[3] && !$r[1]) out(['ok' => false, 'error' => 'متطلب ناقص: ' . $r[0]]);

        $c = dbCfg($in);
        $adminName = trim((string)($in['admin_name'] ?? ''));
        $adminEmail = strtolower(trim((string)($in['admin_email'] ?? '')));
        $adminPass = (string)($in['admin_pass'] ?? '');
        $url = rtrim(trim((string)($in['site_url'] ?? '')), '/');
        if (!filter_var($adminEmail, FILTER_VALIDATE_EMAIL)) out(['ok' => false, 'error' => 'بريد المدير غير صالح']);
        if (mb_strlen($adminPass) < 10 || !preg_match('/\d/', $adminPass) || !preg_match('/[A-Za-z]/', $adminPass)) out(['ok' => false, 'error' => 'كلمة مرور المدير: 10 أحرف على الأقل، حروف إنجليزية وأرقام']);
        if ($url !== '' && !filter_var($url, FILTER_VALIDATE_URL)) out(['ok' => false, 'error' => 'رابط الموقع غير صالح']);

        $config = [
            'app' => [
                'name' => 'Ghani Group Rental',
                'url' => $url,
                'env' => 'production',
                'key' => bin2hex(random_bytes(32)),
                'timezone' => 'Asia/Baghdad',
            ],
            'db' => [
                'primary' => $c,
                'replicas' => replicas((string)($in['replicas'] ?? '')),
                'sticky_seconds' => 5,
                'persistent' => false,
            ],
            'cache' => [
                'driver' => 'auto',
                'prefix' => 'gg_' . substr(md5($c['name'] . $c['host']), 0, 6) . ':',
                'redis' => ['host' => trim((string)($in['redis_host'] ?? '')), 'port' => 6379, 'password' => '', 'db' => 0],
            ],
            'security' => [
                'force_https' => !empty($in['force_https']),
                'trusted_proxies' => [],
                'cors_origins' => [],
                'token_ttl_days' => 30,
                // [عدد الطلبات, خلال ثوانٍ]
                'rate' => ['api' => [300, 60], 'write' => [60, 60], 'auth' => [10, 300], 'orders' => [8, 600], 'upload' => [60, 600]],
            ],
            'uploads' => ['max_mb' => 5],
        ];
        Config::set($config);

        $log = [];
        try {
            ensureDb($c, $in);
            $pdo = DB::primary();
            $log[] = 'تم الاتصال بقاعدة البيانات (' . $pdo->query('SELECT VERSION()')->fetchColumn() . ')';

            // 1) الجداول
            $sql = file_get_contents(__DIR__ . '/schema.sql');
            foreach (array_filter(array_map('trim', preg_split('/;\s*[\r\n]+/', preg_replace('/^--.*$/m', '', $sql)))) as $stmt) {
                $pdo->exec($stmt);
            }
            $pdo->exec("INSERT IGNORE INTO migrations (version) VALUES ('" . SCHEMA_VERSION . "')");
            $log[] = 'تم إنشاء ' . (int)$pdo->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()')->fetchColumn() . ' جدول';

            // 2) ترحيل البيانات من الكود إلى القاعدة (الأقسام، المعدات، الباقات، الإعدادات + الصور)
            $data = json_decode(file_get_contents(__DIR__ . '/seed/data.json'), true);
            if (!empty($in['company_name'])) $data['settings']['company_name'] = mb_substr(trim((string)$in['company_name']), 0, 100);
            if (!empty($in['whatsapp'])) $data['settings']['whatsapp'] = preg_replace('/\D/', '', (string)$in['whatsapp']);
            $data['settings']['currency'] ??= 'IQD';
            $report = (new Importer(__DIR__ . '/seed/images'))->run($data);
            $log[] = "ترحيل البيانات: {$report['categories']} قسم، {$report['equipment']} معدة، {$report['kits']} باقة، {$report['images']} صورة، {$report['settings']} إعداد";
            foreach (array_slice($report['errors'], 0, 10) as $e) $log[] = '⚠ ' . $e;

            // ترحيلات القاعدة (الأدوار، البنرات، الماركات، الإشعارات، محاضر التسليم)
            $mig = App\Migrator::run();
            @file_put_contents(ROOT . '/storage/schema.version', App\Migrator::LATEST);
            $log[] = 'ترقية القاعدة: ' . ($mig ? implode('، ', $mig) : 'محدّثة');

            // 3) حساب المدير
            $hash = Security::hashPassword($adminPass);
            $exists = DB::oneW('SELECT id FROM users WHERE email = ?', [$adminEmail]);
            if ($exists) DB::update('users', ['password_hash' => $hash, 'role' => 'admin', 'status' => 'active', 'name' => $adminName ?: 'Admin'], 'id = :id', ['id' => $exists['id']]);
            else DB::insert('users', ['name' => $adminName ?: 'Admin', 'email' => $adminEmail, 'password_hash' => $hash, 'role' => 'admin']);
            $log[] = 'تم إنشاء حساب المدير: ' . $adminEmail;

            // 4) ملف الإعدادات + القفل
            $php = "<?php\n// Generated by installer " . date('Y-m-d H:i') . " — لا تشارك هذا الملف\nreturn " . var_export($config, true) . ";\n";
            if (file_put_contents(ROOT . '/config/config.php', $php, LOCK_EX) === false) throw new RuntimeException('تعذرت كتابة config/config.php');
            @chmod(ROOT . '/config/config.php', 0640);
            file_put_contents(LOCK, date('c'));
            $log[] = 'تم حفظ الإعدادات وقفل معالج التنصيب';
            session_destroy();
            out(['ok' => true, 'log' => $log]);
        } catch (Throwable $e) {
            out(['ok' => false, 'error' => $e->getMessage(), 'log' => $log]);
        }
    }
    out(['ok' => false, 'error' => 'unknown action'], 400);
}

$req = requirements();
$reqOk = !array_filter($req, fn($r) => $r[3] && !$r[1]);
$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$guessUrl = $scheme . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . rtrim(dirname(dirname($_SERVER['SCRIPT_NAME'] ?? '/install/index.php')), '/');
$seed = json_decode(@file_get_contents(__DIR__ . '/seed/data.json') ?: '{}', true);
$h = fn($s) => htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>تنصيب Ghani Group Rental</title>
<link href="https://fonts.googleapis.com/css2?family=Alexandria:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{--bg:#F2F0EB;--sf:#fff;--ink:#141414;--mut:#85817A;--line:#E6E2DA;--red:#E8414E;--soft:#ECE9E2;--ok:#2C7A45;--okb:#E3F1E6;--warn:#A26A09;--warnb:#FBEFD9}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Alexandria',system-ui,sans-serif;background:var(--bg);color:var(--ink);min-height:100vh;padding:40px 16px}
.wrap{max-width:720px;margin:0 auto}
.brand{display:flex;align-items:center;gap:12px;margin-bottom:28px}
.brand svg{width:30px}
.brand b{font-size:17px;font-weight:600}
.brand span{color:var(--mut);font-size:13px;margin-right:auto}
.steps{display:flex;gap:6px;margin-bottom:22px}
.steps div{flex:1;height:4px;border-radius:4px;background:var(--line);transition:.3s}
.steps div.on{background:var(--ink)}
.card{background:var(--sf);border-radius:28px;padding:30px}
h1{font-size:26px;font-weight:600;letter-spacing:-.3px}
.sub{color:var(--mut);font-size:14px;margin:8px 0 24px;line-height:1.8}
.req{display:grid;gap:2px}
.req div{display:flex;justify-content:space-between;align-items:center;padding:12px 0;border-bottom:1px solid var(--line);font-size:14px}
.req small{color:var(--mut);direction:ltr;margin-left:10px;font-size:12px}
.b{font-size:11.5px;font-weight:600;padding:4px 10px;border-radius:20px}
.b.ok{background:var(--okb);color:var(--ok)}.b.no{background:#FBE3E5;color:var(--red)}.b.wa{background:var(--warnb);color:var(--warn)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.f{display:flex;flex-direction:column;gap:6px;margin-bottom:12px}
.f.full{grid-column:1/-1}
label{font-size:12.5px;color:var(--mut);font-weight:500}
input,textarea{font:inherit;font-size:14.5px;padding:13px 14px;border-radius:14px;border:1px solid var(--line);background:var(--bg);outline:none;transition:.2s;width:100%}
input:focus,textarea:focus{border-color:var(--ink);background:#fff}
input[dir=ltr],textarea[dir=ltr]{text-align:left}
.chk{display:flex;align-items:center;gap:10px;font-size:14px;margin:4px 0 14px;cursor:pointer}
.chk input{width:18px;height:18px;accent-color:var(--ink)}
.hint{font-size:12px;color:var(--mut);line-height:1.7}
.row{display:flex;gap:10px;justify-content:space-between;margin-top:22px}
button{font:inherit;cursor:pointer;border:0;height:52px;padding:0 26px;border-radius:16px;font-weight:600;font-size:15px;background:var(--ink);color:#fff;transition:.15s}
button:disabled{opacity:.4;cursor:not-allowed}
button.lt{background:var(--soft);color:var(--ink)}
button.red{background:var(--red)}
.msg{margin-top:14px;padding:13px 16px;border-radius:14px;font-size:13.5px;line-height:1.7;display:none}
.msg.ok{display:block;background:var(--okb);color:var(--ok)}.msg.no{display:block;background:#FBE3E5;color:var(--red)}
.st{display:none}.st.on{display:block;animation:in .35s}
@keyframes in{from{opacity:0;transform:translateY(8px)}}
.sum{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:6px 0 20px}
.sum div{background:var(--bg);border-radius:16px;padding:14px;text-align:center}
.sum b{font-size:22px;display:block}.sum small{color:var(--mut);font-size:11.5px}
.log{background:var(--ink);color:#d8d4cc;border-radius:18px;padding:18px;font-size:13px;line-height:2;max-height:320px;overflow:auto}
.log div::before{content:"✓ ";color:#7fd3a3}
.spin{width:44px;height:44px;border:3px solid var(--line);border-top-color:var(--ink);border-radius:50%;animation:sp 0.8s linear infinite;margin:30px auto}
@keyframes sp{to{transform:rotate(360deg)}}
.done a{display:inline-flex;align-items:center;justify-content:center;height:52px;padding:0 24px;border-radius:16px;font-weight:600;text-decoration:none;background:var(--ink);color:#fff}
.done a.lt{background:var(--soft);color:var(--ink)}
.warnbox{background:var(--warnb);color:var(--warn);padding:14px 16px;border-radius:14px;font-size:13px;line-height:1.8;margin-top:16px}
@media(max-width:600px){.grid{grid-template-columns:1fr}.sum{grid-template-columns:1fr 1fr}.card{padding:22px}}
</style>
</head>
<body>
<div class="wrap">
  <div class="brand"><svg viewBox="0 0 40 52"><path d="M2 2h18v9h-8v30h8V26h-5v-8h14v32H2z" fill="#141414"/><rect x="32" y="2" width="6" height="48" fill="#E8414E"/></svg><b>Ghani Group Rental</b><span>معالج التنصيب · v<?= APP_VERSION ?></span></div>

<?php if ($locked): ?>
  <div class="card done">
    <h1>تم التنصيب مسبقاً</h1>
    <p class="sub">معالج التنصيب مقفل لحماية الموقع. لإعادة التنصيب احذف الملف <code>config/install.lock</code> من السيرفر.<br>يُنصح بحذف مجلد <code>install</code> بالكامل بعد التنصيب.</p>
    <div class="row" style="justify-content:flex-start"><a href="../">فتح الموقع</a><a class="lt" href="../admin">لوحة التحكم</a></div>
  </div>
<?php else: ?>
  <div class="steps"><div class="on"></div><div></div><div></div><div></div></div>
  <div class="card">
    <!-- 1 -->
    <section class="st on" data-s="1">
      <h1>أهلاً بك 👋</h1>
      <p class="sub">سيقوم المعالج بإنشاء قاعدة البيانات وترحيل كتالوج Ghani Group كاملاً (<?= count($seed['equipment'] ?? []) ?> معدة، <?= count($seed['categories'] ?? []) ?> أقسام، <?= count($seed['kits'] ?? []) ?> باقات مع الصور) ثم إنشاء حساب المدير.</p>
      <div class="req">
        <?php foreach ($req as [$name, $ok, $info, $must]): ?>
          <div><span><?= $h($name) ?><small><?= $h($info) ?></small></span><span class="b <?= $ok ? 'ok' : ($must ? 'no' : 'wa') ?>"><?= $ok ? 'متوفر' : ($must ? 'مطلوب' : 'اختياري') ?></span></div>
        <?php endforeach; ?>
      </div>
      <?php if (!$reqOk): ?><div class="msg no" style="display:block">أصلح المتطلبات المؤشّرة بالأحمر ثم حدّث الصفحة. صلاحيات المجلدات: <code dir="ltr">chmod -R 775 config storage uploads</code></div><?php endif; ?>
      <div class="row"><span></span><button onclick="go(2)" <?= $reqOk ? '' : 'disabled' ?>>التالي</button></div>
    </section>

    <!-- 2 -->
    <section class="st" data-s="2">
      <h1>قاعدة البيانات</h1>
      <p class="sub">MySQL 5.7+ أو MariaDB 10.3+. كل عمليات الكتابة تذهب للسيرفر الرئيسي، والقراءة توزَّع على سيرفرات القراءة إن أضفتها.</p>
      <div class="grid">
        <div class="f"><label>السيرفر</label><input id="db_host" value="localhost" dir="ltr"></div>
        <div class="f"><label>المنفذ</label><input id="db_port" value="3306" dir="ltr" inputmode="numeric"></div>
        <div class="f"><label>اسم القاعدة</label><input id="db_name" placeholder="ghani_rental" dir="ltr"></div>
        <div class="f"><label>المستخدم</label><input id="db_user" dir="ltr" autocomplete="off"></div>
        <div class="f full"><label>كلمة المرور</label><input id="db_pass" type="password" dir="ltr" autocomplete="new-password"></div>
      </div>
      <label class="chk"><input type="checkbox" id="create_db"> أنشئ القاعدة إن لم تكن موجودة</label>
      <div class="f"><label>سيرفرات القراءة — Read Replicas (اختياري، سطر لكل سيرفر)</label>
        <textarea id="replicas" rows="3" dir="ltr" placeholder="10.0.0.12:3306&#10;reader:pass@10.0.0.13:3306"></textarea>
        <span class="hint">اتركه فارغاً إذا عندك سيرفر قاعدة واحد. يمكن إضافتها لاحقاً من config/config.php.</span></div>
      <div class="msg" id="dbmsg"></div>
      <div class="row"><button class="lt" onclick="go(1)">رجوع</button><div style="display:flex;gap:8px"><button class="lt" onclick="test()">اختبار الاتصال</button><button id="dbnext" onclick="test(true)">التالي</button></div></div>
    </section>

    <!-- 3 -->
    <section class="st" data-s="3">
      <h1>الموقع والمدير</h1>
      <p class="sub">سيتم إنشاء حساب مدير بصلاحيات كاملة للوحة التحكم.</p>
      <div class="grid">
        <div class="f full"><label>رابط الموقع</label><input id="site_url" value="<?= $h($guessUrl) ?>" dir="ltr"></div>
        <div class="f"><label>اسم الشركة</label><input id="company_name" value="Ghani Group"></div>
        <div class="f"><label>رقم واتساب الطلبات</label><input id="whatsapp" value="<?= $h($seed['settings']['whatsapp'] ?? '') ?>" dir="ltr"></div>
        <div class="f"><label>اسم المدير</label><input id="admin_name" placeholder="الاسم"></div>
        <div class="f"><label>بريد المدير</label><input id="admin_email" type="email" dir="ltr"></div>
        <div class="f full"><label>كلمة مرور المدير</label><input id="admin_pass" type="password" dir="ltr" autocomplete="new-password"><span class="hint">10 أحرف على الأقل، تحتوي حروفاً إنجليزية وأرقاماً.</span></div>
        <div class="f full"><label>Redis (اختياري — للكاش المشترك بين عدة سيرفرات ويب)</label><input id="redis_host" placeholder="127.0.0.1" dir="ltr"></div>
      </div>
      <label class="chk"><input type="checkbox" id="force_https"> إجبار HTTPS (فعّله إذا عندك شهادة SSL)</label>
      <div class="msg" id="admsg"></div>
      <div class="row"><button class="lt" onclick="go(2)">رجوع</button><button class="red" onclick="install()">ابدأ التنصيب وترحيل البيانات</button></div>
    </section>

    <!-- 4 -->
    <section class="st" data-s="4">
      <div id="working"><h1>جاري التنصيب…</h1><p class="sub">إنشاء الجداول وترحيل المعدات والصور. لا تغلق الصفحة.</p><div class="spin"></div></div>
      <div id="result" style="display:none" class="done">
        <h1 id="rt">تم التنصيب بنجاح 🎉</h1>
        <p class="sub" id="rs">كل البيانات صارت في قاعدة البيانات. سجّل الدخول للوحة التحكم ببيانات المدير.</p>
        <div class="log" id="log"></div>
        <div class="warnbox">للأمان: احذف مجلد <b>install</b> من السيرفر الآن. المعالج مقفل تلقائياً، لكن حذفه أفضل.</div>
        <div class="row" style="justify-content:flex-start"><a href="../admin">لوحة التحكم</a><a class="lt" href="../">فتح الموقع</a></div>
      </div>
    </section>
  </div>
<?php endif; ?>
</div>
<script>
const CSRF = <?= json_encode($_SESSION['csrf']) ?>;
const $ = id => document.getElementById(id);
function go(n){
  document.querySelectorAll('.st').forEach(s => s.classList.toggle('on', s.dataset.s == n));
  document.querySelectorAll('.steps div').forEach((d, i) => d.classList.toggle('on', i < n));
}
function vals(ids){ const o = {csrf: CSRF}; ids.forEach(i => { const e = $(i); o[i] = e.type === 'checkbox' ? e.checked : e.value; }); return o; }
const DB = ['db_host','db_port','db_name','db_user','db_pass','create_db','replicas'];
async function call(action, body){
  const r = await fetch('?action=' + action, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  try { return await r.json(); } catch(e){ return {ok:false, error:'استجابة غير متوقعة من السيرفر (' + r.status + ')'}; }
}
function msg(el, ok, text){ el.className = 'msg ' + (ok ? 'ok' : 'no'); el.textContent = text; }
async function test(next){
  const m = $('dbmsg'); msg(m, true, 'جاري الاختبار…');
  const r = await call('test', vals(DB));
  if (!r.ok) return msg(m, false, r.error);
  let t = 'تم الاتصال ✓  ' + r.version + (r.tables ? ' — تحتوي ' + r.tables + ' جدول (سيتم تحديثها دون حذف)' : '');
  if (r.replicas.length) t += ' | سيرفرات القراءة: ' + r.replicas.map(x => x[0] + (x[1] ? ' ✓' : ' ✗')).join('، ');
  msg(m, true, t);
  if (next) setTimeout(() => go(3), 400);
}
async function install(){
  const m = $('admsg');
  if (!$('admin_email').value || $('admin_pass').value.length < 10) return msg(m, false, 'أدخل بريد المدير وكلمة مرور (10 أحرف على الأقل)');
  go(4);
  const r = await call('install', vals([...DB, 'site_url','company_name','whatsapp','admin_name','admin_email','admin_pass','redis_host','force_https']));
  $('working').style.display = 'none'; $('result').style.display = 'block';
  const log = $('log'); log.innerHTML = '';
  (r.log || []).forEach(l => { const d = document.createElement('div'); d.textContent = l; log.appendChild(d); });
  if (!r.ok){
    $('rt').textContent = 'تعذر إكمال التنصيب'; $('rs').textContent = r.error || 'خطأ غير معروف';
    const b = document.createElement('button'); b.textContent = 'رجوع وتعديل'; b.className = 'lt'; b.onclick = () => go(3);
    document.querySelector('#result .row').replaceChildren(b);
    document.querySelector('.warnbox').style.display = 'none';
  }
}
</script>
</body>
</html>
