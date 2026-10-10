<?php
declare(strict_types=1);

namespace App;

/**
 * ترحيل/استيراد البيانات إلى القاعدة.
 * يُستخدم من:
 *   1) معالج التنصيب: يرحّل بيانات الكتالوج المضمّنة (install/seed/data.json + الصور).
 *   2) لوحة التحكم: استيراد ملف JSON بنفس الصيغة أو CSV.
 * العملية idempotent: إعادة التشغيل تحدّث السجلات الموجودة (حسب slug) ولا تكررها.
 * الصور: اسم ملف داخل مجلد الصور، أو رابط http(s) يتم تنزيله وإعادة ترميزه.
 */
final class Importer
{
    private array $report = ['categories' => 0, 'equipment' => 0, 'kits' => 0, 'images' => 0, 'settings' => 0, 'errors' => []];

    public function __construct(private ?string $imageDir = null) {}

    public function run(array $data): array
    {
        DB::tx(function () use ($data) {
            foreach ($data['categories'] ?? [] as $c) $this->category($c);
            foreach ($data['equipment'] ?? [] as $e) {
                try { $this->equipment($e); }
                catch (\Throwable $ex) { $this->report['errors'][] = ($e['slug'] ?? $e['name'] ?? '?') . ': ' . $ex->getMessage(); }
            }
            foreach ($data['kits'] ?? [] as $k) $this->kit($k);
            foreach ($data['settings'] ?? [] as $k => $v) {
                if (!preg_match('/^[a-z_]{2,60}$/', (string)$k)) continue;
                if (in_array($k, ['hero_image'], true) && is_string($v) && $v !== '') $v = $this->image($v) ?? $v;
                DB::exec('INSERT INTO settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', [$k, (string)$v]);
                $this->report['settings']++;
            }
        });
        Cache::bump('catalog');
        return $this->report;
    }

    private function category(array $c): int
    {
        $slug = Validator::slugify($c['slug'] ?? $c['name_en'] ?? '');
        $row = [
            'name_ar' => Security::cleanText($c['name_ar'] ?? $c['name_en'] ?? $slug, 100),
            'name_en' => Security::cleanText($c['name_en'] ?? $slug, 100),
            'sort' => (int)($c['sort'] ?? 0),
        ];
        if (!empty($c['image'])) $row['image'] = $this->image($c['image']);
        $id = DB::val('SELECT id FROM categories WHERE slug = ?', [$slug]);
        if ($id) DB::update('categories', $row, 'id = :id', ['id' => $id]);
        else $id = DB::insert('categories', $row + ['slug' => $slug]);
        $this->report['categories']++;
        return (int)$id;
    }

    private function categoryId(string $ref): int
    {
        $slug = Validator::slugify($ref);
        $id = DB::oneW('SELECT id FROM categories WHERE slug = ? OR name_en = ? OR name_ar = ? LIMIT 1', [$slug, $ref, $ref]);
        return $id ? (int)$id['id'] : $this->category(['slug' => $slug, 'name_en' => $ref, 'name_ar' => $ref]);
    }

    private function equipment(array $e): void
    {
        if (empty($e['name']) || empty($e['category'])) throw new \RuntimeException('name و category مطلوبة');
        $slug = Validator::slugify($e['slug'] ?? (($e['brand'] ?? '') . ' ' . $e['name']));
        $specs = $e['specs'] ?? null;
        if (is_string($specs)) $specs = json_decode($specs, true) ?: null;
        $row = [
            'category_id' => $this->categoryId((string)$e['category']),
            'brand' => Security::cleanText($e['brand'] ?? '', 80),
            'name' => Security::cleanText($e['name'], 150),
            'description' => isset($e['description']) ? Security::cleanText($e['description'], 5000) : null,
            'specs' => $specs ? json_encode($specs, JSON_UNESCAPED_UNICODE) : null,
            'qty_total' => max(0, min(9999, (int)($e['qty'] ?? 1))),
            'is_featured' => !empty($e['featured']) ? 1 : 0,
            'is_new' => !empty($e['is_new']) ? 1 : 0,
            'daily_rate' => isset($e['daily_rate']) && is_numeric($e['daily_rate']) ? (float)$e['daily_rate'] : null,
            'sort' => (int)($e['sort'] ?? 0),
        ];
        if (!empty($e['image'])) {
            $img = $this->image((string)$e['image']);
            if ($img) $row['image'] = $img;
        }
        $id = DB::oneW('SELECT id FROM equipment WHERE slug = ?', [$slug]);
        if ($id) DB::update('equipment', $row, 'id = :id', ['id' => $id['id']]);
        else DB::insert('equipment', $row + ['slug' => $slug]);
        $this->report['equipment']++;
    }

    private function kit(array $k): void
    {
        $slug = Validator::slugify($k['slug'] ?? $k['name_en'] ?? '');
        $row = ['name_ar' => Security::cleanText($k['name_ar'] ?? $slug, 120), 'name_en' => Security::cleanText($k['name_en'] ?? $slug, 120), 'sort' => (int)($k['sort'] ?? 0)];
        if (!empty($k['image'])) $row['image'] = $this->image($k['image']);
        $id = DB::oneW('SELECT id FROM kits WHERE slug = ?', [$slug])['id'] ?? null;
        if ($id) DB::update('kits', $row, 'id = :id', ['id' => $id]);
        else $id = DB::insert('kits', $row + ['slug' => $slug]);
        DB::exec('DELETE FROM kit_items WHERE kit_id = ?', [$id]);
        foreach ($k['items'] ?? [] as $it) {
            $s = is_array($it) ? ($it['slug'] ?? '') : (string)$it;
            $eq = DB::oneW('SELECT id FROM equipment WHERE slug = ?', [$s]);
            if ($eq) DB::exec('INSERT IGNORE INTO kit_items (kit_id, equipment_id, qty) VALUES (?,?,?)', [$id, $eq['id'], (int)(is_array($it) ? ($it['qty'] ?? 1) : 1)]);
        }
        $this->report['kits']++;
    }

    /** يُرجع المسار النسبي للصورة بعد نسخها/تنزيلها وإعادة ترميزها */
    private function image(string $src): ?string
    {
        $src = trim($src);
        if ($src === '') return null;
        if (str_starts_with($src, 'uploads/equipment/') && !str_contains($src, '..')) return $src;

        static $done = [];
        if (isset($done[$src])) return $done[$src];

        $tmp = null;
        try {
            if (preg_match('#^https?://#i', $src)) {
                $tmp = $this->download($src);
                $path = $tmp;
            } else {
                $name = basename($src);
                if (!$this->imageDir || !preg_match('/^[\w.\-]+$/', $name)) return null;
                $path = $this->imageDir . '/' . $name;
                if (!is_file($path)) return null;
            }
            $rel = Upload::fromPath($path);
            $this->report['images']++;
            return $done[$src] = $rel;
        } catch (\Throwable $e) {
            $this->report['errors'][] = 'image ' . mb_substr($src, 0, 80) . ': ' . $e->getMessage();
            return null;
        } finally {
            if ($tmp) @unlink($tmp);
        }
    }

    private function download(string $url): string
    {
        $host = parse_url($url, PHP_URL_HOST) ?: '';
        // حماية SSRF: لا نسمح بالتنزيل من عناوين داخلية
        $ips = gethostbynamel($host) ?: [];
        if (!$ips) throw new \RuntimeException('host not resolvable');
        foreach ($ips as $ip) {
            if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                throw new \RuntimeException('blocked host');
            }
        }
        $tmp = tempnam(sys_get_temp_dir(), 'ggimg');
        $fh = fopen($tmp, 'wb');
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_FILE => $fh, CURLOPT_FOLLOWLOCATION => false, CURLOPT_TIMEOUT => 20,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS, CURLOPT_USERAGENT => 'GhaniRental-Importer/1.0',
            CURLOPT_MAXFILESIZE => 10 * 1024 * 1024,
        ]);
        $ok = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        fclose($fh);
        if (!$ok || $code !== 200) { @unlink($tmp); throw new \RuntimeException("download failed ($code)"); }
        return $tmp;
    }

    /** تحويل CSV إلى نفس صيغة JSON. الأعمدة: category,brand,name,qty,image,description,featured,is_new,specs(key=value;key=value) */
    public static function fromCsv(string $csv): array
    {
        $lines = array_filter(preg_split('/\r\n|\n|\r/', ltrim($csv, "\xEF\xBB\xBF")) ?: [], 'strlen');
        $head = array_map(fn($h) => strtolower(trim($h)), str_getcsv((string)array_shift($lines)));
        $out = [];
        foreach ($lines as $line) {
            $r = array_combine($head, array_pad(str_getcsv($line), count($head), ''));
            if (!$r) continue;
            if (!empty($r['specs'])) {
                $sp = [];
                foreach (explode(';', $r['specs']) as $pair) {
                    [$k, $v] = array_pad(explode('=', $pair, 2), 2, '');
                    if (trim($k) !== '') $sp[trim($k)] = trim($v);
                }
                $r['specs'] = $sp;
            }
            $out[] = $r;
        }
        return ['equipment' => $out];
    }
}
