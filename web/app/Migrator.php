<?php
declare(strict_types=1);

namespace App;

/**
 * ترقية قاعدة البيانات تلقائياً عند رفع نسخة جديدة من السكربت — بدون إعادة تنصيب.
 * كل ترحيل آمن للتكرار (idempotent). يُشغَّل مرة واحدة ثم يُحفظ رقم النسخة في
 * storage/schema.version حتى لا تُستعلم القاعدة في كل طلب.
 */
final class Migrator
{
    public const LATEST = '2026_10_004';
    private const FLAG = '/storage/schema.version';

    public static function ensure(): void
    {
        $flag = ROOT . self::FLAG;
        if (is_file($flag) && trim((string)@file_get_contents($flag)) === self::LATEST) return;
        $pdo = DB::primary();
        // قفل حتى لا يشغّل طلبان متزامنان نفس الترحيل
        $got = (int)$pdo->query("SELECT GET_LOCK('gg_migrate', 15)")->fetchColumn();
        try {
            self::run();
            @file_put_contents($flag, self::LATEST, LOCK_EX);
        } finally {
            if ($got) $pdo->query("SELECT RELEASE_LOCK('gg_migrate')");
        }
    }

    /** @return string[] أسماء الترحيلات التي طُبّقت الآن */
    public static function run(): array
    {
        $pdo = DB::primary();
        $pdo->exec('CREATE TABLE IF NOT EXISTS `migrations` (`version` VARCHAR(32) NOT NULL PRIMARY KEY, `applied_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
        $done = array_flip($pdo->query('SELECT version FROM migrations')->fetchAll(\PDO::FETCH_COLUMN));
        $applied = [];
        foreach (self::migrations() as $version => $fn) {
            if (isset($done[$version])) continue;
            $fn($pdo);
            $pdo->prepare('INSERT IGNORE INTO migrations (version) VALUES (?)')->execute([$version]);
            $applied[] = $version;
        }
        if ($applied) {
            Cache::bump('catalog');
            Cache::bump('settings');
        }
        return $applied;
    }

    private static function hasColumn(\PDO $pdo, string $table, string $col): bool
    {
        $st = $pdo->prepare('SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?');
        $st->execute([$table, $col]);
        return (int)$st->fetchColumn() > 0;
    }

    private static function migrations(): array
    {
        $T = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';
        return [
            '2026_10_001' => static function (\PDO $pdo) {
                // النسخة الأولى (schema.sql) — لا شيء إضافي
            },

            // أدوار جديدة + البنرات + الماركات + الإشعارات + محاضر التسليم والإرجاع بالتوقيع
            '2026_10_002' => static function (\PDO $pdo) use ($T) {
                $pdo->exec("ALTER TABLE `users` MODIFY `role` ENUM('customer','staff','storekeeper','technician','admin') NOT NULL DEFAULT 'customer'");

                $pdo->exec("CREATE TABLE IF NOT EXISTS `banners` (
                    `id` SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `title` VARCHAR(120) NULL,
                    `subtitle` VARCHAR(200) NULL,
                    `image` VARCHAR(255) NULL,
                    `link_type` ENUM('none','url','category','equipment','brand','kits') NOT NULL DEFAULT 'none',
                    `link_value` VARCHAR(255) NULL,
                    `button_text` VARCHAR(40) NULL,
                    `sort` SMALLINT NOT NULL DEFAULT 0,
                    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
                    `starts_at` DATE NULL,
                    `ends_at` DATE NULL,
                    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    KEY `ix_banner_active` (`is_active`, `sort`)
                ) $T");

                $pdo->exec("CREATE TABLE IF NOT EXISTS `brands` (
                    `id` SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `name` VARCHAR(80) NOT NULL,
                    `slug` VARCHAR(90) NOT NULL,
                    `logo` VARCHAR(255) NULL,
                    `sort` SMALLINT NOT NULL DEFAULT 0,
                    `is_featured` TINYINT(1) NOT NULL DEFAULT 1,
                    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
                    UNIQUE KEY `uq_brand_name` (`name`),
                    UNIQUE KEY `uq_brand_slug` (`slug`)
                ) $T");

                $pdo->exec("CREATE TABLE IF NOT EXISTS `notifications` (
                    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `user_id` INT UNSIGNED NULL COMMENT 'NULL = للجميع',
                    `order_id` INT UNSIGNED NULL,
                    `type` ENUM('promo','order','info') NOT NULL DEFAULT 'promo',
                    `title` VARCHAR(150) NOT NULL,
                    `body` VARCHAR(1000) NULL,
                    `image` VARCHAR(255) NULL,
                    `link_type` ENUM('none','url','category','equipment','brand','kits','order') NOT NULL DEFAULT 'none',
                    `link_value` VARCHAR(255) NULL,
                    `created_by` INT UNSIGNED NULL,
                    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    KEY `ix_notif_user` (`user_id`, `id`),
                    KEY `ix_notif_order` (`order_id`, `id`),
                    CONSTRAINT `fk_notif_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
                    CONSTRAINT `fk_notif_order` FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON DELETE CASCADE
                ) $T");

                $pdo->exec("CREATE TABLE IF NOT EXISTS `order_handovers` (
                    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `order_id` INT UNSIGNED NOT NULL,
                    `type` ENUM('checkout','return') NOT NULL,
                    `employee_id` INT UNSIGNED NULL COMMENT 'الموظف المسؤول',
                    `employee_name` VARCHAR(120) NOT NULL,
                    `technician_id` INT UNSIGNED NULL,
                    `technician_name` VARCHAR(120) NULL COMMENT 'الفني الذي خرج مع المعدات',
                    `receiver_name` VARCHAR(120) NOT NULL COMMENT 'المستلم/المُرجِع من طرف العميل',
                    `receiver_phone` VARCHAR(20) NULL,
                    `items` TEXT NOT NULL COMMENT 'JSON: القطع والكمية والحالة',
                    `notes` TEXT NULL,
                    `signature` VARCHAR(255) NOT NULL COMMENT 'storage/signatures/... (غير عام)',
                    `employee_signature` VARCHAR(255) NULL,
                    `ip` VARCHAR(45) NULL,
                    `created_by` INT UNSIGNED NULL,
                    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    KEY `ix_ho_order` (`order_id`, `type`),
                    KEY `ix_ho_time` (`created_at`),
                    CONSTRAINT `fk_ho_order` FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON DELETE CASCADE
                ) $T");

                // أسماء الماركات الحالية من المعدات، مرتبة حسب عدد المعدات
                $ins = $pdo->prepare('INSERT IGNORE INTO brands (name, slug, sort, is_featured) VALUES (?, ?, ?, ?)');
                $seen = [];
                foreach ($pdo->query("SELECT brand, COUNT(*) n FROM equipment WHERE brand <> '' GROUP BY brand ORDER BY n DESC")->fetchAll() as $i => $b) {
                    $slug = Validator::slugify($b['brand']);
                    if (isset($seen[$slug])) $slug .= '-' . ($i + 1);
                    $seen[$slug] = true;
                    $ins->execute([$b['brand'], $slug, $i + 1, $i < 12 ? 1 : 0]);
                }

                // إعدادات افتراضية للنصوص القابلة للتغيير
                $defaults = [
                    'home_title' => 'ماذا ستصوّر',
                    'home_subtitle' => 'هذا الأسبوع؟',
                    'welcome_enabled' => '0',
                    'welcome_title' => 'أهلاً بك في Ghani Group',
                    'welcome_body' => 'أسطول كامل من كاميرات السينما والعدسات والإضاءة — اطلب عرض سعر خلال دقيقة.',
                    'welcome_button' => 'ابدأ التصفح',
                    'welcome_link' => '',
                    'welcome_frequency' => 'once',
                    'welcome_version' => '1',
                ];
                $st = $pdo->prepare('INSERT IGNORE INTO settings (k, v) VALUES (?, ?)');
                foreach ($defaults as $k => $v) $st->execute([$k, $v]);
            },

            // أجهزة الإشعارات الفورية (Firebase Cloud Messaging)
            '2026_10_003' => static function (\PDO $pdo) use ($T) {
                $pdo->exec("CREATE TABLE IF NOT EXISTS `device_tokens` (
                    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `token` VARCHAR(512) NOT NULL,
                    `token_hash` CHAR(64) NOT NULL,
                    `platform` ENUM('ios','android','web') NOT NULL DEFAULT 'android',
                    `user_id` INT UNSIGNED NULL,
                    `app_version` VARCHAR(20) NULL,
                    `last_seen` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY `uq_dev_token` (`token_hash`),
                    KEY `ix_dev_user` (`user_id`),
                    CONSTRAINT `fk_dev_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE SET NULL
                ) $T");
                // طلبات الضيوف التي يتابعها كل جهاز (رقم الطلب + الهاتف تم التحقق منهما)
                $pdo->exec("CREATE TABLE IF NOT EXISTS `device_orders` (
                    `device_id` INT UNSIGNED NOT NULL,
                    `order_id` INT UNSIGNED NOT NULL,
                    PRIMARY KEY (`device_id`, `order_id`),
                    KEY `ix_do_order` (`order_id`),
                    CONSTRAINT `fk_do_dev` FOREIGN KEY (`device_id`) REFERENCES `device_tokens`(`id`) ON DELETE CASCADE,
                    CONSTRAINT `fk_do_order` FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON DELETE CASCADE
                ) $T");
            },

            // موافقة الجهاز على الإشعارات الإعلانية (متطلب Apple 4.5.4)
            '2026_10_004' => static function (\PDO $pdo) {
                if (!self::hasColumn($pdo, 'device_tokens', 'promo')) {
                    $pdo->exec("ALTER TABLE `device_tokens` ADD `promo` TINYINT(1) NOT NULL DEFAULT 0 AFTER `user_id`, ADD KEY `ix_dev_promo` (`promo`)");
                }
            },
        ];
    }
}
