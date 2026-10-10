<?php
declare(strict_types=1);

namespace App\Controllers;

use App\Auth;
use App\Cache;
use App\DB;
use App\HttpError;
use App\Log;
use App\Request;
use App\Response;
use App\Security;
use App\Validator;

final class AuthController
{
    private const MAX_FAILS = 5;
    private const LOCK_MINUTES = 15;

    /** هل الطلب قادم من موقع الويب (يريد كوكي) أم من تطبيق (يريد توكن)؟ */
    private function wantsCookie(Request $r): bool
    {
        return ($r->header('X-Client') ?? '') === 'web';
    }

    private function present(array $u): array
    {
        return [
            'id' => (int)$u['id'], 'name' => $u['name'], 'email' => $u['email'],
            'phone' => $u['phone'], 'company' => $u['company'], 'role' => $u['role'],
        ] + (in_array($u['role'], Auth::PANEL_ROLES, true) ? ['perms' => Auth::perms($u)] : []);
    }

    public function register(Request $r): void
    {
        Security::throttle('auth', 'reg:' . $r->ip());
        $d = Validator::check($r->input(), [
            'name' => 'required|string|min:2|max:120',
            'email' => 'required|email|max:190',
            'phone' => 'required|phone',
            'company' => 'string|max:150',
            'password' => 'required|string|min:8|max:200',
        ]);
        if (!Security::passwordStrong($d['password'])) {
            throw new HttpError(422, 'validation', 'كلمة المرور ضعيفة', ['password' => '8 أحرف على الأقل وتحتوي حروفاً وأرقاماً']);
        }
        if (DB::oneW('SELECT id FROM users WHERE email = ?', [$d['email']])) {
            throw new HttpError(409, 'exists', 'البريد مسجل مسبقاً', ['email' => 'مسجل مسبقاً']);
        }
        $id = DB::insert('users', [
            'name' => $d['name'], 'email' => $d['email'], 'phone' => $d['phone'],
            'company' => $d['company'] ?? null, 'password_hash' => Security::hashPassword($d['password']),
        ]);
        $token = Auth::issue($id, $r, $this->wantsCookie($r));
        $u = DB::oneW('SELECT * FROM users WHERE id = ?', [$id]);
        Response::json(['user' => $this->present($u)] + ($this->wantsCookie($r) ? [] : ['token' => $token]), 201);
    }

    public function login(Request $r): void
    {
        Security::throttle('auth', 'login:' . $r->ip());
        $d = Validator::check($r->input(), ['email' => 'required|email', 'password' => 'required|string|max:200']);
        Security::throttle('auth', 'login_acct:' . $d['email'], 20, 900);

        $u = DB::oneW('SELECT * FROM users WHERE email = ?', [$d['email']]);
        // نفس الرسالة ونفس الوقت تقريباً سواء الحساب موجود أو لا (منع كشف الحسابات)
        $hash = $u['password_hash'] ?? Cache::remember('dummy_hash', 86400, fn() => Security::hashPassword(bin2hex(random_bytes(8))));

        if ($u && $u['locked_until'] && strtotime($u['locked_until']) > time()) {
            throw new HttpError(423, 'locked', 'الحساب مقفل مؤقتاً بسبب محاولات خاطئة، حاول بعد ' . self::LOCK_MINUTES . ' دقيقة');
        }
        $ok = password_verify($d['password'], $hash);
        if (!$u || !$ok) {
            if ($u) {
                $fails = (int)$u['failed_logins'] + 1;
                DB::update('users', [
                    'failed_logins' => $fails >= self::MAX_FAILS ? 0 : $fails,
                    'locked_until' => $fails >= self::MAX_FAILS ? date('Y-m-d H:i:s', time() + self::LOCK_MINUTES * 60) : null,
                ], 'id = :id', ['id' => $u['id']]);
                if ($fails >= self::MAX_FAILS) Log::warn('Account locked', ['user' => $u['id']]);
            }
            throw new HttpError(401, 'invalid_credentials', 'البريد أو كلمة المرور غير صحيحة');
        }
        if ($u['status'] !== 'active') throw new HttpError(403, 'disabled', 'الحساب معطّل');

        $upd = ['failed_logins' => 0, 'locked_until' => null, 'last_login_at' => date('Y-m-d H:i:s')];
        if (password_needs_rehash($u['password_hash'], defined('PASSWORD_ARGON2ID') ? PASSWORD_ARGON2ID : PASSWORD_BCRYPT)) {
            $upd['password_hash'] = Security::hashPassword($d['password']);
        }
        DB::update('users', $upd, 'id = :id', ['id' => $u['id']]);
        $token = Auth::issue((int)$u['id'], $r, $this->wantsCookie($r));
        if (in_array($u['role'], Auth::PANEL_ROLES, true)) {
            DB::insert('audit_log', ['user_id' => $u['id'], 'action' => 'login', 'entity' => 'user', 'entity_id' => $u['id'], 'ip' => $r->ip()]);
        }
        Response::json(['user' => $this->present($u)] + ($this->wantsCookie($r) ? [] : ['token' => $token]));
    }

    public function logout(Request $r): void
    {
        Auth::revokeCurrent();
        Response::json(['logged_out' => true]);
    }

    public function me(Request $r): void
    {
        header('Cache-Control: no-store');
        $u = Auth::user();
        Response::json($u ? $this->present($u) : null);
    }

    public function updateMe(Request $r): void
    {
        $u = Auth::require();
        $d = Validator::check($r->input(), [
            'name' => 'string|min:2|max:120', 'phone' => 'phone', 'company' => 'string|max:150',
        ], true);
        if ($d) DB::update('users', $d, 'id = :id', ['id' => $u['id']]);
        Cache::delete('tok:' . Security::hashToken($_COOKIE['gg_t'] ?? ''));
        Response::json($this->present(DB::oneW('SELECT * FROM users WHERE id = ?', [$u['id']])));
    }

    public function password(Request $r): void
    {
        $u = Auth::require();
        Security::throttle('auth', 'pw:' . $u['id']);
        $d = Validator::check($r->input(), ['current' => 'required|string', 'new' => 'required|string|min:8|max:200']);
        $row = DB::oneW('SELECT password_hash FROM users WHERE id = ?', [$u['id']]);
        if (!password_verify($d['current'], $row['password_hash'])) throw new HttpError(422, 'validation', 'كلمة المرور الحالية غير صحيحة', ['current' => 'غير صحيحة']);
        if (!Security::passwordStrong($d['new'])) throw new HttpError(422, 'validation', 'كلمة المرور ضعيفة', ['new' => '8 أحرف على الأقل وتحتوي حروفاً وأرقاماً']);
        DB::update('users', ['password_hash' => Security::hashPassword($d['new'])], 'id = :id', ['id' => $u['id']]);
        Auth::revokeAll((int)$u['id']); // تسجيل خروج كل الأجهزة
        $token = Auth::issue((int)$u['id'], $r, $this->wantsCookie($r));
        Response::json(['changed' => true] + ($this->wantsCookie($r) ? [] : ['token' => $token]));
    }

    /**
     * حذف الحساب نهائياً — مطلوب من Apple (5.1.1v) و Google Play.
     * يحذف بيانات المستخدم والجلسات والمفضلة. الطلبات السابقة تبقى كسجل تجاري بدون ربط بالحساب.
     */
    private function destroyAccount(array $user, Request $r): void
    {
        if ($user['role'] === 'admin' && (int)DB::val("SELECT COUNT(*) FROM users WHERE role = 'admin' AND status = 'active'") <= 1) {
            throw new HttpError(409, 'conflict', 'لا يمكن حذف حساب المدير الوحيد');
        }
        DB::tx(function () use ($user) {
            Auth::revokeAll((int)$user['id']);
            DB::exec('UPDATE orders SET email = NULL WHERE user_id = ? AND status IN (\'returned\',\'cancelled\')', [$user['id']]);
            DB::exec('DELETE FROM users WHERE id = ?', [$user['id']]); // favorites + tokens تُحذف تلقائياً (CASCADE)، orders.user_id = NULL
        });
        DB::insert('audit_log', ['user_id' => null, 'action' => 'account.deleted', 'entity' => 'user', 'entity_id' => $user['id'], 'ip' => $r->ip()]);
    }

    /** DELETE /auth/me  { password } — من داخل التطبيق أو الموقع */
    public function deleteMe(Request $r): void
    {
        $u = Auth::require();
        Security::throttle('auth', 'del:' . $u['id']);
        $d = Validator::check($r->input(), ['password' => 'required|string|max:200']);
        $row = DB::oneW('SELECT * FROM users WHERE id = ?', [$u['id']]);
        if (!password_verify($d['password'], $row['password_hash'])) {
            throw new HttpError(422, 'validation', 'كلمة المرور غير صحيحة', ['password' => 'غير صحيحة']);
        }
        $this->destroyAccount($row, $r);
        Auth::revokeCurrent();
        Response::json(['deleted' => true]);
    }

    /** POST /auth/delete-account  { email, password } — صفحة الويب العامة لحذف الحساب (مطلوبة في Google Play) */
    public function deleteByCredentials(Request $r): void
    {
        Security::throttle('auth', 'delweb:' . $r->ip());
        $d = Validator::check($r->input(), ['email' => 'required|email', 'password' => 'required|string|max:200']);
        $row = DB::oneW('SELECT * FROM users WHERE email = ?', [$d['email']]);
        $hash = $row['password_hash'] ?? Cache::remember('dummy_hash', 86400, fn() => Security::hashPassword(bin2hex(random_bytes(8))));
        if (!password_verify($d['password'], $hash) || !$row) {
            throw new HttpError(401, 'invalid_credentials', 'البريد أو كلمة المرور غير صحيحة');
        }
        $this->destroyAccount($row, $r);
        Response::json(['deleted' => true]);
    }
}
