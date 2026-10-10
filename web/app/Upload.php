<?php
declare(strict_types=1);

namespace App;

/**
 * رفع الصور بأمان:
 *  - فحص الحجم والنوع الحقيقي للملف (وليس الامتداد)
 *  - إعادة ترميز الصورة عبر GD (يزيل أي كود مخفي أو بيانات EXIF)
 *  - اسم عشوائي، ومجلد الرفع لا يسمح بتشغيل PHP
 */
final class Upload
{
    public const DIR = '/uploads/equipment';

    public static function image(array $file, int $maxSide = 1400, string $dir = 'equipment', bool $png = false): string
    {
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            throw new HttpError(422, 'upload', 'لم يتم رفع الملف');
        }
        $maxBytes = (int)Config::get('uploads.max_mb', 5) * 1024 * 1024;
        if ($file['size'] > $maxBytes) throw new HttpError(422, 'upload', 'حجم الصورة كبير');
        if (!is_uploaded_file($file['tmp_name'])) throw new HttpError(422, 'upload', 'ملف غير صالح');
        return self::fromPath($file['tmp_name'], $maxSide, $dir, $png);
    }

    /**
     * @param string $dir  equipment | media (بنرات، شعارات الماركات، صورة الترحيب، الإشعارات)
     * @param bool   $png  يحافظ على الشفافية (لشعارات الماركات)
     */
    public static function fromPath(string $path, int $maxSide = 1400, string $dir = 'equipment', bool $png = false): string
    {
        if (!in_array($dir, ['equipment', 'media'], true)) $dir = 'equipment';
        $info = @getimagesize($path);
        $allowed = [IMAGETYPE_JPEG, IMAGETYPE_PNG, IMAGETYPE_WEBP, IMAGETYPE_GIF];
        if (!$info || !in_array($info[2], $allowed, true)) {
            throw new HttpError(422, 'upload', 'نوع الصورة غير مدعوم (JPG, PNG, WEBP)');
        }
        if ($info[0] * $info[1] > 40_000_000) throw new HttpError(422, 'upload', 'أبعاد الصورة كبيرة جداً');

        $src = match ($info[2]) {
            IMAGETYPE_JPEG => @imagecreatefromjpeg($path),
            IMAGETYPE_PNG => @imagecreatefrompng($path),
            IMAGETYPE_WEBP => @imagecreatefromwebp($path),
            IMAGETYPE_GIF => @imagecreatefromgif($path),
        };
        if (!$src) throw new HttpError(422, 'upload', 'تعذرت قراءة الصورة');

        [$w, $h] = [$info[0], $info[1]];
        $scale = min(1, $maxSide / max($w, $h));
        $nw = (int)round($w * $scale);
        $nh = (int)round($h * $scale);
        $dst = imagecreatetruecolor($nw, $nh);
        if ($png) {
            imagealphablending($dst, false);
            imagesavealpha($dst, true);
            imagefill($dst, 0, 0, imagecolorallocatealpha($dst, 0, 0, 0, 127));
        } else {
            imagefill($dst, 0, 0, imagecolorallocate($dst, 255, 255, 255)); // خلفية بيضاء للصور الشفافة
        }
        imagecopyresampled($dst, $src, 0, 0, 0, 0, $nw, $nh, $w, $h);

        $rel = 'uploads/' . $dir . '/' . date('Y/m');
        $abs = ROOT . '/' . $rel;
        if (!is_dir($abs)) mkdir($abs, 0755, true);
        $name = bin2hex(random_bytes(12)) . ($png ? '.png' : '.jpg');
        $png ? imagepng($dst, $abs . '/' . $name, 7) : imagejpeg($dst, $abs . '/' . $name, 84);
        imagedestroy($src);
        imagedestroy($dst);
        return $rel . '/' . $name;
    }

    /**
     * توقيع إلكتروني (PNG بصيغة data URL أو base64) → يُعاد ترميزه ويُحفظ خارج المجلد العام.
     * @return string المسار النسبي داخل storage/
     */
    public static function signature(string $data): string
    {
        $data = preg_replace('#^data:image/png;base64,#', '', trim($data)) ?? '';
        if ($data === '' || strlen($data) > 1_400_000) throw new HttpError(422, 'validation', 'التوقيع مطلوب', ['signature' => 'مطلوب']);
        $bin = base64_decode($data, true);
        $info = $bin ? @getimagesizefromstring($bin) : false;
        if (!$info || $info[2] !== IMAGETYPE_PNG || $info[0] > 3000 || $info[1] > 2000 || $info[0] < 50) {
            throw new HttpError(422, 'validation', 'التوقيع غير صالح', ['signature' => 'غير صالح']);
        }
        $src = @imagecreatefromstring($bin);
        if (!$src) throw new HttpError(422, 'validation', 'التوقيع غير صالح', ['signature' => 'غير صالح']);
        // توقيع فارغ؟ نتحقق من وجود نقاط مرسومة كافية
        $w = imagesx($src); $h = imagesy($src); $ink = 0;
        for ($x = 0; $x < $w; $x += 4) for ($y = 0; $y < $h; $y += 4) {
            $a = (imagecolorat($src, $x, $y) >> 24) & 0x7F;
            if ($a < 100) $ink++;
        }
        if ($ink < 25) { imagedestroy($src); throw new HttpError(422, 'validation', 'ارسم التوقيع داخل المربع', ['signature' => 'فارغ']); }
        $dst = imagecreatetruecolor($w, $h);
        imagealphablending($dst, false);
        imagesavealpha($dst, true);
        imagefill($dst, 0, 0, imagecolorallocatealpha($dst, 255, 255, 255, 127));
        imagecopy($dst, $src, 0, 0, 0, 0, $w, $h);
        $rel = 'signatures/' . date('Y/m');
        $abs = ROOT . '/storage/' . $rel;
        if (!is_dir($abs)) mkdir($abs, 0750, true);
        $name = bin2hex(random_bytes(16)) . '.png';
        imagepng($dst, $abs . '/' . $name, 9);
        imagedestroy($src);
        imagedestroy($dst);
        return $rel . '/' . $name;
    }

    public static function remove(?string $rel): void
    {
        if (!$rel || !(str_starts_with($rel, 'uploads/equipment/') || str_starts_with($rel, 'uploads/media/')) || str_contains($rel, '..')) return;
        @unlink(ROOT . '/' . $rel);
    }
}
