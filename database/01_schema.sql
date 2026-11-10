-- =============================================================================
--  Luceria Cocktail Atelier —— 全站数据库 DDL
--  文件：database/01_schema.sql
--  作用：创建数据库与全部 31 张业务表（含约束、索引、外键、生成列、视图）
--
--  环境要求：
--    MySQL >= 8.0.16   （8.0.16 起 CHECK 约束才真正生效，之前的版本只解析不执行）
--    存储引擎：InnoDB   （唯一支持事务与行级锁的引擎，本项目的并发控制完全依赖它）
--    字符集：  utf8mb4  （4 字节 UTF-8，可存 emoji；utf8/utf8mb3 只有 3 字节，存 emoji 会报错）
--    排序规则：utf8mb4_0900_ai_ci （MySQL 8.0 默认，基于 Unicode 9.0，
--                                  ai = accent insensitive 不区分重音，
--                                  ci = case insensitive 不区分大小写）
--
--  执行方式：
--    mysql -u root -p < 01_schema.sql
--    或在 Navicat / DBeaver / MySQL Workbench 中整体执行
--
--  ⚠️ 本脚本开头会 DROP DATABASE，会清空所有数据。生产环境禁止直接执行。
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
SET @OLD_SQL_MODE = @@SQL_MODE;
-- STRICT_TRANS_TABLES：插入超长/非法数据时直接报错而不是静默截断（数据准确性的第一道保险）
SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,ERROR_FOR_DIVISION_BY_ZERO';

DROP DATABASE IF EXISTS `luceria`;
CREATE DATABASE `luceria`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE `luceria`;


-- #############################################################################
--  模块 A：系统与鉴权（6 张）
--  说明：本模块整体替代原 Supabase Auth + Supabase Storage 的职责。
-- #############################################################################

-- -----------------------------------------------------------------------------
-- A1. sys_config —— 系统配置字典
-- 作用：把「订单超时分钟数」「是否启用 Redis 库存漏斗」等运行期参数放进数据库，
--       改配置不用重启服务，答辩演示时可以把订单超时从 15 分钟临时改成 60 秒。
-- -----------------------------------------------------------------------------
CREATE TABLE `sys_config` (
  `config_key`   VARCHAR(64)  NOT NULL                COMMENT '配置键，如 order.timeout.minutes',
  `config_value` VARCHAR(500) NOT NULL                COMMENT '配置值（统一按字符串存，应用层按需转型）',
  `value_type`   VARCHAR(16)  NOT NULL DEFAULT 'STRING' COMMENT '值类型：STRING/INT/BOOL/JSON',
  `description`  VARCHAR(200) NOT NULL DEFAULT ''     COMMENT '配置说明',
  `editable`     TINYINT      NOT NULL DEFAULT 1      COMMENT '是否允许后台修改：0否 1是',
  `updated_at`   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`config_key`),
  CONSTRAINT `ck_cfg_type` CHECK (`value_type` IN ('STRING','INT','BOOL','JSON'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='系统配置字典表';


-- -----------------------------------------------------------------------------
-- A2. sys_user —— 用户主表（替代 Supabase auth.users）
--
-- 主键选型说明（数据库原理考察点）：
--   采用 BIGINT UNSIGNED AUTO_INCREMENT 而非 CHAR(36) UUID。
--   理由：InnoDB 的主键是聚簇索引，表数据按主键物理有序存放。
--        ① 自增主键顺序插入，页利用率高、几乎不产生页分裂；
--           UUID 随机分布，每次插入都可能落在已满的页中间，触发页分裂，写放大严重。
--        ② InnoDB 的所有二级索引叶子节点都存放主键值。
--           主键 8 字节 vs 36 字节，二级索引体积差 4.5 倍，直接影响 Buffer Pool 命中率。
--        ③ 本表的 legacy_uid 保留原 Supabase 的 UUID，用于迁移期间的数据对齐，
--           迁移完成后可保留作为历史追溯字段（不参与任何业务 JOIN）。
--
-- 密码说明：本项目沿用「邮箱验证码（OTP）登录」，不使用密码。
--          password_hash 字段预留为 NULL，若将来启用必须用 BCrypt/Argon2 哈希，禁止明文。
-- -----------------------------------------------------------------------------
CREATE TABLE `sys_user` (
  `id`                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '用户ID（内部主键）',
  `legacy_uid`         CHAR(36)        NULL                    COMMENT '原 Supabase auth.users.id（UUID），仅迁移与追溯用',
  `email`              VARCHAR(254)    NOT NULL                COMMENT '邮箱（登录账号），存储时统一转小写',
  `email_verified`     TINYINT         NOT NULL DEFAULT 0      COMMENT '邮箱是否已验证：0否 1是',
  `password_hash`      VARCHAR(100)    NULL                    COMMENT '密码哈希（预留，本期 OTP 登录不使用；启用时须为 BCrypt）',
  `display_name`       VARCHAR(24)     NOT NULL DEFAULT 'Guest Bartender' COMMENT '昵称，最长24字符',
  `avatar_url`         VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT '头像访问URL',
  `avatar_file_id`     BIGINT UNSIGNED NULL                    COMMENT '头像文件ID（逻辑外键→sys_file.id，不建物理外键以避免与 sys_file 循环依赖）',
  `role`               VARCHAR(16)     NOT NULL DEFAULT 'user' COMMENT '角色：user普通用户 admin管理员',
  `status`             TINYINT         NOT NULL DEFAULT 1      COMMENT '状态：0封禁 1正常 2注销',
  `profile_updated_at` DATETIME(3)     NULL                    COMMENT '资料最后修改时间，用于「每周仅可修改一次」的冷却判定',
  `last_login_at`      DATETIME(3)     NULL                    COMMENT '最后登录时间',
  `last_login_ip`      VARCHAR(45)     NOT NULL DEFAULT ''     COMMENT '最后登录IP（45字符可容纳IPv6）',
  `created_at`         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '注册时间',
  `updated_at`         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  -- 唯一索引：邮箱是登录账号，必须全局唯一。同时支撑登录时的 WHERE email = ? 等值查询
  UNIQUE KEY `uk_user_email` (`email`),
  -- 唯一索引：保证一个 Supabase UUID 只会被迁移成一个 MySQL 用户，重复导入会被数据库拒绝
  UNIQUE KEY `uk_user_legacy_uid` (`legacy_uid`),
  -- 普通索引：后台按角色筛选管理员列表
  KEY `idx_user_role_status` (`role`, `status`),
  CONSTRAINT `ck_user_role`   CHECK (`role`   IN ('user','admin')),
  CONSTRAINT `ck_user_status` CHECK (`status` IN (0,1,2)),
  -- 邮箱格式的粗校验：必须含 @ 且长度合理（精确校验在应用层用正则完成）
  CONSTRAINT `ck_user_email`  CHECK (CHAR_LENGTH(`email`) BETWEEN 5 AND 254 AND `email` LIKE '%@%.%'),
  CONSTRAINT `ck_user_name`   CHECK (CHAR_LENGTH(`display_name`) BETWEEN 1 AND 24)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='用户主表（替代 Supabase auth.users）';


-- -----------------------------------------------------------------------------
-- A3. sys_auth_code —— 邮箱验证码（OTP）
-- 作用：替代 Supabase 的 signInWithOtp / verifyOtp。
-- 安全设计：
--   ① 只存验证码的 SHA-256 哈希，不存明文。即使数据库泄露也无法直接登录。
--   ② attempt_count 限制爆破次数（超过 5 次直接作废）。
--   ③ consumed_at 保证一码只能用一次（一次性凭证）。
--   ④ 通过 idx_email_purpose_created 支撑「60 秒内不得重复发送」的冷却查询，
--      对应现有 src/stores/auth.js 中的 EMAIL_REQUEST_COOLDOWN_MS = 60000。
-- -----------------------------------------------------------------------------
CREATE TABLE `sys_auth_code` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '验证码记录ID',
  `email`         VARCHAR(254)    NOT NULL                COMMENT '目标邮箱（小写）',
  `code_hash`     CHAR(64)        NOT NULL                COMMENT '验证码的 SHA-256 十六进制哈希（不存明文）',
  `purpose`       VARCHAR(20)     NOT NULL DEFAULT 'LOGIN' COMMENT '用途：LOGIN登录 BIND_EMAIL换绑邮箱',
  `expires_at`    DATETIME(3)     NOT NULL                COMMENT '过期时间（签发后 10 分钟）',
  `consumed_at`   DATETIME(3)     NULL                    COMMENT '被使用的时间，非空表示已作废',
  `attempt_count` INT             NOT NULL DEFAULT 0      COMMENT '已尝试校验次数，超过5次作废',
  `request_ip`    VARCHAR(45)     NOT NULL DEFAULT ''     COMMENT '请求发送验证码的IP',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '签发时间',
  PRIMARY KEY (`id`),
  -- 联合索引：支撑「取该邮箱该用途下最新一条未使用的验证码」，也支撑发送频率冷却判定
  KEY `idx_authcode_email_purpose` (`email`, `purpose`, `created_at` DESC),
  -- 普通索引：支撑定时任务清理过期验证码 WHERE expires_at < NOW()
  KEY `idx_authcode_expires` (`expires_at`),
  CONSTRAINT `ck_authcode_purpose` CHECK (`purpose` IN ('LOGIN','BIND_EMAIL')),
  CONSTRAINT `ck_authcode_attempt` CHECK (`attempt_count` BETWEEN 0 AND 10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='邮箱验证码（OTP），替代 Supabase Auth 的 OTP 能力';


-- -----------------------------------------------------------------------------
-- A4. sys_refresh_token —— 刷新令牌
-- 作用：替代 Supabase 的 session / autoRefreshToken 机制。
-- 设计：access_token（JWT，2 小时）无状态不入库；refresh_token（14 天）入库，
--       这样才能实现「服务端强制下线」「修改角色后立即失效」等能力。
--       同样只存哈希，不存明文。
-- -----------------------------------------------------------------------------
CREATE TABLE `sys_refresh_token` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '令牌记录ID',
  `user_id`      BIGINT UNSIGNED NOT NULL                COMMENT '所属用户ID',
  `token_hash`   CHAR(64)        NOT NULL                COMMENT 'refresh token 的 SHA-256 哈希',
  `expires_at`   DATETIME(3)     NOT NULL                COMMENT '过期时间（签发后14天）',
  `revoked_at`   DATETIME(3)     NULL                    COMMENT '主动吊销时间（退出登录/强制下线）',
  `user_agent`   VARCHAR(300)    NOT NULL DEFAULT ''     COMMENT '签发时的 User-Agent，用于「登录设备」展示',
  `ip`           VARCHAR(45)     NOT NULL DEFAULT ''     COMMENT '签发时的IP',
  `created_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '签发时间',
  PRIMARY KEY (`id`),
  -- 唯一索引：刷新时按 token 哈希直接定位，且保证令牌不重复
  UNIQUE KEY `uk_token_hash` (`token_hash`),
  -- 联合索引：账号中心「我的登录设备」列表，以及「退出全部设备」的批量吊销
  KEY `idx_token_user_expires` (`user_id`, `expires_at`),
  CONSTRAINT `fk_token_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='刷新令牌表（支撑服务端强制下线）';


-- -----------------------------------------------------------------------------
-- A5. sys_login_log —— 登录日志
-- 作用：账号中心「安全信息」展示；也是安全审计与暴力破解检测的依据。
-- -----------------------------------------------------------------------------
CREATE TABLE `sys_login_log` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
  `user_id`     BIGINT UNSIGNED NULL                    COMMENT '用户ID（登录失败且账号不存在时为NULL）',
  `email`       VARCHAR(254)    NOT NULL                COMMENT '尝试登录的邮箱',
  `login_type`  VARCHAR(20)     NOT NULL DEFAULT 'EMAIL_OTP' COMMENT '登录方式：EMAIL_OTP/REFRESH_TOKEN',
  `success`     TINYINT         NOT NULL                COMMENT '是否成功：0失败 1成功',
  `fail_reason` VARCHAR(100)    NOT NULL DEFAULT ''     COMMENT '失败原因：CODE_EXPIRED/CODE_WRONG/USER_BANNED 等',
  `ip`          VARCHAR(45)     NOT NULL DEFAULT ''     COMMENT '来源IP',
  `user_agent`  VARCHAR(300)    NOT NULL DEFAULT ''     COMMENT 'User-Agent',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '发生时间',
  PRIMARY KEY (`id`),
  -- 联合索引：账号中心查「我的最近登录记录」，按时间倒序
  KEY `idx_loginlog_user_time` (`user_id`, `created_at` DESC),
  -- 联合索引：安全审计查「某邮箱近期的失败次数」，用于风控封禁
  KEY `idx_loginlog_email_time` (`email`, `created_at` DESC),
  CONSTRAINT `ck_loginlog_success` CHECK (`success` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='登录日志（安全审计）';


-- -----------------------------------------------------------------------------
-- A6. sys_file —— 文件元数据（替代 Supabase Storage 的 avatars / cocktail-images 两个桶）
--
-- 设计要点：
--   ① 数据库只存「元数据」，文件二进制存放在磁盘/MinIO/对象存储中。
--      绝不把图片以 BLOB 存进 MySQL —— 会撑爆 Buffer Pool，让所有查询变慢。
--   ② sha256 字段实现「秒传/去重」：同一文件重复上传时直接复用已有对象。
--   ③ status 字段实现「两阶段提交」：上传后先置 0（临时），业务写入成功后置 1（已引用）。
--      定时任务清理超过 24 小时仍为 0 的孤儿文件，避免用户传了图但没提交表单造成的垃圾堆积。
--      这正好解决了现有代码 src/lib/user-cocktails.js 里手工 remove 补偿的脆弱做法。
-- -----------------------------------------------------------------------------
CREATE TABLE `sys_file` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '文件ID',
  `biz_type`      VARCHAR(24)     NOT NULL                COMMENT '业务类型：AVATAR头像 COCKTAIL_IMAGE酒款图 PRODUCT_IMAGE商品图',
  `storage_type`  VARCHAR(16)     NOT NULL DEFAULT 'LOCAL' COMMENT '存储介质：LOCAL本地磁盘 MINIO对象存储 OSS云存储',
  `bucket`        VARCHAR(64)     NOT NULL DEFAULT ''     COMMENT '桶名（对应原 Supabase 的 avatars / cocktail-images）',
  `object_key`    VARCHAR(300)    NOT NULL                COMMENT '对象键（存储路径），如 avatar/2026/09/uuid.png',
  `original_name` VARCHAR(255)    NOT NULL DEFAULT ''     COMMENT '用户上传时的原始文件名',
  `content_type`  VARCHAR(100)    NOT NULL                COMMENT 'MIME类型，如 image/png',
  `size_bytes`    BIGINT UNSIGNED NOT NULL                COMMENT '文件字节数',
  `sha256`        CHAR(64)        NOT NULL                COMMENT '文件内容的SHA-256，用于秒传去重',
  `public_url`    VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT '对外访问URL',
  `uploader_id`   BIGINT UNSIGNED NOT NULL                COMMENT '上传者用户ID',
  `status`        TINYINT         NOT NULL DEFAULT 0      COMMENT '状态：0临时未引用 1已被业务引用 2待删除',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '上传时间',
  PRIMARY KEY (`id`),
  -- 唯一索引：对象键在存储中唯一，防止覆盖他人文件
  UNIQUE KEY `uk_file_object_key` (`object_key`),
  -- 联合索引：秒传查询 WHERE sha256 = ? AND biz_type = ?
  KEY `idx_file_sha_biz` (`sha256`, `biz_type`),
  -- 联合索引：清理孤儿文件 WHERE status = 0 AND created_at < NOW() - INTERVAL 1 DAY
  KEY `idx_file_status_created` (`status`, `created_at`),
  -- 联合索引：查「某用户上传的全部文件」，用于注销账号时级联清理
  KEY `idx_file_uploader` (`uploader_id`, `biz_type`),
  CONSTRAINT `fk_file_uploader` FOREIGN KEY (`uploader_id`) REFERENCES `sys_user` (`id`),
  CONSTRAINT `ck_file_biz`     CHECK (`biz_type`     IN ('AVATAR','COCKTAIL_IMAGE','PRODUCT_IMAGE')),
  CONSTRAINT `ck_file_storage` CHECK (`storage_type` IN ('LOCAL','MINIO','OSS')),
  CONSTRAINT `ck_file_status`  CHECK (`status` IN (0,1,2)),
  -- 单文件上限 5MB，与现有 src/lib/user-cocktails.js 的 COCKTAIL_IMAGE_MAX_SIZE 保持一致
  CONSTRAINT `ck_file_size`    CHECK (`size_bytes` > 0 AND `size_bytes` <= 5242880)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='文件元数据表（替代 Supabase Storage）';


-- #############################################################################
--  模块 B：内容社区（9 张）—— 从 Supabase Postgres 全量迁移
-- #############################################################################

-- -----------------------------------------------------------------------------
-- B1. cocktail —— 酒款主表
--
-- 迁移设计说明（重要，数据库原理考察点）：
--   原系统的酒款数据分裂在两个地方：
--     ① 8 款内置酒谱硬编码在前端 src/data/cocktails.js（根本不在数据库里）；
--     ② 用户投稿酒款在 Postgres 的 public.user_cocktails 表。
--   这导致评论表 reviews 只能用 cocktail_name（文本）去关联酒款，
--   既无法建外键，也无法保证引用完整性 —— 改个酒名，历史评论就全变孤儿。
--
--   本次迁移把两者合并进同一张 cocktail 表，用 source 字段区分来源，
--   评论表改为通过 cocktail_id 外键关联。这是一次真正的范式修复：
--   消除了「用非键属性（名称）做关联」造成的更新异常与引用完整性缺失。
--
-- 生成列 name_lower：
--   原 Postgres 用 `create unique index on user_cocktails (lower(name))` 实现大小写不敏感唯一。
--   MySQL 8.0 用「STORED 生成列 + 唯一索引」等价实现，兼容性比函数索引更好。
-- -----------------------------------------------------------------------------
CREATE TABLE `cocktail` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '酒款ID',
  `legacy_uid`   CHAR(36)        NULL                    COMMENT '原 user_cocktails.id（UUID），迁移追溯用',
  `source`       TINYINT         NOT NULL DEFAULT 2      COMMENT '来源：1内置酒谱（原 src/data/cocktails.js） 2用户投稿',
  `name`         VARCHAR(60)     NOT NULL                COMMENT '英文名，如 Whiskey Sour',
  `name_lower`   VARCHAR(60)     GENERATED ALWAYS AS (LOWER(`name`)) STORED COMMENT '英文名小写（生成列），用于大小写不敏感的唯一约束',
  `zh_name`      VARCHAR(40)     NOT NULL                COMMENT '中文名，如 威士忌酸',
  `category`     VARCHAR(20)     NOT NULL                COMMENT '分类：classic经典 signature特调 nonalcoholic无酒精',
  `base`         VARCHAR(20)     NOT NULL                COMMENT '基酒：whiskey/tequila/gin/rum/vodka/none',
  `image_url`    VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT '酒款图片URL',
  `image_file_id` BIGINT UNSIGNED NULL                   COMMENT '图片文件ID→sys_file.id（内置酒款为NULL，图片是静态资源）',
  `naming`       VARCHAR(300)    NOT NULL                COMMENT '命名由来',
  `story`        VARCHAR(800)    NOT NULL                COMMENT '背景故事',
  `profile`      VARCHAR(200)    NOT NULL                COMMENT '风味描述',
  `method`       VARCHAR(80)     NOT NULL                COMMENT '调制手法，如 摇和 Shake',
  `user_id`      BIGINT UNSIGNED NULL                    COMMENT '投稿人ID（内置酒款为NULL）',
  `review_count` INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：评论数（反范式，避免列表页 COUNT 全表）',
  `avg_rating`   DECIMAL(3,1)    NOT NULL DEFAULT 0.0    COMMENT '冗余：平均评分 0.0-10.0',
  `status`       TINYINT         NOT NULL DEFAULT 1      COMMENT '状态：0已删除（逻辑删除） 1正常',
  `created_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `updated_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  -- 唯一索引：英文名大小写不敏感唯一，等价于原 Postgres 的 lower(name) 唯一索引
  UNIQUE KEY `uk_cocktail_name_lower` (`name_lower`),
  -- 唯一索引：保证同一条 Postgres 记录不会被重复导入
  UNIQUE KEY `uk_cocktail_legacy_uid` (`legacy_uid`),
  -- 联合索引：酒单页按「分类 + 基酒」筛选后按时间倒序，最左前缀全命中，避免 filesort
  KEY `idx_cocktail_cat_base_time` (`category`, `base`, `created_at` DESC),
  -- 联合索引：账号中心「我的投稿」列表
  KEY `idx_cocktail_user_time` (`user_id`, `created_at` DESC),
  -- 联合索引：首页「高分酒款」推荐
  KEY `idx_cocktail_status_rating` (`status`, `avg_rating` DESC),
  CONSTRAINT `fk_cocktail_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_cocktail_source`   CHECK (`source` IN (1,2)),
  CONSTRAINT `ck_cocktail_category` CHECK (`category` IN ('classic','signature','nonalcoholic')),
  CONSTRAINT `ck_cocktail_base`     CHECK (`base` IN ('whiskey','tequila','gin','rum','vodka','none')),
  -- 以下长度约束逐条对应原 supabase/user-cocktails-setup.sql 的 char_length 检查
  CONSTRAINT `ck_cocktail_name`     CHECK (CHAR_LENGTH(`name`)    BETWEEN 2  AND 60),
  CONSTRAINT `ck_cocktail_zh_name`  CHECK (CHAR_LENGTH(`zh_name`) BETWEEN 1  AND 40),
  CONSTRAINT `ck_cocktail_naming`   CHECK (CHAR_LENGTH(`naming`)  BETWEEN 10 AND 300),
  CONSTRAINT `ck_cocktail_story`    CHECK (CHAR_LENGTH(`story`)   BETWEEN 20 AND 800),
  CONSTRAINT `ck_cocktail_profile`  CHECK (CHAR_LENGTH(`profile`) BETWEEN 5  AND 200),
  CONSTRAINT `ck_cocktail_method`   CHECK (CHAR_LENGTH(`method`)  BETWEEN 2  AND 80),
  CONSTRAINT `ck_cocktail_rating`   CHECK (`avg_rating` >= 0 AND `avg_rating` <= 10),
  -- 业务规则：内置酒款没有投稿人，用户投稿必须有投稿人
  CONSTRAINT `ck_cocktail_owner`    CHECK ((`source` = 1 AND `user_id` IS NULL) OR (`source` = 2 AND `user_id` IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='酒款主表（合并内置酒谱与用户投稿，原 public.user_cocktails）';


-- -----------------------------------------------------------------------------
-- B2. cocktail_ingredient —— 酒款配方材料（子表）
--
-- ★★★ Postgres text[] 数组类型的迁移方案（本次设计的关键决策）★★★
--   原字段：public.user_cocktails.ingredients text[] NOT NULL
--           CHECK (cardinality(ingredients) BETWEEN 2 AND 12)
--
--   MySQL 没有数组类型，有两条路：
--     方案一：JSON 列  `ingredients JSON`
--     方案二：拆成子表（本方案采用）
--
--   选择拆子表的理由（第一范式 1NF 的直接要求）：
--     ① 1NF 要求「每个字段都是不可再分的原子值」。数组/JSON 存多个材料
--        本质是把一个「重复组」塞进一列，直接违反 1NF。
--     ② 拆表后可以对材料做 SQL 查询：
--        「找出所有用到金酒的酒款」→ WHERE content LIKE '%金酒%'，可走索引；
--        JSON 方案要用 JSON_SEARCH/JSON_TABLE，写法复杂且难以索引。
--     ③ 单条材料可以加 CHECK 长度约束（2–120 字符），
--        JSON 方案只能整体校验，无法约束数组内每个元素。
--     ④ 引用完整性：子表有外键 + ON DELETE CASCADE，删酒款自动清材料。
--     ⑤ 未来可扩展：拆出 amount/unit 字段做「按分量计算成本」，JSON 改起来是灾难。
--
--   代价（诚实说明）：
--     查询酒款详情需要多一次 JOIN 或一次批量 IN 查询。
--     但酒款详情页 QPS 很低，且可整页缓存，这个代价可以忽略。
--
--   「材料 2–12 条」这个跨行约束 MySQL 的 CHECK 无法表达（CHECK 只能作用于单行），
--   实现方式见 04_procedures_triggers.sql 中的 trg_ingredient_count_* 触发器，
--   以及 05_verification.sql 中的校验查询。
-- -----------------------------------------------------------------------------
CREATE TABLE `cocktail_ingredient` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '材料行ID',
  `cocktail_id` BIGINT UNSIGNED NOT NULL                COMMENT '所属酒款ID',
  `sort_no`     SMALLINT UNSIGNED NOT NULL              COMMENT '序号（1开始），保留原数组的顺序语义',
  `content`     VARCHAR(120)    NOT NULL                COMMENT '材料内容，如「波本威士忌 45 ml」',
  PRIMARY KEY (`id`),
  -- 唯一索引：同一酒款内序号不重复，既保证顺序稳定，也天然防止重复插入
  UNIQUE KEY `uk_ingredient_cocktail_sort` (`cocktail_id`, `sort_no`),
  -- 普通索引：支撑「按材料反查酒款」的模糊搜索（前缀索引，只索引前 32 字符以控制索引体积）
  KEY `idx_ingredient_content` (`content`(32)),
  CONSTRAINT `fk_ingredient_cocktail` FOREIGN KEY (`cocktail_id`) REFERENCES `cocktail` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_ingredient_content` CHECK (CHAR_LENGTH(`content`) BETWEEN 2 AND 120),
  CONSTRAINT `ck_ingredient_sort`    CHECK (`sort_no` BETWEEN 1 AND 12)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='酒款配方材料子表（替代 Postgres 的 text[] 数组列，满足1NF）';


-- -----------------------------------------------------------------------------
-- B3. cocktail_review —— 酒款评论（原 public.reviews）
--
-- 迁移改动（范式修复）：
--   原表字段：cocktail_name text, cocktail_zh_name text, user_email, user_name, user_avatar
--   这些冗余是 Supabase 架构下的无奈之举 —— PostgREST 受 RLS 限制无法 JOIN auth.users，
--   只能把用户昵称头像冗余进每一行。副作用是：用户改了昵称，历史评论仍显示旧昵称（更新异常）。
--
--   迁移到 MySQL 后可以自由 JOIN sys_user，因此：
--     ✅ 去掉 user_email / user_name / user_avatar 冗余 → 消除更新异常，达到 3NF
--     ✅ cocktail_name 换成 cocktail_id 外键 → 建立真正的引用完整性
--     ✅ 新增 like_count 冗余计数（这是有意的反范式，理由见下）
--
--   为什么 like_count 可以冗余而 user_name 不可以？
--     判据是「冗余值会不会因为源数据变更而失真」。
--     like_count 是聚合结果，只会被点赞/取消点赞这两个动作改变，
--     且我们在同一事务里同步维护它，不存在其它路径让它失真；
--     user_name 则会被「用户改昵称」这个完全无关的动作弄脏。
-- -----------------------------------------------------------------------------
CREATE TABLE `cocktail_review` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '评论ID',
  `legacy_uid`  CHAR(36)        NULL                    COMMENT '原 reviews.id（UUID），迁移追溯用',
  `cocktail_id` BIGINT UNSIGNED NOT NULL                COMMENT '酒款ID（原来是 cocktail_name 文本，迁移后改为外键）',
  `user_id`     BIGINT UNSIGNED NOT NULL                COMMENT '评论者ID',
  `rating`      DECIMAL(3,1)    NOT NULL                COMMENT '评分 0.0-10.0（用DECIMAL而非FLOAT，避免浮点误差影响均分计算）',
  `content`     VARCHAR(500)    NOT NULL                COMMENT '评论正文，最长500字符',
  `like_count`  INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：点赞数',
  `status`      TINYINT         NOT NULL DEFAULT 1      COMMENT '状态：0已删除 1正常',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '发表时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_review_legacy_uid` (`legacy_uid`),
  -- 联合索引：酒款详情页「该酒款的评论列表，按时间倒序」，
  --           WHERE cocktail_id=? AND status=1 ORDER BY id DESC 三段全走索引
  KEY `idx_review_cocktail_status_id` (`cocktail_id`, `status`, `id` DESC),
  -- 联合索引：账号中心「我的评论」
  KEY `idx_review_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_review_cocktail` FOREIGN KEY (`cocktail_id`) REFERENCES `cocktail` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_review_user`     FOREIGN KEY (`user_id`)     REFERENCES `sys_user` (`id`) ON DELETE CASCADE,
  -- 评分区间约束，对应原 supabase-setup.sql 的 check (rating >= 0 and rating <= 10)
  CONSTRAINT `ck_review_rating`  CHECK (`rating` >= 0 AND `rating` <= 10),
  CONSTRAINT `ck_review_content` CHECK (CHAR_LENGTH(`content`) BETWEEN 1 AND 500),
  CONSTRAINT `ck_review_status`  CHECK (`status` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='酒款评论（原 public.reviews，已修复为外键关联并去除用户信息冗余）';


-- -----------------------------------------------------------------------------
-- B4. cocktail_review_like —— 评论点赞（原 public.review_likes）
--
-- 主键设计：原表用 `id uuid PRIMARY KEY` + `unique(review_id, user_id)`，
--           即「代理主键 + 唯一约束」。迁移后改为直接用复合主键 (review_id, user_id)：
--     ① 少一个自增列、少一个二级索引，表更窄；
--     ② 聚簇索引直接按 (review_id, user_id) 组织，
--        「查某条评论的全部点赞人」和「判断我是否点过赞」都能走聚簇索引，无需回表；
--     ③ 唯一性由主键本身保证 —— 这是「点赞并发去重」的核心：
--        两个并发的点赞请求，第二个会直接撞主键冲突（Duplicate entry），
--        数据库层面物理上不可能产生两条重复点赞。
-- -----------------------------------------------------------------------------
CREATE TABLE `cocktail_review_like` (
  `review_id`  BIGINT UNSIGNED NOT NULL COMMENT '评论ID',
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '点赞者ID',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '点赞时间',
  -- 复合主键 = 唯一约束 = 并发去重的物理保证
  PRIMARY KEY (`review_id`, `user_id`),
  -- 反向联合索引：账号中心「我点赞过的评论」，按时间倒序
  KEY `idx_reviewlike_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_reviewlike_review` FOREIGN KEY (`review_id`) REFERENCES `cocktail_review` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reviewlike_user`   FOREIGN KEY (`user_id`)   REFERENCES `sys_user` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='评论点赞（原 public.review_likes）';


-- -----------------------------------------------------------------------------
-- B5. story_post —— 喝酒故事帖子（原 public.stories_posts）
-- 同样去除了 user_email / user_name / user_avatar 三个冗余字段。
-- -----------------------------------------------------------------------------
CREATE TABLE `story_post` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '帖子ID',
  `legacy_uid`     CHAR(36)        NULL                    COMMENT '原 stories_posts.id（UUID）',
  `title`          VARCHAR(60)     NOT NULL                COMMENT '标题，1-60字符',
  `body`           VARCHAR(500)    NOT NULL                COMMENT '正文，1-500字符',
  `category`       VARCHAR(20)     NOT NULL                COMMENT '分类：bar酒吧 recipe配方 city城市 memory回忆',
  `user_id`        BIGINT UNSIGNED NOT NULL                COMMENT '发帖人ID',
  `reply_count`    INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：回复数',
  `like_count`     INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：点赞数',
  `favorite_count` INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：收藏数',
  `status`         TINYINT         NOT NULL DEFAULT 1      COMMENT '状态：0已删除 1正常',
  `created_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '发表时间',
  `updated_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_post_legacy_uid` (`legacy_uid`),
  -- 联合索引：论坛首页「按分类筛选 + 时间倒序」，对应原 stories_posts_created_at_idx 的加强版
  KEY `idx_post_status_cat_id` (`status`, `category`, `id` DESC),
  -- 联合索引：账号中心「我的帖子」
  KEY `idx_post_user_time` (`user_id`, `created_at` DESC),
  -- 联合索引：「热门帖子」排行
  KEY `idx_post_status_like` (`status`, `like_count` DESC),
  CONSTRAINT `fk_post_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_post_category` CHECK (`category` IN ('bar','recipe','city','memory')),
  CONSTRAINT `ck_post_title`    CHECK (CHAR_LENGTH(`title`) BETWEEN 1 AND 60),
  CONSTRAINT `ck_post_body`     CHECK (CHAR_LENGTH(`body`)  BETWEEN 1 AND 500),
  CONSTRAINT `ck_post_status`   CHECK (`status` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='喝酒故事帖子（原 public.stories_posts）';


-- -----------------------------------------------------------------------------
-- B6. story_reply —— 帖子回复（原 public.stories_replies）
--
-- 嵌套回复的存储：沿用原设计的「邻接表」模型（parent_reply_id 自引用）。
--   新增 root_reply_id 字段是一个针对邻接表缺陷的优化：
--   邻接表查整棵子树需要递归（MySQL 8 的 WITH RECURSIVE CTE），成本较高；
--   加上 root_reply_id 后，「取某个一级回复下的全部楼中楼」变成一次等值查询。
--   这是「路径枚举/闭包表」思想的轻量化版本，适合本项目只有两层的回复结构。
-- -----------------------------------------------------------------------------
CREATE TABLE `story_reply` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '回复ID',
  `legacy_uid`      CHAR(36)        NULL                    COMMENT '原 stories_replies.id（UUID）',
  `post_id`         BIGINT UNSIGNED NOT NULL                COMMENT '所属帖子ID',
  `parent_reply_id` BIGINT UNSIGNED NULL                    COMMENT '父回复ID（自引用），NULL表示一级回复',
  `root_reply_id`   BIGINT UNSIGNED NULL                    COMMENT '所属一级回复ID，用于一次查询取出整个楼中楼',
  `user_id`         BIGINT UNSIGNED NOT NULL                COMMENT '回复者ID',
  `body`            VARCHAR(280)    NOT NULL                COMMENT '回复正文，1-280字符',
  `like_count`      INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：点赞数',
  `status`          TINYINT         NOT NULL DEFAULT 1      COMMENT '状态：0已删除 1正常',
  `created_at`      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '回复时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reply_legacy_uid` (`legacy_uid`),
  -- 联合索引：帖子详情页拉取全部回复，对应原 stories_replies_post_id_idx
  KEY `idx_reply_post_status_id` (`post_id`, `status`, `id`),
  -- 普通索引：对应原 stories_replies_parent_reply_id_idx，支撑父子关系查询
  KEY `idx_reply_parent` (`parent_reply_id`),
  -- 普通索引：一次取出某一级回复下的全部楼中楼
  KEY `idx_reply_root` (`root_reply_id`),
  -- 联合索引：账号中心「我的回复」
  KEY `idx_reply_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_reply_post`   FOREIGN KEY (`post_id`)         REFERENCES `story_post` (`id`)   ON DELETE CASCADE,
  CONSTRAINT `fk_reply_parent` FOREIGN KEY (`parent_reply_id`) REFERENCES `story_reply` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reply_user`   FOREIGN KEY (`user_id`)         REFERENCES `sys_user` (`id`)     ON DELETE CASCADE,
  CONSTRAINT `ck_reply_body`   CHECK (CHAR_LENGTH(`body`) BETWEEN 1 AND 280),
  CONSTRAINT `ck_reply_status` CHECK (`status` IN (0,1)),
  -- 防止自己回复自己造成的环
  CONSTRAINT `ck_reply_no_self` CHECK (`parent_reply_id` IS NULL OR `parent_reply_id` <> `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='帖子回复（原 public.stories_replies，支持两层嵌套）';


-- -----------------------------------------------------------------------------
-- B7/B8/B9. 帖子点赞 / 帖子收藏 / 回复点赞
-- 三张表结构同构，全部沿用原 Postgres 的复合主键设计（原本就是 primary key (x_id, user_id)）。
-- 复合主键既是唯一约束，也是并发去重的物理保证。
-- -----------------------------------------------------------------------------
CREATE TABLE `story_post_like` (
  `post_id`    BIGINT UNSIGNED NOT NULL COMMENT '帖子ID',
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '点赞者ID',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '点赞时间',
  PRIMARY KEY (`post_id`, `user_id`),
  -- 反向索引：账号中心「我点赞过的帖子」，按时间倒序聚合
  KEY `idx_postlike_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_postlike_post` FOREIGN KEY (`post_id`) REFERENCES `story_post` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_postlike_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='帖子点赞（原 public.stories_post_likes）';

CREATE TABLE `story_post_favorite` (
  `post_id`    BIGINT UNSIGNED NOT NULL COMMENT '帖子ID',
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '收藏者ID',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '收藏时间',
  PRIMARY KEY (`post_id`, `user_id`),
  -- 反向索引：账号中心「我的收藏」列表
  KEY `idx_postfav_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_postfav_post` FOREIGN KEY (`post_id`) REFERENCES `story_post` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_postfav_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='帖子收藏（原 public.stories_post_favorites）';

CREATE TABLE `story_reply_like` (
  `reply_id`   BIGINT UNSIGNED NOT NULL COMMENT '回复ID',
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '点赞者ID',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '点赞时间',
  PRIMARY KEY (`reply_id`, `user_id`),
  KEY `idx_replylike_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_replylike_reply` FOREIGN KEY (`reply_id`) REFERENCES `story_reply` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_replylike_user`  FOREIGN KEY (`user_id`)  REFERENCES `sys_user` (`id`)    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='回复点赞（原 public.stories_reply_likes）';


-- #############################################################################
--  模块 C：电商购物（15 张）—— 全新模块
-- #############################################################################

-- -----------------------------------------------------------------------------
-- C1. shop_user_address —— 收货地址簿
-- 「同一用户仅一条默认地址」的实现：
--   MySQL 的唯一索引把多个 NULL 视为互不相同，
--   因此用生成列 default_flag（is_default=1 时为 user_id，否则为 NULL）
--   加唯一索引，即可在数据库层强制「每人至多一条默认地址」。
--   这是一个很实用的技巧：把业务规则下沉到数据库约束，而不是靠应用层自觉。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_user_address` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '地址ID',
  `user_id`        BIGINT UNSIGNED NOT NULL                COMMENT '所属用户ID',
  `receiver_name`  VARCHAR(32)     NOT NULL                COMMENT '收货人姓名',
  `receiver_phone` VARCHAR(20)     NOT NULL                COMMENT '收货人手机号',
  `province`       VARCHAR(32)     NOT NULL DEFAULT ''     COMMENT '省',
  `city`           VARCHAR(32)     NOT NULL DEFAULT ''     COMMENT '市',
  `district`       VARCHAR(32)     NOT NULL DEFAULT ''     COMMENT '区/县',
  `detail`         VARCHAR(200)    NOT NULL                COMMENT '详细地址',
  `is_default`     TINYINT         NOT NULL DEFAULT 0      COMMENT '是否默认地址：0否 1是',
  `default_flag`   BIGINT UNSIGNED GENERATED ALWAYS AS (IF(`is_default` = 1, `user_id`, NULL)) STORED
                                                           COMMENT '生成列：默认地址时等于user_id，否则NULL。配合唯一索引强制「每人至多一条默认地址」',
  `deleted`        TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除：0未删 1已删',
  `created_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `updated_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  -- 唯一索引 + 生成列：数据库层强制每个用户最多一条默认地址（NULL 不参与唯一性比较）
  UNIQUE KEY `uk_addr_default` (`default_flag`),
  -- 联合索引：查「我的地址簿（未删除的）」
  KEY `idx_addr_user_deleted` (`user_id`, `deleted`),
  CONSTRAINT `fk_addr_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_addr_phone`   CHECK (CHAR_LENGTH(`receiver_phone`) BETWEEN 5 AND 20),
  CONSTRAINT `ck_addr_default` CHECK (`is_default` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='收货地址簿';


-- -----------------------------------------------------------------------------
-- C2. shop_category —— 商品分类
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_category` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '分类ID',
  `code`       VARCHAR(32)  NOT NULL                COMMENT '分类编码，如 spirit / tool / gift',
  `name`       VARCHAR(32)  NOT NULL                COMMENT '英文名',
  `zh_name`    VARCHAR(32)  NOT NULL                COMMENT '中文名',
  `icon`       VARCHAR(500) NOT NULL DEFAULT ''     COMMENT '分类图标URL',
  `sort_order` INT          NOT NULL DEFAULT 0      COMMENT '排序权重，越小越靠前',
  `status`     TINYINT      NOT NULL DEFAULT 1      COMMENT '状态：0隐藏 1显示',
  `created_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_category_code` (`code`),
  KEY `idx_category_status_sort` (`status`, `sort_order`),
  CONSTRAINT `ck_category_status` CHECK (`status` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='商品分类';


-- -----------------------------------------------------------------------------
-- C3. shop_product —— 商品 SPU（Standard Product Unit）
-- 与 cocktail 表的关系：可选关联。例如「Whiskey Sour 调酒礼盒」关联到 Whiskey Sour 酒款，
-- 商品详情页可以展示对应酒谱，酒款详情页可以展示「购买同款材料」。
-- 这是全量迁移到单一数据库后才能做到的跨模块 JOIN —— 共存架构下做不到。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_product` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '商品ID(SPU)',
  `product_code` VARCHAR(32)     NOT NULL                COMMENT '商品编码',
  `name`         VARCHAR(60)     NOT NULL                COMMENT '英文名',
  `zh_name`      VARCHAR(40)     NOT NULL                COMMENT '中文名',
  `subtitle`     VARCHAR(120)    NOT NULL DEFAULT ''     COMMENT '副标题/卖点',
  `category_id`  INT UNSIGNED    NOT NULL                COMMENT '分类ID',
  `cocktail_id`  BIGINT UNSIGNED NULL                    COMMENT '关联酒款ID（可选），支撑「酒谱↔商品」互相导流',
  `cover_image`  VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT '封面图URL',
  `images`       JSON            NULL                    COMMENT '轮播图URL数组。此处用JSON是合理的：图片列表只整体读写，不做条件查询',
  `detail`       TEXT            NULL                    COMMENT '商品详情（HTML，入库前经白名单过滤防XSS）',
  `min_price`    DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '冗余：最低SKU价格，用于列表页排序，避免每次子查询',
  `sale_count`   INT UNSIGNED    NOT NULL DEFAULT 0      COMMENT '冗余：累计销量',
  `status`       TINYINT         NOT NULL DEFAULT 0      COMMENT '状态：0下架 1上架',
  `created_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `updated_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_product_code` (`product_code`),
  -- 联合索引：分类页「上架商品按销量倒序」，三段全走索引
  KEY `idx_product_cat_status_sale` (`category_id`, `status`, `sale_count` DESC),
  -- 联合索引：全站「上架商品按价格排序」
  KEY `idx_product_status_price` (`status`, `min_price`),
  -- 普通索引：从酒款详情页反查关联商品
  KEY `idx_product_cocktail` (`cocktail_id`),
  CONSTRAINT `fk_product_category` FOREIGN KEY (`category_id`) REFERENCES `shop_category` (`id`),
  CONSTRAINT `fk_product_cocktail` FOREIGN KEY (`cocktail_id`) REFERENCES `cocktail` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_product_status` CHECK (`status` IN (0,1)),
  CONSTRAINT `ck_product_price`  CHECK (`min_price` >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='商品SPU';


-- -----------------------------------------------------------------------------
-- C4. shop_sku —— 商品 SKU（Stock Keeping Unit）
-- 库存不放在这张表里，原因见 shop_inventory 的注释（读写分离）。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_sku` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'SKU ID',
  `product_id` BIGINT UNSIGNED NOT NULL                COMMENT '所属商品ID',
  `sku_code`   VARCHAR(40)     NOT NULL                COMMENT 'SKU编码',
  `spec_name`  VARCHAR(60)     NOT NULL                COMMENT '规格名，如「700ml / 单瓶装」',
  `price`      DECIMAL(10,2)   NOT NULL                COMMENT '售价（元）。用DECIMAL，绝不用FLOAT/DOUBLE',
  `image`      VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT 'SKU图片URL',
  `status`     TINYINT         NOT NULL DEFAULT 1      COMMENT '状态：0停售 1在售',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_sku_code` (`sku_code`),
  -- 联合索引：商品详情页拉取该商品的全部在售SKU
  KEY `idx_sku_product_status` (`product_id`, `status`),
  CONSTRAINT `fk_sku_product` FOREIGN KEY (`product_id`) REFERENCES `shop_product` (`id`),
  CONSTRAINT `ck_sku_price`  CHECK (`price` > 0),
  CONSTRAINT `ck_sku_status` CHECK (`status` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='商品SKU';


-- -----------------------------------------------------------------------------
-- ★★★ C5. shop_inventory —— 库存表（三段式模型）★★★
--
-- 这是全系统写入最热的一张表，也是「保证数据不会错乱」的核心。
--
-- 为什么库存单独建表而不是放在 shop_sku 里？
--   shop_sku 是「读多写少」，适合大范围缓存；
--   shop_inventory 是「写极多」，每次下单都要更新，是行锁热点。
--   分表之后：
--     ① SKU 行不会被库存的行锁阻塞；
--     ② 库存表每行只有 6 个整数列，行很窄 → 单个数据页能放更多行
--        → Buffer Pool 命中率更高 → 热点行几乎永远在内存里；
--     ③ 库存表不建任何二级索引，写入时无需维护额外索引。
--
-- 主键就是 sku_id（不另设自增列）：
--   InnoDB 主键是聚簇索引，`WHERE sku_id = ?` 直接命中聚簇索引叶子页，
--   只加一把行锁，没有二级索引回表、没有额外的锁。这是热点写入的最优形态。
--
-- 三段式不变式：available_stock + locked_stock + sold_stock = total_stock
--   这条不变式被写成 CHECK 约束。任何代码 bug 只要破坏守恒，
--   MySQL 会直接报错并回滚整个事务 —— 错误在第一现场就被拦下，不会扩散。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_inventory` (
  `sku_id`          BIGINT UNSIGNED NOT NULL           COMMENT 'SKU ID（与shop_sku一对一，直接做主键）',
  `total_stock`     INT             NOT NULL DEFAULT 0 COMMENT '总库存 = 仓库实物总数',
  `available_stock` INT             NOT NULL DEFAULT 0 COMMENT '★可售库存：可被新订单占用',
  `locked_stock`    INT             NOT NULL DEFAULT 0 COMMENT '★已锁定：已下单未支付',
  `sold_stock`      INT             NOT NULL DEFAULT 0 COMMENT '★已售出：已支付',
  `safety_stock`    INT             NOT NULL DEFAULT 5 COMMENT '低库存预警阈值，低于此值前端显示「仅剩N件」',
  `version`         BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '版本号，每次变更+1，用于审计与问题排查',
  `updated_at`      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最后变更时间',
  PRIMARY KEY (`sku_id`),
  CONSTRAINT `fk_inv_sku` FOREIGN KEY (`sku_id`) REFERENCES `shop_sku` (`id`),
  -- ★ 数据库层最后一道防线：任何路径都不可能把库存写成负数
  CONSTRAINT `ck_inv_available_nonneg` CHECK (`available_stock` >= 0),
  CONSTRAINT `ck_inv_locked_nonneg`    CHECK (`locked_stock`    >= 0),
  CONSTRAINT `ck_inv_sold_nonneg`      CHECK (`sold_stock`      >= 0),
  CONSTRAINT `ck_inv_total_nonneg`     CHECK (`total_stock`     >= 0),
  CONSTRAINT `ck_inv_safety_nonneg`    CHECK (`safety_stock`    >= 0),
  -- ★★★ 库存守恒不变式：三段之和必须严格等于总量 ★★★
  CONSTRAINT `ck_inv_conservation`
    CHECK (`available_stock` + `locked_stock` + `sold_stock` = `total_stock`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='库存主表（三段式：可售/锁定/已售，含守恒CHECK约束）';


-- -----------------------------------------------------------------------------
-- ★ C6. shop_inventory_ledger —— 库存流水台账（append-only）
--
-- 双重作用：
--   ① 审计：每一次库存变动都留痕，含变动前后的完整快照，事后可逐笔追溯。
--   ② 幂等：uk_ledger_biz 唯一索引是整个系统「防重复扣减/重复回补」的物理保证。
--      同一业务单（订单号/退款单号）对同一SKU的同类操作，物理上只能记录一次。
--      即使支付回调重复通知 100 次，第二次插入就会被数据库拒绝，事务回滚，
--      库存一次都不会多扣或多加。
--
-- 本表禁止 UPDATE 和 DELETE（由 04_procedures_triggers.sql 中的触发器强制），
-- 这样台账就是不可篡改的事实记录，可以用它反推任意时刻的库存状态。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_inventory_ledger` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '流水ID',
  `sku_id`          BIGINT UNSIGNED NOT NULL                COMMENT 'SKU ID',
  `biz_type`        VARCHAR(24)     NOT NULL                COMMENT '业务类型：INIT初始化 RESTOCK补货 ADJUST调整 ORDER_LOCK下单锁定 ORDER_CANCEL取消释放 ORDER_EXPIRE超时释放 PAY_CONFIRM支付确认 REFUND_RETURN退货入库 REFUND_WRITEOFF仅退款核销',
  `biz_no`          VARCHAR(64)     NOT NULL                COMMENT '业务单号：订单号/退款单号/调整单号',
  `delta_available` INT             NOT NULL DEFAULT 0      COMMENT '可售库存变化量（可正可负）',
  `delta_locked`    INT             NOT NULL DEFAULT 0      COMMENT '锁定库存变化量',
  `delta_sold`      INT             NOT NULL DEFAULT 0      COMMENT '已售库存变化量',
  `delta_total`     INT             NOT NULL DEFAULT 0      COMMENT '总库存变化量',
  `after_available` INT             NOT NULL                COMMENT '变更后可售库存快照',
  `after_locked`    INT             NOT NULL                COMMENT '变更后锁定库存快照',
  `after_sold`      INT             NOT NULL                COMMENT '变更后已售库存快照',
  `after_total`     INT             NOT NULL                COMMENT '变更后总库存快照',
  `operator_type`   VARCHAR(16)     NOT NULL DEFAULT 'SYSTEM' COMMENT '操作方：USER用户 ADMIN管理员 SYSTEM系统',
  `operator_id`     BIGINT UNSIGNED NULL                    COMMENT '操作人用户ID',
  `remark`          VARCHAR(200)    NOT NULL DEFAULT ''     COMMENT '备注',
  `created_at`      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '发生时间',
  PRIMARY KEY (`id`),
  -- ★★★ 幂等核心：同一业务单对同一SKU的同类操作只能记录一次 ★★★
  UNIQUE KEY `uk_ledger_biz` (`biz_type`, `biz_no`, `sku_id`),
  -- 联合索引：后台「某SKU的库存变动历史」，按时间倒序
  KEY `idx_ledger_sku_time` (`sku_id`, `created_at` DESC),
  -- 普通索引：按订单号追溯该单涉及的全部库存变动
  KEY `idx_ledger_biz_no` (`biz_no`),
  CONSTRAINT `fk_ledger_sku` FOREIGN KEY (`sku_id`) REFERENCES `shop_sku` (`id`),
  CONSTRAINT `ck_ledger_biz_type` CHECK (`biz_type` IN
    ('INIT','RESTOCK','ADJUST','ORDER_LOCK','ORDER_CANCEL','ORDER_EXPIRE','PAY_CONFIRM','REFUND_RETURN','REFUND_WRITEOFF')),
  CONSTRAINT `ck_ledger_operator` CHECK (`operator_type` IN ('USER','ADMIN','SYSTEM')),
  -- ★ 单条流水自身也必须守恒：三段增量之和 = 总量增量
  CONSTRAINT `ck_ledger_conservation`
    CHECK (`delta_available` + `delta_locked` + `delta_sold` = `delta_total`),
  -- ★ 快照自身也必须守恒
  CONSTRAINT `ck_ledger_after_conservation`
    CHECK (`after_available` + `after_locked` + `after_sold` = `after_total`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='库存变动流水台账（只增不改，幂等载体+审计依据）';


-- -----------------------------------------------------------------------------
-- C7. shop_cart_item —— 购物车
-- 购物车不占库存（电商通用设计），只在展示时实时查询库存做失效提示。
-- uk_cart_user_sku 唯一索引的作用：让「加购已存在的商品则累加数量」
-- 变成一条原子的 INSERT ... ON DUPLICATE KEY UPDATE，
-- 消除「先SELECT判断存在再INSERT或UPDATE」的 TOCTOU 竞态。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_cart_item` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '购物车条目ID',
  `user_id`    BIGINT UNSIGNED NOT NULL                COMMENT '用户ID',
  `sku_id`     BIGINT UNSIGNED NOT NULL                COMMENT 'SKU ID',
  `quantity`   INT             NOT NULL DEFAULT 1      COMMENT '数量 1-99',
  `selected`   TINYINT         NOT NULL DEFAULT 1      COMMENT '是否勾选结算：0否 1是',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '加入时间',
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  -- ★ 唯一索引：支撑 INSERT ... ON DUPLICATE KEY UPDATE 的原子加购
  UNIQUE KEY `uk_cart_user_sku` (`user_id`, `sku_id`),
  -- 联合索引：购物车列表按最近加入排序
  KEY `idx_cart_user_updated` (`user_id`, `updated_at` DESC),
  CONSTRAINT `fk_cart_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_cart_sku`  FOREIGN KEY (`sku_id`)  REFERENCES `shop_sku` (`id`)  ON DELETE CASCADE,
  CONSTRAINT `ck_cart_quantity` CHECK (`quantity` BETWEEN 1 AND 99),
  CONSTRAINT `ck_cart_selected` CHECK (`selected` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='购物车（不占库存）';


-- -----------------------------------------------------------------------------
-- ★ C8. shop_order —— 订单主表
--
-- 有意反范式说明（数据库原理考察点）：
--   receiver_name / receiver_phone / receiver_address 三个字段冗余存储了
--   下单时刻的收货信息，而不是只存 address_id 去 JOIN shop_user_address。
--   这看起来违反 2NF/3NF，但是必要的：
--     收货地址是「历史事实的快照」。用户三个月后修改或删除了地址簿里的地址，
--     不能让三个月前那笔订单的收货信息跟着变 —— 那会让订单记录失去法律与对账意义。
--   判据：快照字段写入后永不修改，因此不存在「更新异常」，
--        反范式的经典风险在这里并不成立。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_order` (
  `id`               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '订单ID',
  `order_no`         VARCHAR(32)     NOT NULL                COMMENT '业务订单号 yyyyMMddHHmmss+机器码2位+序列4位',
  `user_id`          BIGINT UNSIGNED NOT NULL                COMMENT '下单用户ID',
  `status`           VARCHAR(20)     NOT NULL DEFAULT 'PENDING_PAYMENT' COMMENT '订单状态，取值见CHECK约束',
  `total_amount`     DECIMAL(10,2)   NOT NULL                COMMENT '商品总额',
  `freight_amount`   DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '运费',
  `discount_amount`  DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '优惠金额',
  `pay_amount`       DECIMAL(10,2)   NOT NULL                COMMENT '应付金额 = 商品总额 + 运费 - 优惠',
  `refunded_amount`  DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '累计已退款金额',
  `item_count`       INT             NOT NULL DEFAULT 0      COMMENT '商品总件数',
  `receiver_name`    VARCHAR(32)     NOT NULL                COMMENT '收货人（下单时快照，有意反范式）',
  `receiver_phone`   VARCHAR(20)     NOT NULL                COMMENT '收货电话（快照）',
  `receiver_address` VARCHAR(300)    NOT NULL                COMMENT '收货地址（快照）',
  `remark`           VARCHAR(200)    NOT NULL DEFAULT ''     COMMENT '买家留言',
  `tracking_no`      VARCHAR(64)     NOT NULL DEFAULT ''     COMMENT '物流单号',
  `idempotency_key`  VARCHAR(64)     NOT NULL                COMMENT '★下单幂等键（前端生成UUID）',
  `expire_at`        DATETIME(3)     NOT NULL                COMMENT '超时未支付的关单时间',
  `pay_time`         DATETIME(3)     NULL                    COMMENT '支付成功时间',
  `ship_time`        DATETIME(3)     NULL                    COMMENT '发货时间',
  `finish_time`      DATETIME(3)     NULL                    COMMENT '完成时间',
  `close_time`       DATETIME(3)     NULL                    COMMENT '关闭时间',
  `close_reason`     VARCHAR(64)     NOT NULL DEFAULT ''     COMMENT '关闭原因',
  `version`          BIGINT UNSIGNED NOT NULL DEFAULT 0      COMMENT '版本号（审计用）',
  `created_at`       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '下单时间',
  `updated_at`       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_no` (`order_no`),
  -- ★★★ 防重复下单的数据库级兜底：即使 Redis 幂等令牌失效，
  --      同一用户用同一 idempotency_key 的第二次插入也会被拒绝 ★★★
  UNIQUE KEY `uk_order_user_idem` (`user_id`, `idempotency_key`),
  -- 联合索引：「我的订单」列表 WHERE user_id=? AND status=? ORDER BY id DESC
  --           三段全走索引，避免 Using filesort
  KEY `idx_order_user_status_id` (`user_id`, `status`, `id` DESC),
  -- 联合索引：超时扫描兜底任务 WHERE status='PENDING_PAYMENT' AND expire_at < NOW()
  --           待支付订单占比小，索引选择性高
  KEY `idx_order_status_expire` (`status`, `expire_at`),
  -- 普通索引：后台按时间范围检索订单、统计当日GMV
  KEY `idx_order_created` (`created_at`),
  CONSTRAINT `fk_order_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`),
  CONSTRAINT `ck_order_status` CHECK (`status` IN
    ('PENDING_PAYMENT','PAID','SHIPPED','COMPLETED','CANCELLED','CLOSED','REFUNDING','PARTIAL_REFUNDED','REFUNDED')),
  CONSTRAINT `ck_order_amount_nonneg` CHECK (`total_amount` >= 0 AND `pay_amount` >= 0
                                         AND `freight_amount` >= 0 AND `discount_amount` >= 0),
  -- ★ 应付金额的计算关系必须恒成立（防止改价接口算错）
  CONSTRAINT `ck_order_amount_formula`
    CHECK (`pay_amount` = `total_amount` + `freight_amount` - `discount_amount`),
  -- ★ 已退金额不能超过应付金额
  CONSTRAINT `ck_order_refunded` CHECK (`refunded_amount` >= 0 AND `refunded_amount` <= `pay_amount`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='订单主表';


-- -----------------------------------------------------------------------------
-- ★ C9. shop_order_item —— 订单明细（商品快照，有意反范式）
--
-- 冗余 product_name / sku_spec_name / sku_image / unit_price 的理由：
--   商品改名、调价、下架后，历史订单必须仍能正确展示成交时的信息。
--   如果只存 sku_id 靠 JOIN 取名字和价格，会出现
--   「三年前买的酒现在显示成新品名和新价格」这种严重业务错误。
--   这些字段写入后永不修改，因此不存在更新异常。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_order_item` (
  `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '明细ID',
  `order_id`          BIGINT UNSIGNED NOT NULL                COMMENT '订单ID',
  `order_no`          VARCHAR(32)     NOT NULL                COMMENT '冗余：订单号，便于按单号直查免JOIN',
  `user_id`           BIGINT UNSIGNED NOT NULL                COMMENT '冗余：用户ID，便于按用户做购买统计',
  `product_id`        BIGINT UNSIGNED NOT NULL                COMMENT '商品ID',
  `sku_id`            BIGINT UNSIGNED NOT NULL                COMMENT 'SKU ID',
  `product_name`      VARCHAR(60)     NOT NULL                COMMENT '★快照：成交时的商品英文名',
  `product_zh_name`   VARCHAR(40)     NOT NULL                COMMENT '★快照：成交时的商品中文名',
  `sku_spec_name`     VARCHAR(60)     NOT NULL                COMMENT '★快照：成交时的规格名',
  `sku_image`         VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT '★快照：成交时的SKU图片',
  `unit_price`        DECIMAL(10,2)   NOT NULL                COMMENT '★快照：成交单价',
  `quantity`          INT             NOT NULL                COMMENT '购买数量',
  `total_amount`      DECIMAL(10,2)   NOT NULL                COMMENT '小计 = 单价 × 数量',
  `refunded_quantity` INT             NOT NULL DEFAULT 0      COMMENT '累计已退数量（支持部分退款）',
  `refunded_amount`   DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '累计已退金额',
  `created_at`        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  PRIMARY KEY (`id`),
  -- 普通索引：订单详情页拉取明细
  KEY `idx_item_order` (`order_id`),
  -- 普通索引：按订单号直查明细
  KEY `idx_item_order_no` (`order_no`),
  -- 普通索引：统计某SKU的销量、对账时按SKU汇总
  KEY `idx_item_sku` (`sku_id`),
  -- 联合索引：账号中心「我买过的商品」
  KEY `idx_item_user_created` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_item_order` FOREIGN KEY (`order_id`) REFERENCES `shop_order` (`id`),
  CONSTRAINT `fk_item_sku`   FOREIGN KEY (`sku_id`)   REFERENCES `shop_sku` (`id`),
  CONSTRAINT `ck_item_quantity` CHECK (`quantity` > 0),
  -- ★ 小计的计算关系必须恒成立
  CONSTRAINT `ck_item_amount_formula` CHECK (`total_amount` = `unit_price` * `quantity`),
  -- ★ 退款数量永远不能超过购买数量（防超退的数据库兜底）
  CONSTRAINT `ck_item_refund_qty` CHECK (`refunded_quantity` >= 0 AND `refunded_quantity` <= `quantity`),
  CONSTRAINT `ck_item_refund_amt` CHECK (`refunded_amount` >= 0 AND `refunded_amount` <= `total_amount`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='订单明细（含成交快照，有意反范式）';


-- -----------------------------------------------------------------------------
-- C10. shop_payment —— 支付流水（对接支付宝沙箱 / 微信支付沙箱）
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_payment` (
  `id`               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '支付单ID',
  `payment_no`       VARCHAR(32)     NOT NULL                COMMENT '本地支付单号（提交给支付宝的 out_trade_no）',
  `order_no`         VARCHAR(32)     NOT NULL                COMMENT '关联订单号',
  `user_id`          BIGINT UNSIGNED NOT NULL                COMMENT '付款用户ID',
  `channel`          VARCHAR(24)     NOT NULL                COMMENT '支付渠道：ALIPAY_SANDBOX支付宝沙箱 WECHAT_SANDBOX微信沙箱',
  `amount`           DECIMAL(10,2)   NOT NULL                COMMENT '支付金额',
  `status`           VARCHAR(16)     NOT NULL DEFAULT 'PENDING' COMMENT '状态：PENDING待支付 SUCCESS成功 FAILED失败 CLOSED已关闭',
  `channel_trade_no` VARCHAR(64)     NULL                    COMMENT '渠道流水号（支付宝的 trade_no / 微信的 transaction_id）',
  `buyer_account`    VARCHAR(100)    NOT NULL DEFAULT ''     COMMENT '付款方账号（支付宝沙箱买家账号），脱敏后存储',
  `notify_payload`   JSON            NULL                    COMMENT '最后一次成功回调的原始报文（排查问题用）',
  `paid_at`          DATETIME(3)     NULL                    COMMENT '支付成功时间（以渠道回调的 gmt_payment 为准）',
  `expire_at`        DATETIME(3)     NOT NULL                COMMENT '支付单过期时间',
  `created_at`       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `updated_at`       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_no` (`payment_no`),
  -- ★ 唯一索引：同一笔渠道流水只能对应一条支付记录，防止重复入账
  --   （NULL 不参与唯一性比较，所以待支付的记录可以有多条 channel_trade_no IS NULL）
  UNIQUE KEY `uk_payment_channel_trade_no` (`channel_trade_no`),
  -- 普通索引：按订单号查该单的全部支付尝试
  KEY `idx_payment_order_no` (`order_no`),
  -- 联合索引：对账任务扫描「超过1分钟仍为PENDING的支付单」，主动向渠道查询
  KEY `idx_payment_status_created` (`status`, `created_at`),
  CONSTRAINT `fk_payment_user` FOREIGN KEY (`user_id`) REFERENCES `sys_user` (`id`),
  CONSTRAINT `ck_payment_channel` CHECK (`channel` IN ('ALIPAY_SANDBOX','WECHAT_SANDBOX')),
  CONSTRAINT `ck_payment_status`  CHECK (`status`  IN ('PENDING','SUCCESS','FAILED','CLOSED')),
  CONSTRAINT `ck_payment_amount`  CHECK (`amount` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='支付流水（支付宝/微信沙箱）';


-- -----------------------------------------------------------------------------
-- ★ C11. shop_payment_notify_log —— 支付回调原始日志
--
-- 支付宝的异步通知规则：商户未返回 "success" 时，
-- 会按 4m / 10m / 10m / 1h / 2h / 6h / 15h 的间隔重复通知，最多 8 次。
-- 也就是说「重复回调」是必然事件，不是异常情况。
--
-- uk_notify 唯一索引是防重的第一道闸：
--   支付宝每次通知都带唯一的 notify_id，
--   重复通知在 INSERT 这一步就被数据库拒绝（Duplicate entry），
--   应用层捕获后直接返回 "success"，不进入任何业务逻辑。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_payment_notify_log` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
  `channel`       VARCHAR(24)     NOT NULL                COMMENT '渠道',
  `notify_id`     VARCHAR(128)    NOT NULL                COMMENT '★渠道通知唯一ID（支付宝的 notify_id）',
  `notify_type`   VARCHAR(32)     NOT NULL DEFAULT ''     COMMENT '通知类型：trade_status_sync 等',
  `payment_no`    VARCHAR(32)     NOT NULL DEFAULT ''     COMMENT '关联的本地支付单号',
  `trade_status`  VARCHAR(32)     NOT NULL DEFAULT ''     COMMENT '渠道交易状态：TRADE_SUCCESS/TRADE_CLOSED 等',
  `raw_body`      TEXT            NOT NULL                COMMENT '完整原始报文（排查纠纷的唯一依据）',
  `sign_verified` TINYINT         NOT NULL DEFAULT 0      COMMENT '验签是否通过：0否 1是',
  `handle_status` VARCHAR(16)     NOT NULL DEFAULT 'PENDING' COMMENT '处理结果：PENDING/SUCCESS/IGNORED重复/FAILED',
  `handle_remark` VARCHAR(200)    NOT NULL DEFAULT ''     COMMENT '处理备注',
  `source_ip`     VARCHAR(45)     NOT NULL DEFAULT ''     COMMENT '回调来源IP',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '接收时间',
  PRIMARY KEY (`id`),
  -- ★★★ 重复通知在这里被数据库直接拒绝 ★★★
  UNIQUE KEY `uk_notify` (`channel`, `notify_id`),
  KEY `idx_notify_payment_no` (`payment_no`),
  -- 联合索引：排查「验签失败的回调」，安全审计用
  KEY `idx_notify_verified_time` (`sign_verified`, `created_at` DESC),
  CONSTRAINT `ck_notify_handle` CHECK (`handle_status` IN ('PENDING','SUCCESS','IGNORED','FAILED')),
  CONSTRAINT `ck_notify_verified` CHECK (`sign_verified` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='支付回调原始日志（幂等第一道闸+纠纷证据）';


-- -----------------------------------------------------------------------------
-- ★ C12. shop_refund —— 退款单
-- restock 字段区分两种退款语义：
--   restock=1 退货退款：商品回到仓库 → sold -= n, available += n，total 不变
--   restock=0 仅退款：  商品未退回   → sold -= n, total -= n（核销损失）
-- 这个区分是「库存回滚正确姿势」的关键，简单的 stock = stock + n 无法表达。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_refund` (
  `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '退款单ID',
  `refund_no`         VARCHAR(32)     NOT NULL                COMMENT '退款单号（提交给渠道的 out_request_no）',
  `order_no`          VARCHAR(32)     NOT NULL                COMMENT '关联订单号',
  `order_item_id`     BIGINT UNSIGNED NOT NULL                COMMENT '关联订单明细ID（支持按行部分退款）',
  `sku_id`            BIGINT UNSIGNED NOT NULL                COMMENT 'SKU ID（冗余，便于库存回滚免JOIN）',
  `user_id`           BIGINT UNSIGNED NOT NULL                COMMENT '申请人ID',
  `refund_type`       VARCHAR(24)     NOT NULL                COMMENT '类型：REFUND_ONLY仅退款 RETURN_AND_REFUND退货退款',
  `quantity`          INT             NOT NULL                COMMENT '退款数量',
  `refund_amount`     DECIMAL(10,2)   NOT NULL                COMMENT '退款金额',
  `reason`            VARCHAR(200)    NOT NULL DEFAULT ''     COMMENT '退款原因',
  `status`            VARCHAR(20)     NOT NULL DEFAULT 'APPLYING' COMMENT '状态：APPLYING申请中 AUDITED已审核 REJECTED已驳回 REFUNDING退款中 SUCCESS成功 FAILED失败',
  `restock`           TINYINT         NOT NULL DEFAULT 1      COMMENT '★是否回补库存：1退货入库 0仅退款核销',
  `idempotency_key`   VARCHAR(64)     NOT NULL                COMMENT '申请幂等键',
  `channel_refund_no` VARCHAR(64)     NULL                    COMMENT '渠道退款流水号',
  `audit_remark`      VARCHAR(200)    NOT NULL DEFAULT ''     COMMENT '审核备注',
  `apply_at`          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '申请时间',
  `audit_at`          DATETIME(3)     NULL                    COMMENT '审核时间',
  `refund_at`         DATETIME(3)     NULL                    COMMENT '退款到账时间',
  `updated_at`        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_refund_no` (`refund_no`),
  -- ★ 防重复申请
  UNIQUE KEY `uk_refund_user_idem` (`user_id`, `idempotency_key`),
  -- ★ 防重复入账
  UNIQUE KEY `uk_refund_channel_no` (`channel_refund_no`),
  KEY `idx_refund_order_no` (`order_no`),
  -- 联合索引：后台「待审核退款单」列表
  KEY `idx_refund_status_apply` (`status`, `apply_at`),
  KEY `idx_refund_user_time` (`user_id`, `apply_at` DESC),
  CONSTRAINT `fk_refund_item` FOREIGN KEY (`order_item_id`) REFERENCES `shop_order_item` (`id`),
  CONSTRAINT `fk_refund_user` FOREIGN KEY (`user_id`)       REFERENCES `sys_user` (`id`),
  CONSTRAINT `ck_refund_type`   CHECK (`refund_type` IN ('REFUND_ONLY','RETURN_AND_REFUND')),
  CONSTRAINT `ck_refund_status` CHECK (`status` IN ('APPLYING','AUDITED','REJECTED','REFUNDING','SUCCESS','FAILED')),
  CONSTRAINT `ck_refund_qty`    CHECK (`quantity` > 0),
  CONSTRAINT `ck_refund_amount` CHECK (`refund_amount` >= 0),
  CONSTRAINT `ck_refund_restock` CHECK (`restock` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='退款单';


-- -----------------------------------------------------------------------------
-- C13. shop_order_status_log —— 订单状态流转日志
-- 作用：① 订单详情页的「状态时间轴」展示；② 审计追溯；③ 答辩时直观演示状态机。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_order_status_log` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
  `order_no`      VARCHAR(32)     NOT NULL                COMMENT '订单号',
  `from_status`   VARCHAR(20)     NOT NULL DEFAULT ''     COMMENT '原状态（创建时为空）',
  `to_status`     VARCHAR(20)     NOT NULL                COMMENT '新状态',
  `event`         VARCHAR(32)     NOT NULL                COMMENT '触发事件：CREATE/PAY/CANCEL/EXPIRE/SHIP/CONFIRM/REFUND_APPLY/REFUND_DONE/REFUND_REJECT',
  `operator_type` VARCHAR(16)     NOT NULL DEFAULT 'SYSTEM' COMMENT '操作方：USER/ADMIN/SYSTEM',
  `operator_id`   BIGINT UNSIGNED NULL                    COMMENT '操作人ID',
  `remark`        VARCHAR(200)    NOT NULL DEFAULT ''     COMMENT '备注',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '发生时间',
  PRIMARY KEY (`id`),
  -- 联合索引：订单详情页按时间正序渲染时间轴
  KEY `idx_statuslog_order_time` (`order_no`, `created_at`),
  CONSTRAINT `ck_statuslog_operator` CHECK (`operator_type` IN ('USER','ADMIN','SYSTEM'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='订单状态机流转日志';


-- -----------------------------------------------------------------------------
-- C14. shop_product_favorite —— 商品收藏
-- 与内容社区的 story_post_favorite 保持同构设计（复合主键 = 并发去重）。
-- 账号中心的「我的收藏」通过 UNION ALL 聚合两张表，见 05_verification.sql 中的视图。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_product_favorite` (
  `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '收藏者ID',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '收藏时间',
  PRIMARY KEY (`product_id`, `user_id`),
  KEY `idx_prodfav_user_time` (`user_id`, `created_at` DESC),
  CONSTRAINT `fk_prodfav_product` FOREIGN KEY (`product_id`) REFERENCES `shop_product` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_prodfav_user`    FOREIGN KEY (`user_id`)    REFERENCES `sys_user` (`id`)     ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='商品收藏';


-- -----------------------------------------------------------------------------
-- C15. shop_delay_task —— 延迟任务兜底表
-- 主通道是 Redisson 延迟队列（秒级精度）；本表是「Redis宕机/消息丢失」时的最后保险。
-- 两个通道调用同一个幂等方法，重复执行完全无害。
-- -----------------------------------------------------------------------------
CREATE TABLE `shop_delay_task` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '任务ID',
  `task_type`   VARCHAR(32)     NOT NULL                COMMENT '任务类型：CLOSE_ORDER超时关单 AUTO_CONFIRM自动确认收货',
  `biz_no`      VARCHAR(64)     NOT NULL                COMMENT '业务单号',
  `execute_at`  DATETIME(3)     NOT NULL                COMMENT '计划执行时间',
  `status`      TINYINT         NOT NULL DEFAULT 0      COMMENT '状态：0待执行 1已执行 2已取消',
  `retry_count` INT             NOT NULL DEFAULT 0      COMMENT '重试次数',
  `last_error`  VARCHAR(500)    NOT NULL DEFAULT ''     COMMENT '最后一次失败原因',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `updated_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  -- 唯一索引：同一业务单的同类任务只登记一次
  UNIQUE KEY `uk_task_type_biz` (`task_type`, `biz_no`),
  -- 联合索引：扫描任务 WHERE status=0 AND execute_at <= NOW()
  KEY `idx_task_status_execute` (`status`, `execute_at`),
  CONSTRAINT `ck_task_type`   CHECK (`task_type` IN ('CLOSE_ORDER','AUTO_CONFIRM')),
  CONSTRAINT `ck_task_status` CHECK (`status` IN (0,1,2))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='延迟任务兜底表';


-- #############################################################################
--  模块 D：迁移辅助（1 张）
-- #############################################################################

-- -----------------------------------------------------------------------------
-- D1. mig_uid_map —— Postgres UUID 到 MySQL BIGINT 的映射表
--
-- 用途：从 Supabase 导出的数据里，所有外键都是 UUID。
--       导入 MySQL 时必须把 UUID 换算成新的自增 ID，这张表就是换算字典。
-- 迁移流程：
--   ① 先导入主表（sys_user / cocktail / story_post ...），
--      导入时把 legacy_uid 填上，MySQL 自动分配 id；
--   ② 从主表 SELECT legacy_uid, id 写入本表；
--   ③ 导入从表时 JOIN 本表把 UUID 外键翻译成 BIGINT。
-- 迁移验收通过后本表可归档，但建议保留以备追溯。
-- -----------------------------------------------------------------------------
CREATE TABLE `mig_uid_map` (
  `entity_type` VARCHAR(32)     NOT NULL COMMENT '实体类型：USER/COCKTAIL/REVIEW/POST/REPLY',
  `legacy_uid`  CHAR(36)        NOT NULL COMMENT '原 Postgres 的 UUID',
  `new_id`      BIGINT UNSIGNED NOT NULL COMMENT '新 MySQL 的自增ID',
  `migrated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '迁移时间',
  PRIMARY KEY (`entity_type`, `legacy_uid`),
  -- 反向索引：从新ID反查原UUID（排查问题时用）
  KEY `idx_mig_new_id` (`entity_type`, `new_id`),
  CONSTRAINT `ck_mig_entity` CHECK (`entity_type` IN ('USER','COCKTAIL','REVIEW','POST','REPLY'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='迁移辅助：Postgres UUID → MySQL BIGINT 映射字典';


-- #############################################################################
--  视图：跨模块聚合（全量迁移后才可能实现，共存架构下做不到）
-- #############################################################################

-- -----------------------------------------------------------------------------
-- V1. v_user_favorite —— 我的收藏（跨模块聚合）
-- 用 UNION ALL 把「帖子收藏」和「商品收藏」合并成统一的时间线。
-- 用 UNION ALL 而非 UNION：两个分支的 target_type 不同，不可能产生重复行，
-- 用 UNION 会白白多做一次去重排序，性能更差。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `v_user_favorite` AS
SELECT
    f.`user_id`                       AS `user_id`,
    'POST'                            AS `target_type`,
    f.`post_id`                       AS `target_id`,
    p.`title`                         AS `title`,
    LEFT(p.`body`, 80)                AS `summary`,
    ''                                AS `cover_image`,
    f.`created_at`                    AS `created_at`
FROM `story_post_favorite` f
JOIN `story_post` p ON p.`id` = f.`post_id` AND p.`status` = 1
UNION ALL
SELECT
    f.`user_id`,
    'PRODUCT',
    f.`product_id`,
    pr.`zh_name`,
    pr.`subtitle`,
    pr.`cover_image`,
    f.`created_at`
FROM `shop_product_favorite` f
JOIN `shop_product` pr ON pr.`id` = f.`product_id`;


-- -----------------------------------------------------------------------------
-- V2. v_user_like —— 我的点赞（跨三种目标聚合）
-- 支撑账号中心的「近期点赞内容」。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `v_user_like` AS
SELECT
    l.`user_id`            AS `user_id`,
    'POST'                 AS `target_type`,
    l.`post_id`            AS `target_id`,
    p.`title`              AS `title`,
    LEFT(p.`body`, 80)     AS `snippet`,
    l.`created_at`         AS `created_at`
FROM `story_post_like` l
JOIN `story_post` p ON p.`id` = l.`post_id` AND p.`status` = 1
UNION ALL
SELECT
    l.`user_id`, 'REPLY', l.`reply_id`,
    CONCAT('回复 #', r.`id`), LEFT(r.`body`, 80), l.`created_at`
FROM `story_reply_like` l
JOIN `story_reply` r ON r.`id` = l.`reply_id` AND r.`status` = 1
UNION ALL
SELECT
    l.`user_id`, 'REVIEW', l.`review_id`,
    c.`zh_name`, LEFT(rv.`content`, 80), l.`created_at`
FROM `cocktail_review_like` l
JOIN `cocktail_review` rv ON rv.`id` = l.`review_id` AND rv.`status` = 1
JOIN `cocktail` c ON c.`id` = rv.`cocktail_id`;


-- -----------------------------------------------------------------------------
-- V3. v_inventory_health —— 库存健康快照（后台一键对账用）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `v_inventory_health` AS
SELECT
    i.`sku_id`,
    s.`sku_code`,
    p.`zh_name`                                                            AS `product_name`,
    i.`total_stock`,
    i.`available_stock`,
    i.`locked_stock`,
    i.`sold_stock`,
    (i.`available_stock` + i.`locked_stock` + i.`sold_stock` - i.`total_stock`) AS `conservation_diff`,
    COALESCE(l.`ledger_available`, 0)                                      AS `ledger_available`,
    (i.`available_stock` - COALESCE(l.`ledger_available`, 0))              AS `ledger_diff`,
    CASE
        WHEN i.`available_stock` = 0                    THEN 'SOLD_OUT'
        WHEN i.`available_stock` <= i.`safety_stock`    THEN 'LOW_STOCK'
        ELSE 'IN_STOCK'
    END                                                                    AS `stock_status`
FROM `shop_inventory` i
JOIN `shop_sku` s     ON s.`id` = i.`sku_id`
JOIN `shop_product` p ON p.`id` = s.`product_id`
LEFT JOIN (
    SELECT `sku_id`,
           SUM(`delta_available`) AS `ledger_available`
    FROM `shop_inventory_ledger`
    GROUP BY `sku_id`
) l ON l.`sku_id` = i.`sku_id`;


SET FOREIGN_KEY_CHECKS = 1;
SET SQL_MODE = @OLD_SQL_MODE;

-- =============================================================================
--  建表完成：31 张表 + 3 个视图
--    模块A 系统与鉴权  6 张：sys_config / sys_user / sys_auth_code /
--                            sys_refresh_token / sys_login_log / sys_file
--    模块B 内容社区    9 张：cocktail / cocktail_ingredient / cocktail_review /
--                            cocktail_review_like / story_post / story_reply /
--                            story_post_like / story_post_favorite / story_reply_like
--    模块C 电商购物   15 张：shop_user_address / shop_category / shop_product /
--                            shop_sku / shop_inventory / shop_inventory_ledger /
--                            shop_cart_item / shop_order / shop_order_item /
--                            shop_payment / shop_payment_notify_log / shop_refund /
--                            shop_order_status_log / shop_product_favorite / shop_delay_task
--    模块D 迁移辅助    1 张：mig_uid_map
--
--  下一步：依次执行 02_indexes.sql → 03_seed_data.sql →
--          04_procedures_triggers.sql → 05_verification.sql
-- =============================================================================
