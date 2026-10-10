-- Ghani Group Rental — database schema
-- MySQL 5.7+ / MariaDB 10.3+  (InnoDB, utf8mb4)

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS `migrations` (
  `version`     VARCHAR(32) NOT NULL PRIMARY KEY,
  `applied_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `users` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name`           VARCHAR(120) NOT NULL,
  `email`          VARCHAR(190) NOT NULL,
  `phone`          VARCHAR(20)  NULL,
  `company`        VARCHAR(150) NULL,
  `password_hash`  VARCHAR(255) NOT NULL,
  `role`           ENUM('customer','staff','admin') NOT NULL DEFAULT 'customer',
  `status`         ENUM('active','disabled') NOT NULL DEFAULT 'active',
  `failed_logins`  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `locked_until`   DATETIME NULL,
  `last_login_at`  DATETIME NULL,
  `created_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_users_email` (`email`),
  KEY `ix_users_role` (`role`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `api_tokens` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id`       INT UNSIGNED NOT NULL,
  `token_hash`    CHAR(64) NOT NULL,
  `ip`            VARCHAR(45) NULL,
  `user_agent`    VARCHAR(255) NULL,
  `expires_at`    DATETIME NOT NULL,
  `last_used_at`  DATETIME NULL,
  `created_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_token_hash` (`token_hash`),
  KEY `ix_tokens_user` (`user_id`),
  KEY `ix_tokens_exp` (`expires_at`),
  CONSTRAINT `fk_tokens_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `categories` (
  `id`         SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `slug`       VARCHAR(60)  NOT NULL,
  `name_ar`    VARCHAR(100) NOT NULL,
  `name_en`    VARCHAR(100) NOT NULL,
  `image`      VARCHAR(255) NULL,
  `sort`       SMALLINT NOT NULL DEFAULT 0,
  `is_active`  TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_cat_slug` (`slug`),
  KEY `ix_cat_sort` (`is_active`, `sort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `equipment` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `category_id`  SMALLINT UNSIGNED NOT NULL,
  `slug`         VARCHAR(120) NOT NULL,
  `brand`        VARCHAR(80)  NOT NULL,
  `name`         VARCHAR(150) NOT NULL,
  `description`  TEXT NULL,
  `specs`        TEXT NULL COMMENT 'JSON object',
  `qty_total`    SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `image`        VARCHAR(255) NULL,
  `daily_rate`   DECIMAL(12,2) NULL COMMENT 'internal, not exposed publicly unless enabled',
  `is_featured`  TINYINT(1) NOT NULL DEFAULT 0,
  `is_new`       TINYINT(1) NOT NULL DEFAULT 0,
  `is_active`    TINYINT(1) NOT NULL DEFAULT 1,
  `sort`         INT NOT NULL DEFAULT 0,
  `created_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_eq_slug` (`slug`),
  KEY `ix_eq_cat` (`category_id`, `is_active`, `sort`),
  KEY `ix_eq_flags` (`is_active`, `is_featured`, `is_new`),
  KEY `ix_eq_brand` (`brand`),
  FULLTEXT KEY `ft_eq_search` (`brand`, `name`, `description`),
  CONSTRAINT `fk_eq_cat` FOREIGN KEY (`category_id`) REFERENCES `categories`(`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `equipment_images` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `equipment_id`  INT UNSIGNED NOT NULL,
  `path`          VARCHAR(255) NOT NULL,
  `sort`          SMALLINT NOT NULL DEFAULT 0,
  KEY `ix_img_eq` (`equipment_id`, `sort`),
  CONSTRAINT `fk_img_eq` FOREIGN KEY (`equipment_id`) REFERENCES `equipment`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `kits` (
  `id`         SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `slug`       VARCHAR(80)  NOT NULL,
  `name_ar`    VARCHAR(120) NOT NULL,
  `name_en`    VARCHAR(120) NOT NULL,
  `image`      VARCHAR(255) NULL,
  `sort`       SMALLINT NOT NULL DEFAULT 0,
  `is_active`  TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY `uq_kit_slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `kit_items` (
  `kit_id`        SMALLINT UNSIGNED NOT NULL,
  `equipment_id`  INT UNSIGNED NOT NULL,
  `qty`           SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`kit_id`, `equipment_id`),
  CONSTRAINT `fk_ki_kit` FOREIGN KEY (`kit_id`) REFERENCES `kits`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ki_eq`  FOREIGN KEY (`equipment_id`) REFERENCES `equipment`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `orders` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `ref`           VARCHAR(16) NOT NULL,
  `user_id`       INT UNSIGNED NULL,
  `contact_name`  VARCHAR(120) NOT NULL,
  `phone`         VARCHAR(20)  NOT NULL,
  `email`         VARCHAR(190) NULL,
  `project`       VARCHAR(150) NULL,
  `location`      VARCHAR(190) NULL,
  `start_date`    DATE NOT NULL,
  `end_date`      DATE NOT NULL,
  `technician`    TINYINT(1) NOT NULL DEFAULT 0,
  `delivery`      TINYINT(1) NOT NULL DEFAULT 0,
  `notes`         TEXT NULL,
  `status`        ENUM('pending','quoted','confirmed','out','returned','cancelled') NOT NULL DEFAULT 'pending',
  `quote_amount`  DECIMAL(14,2) NULL,
  `admin_notes`   TEXT NULL,
  `ip`            VARCHAR(45) NULL,
  `created_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_order_ref` (`ref`),
  KEY `ix_order_user` (`user_id`, `created_at`),
  KEY `ix_order_status` (`status`, `created_at`),
  KEY `ix_order_dates` (`start_date`, `end_date`),
  CONSTRAINT `fk_order_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_items` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `order_id`      INT UNSIGNED NOT NULL,
  `equipment_id`  INT UNSIGNED NOT NULL,
  `qty`           SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  KEY `ix_oi_order` (`order_id`),
  KEY `ix_oi_eq` (`equipment_id`),
  CONSTRAINT `fk_oi_order` FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_oi_eq`    FOREIGN KEY (`equipment_id`) REFERENCES `equipment`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `favorites` (
  `user_id`       INT UNSIGNED NOT NULL,
  `equipment_id`  INT UNSIGNED NOT NULL,
  `created_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `equipment_id`),
  CONSTRAINT `fk_fav_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_fav_eq`   FOREIGN KEY (`equipment_id`) REFERENCES `equipment`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `settings` (
  `k`  VARCHAR(60) NOT NULL PRIMARY KEY,
  `v`  TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `audit_log` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id`     INT UNSIGNED NULL,
  `action`      VARCHAR(60) NOT NULL,
  `entity`      VARCHAR(40) NULL,
  `entity_id`   INT UNSIGNED NULL,
  `meta`        TEXT NULL,
  `ip`          VARCHAR(45) NULL,
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `ix_audit_time` (`created_at`),
  KEY `ix_audit_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
