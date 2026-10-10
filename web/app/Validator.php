<?php
declare(strict_types=1);

namespace App;

/**
 * تحقق بسيط وصارم من المدخلات.
 * القواعد: required, string, int, num, bool, email, phone, date, max:N, min:N, in:a,b,c, slug, array, json
 * يُرجع فقط الحقول المعرّفة (whitelist) — أي حقل إضافي يُتجاهل.
 */
final class Validator
{
    public static function check(array $data, array $rules, bool $partial = false): array
    {
        $out = [];
        $errors = [];
        foreach ($rules as $field => $ruleStr) {
            $rs = explode('|', $ruleStr);
            $present = array_key_exists($field, $data) && $data[$field] !== '' && $data[$field] !== null;
            if (!$present) {
                if (in_array('required', $rs, true) && !$partial) $errors[$field] = 'مطلوب';
                elseif (array_key_exists($field, $data) && in_array('nullable', $rs, true)) $out[$field] = null;
                continue;
            }
            $v = $data[$field];
            $type = 'string';
            foreach ($rs as $r) {
                [$name, $arg] = array_pad(explode(':', $r, 2), 2, null);
                switch ($name) {
                    case 'string':
                        if (!is_scalar($v)) { $errors[$field] = 'نص غير صالح'; break 2; }
                        $v = Security::cleanText((string)$v, 20000);
                        break;
                    case 'int':
                        if (filter_var($v, FILTER_VALIDATE_INT) === false) { $errors[$field] = 'رقم صحيح مطلوب'; break 2; }
                        $v = (int)$v; $type = 'num';
                        break;
                    case 'num':
                        if (!is_numeric($v)) { $errors[$field] = 'رقم مطلوب'; break 2; }
                        $v = (float)$v; $type = 'num';
                        break;
                    case 'bool':
                        $v = filter_var($v, FILTER_VALIDATE_BOOLEAN) ? 1 : 0; $type = 'num';
                        break;
                    case 'email':
                        $v = mb_strtolower(trim((string)$v));
                        if (!filter_var($v, FILTER_VALIDATE_EMAIL)) { $errors[$field] = 'بريد غير صالح'; break 2; }
                        break;
                    case 'phone':
                        $v = preg_replace('/[^\d+]/', '', (string)$v);
                        if (!preg_match('/^\+?\d{8,15}$/', $v)) { $errors[$field] = 'رقم هاتف غير صالح'; break 2; }
                        break;
                    case 'date':
                        $d = \DateTime::createFromFormat('Y-m-d', (string)$v);
                        if (!$d || $d->format('Y-m-d') !== $v) { $errors[$field] = 'تاريخ غير صالح (YYYY-MM-DD)'; break 2; }
                        break;
                    case 'slug':
                        if (!preg_match('/^[a-z0-9][a-z0-9\-]{0,118}$/', (string)$v)) { $errors[$field] = 'معرّف غير صالح'; break 2; }
                        break;
                    case 'in':
                        if (!in_array((string)$v, explode(',', (string)$arg), true)) { $errors[$field] = 'قيمة غير مسموحة'; break 2; }
                        break;
                    case 'array':
                        if (!is_array($v)) { $errors[$field] = 'قائمة مطلوبة'; break 2; }
                        $type = 'array';
                        break;
                    case 'max':
                        $len = $type === 'num' ? $v : ($type === 'array' ? count($v) : mb_strlen((string)$v));
                        if ($len > (float)$arg) { $errors[$field] = $type === 'num' ? "الحد الأقصى $arg" : "الحد الأقصى $arg حرف"; break 2; }
                        break;
                    case 'min':
                        $len = $type === 'num' ? $v : ($type === 'array' ? count($v) : mb_strlen((string)$v));
                        if ($len < (float)$arg) { $errors[$field] = $type === 'num' ? "الحد الأدنى $arg" : "الحد الأدنى $arg"; break 2; }
                        break;
                }
            }
            if (!isset($errors[$field])) $out[$field] = $v;
        }
        if ($errors) throw new HttpError(422, 'validation', 'تحقق من البيانات المدخلة', $errors);
        return $out;
    }

    public static function slugify(string $s): string
    {
        $s = mb_strtolower(trim($s));
        $s = preg_replace('/[^a-z0-9]+/u', '-', iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $s) ?: $s) ?? '';
        $s = trim($s, '-');
        return $s !== '' ? substr($s, 0, 100) : 'item-' . bin2hex(random_bytes(3));
    }
}
