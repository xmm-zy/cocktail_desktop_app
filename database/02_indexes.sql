-- =============================================================================
--  Luceria Cocktail Atelier —— 补充索引与索引验证
--  文件：database/02_indexes.sql
--  前置：必须先执行 01_schema.sql
--
--  说明：
--    绝大多数索引已经内联在 01_schema.sql 的建表语句中（这样表定义自成文档）。
--    本文件只放三类内容：
--      第一部分：全文索引 —— 建表时不建，因为在空表上建和在有数据的表上建
--                成本差异很大，且中文全文索引需要 ngram 分词器的额外配置。
--      第二部分：索引清单与体积统计 —— 用来向老师展示「索引不是乱建的」。
--      第三部分：EXPLAIN 验证脚本 —— 逐条证明关键查询确实走了预期的索引，
--                这是《数据库原理》课程最有说服力的证据。
-- =============================================================================

USE `luceria`;


-- #############################################################################
--  第一部分：全文索引（中文分词）
-- #############################################################################

-- -----------------------------------------------------------------------------
-- 为什么需要全文索引？
--   论坛搜索与酒款搜索的需求是「标题或正文里包含某个词」。
--   如果用 LIKE '%关键词%'，前导通配符会让 B+ 树索引完全失效，只能全表扫描。
--   MySQL 8.0 内置的 ngram 分词器专为中日韩设计，
--   把连续文本切成 N 元组（默认 ngram_token_size=2，即二元切分），
--   这样中文也能用 MATCH ... AGAINST 走倒排索引。
--
-- 使用前请确认 my.cnf 中有：
--   [mysqld]
--   ngram_token_size = 2
--   （默认值就是 2，通常无需修改。修改后必须重启并重建全文索引。）
--
-- 查询写法：
--   SELECT * FROM story_post
--    WHERE MATCH(title, body) AGAINST('威士忌' IN NATURAL LANGUAGE MODE)
--      AND status = 1;
-- -----------------------------------------------------------------------------

-- 论坛帖子搜索：标题 + 正文
ALTER TABLE `story_post`
  ADD FULLTEXT INDEX `ft_post_title_body` (`title`, `body`) WITH PARSER ngram
  COMMENT '中文全文索引，支撑论坛关键词搜索，替代低效的 LIKE %kw%';

-- 酒款搜索：中英文名 + 风味描述
ALTER TABLE `cocktail`
  ADD FULLTEXT INDEX `ft_cocktail_search` (`name`, `zh_name`, `profile`) WITH PARSER ngram
  COMMENT '中文全文索引，支撑酒单页搜索框';

-- 商品搜索：中英文名 + 副标题
ALTER TABLE `shop_product`
  ADD FULLTEXT INDEX `ft_product_search` (`name`, `zh_name`, `subtitle`) WITH PARSER ngram
  COMMENT '中文全文索引，支撑商城搜索框';


-- #############################################################################
--  第二部分：索引清单与体积统计（答辩展示用）
-- #############################################################################

-- -----------------------------------------------------------------------------
-- 2.1 列出全库所有索引，按表分组
--     可以直接把结果贴进课程报告，证明索引设计是有规划的。
-- -----------------------------------------------------------------------------
SELECT
    s.`TABLE_NAME`                                   AS `表名`,
    s.`INDEX_NAME`                                   AS `索引名`,
    CASE
        WHEN s.`INDEX_NAME` = 'PRIMARY' THEN '主键(聚簇索引)'
        WHEN s.`NON_UNIQUE` = 0         THEN '唯一索引'
        WHEN s.`INDEX_TYPE` = 'FULLTEXT' THEN '全文索引'
        ELSE '普通索引'
    END                                              AS `索引类型`,
    GROUP_CONCAT(s.`COLUMN_NAME` ORDER BY s.`SEQ_IN_INDEX` SEPARATOR ', ') AS `索引列(按顺序)`,
    COUNT(*)                                         AS `列数`,
    MAX(s.`CARDINALITY`)                             AS `基数(区分度估算)`
FROM `information_schema`.`STATISTICS` s
WHERE s.`TABLE_SCHEMA` = 'luceria'
GROUP BY s.`TABLE_NAME`, s.`INDEX_NAME`, s.`NON_UNIQUE`, s.`INDEX_TYPE`
ORDER BY s.`TABLE_NAME`,
         FIELD(s.`INDEX_NAME`, 'PRIMARY') DESC,
         s.`INDEX_NAME`;


-- -----------------------------------------------------------------------------
-- 2.2 数据体积 vs 索引体积
--     索引不是越多越好。这个查询用来检查「索引体积是否失控」。
--     经验参考：索引总量超过数据量的 1.5 倍就要复查是否有冗余索引。
-- -----------------------------------------------------------------------------
SELECT
    `TABLE_NAME`                                            AS `表名`,
    `TABLE_ROWS`                                            AS `估算行数`,
    ROUND(`DATA_LENGTH`  / 1024, 2)                         AS `数据KB`,
    ROUND(`INDEX_LENGTH` / 1024, 2)                         AS `索引KB`,
    CASE WHEN `DATA_LENGTH` = 0 THEN NULL
         ELSE ROUND(`INDEX_LENGTH` / `DATA_LENGTH`, 2) END  AS `索引数据比`,
    `TABLE_COMMENT`                                         AS `表说明`
FROM `information_schema`.`TABLES`
WHERE `TABLE_SCHEMA` = 'luceria' AND `TABLE_TYPE` = 'BASE TABLE'
ORDER BY (`DATA_LENGTH` + `INDEX_LENGTH`) DESC;


-- -----------------------------------------------------------------------------
-- 2.3 冗余索引自检
--     如果索引 A 的列是索引 B 的最左前缀，那么 A 是冗余的，应该删掉。
--     例：已有 (user_id, status, id) 就不需要再单独建 (user_id)。
--     本设计已人工避免此类冗余，这条查询用于回归验证。
-- -----------------------------------------------------------------------------
SELECT
    a.`TABLE_NAME`  AS `表名`,
    a.`INDEX_NAME`  AS `可能冗余的索引`,
    a.`cols`        AS `其列`,
    b.`INDEX_NAME`  AS `已覆盖它的索引`,
    b.`cols`        AS `其列`
FROM (
    SELECT `TABLE_NAME`, `INDEX_NAME`,
           GROUP_CONCAT(`COLUMN_NAME` ORDER BY `SEQ_IN_INDEX`) AS `cols`
    FROM `information_schema`.`STATISTICS`
    WHERE `TABLE_SCHEMA` = 'luceria' AND `INDEX_TYPE` = 'BTREE'
    GROUP BY `TABLE_NAME`, `INDEX_NAME`
) a
JOIN (
    SELECT `TABLE_NAME`, `INDEX_NAME`,
           GROUP_CONCAT(`COLUMN_NAME` ORDER BY `SEQ_IN_INDEX`) AS `cols`
    FROM `information_schema`.`STATISTICS`
    WHERE `TABLE_SCHEMA` = 'luceria' AND `INDEX_TYPE` = 'BTREE'
    GROUP BY `TABLE_NAME`, `INDEX_NAME`
) b
  ON  a.`TABLE_NAME` = b.`TABLE_NAME`
  AND a.`INDEX_NAME` <> b.`INDEX_NAME`
  AND b.`cols` LIKE CONCAT(a.`cols`, ',%');


-- #############################################################################
--  第三部分：EXPLAIN 验证脚本
--
--  执行前请先运行 03_seed_data.sql 灌入数据，否则优化器会因为表太小
--  而选择全表扫描（几十行的表走索引反而更慢，这是正常且正确的行为）。
--
--  重点看三列：
--    type  —— 期望 const / eq_ref / ref / range，出现 ALL(全表扫描) 要警惕
--    key   —— 实际使用的索引名，必须与设计意图一致
--    Extra —— 出现 "Using filesort" 或 "Using temporary" 说明排序没走索引，需优化
--             出现 "Using index" 说明是覆盖索引，无需回表，最理想
-- #############################################################################

-- -----------------------------------------------------------------------------
-- 验证 1：登录 —— 按邮箱查用户
-- 期望：type=const，key=uk_user_email
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `display_name`, `role`, `status`
  FROM `sys_user`
 WHERE `email` = 'demo01@luceria.test';

-- -----------------------------------------------------------------------------
-- 验证 2：验证码校验 —— 取该邮箱最新一条未使用的登录验证码
-- 期望：key=idx_authcode_email_purpose，Extra 不含 Using filesort
--       （因为索引本身已按 created_at DESC 有序）
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `code_hash`, `expires_at`, `attempt_count`
  FROM `sys_auth_code`
 WHERE `email` = 'demo01@luceria.test' AND `purpose` = 'LOGIN'
 ORDER BY `created_at` DESC
 LIMIT 1;

-- -----------------------------------------------------------------------------
-- 验证 3：酒单页 —— 按分类+基酒筛选，时间倒序
-- 期望：key=idx_cocktail_cat_base_time，Extra 不含 Using filesort
-- 这是「最左前缀原则」的典型演示：category 等值 → base 等值 → created_at 排序
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `name`, `zh_name`, `image_url`, `avg_rating`
  FROM `cocktail`
 WHERE `category` = 'classic' AND `base` = 'whiskey'
 ORDER BY `created_at` DESC
 LIMIT 20;

-- -----------------------------------------------------------------------------
-- 验证 4：反例对照 —— 跳过最左列直接查 base
-- 期望：key 为 NULL 或走了别的索引，type=ALL
-- 用途：向老师演示「违反最左前缀原则会导致索引失效」，
--       与验证 3 形成鲜明对比，这是很好的答辩素材。
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `name` FROM `cocktail` WHERE `base` = 'whiskey';

-- -----------------------------------------------------------------------------
-- 验证 5：酒款详情页 —— 该酒款的评论列表
-- 期望：key=idx_review_cocktail_status_id，Extra 不含 Using filesort
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `user_id`, `rating`, `content`, `like_count`, `created_at`
  FROM `cocktail_review`
 WHERE `cocktail_id` = 1 AND `status` = 1
 ORDER BY `id` DESC
 LIMIT 20;

-- -----------------------------------------------------------------------------
-- 验证 6：判断「我是否点赞过这条评论」
-- 期望：type=const，key=PRIMARY，Extra=Using index（覆盖索引，完全不回表）
-- 这是复合主键设计带来的收益：判断存在性只读聚簇索引，一次页访问搞定。
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT 1 FROM `cocktail_review_like` WHERE `review_id` = 1 AND `user_id` = 1;

-- -----------------------------------------------------------------------------
-- 验证 7：账号中心 —— 我收藏的帖子
-- 期望：key=idx_postfav_user_time，Extra=Using index（覆盖索引）
-- 说明：索引 (user_id, created_at) 加上聚簇索引里的 post_id，
--       三列都在索引中，无需回表。
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `post_id`, `created_at`
  FROM `story_post_favorite`
 WHERE `user_id` = 1
 ORDER BY `created_at` DESC
 LIMIT 20;

-- -----------------------------------------------------------------------------
-- 验证 8：★ 核心 —— 库存扣减（防超卖的那条 CAS 语句）
-- 期望：type=range 或 const，key=PRIMARY
-- 意义：库存表主键就是 sku_id，扣减时直接命中聚簇索引，
--       只加一把行锁，没有二级索引回表，这是热点写入的最优形态。
-- 注意：EXPLAIN UPDATE 不会真的执行更新。
-- -----------------------------------------------------------------------------
EXPLAIN
UPDATE `shop_inventory`
   SET `available_stock` = `available_stock` - 1,
       `locked_stock`    = `locked_stock`    + 1,
       `version`         = `version` + 1
 WHERE `sku_id` = 1001 AND `available_stock` >= 1;

-- -----------------------------------------------------------------------------
-- 验证 9：「我的订单」列表
-- 期望：key=idx_order_user_status_id，Extra 不含 Using filesort
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `order_no`, `status`, `pay_amount`, `item_count`, `created_at`
  FROM `shop_order`
 WHERE `user_id` = 1 AND `status` = 'PENDING_PAYMENT'
 ORDER BY `id` DESC
 LIMIT 10;

-- -----------------------------------------------------------------------------
-- 验证 10：超时订单扫描（兜底定时任务）
-- 期望：type=range，key=idx_order_status_expire
-- 意义：待支付订单在全表中占比很小，这个复合索引选择性高，扫描范围可控。
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `order_no`
  FROM `shop_order`
 WHERE `status` = 'PENDING_PAYMENT' AND `expire_at` < NOW(3)
 LIMIT 500;

-- -----------------------------------------------------------------------------
-- 验证 11：支付回调防重（唯一索引拦截）
-- 期望：type=const，key=uk_notify
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id` FROM `shop_payment_notify_log`
 WHERE `channel` = 'ALIPAY_SANDBOX' AND `notify_id` = 'demo-notify-001';

-- -----------------------------------------------------------------------------
-- 验证 12：库存台账幂等判定
-- 期望：type=const，key=uk_ledger_biz
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id` FROM `shop_inventory_ledger`
 WHERE `biz_type` = 'ORDER_LOCK' AND `biz_no` = '20260903120000010001' AND `sku_id` = 1001;

-- -----------------------------------------------------------------------------
-- 验证 13：全文索引是否生效
-- 期望：type=fulltext，key=ft_post_title_body
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `title`
  FROM `story_post`
 WHERE MATCH(`title`, `body`) AGAINST('威士忌' IN NATURAL LANGUAGE MODE)
   AND `status` = 1;

-- -----------------------------------------------------------------------------
-- 验证 14：反例对照 —— 同样的搜索用 LIKE
-- 期望：type=ALL（全表扫描），key=NULL
-- 与验证 13 对照，说明为什么要引入全文索引。
-- -----------------------------------------------------------------------------
EXPLAIN
SELECT `id`, `title` FROM `story_post` WHERE `body` LIKE '%威士忌%' AND `status` = 1;


-- #############################################################################
--  第四部分：慢查询与锁监控（压测时使用）
-- #############################################################################

-- 开启慢查询日志，阈值 100ms（对应非功能需求 NFR：慢查询占比 < 0.1%）
-- SET GLOBAL slow_query_log = 'ON';
-- SET GLOBAL long_query_time = 0.1;
-- SET GLOBAL log_queries_not_using_indexes = 'ON';

-- 压测中查看当前的行锁等待情况（MySQL 8.0）
-- SELECT * FROM performance_schema.data_lock_waits;
-- SELECT * FROM performance_schema.data_locks WHERE OBJECT_NAME = 'shop_inventory';

-- 压测后查看最近一次死锁（应为空）
-- SHOW ENGINE INNODB STATUS;

-- 查看 InnoDB 行锁统计：Innodb_row_lock_waits 应尽量小
-- SHOW STATUS LIKE 'Innodb_row_lock%';

-- =============================================================================
--  索引脚本结束
-- =============================================================================
