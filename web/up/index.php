<?php
declare(strict_types=1);

/*
 * Ghani Group — مُحدِّث الموقع
 * ضع هذا المجلد (up) داخل مجلد الموقع، وضع ملف التحديث (zip) بداخله، ثم افتح:  https://موقعك/up/
 *
 * ما يفعله:
 *  1) يتحقق أنك المدير (البريد وكلمة المرور من قاعدة البيانات)
 *  2) يعرض الإصدار الحالي والجديد وعدد الملفات التي ستتغير
 *  3) يأخذ نسخة احتياطية من كل ملف سيُستبدل ← storage/backups/
 *  4) يستبدل ملفات البرنامج فقط. لا يلمس أبداً: config/ (إعدادات القاعدة)، storage/، uploads/ (الصور)
 *     ولا يحذف أي ملف موجود
 *  5) يرقّي قاعدة البيانات (جداول جديدة فقط، بدون حذف بيانات) ويمسح الكاش
 *  6) زر استرجاع النسخة السابقة إذا احتجت
 */

$ROOT = dirname(__DIR__);
const PROTECTED_DIRS = ['config/', 'storage/', 'uploads/', 'up/'];
const ALLOWED_EXT = ['php', 'js', 'css', 'html', 'htm', 'json', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'ico', 'woff', 'woff2', 'ttf', 'txt', 'md', 'webmanifest', 'sql', 'example', 'xml', 'csv', 'htaccess', 'gitkeep'];

header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; form-action 'self'");
session_name('gg_updater');
session_start(['cookie_httponly' => true, 'cookie_samesite' => 'Strict']);
$_SESSION['csrf'] ??= bin2hex(random_bytes(16));
@set_time_limit(300);

$h = fn($s) => htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
$msg = []; $err = [];

// ---------------------------------------------------------------- أدوات
function cfg(string $root): ?array
{
    $f = $root . '/config/config.php';
    if (!is_file($f)) return null;
    $c = include $f;
    return is_array($c) ? $c : null;
}

function pdo(array $c): PDO
{
    $p = $c['db']['primary'];
    return new PDO("mysql:host={$p['host']};port=" . ($p['port'] ?? 3306) . ";dbname={$p['name']};charset=utf8mb4", $p['user'], $p['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC, PDO::ATTR_TIMEOUT => 5,
    ]);
}

function versionOf(string $bootstrapCode): string
{
    return preg_match("/APP_VERSION',\s*'([^']+)'/", $bootstrapCode, $m) ? $m[1] : '؟';
}

function packages(): array
{
    $z = glob(__DIR__ . '/*.zip') ?: [];
    usort($z, fn($a, $b) => filemtime($b) <=> filemtime($a));
    return $z;
}

/** يقرأ الحزمة: [مسار نسبي => محتوى]، ويتجاهل مجلداً رئيسياً واحداً إن وُجد */
function readPackage(string $zip): array
{
    if (!class_exists('ZipArchive')) throw new RuntimeException('إضافة PHP zip غير مفعّلة على الاستضافة — فعّلها من cPanel ← Select PHP Version ← Extensions');
    $za = new ZipArchive();
    if ($za->open($zip) !== true) throw new RuntimeException('تعذر فتح ملف التحديث — تأكد أنه رُفع كاملاً');
    $names = [];
    for ($i = 0; $i < $za->numFiles; $i++) $names[] = $za->getNameIndex($i);
    // إزالة مجلد أعلى مشترك (لو كان الملف مضغوطاً مع مجلد)
    $prefix = '';
    $first = array_values(array_filter($names, fn($n) => !str_ends_with($n, '/')));
    if ($first && !in_array('index.php', $names, true)) {
        $top = explode('/', $first[0])[0] . '/';
        if (count(array_filter($first, fn($n) => str_starts_with($n, $top))) === count($first) && in_array($top . 'index.php', $names, true)) $prefix = $top;
    }
    $files = [];
    foreach ($names as $i => $n) {
        if (str_ends_with($n, '/')) continue;
        $rel = substr($n, strlen($prefix));
        if ($rel === '' || str_contains($rel, '..') || str_starts_with($rel, '/') || str_contains($rel, "\0") || str_contains($rel, '\\')) {
            throw new RuntimeException('ملف التحديث يحتوي مسارات غير آمنة: ' . $n);
        }
        if (str_starts_with($rel, '__MACOSX/') || basename($rel) === '.DS_Store') continue;
        $base = basename($rel);
        $ext = str_starts_with($base, '.') ? ltrim($base, '.') : strtolower(pathinfo($rel, PATHINFO_EXTENSION));
        if (!in_array($ext, ALLOWED_EXT, true)) continue;
        $files[$rel] = $za->getFromName($n);
    }
    $za->close();
    if (!isset($files['index.php'], $files['app/bootstrap.php'])) throw new RuntimeException('هذا ليس ملف تحديث موقع Ghani Group (لا يحتوي index.php و app/bootstrap.php)');
    return $files;
}

function isProtected(string $rel): bool
{
    foreach (PROTECTED_DIRS as $d) if (str_starts_with($rel, $d)) return true;
    return false;
}

/** خطة التحديث: الملفات الجديدة، المتغيرة، المحمية */
function plan(string $root, array $files): array
{
    $p = ['new' => [], 'changed' => [], 'same' => 0, 'protected' => [], 'mkdirs' => []];
    foreach ($files as $rel => $data) {
        if (isProtected($rel)) {
            // مجلدات جديدة داخل uploads/storage تُنشأ فقط (بدون استبدال أي ملف)
            $dir = dirname($rel);
            if (!is_dir("$root/$dir") && preg_match('#^(uploads|storage)/#', $rel)) $p['mkdirs'][] = $dir;
            $p['protected'][] = $rel;
            continue;
        }
        $abs = "$root/$rel";
        if (!is_file($abs)) $p['new'][] = $rel;
        elseif (hash('sha256', (string)file_get_contents($abs)) !== hash('sha256', $data)) $p['changed'][] = $rel;
        else $p['same']++;
    }
    $p['mkdirs'] = array_values(array_unique($p['mkdirs']));
    return $p;
}

function writeAtomic(string $abs, string $data): void
{
    $dir = dirname($abs);
    if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) throw new RuntimeException("تعذر إنشاء المجلد $dir");
    $tmp = $abs . '.tmp-' . bin2hex(random_bytes(4));
    if (file_put_contents($tmp, $data, LOCK_EX) === false) throw new RuntimeException("تعذرت الكتابة: $abs — تحقق من صلاحيات المجلد");
    @chmod($tmp, 0644);
    if (!rename($tmp, $abs)) { @unlink($tmp); throw new RuntimeException("تعذر استبدال $abs"); }
}

function clearCaches(string $root): int
{
    $n = 0;
    foreach (glob("$root/storage/cache/*") ?: [] as $f) {
        if (is_file($f) && basename($f) !== '.gitkeep') { @unlink($f); $n++; }
    }
    @unlink("$root/storage/schema.version");
    if (function_exists('opcache_reset')) @opcache_reset();
    if (function_exists('apcu_clear_cache')) @apcu_clear_cache();
    return $n;
}

/** ترقية القاعدة بالكود الجديد (جداول وأعمدة جديدة فقط) */
function migrate(string $root): array
{
    if (!is_file("$root/app/Migrator.php")) return [];
    $boot = function () use ($root) {
        require "$root/app/bootstrap.php";
        if (!class_exists('App\\Migrator')) return [];
        $applied = App\Migrator::run();
        @file_put_contents("$root/storage/schema.version", App\Migrator::LATEST);
        return $applied;
    };
    $r = $boot();
    restore_error_handler();
    restore_exception_handler();
    return $r;
}

function backups(string $root): array
{
    $b = glob("$root/storage/backups/*.zip") ?: [];
    usort($b, fn($a, $c) => filemtime($c) <=> filemtime($a));
    return $b;
}

// ---------------------------------------------------------------- المصادقة
$config = cfg($ROOT);
if (!$config) { $err[] = 'لم أجد config/config.php — هذا المجلد يجب أن يكون داخل مجلد موقع Ghani Group المنصّب.'; }
$authed = !empty($_SESSION['admin']);
$post = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($post && !hash_equals($_SESSION['csrf'], (string)($_POST['csrf'] ?? ''))) { $err[] = 'انتهت الجلسة، أعد المحاولة.'; $post = false; }

if ($config && $post && ($_POST['do'] ?? '') === 'login') {
    $_SESSION['tries'] = ($_SESSION['tries'] ?? 0) + 1;
    if ($_SESSION['tries'] > 8) { $err[] = 'محاولات كثيرة — أغلق المتصفح وحاول لاحقاً.'; }
    else {
        try {
            $u = pdo($config)->prepare("SELECT id, name, password_hash FROM users WHERE email = ? AND role = 'admin' AND status = 'active' LIMIT 1");
            $u->execute([strtolower(trim((string)($_POST['email'] ?? '')))]);
            $row = $u->fetch();
            if ($row && password_verify((string)($_POST['password'] ?? ''), $row['password_hash'])) {
                session_regenerate_id(true);
                $_SESSION['admin'] = $row['name']; $_SESSION['tries'] = 0; $authed = true;
            } else { usleep(800000); $err[] = 'البريد أو كلمة المرور غير صحيحة (حساب مدير فقط).'; }
        } catch (Throwable $e) { $err[] = 'تعذر الاتصال بقاعدة البيانات: ' . $e->getMessage(); }
    }
}
if ($post && ($_POST['do'] ?? '') === 'logout') { $_SESSION = []; session_destroy(); header('Location: ./'); exit; }

// ---------------------------------------------------------------- العمليات
$currentVer = is_file("$ROOT/app/bootstrap.php") ? versionOf((string)file_get_contents("$ROOT/app/bootstrap.php")) : '؟';
$pkgs = packages();
$pkg = $pkgs[0] ?? null;
$files = null; $planned = null; $pkgVer = null;

if ($authed && $config && $pkg) {
    try {
        $files = readPackage($pkg);
        $pkgVer = versionOf($files['app/bootstrap.php']);
        $planned = plan($ROOT, $files);
    } catch (Throwable $e) { $err[] = $e->getMessage(); }
}

if ($authed && $post && ($_POST['do'] ?? '') === 'apply' && $files && $planned) {
    $toWrite = array_merge($planned['new'], $planned['changed']);
    try {
        // 1) نسخة احتياطية للملفات التي ستُستبدل
        $bdir = "$ROOT/storage/backups";
        if (!is_dir($bdir)) mkdir($bdir, 0750, true);
        @file_put_contents("$bdir/.htaccess", "Require all denied\n");
        $bname = 'backup-' . preg_replace('/[^0-9.]/', '', $currentVer) . '-' . date('Ymd-His') . '.zip';
        $za = new ZipArchive();
        if ($za->open("$bdir/$bname", ZipArchive::CREATE) !== true) throw new RuntimeException('تعذر إنشاء النسخة الاحتياطية في storage/backups');
        foreach ($planned['changed'] as $rel) $za->addFile("$ROOT/$rel", $rel);
        $za->addFromString('_new_files.json', json_encode($planned['new'], JSON_UNESCAPED_UNICODE));
        $za->addFromString('_info.json', json_encode(['from' => $currentVer, 'to' => $pkgVer, 'at' => date('c')]));
        $za->close();
        $msg[] = 'نسخة احتياطية: storage/backups/' . $bname . ' (' . count($planned['changed']) . ' ملف)';

        // 2) كتابة الملفات (index.php أخيراً حتى يبقى الموقع متسقاً أثناء التحديث)
        usort($toWrite, fn($a, $b) => ($a === 'index.php') <=> ($b === 'index.php'));
        foreach ($toWrite as $rel) writeAtomic("$ROOT/$rel", $files[$rel]);
        foreach ($planned['mkdirs'] as $d) { @mkdir("$ROOT/$d", 0755, true); }
        $msg[] = 'تم تحديث ' . count($planned['changed']) . ' ملف وإضافة ' . count($planned['new']) . ' ملف جديد.';

        // 3) الكاش + القاعدة
        $msg[] = 'تم مسح ' . clearCaches($ROOT) . ' ملف كاش.';
        try {
            $mig = migrate($ROOT);
            $msg[] = $mig ? 'ترقية قاعدة البيانات: ' . implode('، ', $mig) : 'قاعدة البيانات محدّثة مسبقاً.';
        } catch (Throwable $e) {
            $msg[] = 'ستكتمل ترقية القاعدة تلقائياً عند أول فتح للموقع (' . $e->getMessage() . ')';
        }
        @rename($pkg, $pkg . '.applied');
        $msg[] = '✓ اكتمل التحديث إلى الإصدار ' . $pkgVer;
        $_SESSION['done'] = $msg;
        header('Location: ./?ok=1'); exit;
    } catch (Throwable $e) {
        $err[] = 'توقف التحديث: ' . $e->getMessage() . ' — يمكنك استرجاع النسخة الاحتياطية من الأسفل.';
    }
}

if ($authed && $post && ($_POST['do'] ?? '') === 'rollback') {
    $name = basename((string)($_POST['backup'] ?? ''));
    $file = "$ROOT/storage/backups/$name";
    try {
        if (!preg_match('/^backup-[0-9.]*-\d{8}-\d{6}\.zip$/', $name) || !is_file($file)) throw new RuntimeException('النسخة غير موجودة');
        $za = new ZipArchive(); $za->open($file);
        $n = 0;
        for ($i = 0; $i < $za->numFiles; $i++) {
            $rel = $za->getNameIndex($i);
            if ($rel[0] === '_' || str_contains($rel, '..') || isProtected($rel)) continue;
            writeAtomic("$ROOT/$rel", (string)$za->getFromIndex($i)); $n++;
        }
        $za->close();
        clearCaches($ROOT);
        $_SESSION['done'] = ["تم استرجاع $n ملف من $name. (الجداول الجديدة في القاعدة تبقى ولا تؤثر على النسخة القديمة)"];
        header('Location: ./?ok=1'); exit;
    } catch (Throwable $e) { $err[] = 'تعذر الاسترجاع: ' . $e->getMessage(); }
}

if (isset($_GET['ok']) && !empty($_SESSION['done'])) { $msg = $_SESSION['done']; unset($_SESSION['done']); $currentVer = versionOf((string)file_get_contents("$ROOT/app/bootstrap.php")); }
$reqs = [
    ['PHP 8.1+', version_compare(PHP_VERSION, '8.1.0', '>='), PHP_VERSION],
    ['إضافة zip', class_exists('ZipArchive'), ''],
    ['صلاحية الكتابة على ملفات الموقع', is_writable("$ROOT/app") && is_writable("$ROOT/assets"), ''],
    ['صلاحية الكتابة على storage', is_writable("$ROOT/storage"), ''],
];
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>تحديث الموقع — Ghani Group</title>
<style>
:root{--bg:#F2F0EB;--sf:#fff;--ink:#141414;--mut:#85817A;--line:#E6E2DA;--red:#B82619;--ok:#2C7A45;--okb:#E3F1E6;--warn:#A26A09;--warnb:#FBEFD9;--redb:#FBE3E5}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,'Segoe UI',Tahoma,sans-serif;background:var(--bg);color:var(--ink);min-height:100vh;padding:40px 16px}
.wrap{max-width:720px;margin:0 auto;display:grid;gap:14px}
.brand{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:6px}
.brand b{font-size:17px}.brand small{color:var(--mut);font-size:13px}
.card{background:var(--sf);border-radius:24px;padding:24px}
h1{font-size:24px;margin-bottom:6px}
.sub{color:var(--mut);font-size:14px;line-height:1.8}
.vers{display:grid;grid-template-columns:1fr auto 1fr;gap:12px;align-items:center;margin:18px 0}
.vers div{background:var(--bg);border-radius:18px;padding:16px;text-align:center}
.vers small{display:block;color:var(--mut);font-size:12px}.vers b{font-size:26px;direction:ltr;display:block}
.vers .new{background:var(--ink);color:#fff}.vers .new small{color:#aaa}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:16px}
.stats div{border:1px solid var(--line);border-radius:14px;padding:10px;text-align:center}.stats b{display:block;font-size:20px}.stats small{color:var(--mut);font-size:11.5px}
.alert{border-radius:14px;padding:12px 14px;font-size:13.5px;line-height:1.9}
.ok{background:var(--okb);color:var(--ok)}.warn{background:var(--warnb);color:var(--warn)}.bad{background:var(--redb);color:var(--red)}
label{display:block;font-size:12.5px;color:var(--mut);margin:12px 0 6px}
input{width:100%;font:inherit;font-size:15px;padding:13px 14px;border-radius:14px;border:1px solid var(--line);background:var(--bg);direction:ltr;text-align:left}
input:focus{outline:2px solid var(--ink);background:#fff}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;height:52px;padding:0 22px;border-radius:16px;border:0;background:var(--ink);color:#fff;font:inherit;font-size:15px;font-weight:600;cursor:pointer;width:100%;margin-top:16px}
.btn.lt{background:var(--sf);color:var(--ink);border:1px solid var(--line);height:40px;width:auto;margin:0;font-size:13px}
.btn:focus-visible{outline:3px solid var(--red);outline-offset:2px}
.req{display:grid;gap:4px;font-size:13.5px}.req div{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid var(--line)}
details{font-size:13px;margin-top:10px}summary{cursor:pointer;color:var(--mut)}
.list{max-height:220px;overflow:auto;direction:ltr;text-align:left;font:12px ui-monospace,monospace;background:var(--bg);border-radius:12px;padding:10px;margin-top:8px;line-height:1.8}
.row{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--line);font-size:13px}
.row:last-child{border:0}
code{direction:ltr;unicode-bidi:isolate;background:var(--bg);padding:2px 6px;border-radius:6px;font-size:12.5px}
@media (max-width:560px){.stats{grid-template-columns:1fr 1fr}.vers{grid-template-columns:1fr}.vers i{display:none}}
</style>
</head>
<body>
<div class="wrap">
  <div class="brand"><b>Ghani Group</b><small>مُحدِّث الموقع</small></div>

  <?php foreach ($err as $e): ?><div class="alert bad"><?= $h($e) ?></div><?php endforeach; ?>
  <?php if ($msg): ?><div class="alert ok"><?= implode('<br>', array_map($h, $msg)) ?></div>
    <div class="alert warn">للأمان: بعد ما تتأكد أن الموقع يعمل، احذف مجلد <code>up</code> من الاستضافة (أو أبقِه — لا يعمل إلا بحساب المدير).</div><?php endif; ?>

  <?php if (!$config): ?>
  <?php elseif (!$authed): ?>
    <form class="card" method="post" autocomplete="on">
      <h1>تحديث الموقع</h1>
      <p class="sub">سجّل الدخول بحساب <b>المدير</b> في لوحة التحكم للمتابعة.</p>
      <input type="hidden" name="csrf" value="<?= $h($_SESSION['csrf']) ?>"><input type="hidden" name="do" value="login">
      <label for="em">البريد الإلكتروني</label><input id="em" name="email" type="email" required autocomplete="username">
      <label for="pw">كلمة المرور</label><input id="pw" name="password" type="password" required autocomplete="current-password">
      <button class="btn">دخول</button>
    </form>
  <?php else: ?>
    <div class="card">
      <h1>تحديث الموقع</h1>
      <p class="sub">يستبدل ملفات البرنامج فقط. إعدادات القاعدة (<code>config</code>) والصور (<code>uploads</code>) والملفات الخاصة (<code>storage</code>) لا تُلمس، ولا يُحذف أي ملف، وتُحفظ نسخة احتياطية قبل أي تغيير.</p>
      <?php if (!$pkg): ?>
        <div class="alert warn" style="margin-top:14px">لا يوجد ملف تحديث. ارفع ملف التحديث (مثل <code>ghani-rental-v1.2.1.zip</code>) داخل هذا المجلد <code>up/</code> ثم حدّث الصفحة.</div>
      <?php elseif ($planned): ?>
        <div class="vers"><div><small>الإصدار الحالي</small><b><?= $h($currentVer) ?></b></div><i>←</i><div class="new"><small>الإصدار الجديد</small><b><?= $h($pkgVer) ?></b></div></div>
        <div class="stats">
          <div><b><?= count($planned['changed']) ?></b><small>ملف سيُحدَّث</small></div>
          <div><b><?= count($planned['new']) ?></b><small>ملف جديد</small></div>
          <div><b><?= $planned['same'] ?></b><small>بدون تغيير</small></div>
          <div><b><?= count($planned['protected']) ?></b><small>محمي (لن يُلمس)</small></div>
        </div>
        <?php if (version_compare((string)$pkgVer, (string)$currentVer, '<')): ?><div class="alert warn">تنبيه: ملف التحديث أقدم من الإصدار الحالي.</div><?php endif; ?>
        <div class="req"><?php foreach ($reqs as [$n, $ok, $v]): ?><div><span><?= $h($n) ?> <small style="color:var(--mut)"><?= $h($v) ?></small></span><span style="color:var(<?= $ok ? '--ok' : '--red' ?>)"><?= $ok ? '✓' : '✗' ?></span></div><?php endforeach; ?></div>
        <details><summary>عرض الملفات التي ستتغير</summary><div class="list"><?= implode('<br>', array_map(fn($f) => '~ ' . $h($f), $planned['changed'])) ?><?= $planned['new'] ? '<br>' . implode('<br>', array_map(fn($f) => '+ ' . $h($f), $planned['new'])) : '' ?></div></details>
        <?php if (!$planned['changed'] && !$planned['new']): ?>
          <div class="alert ok" style="margin-top:14px">الموقع محدّث — لا يوجد شيء لتغييره.</div>
        <?php else: ?>
        <form method="post" onsubmit="this.querySelector('button').disabled=true;this.querySelector('button').textContent='جاري التحديث… لا تغلق الصفحة'">
          <input type="hidden" name="csrf" value="<?= $h($_SESSION['csrf']) ?>"><input type="hidden" name="do" value="apply">
          <button class="btn" <?= array_filter($reqs, fn($r) => !$r[1]) ? 'disabled' : '' ?>>تحديث الآن إلى <?= $h($pkgVer) ?></button>
        </form>
        <?php endif; ?>
      <?php endif; ?>
    </div>

    <?php $bk = backups($ROOT); if ($bk): ?>
    <div class="card">
      <h1 style="font-size:18px">النسخ الاحتياطية</h1>
      <p class="sub">لإرجاع ملفات الموقع كما كانت قبل تحديث معيّن.</p>
      <?php foreach (array_slice($bk, 0, 6) as $b): ?>
        <form class="row" method="post" onsubmit="return confirm('استرجاع هذه النسخة؟')">
          <span><code><?= $h(basename($b)) ?></code> <small style="color:var(--mut)"><?= round(filesize($b) / 1024) ?> KB</small></span>
          <input type="hidden" name="csrf" value="<?= $h($_SESSION['csrf']) ?>"><input type="hidden" name="do" value="rollback"><input type="hidden" name="backup" value="<?= $h(basename($b)) ?>">
          <button class="btn lt">استرجاع</button>
        </form>
      <?php endforeach; ?>
    </div>
    <?php endif; ?>

    <form method="post" style="text-align:center"><input type="hidden" name="csrf" value="<?= $h($_SESSION['csrf']) ?>"><input type="hidden" name="do" value="logout"><button class="btn lt">خروج (<?= $h($_SESSION['admin']) ?>)</button></form>
  <?php endif; ?>
</div>
</body>
</html>
