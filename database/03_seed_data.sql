-- =============================================================================
--  Luceria Cocktail Atelier —— 初始化与测试数据
--  文件：database/03_seed_data.sql
--  前置：必须先执行 01_schema.sql（02_indexes.sql 可后执行）
--
--  本脚本内容：
--    1. 系统配置          8 条
--    2. 测试用户          6 个（含 1 个管理员）
--    3. ★ 8 款内置鸡尾酒  —— 完整搬运自 src/data/cocktails.js，含 33 条配方材料
--    4. 酒款评论与点赞    示例数据
--    5. 论坛帖子/回复/点赞/收藏  示例数据
--    6. 商品分类 / 商品 / SKU / ★库存（含 INIT 台账）
--    7. 收货地址
--    8. 一笔完整的示例订单（用于演示订单详情页与状态时间轴）
--
--  ★ 显式指定主键 ID 的原因：
--    压测脚本、验证脚本、接口文档里都写死了 sku_id = 1001 这类 ID。
--    如果依赖自增，重跑一次脚本 ID 就会漂移，导致所有引用失效。
--    因此这里显式给定 ID，保证任何时候重置数据库后 ID 都一致、可复现。
-- =============================================================================

USE `luceria`;
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- 清空（按外键依赖的逆序），便于反复执行本脚本
TRUNCATE TABLE `mig_uid_map`;
TRUNCATE TABLE `shop_delay_task`;
TRUNCATE TABLE `shop_product_favorite`;
TRUNCATE TABLE `shop_order_status_log`;
TRUNCATE TABLE `shop_refund`;
TRUNCATE TABLE `shop_payment_notify_log`;
TRUNCATE TABLE `shop_payment`;
TRUNCATE TABLE `shop_order_item`;
TRUNCATE TABLE `shop_order`;
TRUNCATE TABLE `shop_cart_item`;
TRUNCATE TABLE `shop_inventory_ledger`;
TRUNCATE TABLE `shop_inventory`;
TRUNCATE TABLE `shop_sku`;
TRUNCATE TABLE `shop_product`;
TRUNCATE TABLE `shop_category`;
TRUNCATE TABLE `shop_user_address`;
TRUNCATE TABLE `story_reply_like`;
TRUNCATE TABLE `story_post_favorite`;
TRUNCATE TABLE `story_post_like`;
TRUNCATE TABLE `story_reply`;
TRUNCATE TABLE `story_post`;
TRUNCATE TABLE `cocktail_review_like`;
TRUNCATE TABLE `cocktail_review`;
TRUNCATE TABLE `cocktail_ingredient`;
TRUNCATE TABLE `cocktail`;
TRUNCATE TABLE `sys_file`;
TRUNCATE TABLE `sys_login_log`;
TRUNCATE TABLE `sys_refresh_token`;
TRUNCATE TABLE `sys_auth_code`;
TRUNCATE TABLE `sys_user`;
TRUNCATE TABLE `sys_config`;

SET FOREIGN_KEY_CHECKS = 1;


-- #############################################################################
--  1. 系统配置
-- #############################################################################
INSERT INTO `sys_config` (`config_key`, `config_value`, `value_type`, `description`, `editable`) VALUES
('order.timeout.minutes',        '15',    'INT',    '订单超时未支付的关闭时长（分钟）。答辩演示时可临时改为 1 便于展示自动关单', 1),
('order.autoConfirm.days',       '7',     'INT',    '发货后自动确认收货的天数', 1),
('order.afterSale.days',         '7',     'INT',    '订单完成后可申请售后的天数', 1),
('stock.redis.enabled',          'true',  'BOOL',   '是否启用 Redis 库存预扣减漏斗。关闭后直连 MySQL CAS，吞吐下降但正确性不变', 1),
('stock.reconcile.cron',         '0 */5 * * * ?', 'STRING', '库存对账任务的 cron 表达式（每5分钟）', 1),
('auth.code.expireMinutes',      '10',    'INT',    '邮箱验证码有效期（分钟）', 1),
('auth.code.resendCooldownSec',  '60',    'INT',    '验证码重发冷却秒数，对应原 src/stores/auth.js 的 EMAIL_REQUEST_COOLDOWN_MS', 1),
('profile.editCooldownDays',     '7',     'INT',    '资料修改冷却天数，对应原 PROFILE_UPDATE_COOLDOWN_MS（7天）', 1);


-- #############################################################################
--  2. 测试用户
--
--  说明：本系统采用邮箱验证码登录，无密码。
--        password_hash 留空，测试时通过接口 POST /api/v1/auth/code 获取验证码，
--        开发环境的验证码会直接打印在后端控制台日志里，无需真实收信。
--
--  legacy_uid 模拟从 Supabase 迁移过来的原始 UUID，用于验证迁移映射逻辑。
-- #############################################################################
INSERT INTO `sys_user`
(`id`, `legacy_uid`, `email`, `email_verified`, `display_name`, `avatar_url`, `role`, `status`, `profile_updated_at`, `created_at`) VALUES
(1, 'a1b2c3d4-0001-4000-8000-000000000001', '17622609612@163.com', 1, 'Luceria 主理人', '', 'admin', 1, NULL, '2026-03-01 10:00:00.000'),
(2, 'a1b2c3d4-0002-4000-8000-000000000002', 'demo01@luceria.test', 1, '深夜调酒师',     '', 'user',  1, '2026-08-20 21:30:00.000', '2026-03-14 10:22:00.000'),
(3, 'a1b2c3d4-0003-4000-8000-000000000003', 'demo02@luceria.test', 1, '柑橘控 Aria',    '', 'user',  1, NULL, '2026-04-02 15:05:00.000'),
(4, 'a1b2c3d4-0004-4000-8000-000000000004', 'demo03@luceria.test', 1, '不喝酒的旁观者', '', 'user',  1, NULL, '2026-05-19 09:41:00.000'),
(5, 'a1b2c3d4-0005-4000-8000-000000000005', 'demo04@luceria.test', 1, 'Negroni 信徒',   '', 'user',  1, NULL, '2026-06-08 18:12:00.000'),
(6, 'a1b2c3d4-0006-4000-8000-000000000006', 'bench@luceria.test',  1, '压测专用账号',   '', 'user',  1, NULL, '2026-09-01 00:00:00.000');

-- 迁移映射字典（演示用：真实迁移时由 ETL 脚本自动生成）
INSERT INTO `mig_uid_map` (`entity_type`, `legacy_uid`, `new_id`)
SELECT 'USER', `legacy_uid`, `id` FROM `sys_user` WHERE `legacy_uid` IS NOT NULL;

-- 登录日志示例（支撑账号中心的「安全信息」区块）
INSERT INTO `sys_login_log` (`user_id`, `email`, `login_type`, `success`, `ip`, `user_agent`, `created_at`) VALUES
(2, 'demo01@luceria.test', 'EMAIL_OTP',     1, '116.230.11.7',  'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', '2026-09-03 09:10:00.000'),
(2, 'demo01@luceria.test', 'REFRESH_TOKEN', 1, '116.230.11.7',  'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', '2026-09-03 11:40:00.000'),
(3, 'demo02@luceria.test', 'EMAIL_OTP',     1, '223.104.38.90', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)',  '2026-09-02 20:03:00.000');


-- #############################################################################
--  3. ★ 8 款内置鸡尾酒
--     数据 1:1 搬运自 src/data/cocktails.js。
--     迁移后这 8 款不再硬编码在前端，而是和用户投稿酒款一起存在 cocktail 表里，
--     source=1 表示内置。这样评论表才能通过 cocktail_id 外键正确关联它们
--     —— 原来评论只能靠 cocktail_name 文本关联，无法建立引用完整性。
-- #############################################################################
INSERT INTO `cocktail`
(`id`, `source`, `name`, `zh_name`, `category`, `base`, `image_url`, `naming`, `story`, `profile`, `method`, `user_id`, `created_at`) VALUES
(1, 1, 'Whiskey Sour', '威士忌酸', 'classic', 'whiskey', '/assets/whiskey-sour.webp',
 '名字来自酸酒 Sour 家族，以威士忌、柠檬与糖的平衡为核心。',
 'Whiskey Sour 在 19 世纪的美国酒吧文化中成形，早期酸酒常被水手和旅人用于平衡烈酒口感。它的魅力不在复杂，而在酸、甜、烈三者的准确比例。',
 'Bourbon / 柠檬 / 甜酸 / 酒体饱满', '摇和 Shake', NULL, '2026-01-01 00:00:00.000'),

(2, 1, 'Margarita', '玛格丽特', 'classic', 'tequila', '',
 'Margarita 在西班牙语中意为“雏菊”，也被视为 Daisy 酸酒家族的龙舌兰版本。',
 '关于 Margarita 的起源有多种说法，常见故事发生在 20 世纪上半叶的墨西哥与美国边境。盐边、青柠与龙舌兰共同构成了它极具辨识度的仪式感。',
 'Tequila / 青柠 / 橙香 / 清爽咸口', '摇和 Shake', NULL, '2026-01-01 00:01:00.000'),

(3, 1, 'Negroni', '尼格罗尼', 'classic', 'gin', '',
 '相传以意大利 Count Negroni 伯爵命名，源于对 Americano 的烈度升级。',
 'Negroni 诞生于佛罗伦萨的酒吧传说中，金酒替代苏打水后，苦甜草本气息更强。它是餐前酒文化的代表，比例简洁却极考验材料品质。',
 'Gin / Campari / Vermouth / 苦甜草本', '搅拌 Stir', NULL, '2026-01-01 00:02:00.000'),

(4, 1, 'Mojito', '莫吉托', 'classic', 'rum', '',
 '名字常被认为与古巴语境中的香料、酱汁或小魔法有关。',
 'Mojito 与古巴朗姆酒文化密不可分。薄荷、青柠、糖和苏打让朗姆变得明亮，海明威相关传说也让它成为热带酒单上绕不开的经典。',
 'White Rum / 薄荷 / 青柠 / 气泡清爽', '杯中调制 Build', NULL, '2026-01-01 00:03:00.000'),

(5, 1, 'Cosmopolitan', '大都会', 'signature', 'vodka', '',
 'Cosmopolitan 指“世界化、都会感”，名字与它的粉红色视觉一样现代。',
 'Cosmopolitan 在 20 世纪末的纽约酒吧与流行文化中走红。它把伏特加的干净、蔓越莓的酸甜和橙香利口酒结合成优雅的都会风味。',
 'Vodka / 蔓越莓 / 橙香 / 都会酸甜', '摇和 Shake', NULL, '2026-01-01 00:04:00.000'),

(6, 1, 'Pina Colada', '椰林飘香', 'signature', 'rum', '',
 '西班牙语意为“过滤后的菠萝”，直接指向菠萝汁的热带意象。',
 'Pina Colada 与波多黎各度假文化紧密相连。椰子、菠萝和朗姆带来奶油般的热带口感，是最具画面感的经典长饮之一。',
 'White Rum / 菠萝 / 椰子 / 热带奶油感', '搅打 Blend', NULL, '2026-01-01 00:05:00.000'),

(7, 1, 'Black Russian', '黑俄罗斯', 'signature', 'vodka', '',
 'Black 来自咖啡利口酒的深色，Russian 则指伏特加基酒。',
 'Black Russian 通常被认为诞生于 1940 年代布鲁塞尔。它以伏特加和咖啡利口酒构成冷峻而直接的甜苦风味，后来延伸出 White Russian。',
 'Vodka / Coffee Liqueur / 深色甜苦', '杯中调制 Build', NULL, '2026-01-01 00:06:00.000'),

(8, 1, 'Virgin Pina Colada', '无酒精椰林飘香', 'nonalcoholic', 'none', '',
 '沿用 Pina Colada 的热带命名，Virgin 表示无酒精版本。',
 '这款无酒精版本保留菠萝和椰子的度假感，适合不饮酒用户、下午茶场景或餐厅菜单中的轻饮部分。',
 '菠萝 / 椰子 / 奶油感 / 无酒精', '搅打 Blend', NULL, '2026-01-01 00:07:00.000');

-- 用户投稿酒款示例（source=2，必须有 user_id，由 ck_cocktail_owner 约束保证）
INSERT INTO `cocktail`
(`id`, `legacy_uid`, `source`, `name`, `zh_name`, `category`, `base`, `image_url`, `naming`, `story`, `profile`, `method`, `user_id`, `created_at`) VALUES
(9,  'b1b2c3d4-0001-4000-8000-000000000001', 2, 'Midnight Osmanthus', '子夜桂花', 'signature', 'gin', '',
 '把中式桂花香气嫁接到金酒的杜松骨架上，取名自深夜独饮时窗外飘来的桂花味。',
 '这是我在天津的秋夜里试出来的配方。桂花糖浆的甜要克制，否则会压过金酒的草本层次；加一点点盐水可以把香气从甜里拽出来，这个技巧来自糖水铺子。',
 'Gin / 桂花 / 柑橘 / 干型微甜', '摇和 Shake', 2, '2026-08-11 22:40:00.000'),
(10, 'b1b2c3d4-0002-4000-8000-000000000002', 2, 'Grapefruit Static', '西柚静电', 'signature', 'tequila', '',
 '西柚汁与气泡在杯壁上炸开的细密声响，像收音机没调准时的静电噪音。',
 '灵感来自 Paloma，但把苏打换成了西柚风味气泡水，并用龙舌兰的烟熏感去撑住西柚的苦。夏天在阳台上喝，冰块化得比人喝得快。',
 'Tequila / 西柚 / 咸边 / 气泡苦甜', '杯中调制 Build', 3, '2026-08-25 19:15:00.000');

INSERT INTO `mig_uid_map` (`entity_type`, `legacy_uid`, `new_id`)
SELECT 'COCKTAIL', `legacy_uid`, `id` FROM `cocktail` WHERE `legacy_uid` IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 3.1 配方材料（原 Postgres 的 ingredients text[] 拆成的子表，共 41 行）
--     每个酒款的 sort_no 从 1 开始连续编号，保留原数组的顺序语义。
-- -----------------------------------------------------------------------------
INSERT INTO `cocktail_ingredient` (`cocktail_id`, `sort_no`, `content`) VALUES
-- 1 Whiskey Sour（原数组 5 个元素）
(1, 1, '波本威士忌 45 ml'),
(1, 2, '新鲜柠檬汁 25 ml'),
(1, 3, '糖浆 20 ml'),
(1, 4, '蛋清 20 ml（可选）'),
(1, 5, '安格斯图拉苦精 1 dash'),
-- 2 Margarita（4）
(2, 1, '100% Agave Tequila 50 ml'),
(2, 2, 'Triple Sec 20 ml'),
(2, 3, '新鲜青柠汁 15 ml'),
(2, 4, '杯口盐边'),
-- 3 Negroni（4）
(3, 1, '金酒 30 ml'),
(3, 2, 'Campari 30 ml'),
(3, 3, '甜味美思 30 ml'),
(3, 4, '橙皮装饰'),
-- 4 Mojito（5）
(4, 1, '白朗姆 45 ml'),
(4, 2, '新鲜青柠汁 20 ml'),
(4, 3, '细砂糖 2 茶匙'),
(4, 4, '薄荷叶 6-8 片'),
(4, 5, '苏打水补满'),
-- 5 Cosmopolitan（4）
(5, 1, '柑橘伏特加 40 ml'),
(5, 2, 'Triple Sec 15 ml'),
(5, 3, '蔓越莓汁 30 ml'),
(5, 4, '新鲜青柠汁 15 ml'),
-- 6 Pina Colada（4）
(6, 1, '白朗姆 50 ml'),
(6, 2, '椰浆 30 ml'),
(6, 3, '新鲜菠萝汁 50 ml'),
(6, 4, '碎冰适量'),
-- 7 Black Russian（3）
(7, 1, '伏特加 50 ml'),
(7, 2, '咖啡利口酒 20 ml'),
(7, 3, '大冰块'),
-- 8 Virgin Pina Colada（4）
(8, 1, '新鲜菠萝汁 90 ml'),
(8, 2, '椰浆 45 ml'),
(8, 3, '淡奶油 15 ml（可选）'),
(8, 4, '碎冰适量'),
-- 9 子夜桂花（用户投稿，4）
(9, 1, '干型金酒 45 ml'),
(9, 2, '桂花糖浆 12 ml'),
(9, 3, '新鲜柠檬汁 15 ml'),
(9, 4, '盐水 2 drops'),
-- 10 西柚静电（用户投稿，4）
(10, 1, 'Blanco Tequila 45 ml'),
(10, 2, '新鲜西柚汁 45 ml'),
(10, 3, '青柠汁 10 ml'),
(10, 4, '西柚风味气泡水补满');


-- #############################################################################
--  4. 酒款评论与点赞
-- #############################################################################
INSERT INTO `cocktail_review` (`id`, `cocktail_id`, `user_id`, `rating`, `content`, `like_count`, `created_at`) VALUES
(1, 1, 2, 9.0, '蛋清那一步别偷懒，干摇二十秒出来的绵密泡沫是这杯酒的全部体面。', 2, '2026-07-02 21:10:00.000'),
(2, 1, 3, 7.5, '糖浆减到 15 ml 更合我口味，20 ml 对我来说甜了半档。',                 1, '2026-07-05 22:31:00.000'),
(3, 3, 5, 9.5, '三等分才是 Negroni 的灵魂，任何"改良"我都持保留意见。',              3, '2026-07-18 20:05:00.000'),
(4, 4, 2, 8.0, '薄荷别捣碎，轻拍出味就行，捣碎了会发苦，这是我交过的学费。',           1, '2026-08-01 19:22:00.000'),
(5, 8, 4, 8.5, '不喝酒的人终于有一杯不是甜饮料的选择了，菠萝椰浆比例刚好。',           0, '2026-08-14 15:48:00.000'),
(6, 5, 3, 7.0, '蔓越莓汁的品牌影响很大，纯度低的会让整杯变成糖水。',                   0, '2026-08-22 21:03:00.000');

INSERT INTO `cocktail_review_like` (`review_id`, `user_id`, `created_at`) VALUES
(1, 3, '2026-07-03 08:12:00.000'),
(1, 5, '2026-07-03 12:40:00.000'),
(2, 2, '2026-07-06 09:05:00.000'),
(3, 2, '2026-07-19 10:11:00.000'),
(3, 3, '2026-07-19 14:33:00.000'),
(3, 4, '2026-07-20 08:52:00.000'),
(4, 5, '2026-08-02 11:27:00.000');

-- 同步冗余计数（正式运行时由 Service 在同一事务内维护，此处仅为初始化对齐）
UPDATE `cocktail` c
SET c.`review_count` = (SELECT COUNT(*) FROM `cocktail_review` r WHERE r.`cocktail_id` = c.`id` AND r.`status` = 1),
    c.`avg_rating`   = COALESCE((SELECT ROUND(AVG(r.`rating`), 1) FROM `cocktail_review` r WHERE r.`cocktail_id` = c.`id` AND r.`status` = 1), 0.0);


-- #############################################################################
--  5. 论坛：帖子 / 回复 / 点赞 / 收藏
-- #############################################################################
INSERT INTO `story_post` (`id`, `legacy_uid`, `title`, `body`, `category`, `user_id`, `created_at`) VALUES
(1, 'c1b2c3d4-0001-4000-8000-000000000001', '在天津五大道找到一家只有六个座位的酒吧',
 '门口没有招牌，推门进去只有一盏灯和一排酒。老板问我想喝什么，我说随便，他给我调了一杯用桂花糖浆的金酒酸。那一刻我决定把这个配方写进我的投稿里。',
 'bar', 2, '2026-08-12 23:05:00.000'),
(2, 'c1b2c3d4-0002-4000-8000-000000000002', '关于 Negroni 到底能不能加冰块的争论',
 '我坚持大冰球，融水慢，草本层次能撑住十五分钟。有人说应该用碎冰快速稀释，我不同意，那是在喝一杯被稀释的 Campari。',
 'recipe', 5, '2026-08-19 20:41:00.000'),
(3, 'c1b2c3d4-0003-4000-8000-000000000003', '第一次给不喝酒的朋友调无酒精',
 '她说以为无酒精就是果汁，喝完说这个有层次。其实只是把椰浆比例压下来，加了一点盐。有时候让人愿意坐下来的不是酒精。',
 'memory', 4, '2026-08-28 21:17:00.000'),
(4, 'c1b2c3d4-0004-4000-8000-000000000004', '夏天的西柚配方合集，欢迎补充',
 'Paloma 是起点不是终点。我试过西柚 + 龙舌兰 + 盐边、西柚 + 金酒 + 迷迭香、西柚 + 清酒。第三个意外地好，推荐给喜欢清淡的人。',
 'city', 3, '2026-09-01 18:30:00.000');

INSERT INTO `mig_uid_map` (`entity_type`, `legacy_uid`, `new_id`)
SELECT 'POST', `legacy_uid`, `id` FROM `story_post` WHERE `legacy_uid` IS NOT NULL;

-- 回复：1、2、4 是一级回复（parent 为 NULL）；3、5 是楼中楼
INSERT INTO `story_reply` (`id`, `post_id`, `parent_reply_id`, `root_reply_id`, `user_id`, `body`, `like_count`, `created_at`) VALUES
(1, 1, NULL, NULL, 3, '求地址，我下周去天津出差。',                                      2, '2026-08-13 09:12:00.000'),
(2, 1, NULL, NULL, 5, '六个座位的酒吧通常酒单很短，但每一杯都值得点。',                    1, '2026-08-13 12:45:00.000'),
(3, 1, 1,    1,    2, '在重庆道附近，不过老板不太喜欢被写出来，你去了就知道是哪家。',        1, '2026-08-13 14:20:00.000'),
(4, 2, NULL, NULL, 2, '同意大冰球。碎冰适合 Mojito 这种本来就要稀释的，Negroni 不行。',      3, '2026-08-20 08:30:00.000'),
(5, 2, 4,    4,    5, '而且碎冰会让 Campari 的苦提前散掉，喝到后面只剩甜。',                0, '2026-08-20 09:05:00.000'),
(6, 3, NULL, NULL, 2, '盐是无酒精饮品的秘密武器，能把香气从甜里拉出来。',                   1, '2026-08-29 10:02:00.000');

INSERT INTO `story_post_like` (`post_id`, `user_id`, `created_at`) VALUES
(1, 3, '2026-08-13 09:10:00.000'),
(1, 4, '2026-08-13 19:22:00.000'),
(1, 5, '2026-08-14 08:41:00.000'),
(2, 2, '2026-08-20 08:28:00.000'),
(2, 3, '2026-08-21 11:15:00.000'),
(3, 2, '2026-08-29 09:58:00.000'),
(3, 5, '2026-08-30 20:07:00.000'),
(4, 2, '2026-09-01 19:44:00.000');

INSERT INTO `story_post_favorite` (`post_id`, `user_id`, `created_at`) VALUES
(1, 3, '2026-08-13 09:11:00.000'),
(2, 2, '2026-08-20 08:29:00.000'),
(4, 2, '2026-09-01 19:45:00.000'),
(4, 5, '2026-09-02 07:30:00.000');

INSERT INTO `story_reply_like` (`reply_id`, `user_id`, `created_at`) VALUES
(1, 2, '2026-08-13 10:00:00.000'),
(1, 5, '2026-08-13 15:31:00.000'),
(2, 3, '2026-08-13 13:02:00.000'),
(3, 3, '2026-08-13 15:00:00.000'),
(4, 3, '2026-08-20 09:00:00.000'),
(4, 4, '2026-08-20 10:11:00.000'),
(4, 5, '2026-08-20 11:20:00.000'),
(6, 4, '2026-08-29 11:30:00.000');

-- 同步冗余计数
UPDATE `story_post` p SET
  p.`reply_count`    = (SELECT COUNT(*) FROM `story_reply`        r WHERE r.`post_id` = p.`id` AND r.`status` = 1),
  p.`like_count`     = (SELECT COUNT(*) FROM `story_post_like`    l WHERE l.`post_id` = p.`id`),
  p.`favorite_count` = (SELECT COUNT(*) FROM `story_post_favorite` f WHERE f.`post_id` = p.`id`);

UPDATE `story_reply` r SET
  r.`like_count` = (SELECT COUNT(*) FROM `story_reply_like` l WHERE l.`reply_id` = r.`id`);


-- #############################################################################
--  6. 电商：分类 / 商品 / SKU / ★库存
-- #############################################################################
INSERT INTO `shop_category` (`id`, `code`, `name`, `zh_name`, `sort_order`, `status`) VALUES
(1, 'spirit', 'Base Spirits',  '基酒',   10, 1),
(2, 'tool',   'Bar Tools',     '调酒器具', 20, 1),
(3, 'gift',   'Gift Sets',     '礼盒',   30, 1),
(4, 'mixer',  'Mixers & Syrup','辅料与糖浆', 40, 1);

-- 商品（部分商品通过 cocktail_id 关联到酒款，实现「酒谱 ↔ 商品」互相导流。
--       这种跨模块外键在原来的 Supabase / MySQL 共存架构下是不可能建立的。）
INSERT INTO `shop_product`
(`id`, `product_code`, `name`, `zh_name`, `subtitle`, `category_id`, `cocktail_id`, `cover_image`, `min_price`, `sale_count`, `status`, `created_at`) VALUES
(1, 'P-WS-GIFT',   'Whiskey Sour Kit',    '威士忌酸调酒礼盒',  '含波本、苦精与柠檬糖浆，照着酒谱就能复刻', 3, 1,    '/assets/whiskey-sour.webp', 129.00, 0, 1, '2026-08-01 10:00:00.000'),
(2, 'P-SHAKER',    'Boston Shaker',       '波士顿摇酒壶',      '304 不锈钢 550ml，专业酒吧同款',        2, NULL, '',                          70.00,  0, 1, '2026-08-01 10:05:00.000'),
(3, 'P-JIGGER',    'Japanese Jigger',     '日式量酒器',        '30/45ml 双头，刻度清晰不挂液',          2, NULL, '',                          38.00,  0, 1, '2026-08-01 10:10:00.000'),
(4, 'P-GIN-DRY',   'London Dry Gin',      '伦敦干金酒',        '杜松突出，Negroni 与 Gin Tonic 通用',   1, 3,    '',                          188.00, 0, 1, '2026-08-02 09:00:00.000'),
(5, 'P-CAMPARI',   'Bitter Aperitivo',    '苦味餐前酒',        'Negroni 三等分中的那一份苦',            1, 3,    '',                          158.00, 0, 1, '2026-08-02 09:05:00.000'),
(6, 'P-SYRUP-OSM', 'Osmanthus Syrup',     '桂花糖浆',          '子夜桂花配方指定，甜度克制',            4, 9,    '',                          46.00,  0, 1, '2026-08-15 14:00:00.000'),
(7, 'P-MOJITO-KIT','Mojito Summer Kit',   '莫吉托夏日套装',    '白朗姆 + 薄荷 + 捣棒，开箱即调',        3, 4,    '',                          148.00, 0, 1, '2026-08-20 11:00:00.000'),
(8, 'P-GLASS-SET', 'Coupe Glass Set',     '碟形杯两只装',      '160ml 手工吹制，适合所有短饮',          2, NULL, '',                          96.00,  0, 1, '2026-08-25 16:00:00.000');

-- SKU：★ ID 从 1001 开始，与接口文档、压测脚本、EXPLAIN 验证脚本中的示例保持一致
INSERT INTO `shop_sku` (`id`, `product_id`, `sku_code`, `spec_name`, `price`, `status`) VALUES
(1001, 1, 'SKU-WS-GIFT-STD',  '标准装 / 含 200ml 波本',   129.00, 1),
(1002, 1, 'SKU-WS-GIFT-PRO',  '进阶装 / 含 500ml 单一麦芽', 268.00, 1),
(1003, 2, 'SKU-SHAKER-550',   '550ml / 银色',              70.00, 1),
(1004, 2, 'SKU-SHAKER-750',   '750ml / 黑色钛镀层',        92.00, 1),
(1005, 3, 'SKU-JIGGER-3045',  '30/45ml / 镜面抛光',        38.00, 1),
(1006, 4, 'SKU-GIN-700',      '700ml',                    188.00, 1),
(1007, 5, 'SKU-CAMPARI-700',  '700ml',                    158.00, 1),
(1008, 6, 'SKU-SYRUP-250',    '250ml',                     46.00, 1),
(1009, 7, 'SKU-MOJITO-KIT',   '单套 / 含捣棒',            148.00, 1),
(1010, 8, 'SKU-COUPE-2',      '两只装 / 160ml',            96.00, 1);

-- ★★★ 库存初始化 ★★★
-- 注意：三段式必须严格守恒 available + locked + sold = total，
--       否则 ck_inv_conservation 约束会直接拒绝插入。
--       sku_id=1001 的库存设为 100，是压测场景 T-01「1000并发抢100件」的目标。
INSERT INTO `shop_inventory`
(`sku_id`, `total_stock`, `available_stock`, `locked_stock`, `sold_stock`, `safety_stock`) VALUES
(1001, 100, 100, 0, 0,  5),
(1002,  30,  30, 0, 0,  3),
(1003, 200, 200, 0, 0, 10),
(1004, 120, 120, 0, 0, 10),
(1005, 500, 500, 0, 0, 20),
(1006,  60,  60, 0, 0,  5),
(1007,  60,  60, 0, 0,  5),
(1008, 300, 300, 0, 0, 15),
(1009,  80,  80, 0, 0,  8),
(1010, 150, 150, 0, 0, 10);

-- ★ 每一笔库存变动都必须有台账，初始化也不例外。
--   这样 05_verification.sql 中的「快照 vs 台账」校验才能从第一天就成立。
INSERT INTO `shop_inventory_ledger`
(`sku_id`, `biz_type`, `biz_no`, `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
 `after_available`, `after_locked`, `after_sold`, `after_total`, `operator_type`, `operator_id`, `remark`)
SELECT
    i.`sku_id`, 'INIT', CONCAT('INIT-', i.`sku_id`),
    i.`available_stock`, 0, 0, i.`total_stock`,
    i.`available_stock`, i.`locked_stock`, i.`sold_stock`, i.`total_stock`,
    'ADMIN', 1, '种子数据初始化入库'
FROM `shop_inventory` i;


-- #############################################################################
--  7. 收货地址
--     注意 default_flag 是生成列，不能显式插入；
--     is_default=1 时它自动等于 user_id，由 uk_addr_default 唯一索引
--     强制「每个用户至多一条默认地址」。
-- #############################################################################
INSERT INTO `shop_user_address`
(`id`, `user_id`, `receiver_name`, `receiver_phone`, `province`, `city`, `district`, `detail`, `is_default`) VALUES
(1, 2, '秦野', '13800138000', '天津市', '天津市', '南开区', '卫津路 92 号 天津大学北洋园', 1),
(2, 2, '秦野', '13800138000', '天津市', '天津市', '和平区', '重庆道 55 号 3 门 201',        0),
(3, 3, 'Aria', '13900139000', '上海市', '上海市', '徐汇区', '衡山路 811 号',               1),
(4, 6, '压测收货人', '13700137000', '北京市', '北京市', '朝阳区', '压测地址 1 号',          1);


-- #############################################################################
--  8. 一笔完整的示例订单（已支付 + 已发货）
--     用于演示订单详情页、状态时间轴、以及「库存三段式流转」的完整链路。
--     这笔订单会让 sku_id=1003 的库存从 available 流转到 sold。
-- #############################################################################

-- 8.1 订单主表
--     金额关系必须满足 ck_order_amount_formula：
--     pay_amount = total_amount + freight_amount - discount_amount
--     明细合计 70.00 + 38.00 + 96.00 = 204.00，与 total_amount 一致。
INSERT INTO `shop_order`
(`id`, `order_no`, `user_id`, `status`, `total_amount`, `freight_amount`, `discount_amount`, `pay_amount`,
 `item_count`, `receiver_name`, `receiver_phone`, `receiver_address`, `remark`, `tracking_no`,
 `idempotency_key`, `expire_at`, `pay_time`, `ship_time`, `created_at`) VALUES
(1, '20260901103015010001', 2, 'SHIPPED', 204.00, 0.00, 0.00, 204.00,
 3, '秦野', '13800138000', '天津市天津市南开区卫津路 92 号 天津大学北洋园', '请工作日配送', 'SF1234567890',
 'seed-idem-0001', '2026-09-01 10:45:15.000', '2026-09-01 10:33:02.000', '2026-09-02 09:20:00.000', '2026-09-01 10:30:15.000');

-- 8.2 订单明细（含成交快照：即使商品日后改名改价，这里也不变）
INSERT INTO `shop_order_item`
(`id`, `order_id`, `order_no`, `user_id`, `product_id`, `sku_id`,
 `product_name`, `product_zh_name`, `sku_spec_name`, `sku_image`, `unit_price`, `quantity`, `total_amount`) VALUES
(1, 1, '20260901103015010001', 2, 2, 1003, 'Boston Shaker',   '波士顿摇酒壶',   '550ml / 银色',        '', 70.00, 1, 70.00),
(2, 1, '20260901103015010001', 2, 3, 1005, 'Japanese Jigger', '日式量酒器',     '30/45ml / 镜面抛光',  '', 38.00, 1, 38.00),
(3, 1, '20260901103015010001', 2, 8, 1010, 'Coupe Glass Set', '碟形杯两只装',   '两只装 / 160ml',      '', 96.00, 1, 96.00);

-- 8.3 库存流转：这三个 SKU 各卖出 1 件
--     完整链路是 available → locked（下单）→ sold（支付），total 全程不变。
--     台账必须逐笔记录这两步，且每一步的 after_* 快照都要守恒，
--     否则 ck_ledger_after_conservation 会拒绝插入。
--
--     各 SKU 的初始总量：1003=200, 1005=500, 1010=150
--     第一步 ORDER_LOCK：available -1, locked +1
--     第二步 PAY_CONFIRM：locked -1, sold +1
UPDATE `shop_inventory`
   SET `available_stock` = `available_stock` - 1,
       `sold_stock`      = `sold_stock` + 1,
       `version`         = `version` + 2
 WHERE `sku_id` IN (1003, 1005, 1010);

INSERT INTO `shop_inventory_ledger`
(`sku_id`, `biz_type`, `biz_no`, `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
 `after_available`, `after_locked`, `after_sold`, `after_total`, `operator_type`, `operator_id`, `remark`) VALUES
-- 第一步：下单锁定
(1003, 'ORDER_LOCK',  '20260901103015010001', -1,  1, 0, 0, 199, 1, 0, 200, 'USER',   2,    '下单锁定'),
(1005, 'ORDER_LOCK',  '20260901103015010001', -1,  1, 0, 0, 499, 1, 0, 500, 'USER',   2,    '下单锁定'),
(1010, 'ORDER_LOCK',  '20260901103015010001', -1,  1, 0, 0, 149, 1, 0, 150, 'USER',   2,    '下单锁定'),
-- 第二步：支付确认，锁定转已售
(1003, 'PAY_CONFIRM', '20260901103015010001',  0, -1, 1, 0, 199, 0, 1, 200, 'SYSTEM', NULL, '支付确认，锁定转已售'),
(1005, 'PAY_CONFIRM', '20260901103015010001',  0, -1, 1, 0, 499, 0, 1, 500, 'SYSTEM', NULL, '支付确认，锁定转已售'),
(1010, 'PAY_CONFIRM', '20260901103015010001',  0, -1, 1, 0, 149, 0, 1, 150, 'SYSTEM', NULL, '支付确认，锁定转已售');

-- 8.4 支付流水（支付宝沙箱）
INSERT INTO `shop_payment`
(`id`, `payment_no`, `order_no`, `user_id`, `channel`, `amount`, `status`, `channel_trade_no`,
 `buyer_account`, `paid_at`, `expire_at`, `created_at`) VALUES
(1, 'PAY20260901103020001', '20260901103015010001', 2, 'ALIPAY_SANDBOX', 204.00, 'SUCCESS',
 '2026090122001453920500****', 'jfj***@sandbox.com', '2026-09-01 10:33:02.000',
 '2026-09-01 10:45:15.000', '2026-09-01 10:30:20.000');

-- 8.5 支付回调日志（演示幂等：同一 notify_id 再来一次会被 uk_notify 拒绝）
INSERT INTO `shop_payment_notify_log`
(`channel`, `notify_id`, `notify_type`, `payment_no`, `trade_status`, `raw_body`, `sign_verified`, `handle_status`, `source_ip`) VALUES
('ALIPAY_SANDBOX', '2026090100222103300000000001', 'trade_status_sync', 'PAY20260901103020001', 'TRADE_SUCCESS',
 '{"gmt_create":"2026-09-01 10:30:20","charset":"utf-8","trade_status":"TRADE_SUCCESS","out_trade_no":"PAY20260901103020001","total_amount":"204.00"}',
 1, 'SUCCESS', '110.75.128.1');

-- 8.6 订单状态流转日志（订单详情页的时间轴数据源）
INSERT INTO `shop_order_status_log`
(`order_no`, `from_status`, `to_status`, `event`, `operator_type`, `operator_id`, `remark`, `created_at`) VALUES
('20260901103015010001', '',                 'PENDING_PAYMENT', 'CREATE',  'USER',   2,    '用户提交订单',       '2026-09-01 10:30:15.000'),
('20260901103015010001', 'PENDING_PAYMENT',  'PAID',            'PAY',     'SYSTEM', NULL, '支付宝沙箱回调成功', '2026-09-01 10:33:02.000'),
('20260901103015010001', 'PAID',             'SHIPPED',         'SHIP',    'ADMIN',  1,    '顺丰 SF1234567890',  '2026-09-02 09:20:00.000');

-- 8.7 更新商品销量冗余字段
UPDATE `shop_product` p
SET p.`sale_count` = COALESCE((
    SELECT SUM(oi.`quantity` - oi.`refunded_quantity`)
      FROM `shop_order_item` oi
      JOIN `shop_order` o ON o.`order_no` = oi.`order_no`
     WHERE oi.`product_id` = p.`id`
       AND o.`status` IN ('PAID','SHIPPED','COMPLETED','PARTIAL_REFUNDED')
), 0);

-- 8.8 购物车示例
INSERT INTO `shop_cart_item` (`user_id`, `sku_id`, `quantity`, `selected`) VALUES
(2, 1001, 1, 1),
(2, 1008, 2, 1),
(3, 1006, 1, 1);

-- 8.9 商品收藏示例
INSERT INTO `shop_product_favorite` (`product_id`, `user_id`, `created_at`) VALUES
(1, 2, '2026-08-28 20:11:00.000'),
(4, 2, '2026-08-30 21:02:00.000'),
(7, 3, '2026-09-01 12:35:00.000');


-- #############################################################################
--  完成提示
-- #############################################################################
SELECT '种子数据导入完成' AS `状态`;
SELECT
    (SELECT COUNT(*) FROM `sys_user`)              AS `用户数`,
    (SELECT COUNT(*) FROM `cocktail`)              AS `酒款数`,
    (SELECT COUNT(*) FROM `cocktail_ingredient`)   AS `配方材料数`,
    (SELECT COUNT(*) FROM `cocktail_review`)       AS `评论数`,
    (SELECT COUNT(*) FROM `story_post`)            AS `帖子数`,
    (SELECT COUNT(*) FROM `story_reply`)           AS `回复数`,
    (SELECT COUNT(*) FROM `shop_product`)          AS `商品数`,
    (SELECT COUNT(*) FROM `shop_sku`)              AS `SKU数`,
    (SELECT SUM(`total_stock`) FROM `shop_inventory`) AS `库存总量`,
    (SELECT COUNT(*) FROM `shop_order`)            AS `订单数`;

-- 立刻跑一遍守恒校验，确认种子数据本身是自洽的（期望：0 行）
SELECT '库存守恒异常行数' AS `校验项`, COUNT(*) AS `异常行数`
  FROM `shop_inventory`
 WHERE `available_stock` + `locked_stock` + `sold_stock` <> `total_stock`;

-- =============================================================================
--  种子数据脚本结束。下一步执行 04_procedures_triggers.sql
-- =============================================================================
