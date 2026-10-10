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

    public static function image(array $file, int $maxSide = 1400): string
    {
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            throw new HttpError(422, 'upload', 'لم يتم رفع الملف');
        }
        $maxBytes = (int)Config::get('uploads.max_mb', 5) * 1024 * 1024;
        if ($file['size'] > $maxBytes) throw new HttpError(422, 'upload', 'حجم الصورة كبير');
        if (!is_uploaded_file($file['tmp_name'])) throw new HttpError(422, 'upload', 'ملف غير صالح');
        return self::fromPath($file['tmp_name'], $maxSide);
    }

    public static function fromPath(string $path, int $maxSide = 1400): string
    {
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
        imagefill($dst, 0, 0, imagecolorallocate($dst, 255, 255, 255)); // خلفية بيضاء للصور الشفافة
        imagecopyresampled($dst, $src, 0, 0, 0, 0, $nw, $nh, $w, $h);

        $dir = ROOT . self::DIR . '/' . date('Y/m');
        if (!is_dir($dir)) mkdir($dir, 0755, true);
        $name = bin2hex(random_bytes(12)) . '.jpg';
        imagejpeg($dst, $dir . '/' . $name, 84);
        imagedestroy($src);
        imagedestroy($dst);
        return ltrim(self::DIR, '/') . '/' . date('Y/m') . '/' . $name;
    }

    public static function remove(?string $rel): void
    {
        if (!$rel || !str_starts_with($rel, 'uploads/equipment/') || str_contains($rel, '..')) return;
        @unlink(ROOT . '/' . $rel);
    }
}
