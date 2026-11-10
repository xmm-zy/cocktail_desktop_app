-- =============================================================================
--  Luceria Cocktail Atelier —— 数据一致性验证脚本
--  文件：database/05_verification.sql
--  前置：01_schema.sql → 03_seed_data.sql（04 可选）
--
--  用途：
--    ① 压测（尤其是「1000 并发抢 100 件库存」）之后立刻执行，
--       用来证明系统在高并发下没有超卖、没有少卖、没有数据错乱；
--    ② 日常巡检 / 后台「一键对账」按钮的 SQL 实现；
--    ③ 答辩演示 —— 这一屏全绿的 ✅ PASS 是最直接的证据。
--
--  ★ 判定标准：所有 CHECK_* 查询都应输出 PASS。
--    任何一条 FAIL 都意味着存在真实的数据一致性问题，必须排查后重跑。
--
--  执行方式：
--    mysql -u root -p luceria < 05_verification.sql > verify_report.txt
-- =============================================================================

USE `luceria`;

SELECT '==================================================' AS ``;
SELECT '  Luceria 数据一致性校验报告' AS ``;
SELECT CONCAT('  生成时间：', NOW(3)) AS ``;
SELECT '==================================================' AS ``;


-- #############################################################################
--  第一组：★ 库存一致性（核心，直接对应「不超卖 / 不库存冗余」的需求）
-- #############################################################################

SELECT '--- 第一组：库存一致性 ---' AS ``;

-- -----------------------------------------------------------------------------
-- CHECK-01 库存三段守恒
-- 断言：available + locked + sold = total，对每一个 SKU 都成立
-- 意义：这是整个库存模型的根本不变式。它被写成了 CHECK 约束，
--       所以理论上永远成立；这条查询是对「约束确实生效了」的独立验证。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-01 库存三段守恒 (available+locked+sold=total)' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个SKU守恒被破坏')) AS `结果`
FROM `shop_inventory`
WHERE `available_stock` + `locked_stock` + `sold_stock` <> `total_stock`;

-- 出问题时的明细
SELECT `sku_id`, `total_stock`, `available_stock`, `locked_stock`, `sold_stock`,
       (`available_stock` + `locked_stock` + `sold_stock` - `total_stock`) AS `差额`
  FROM `shop_inventory`
 WHERE `available_stock` + `locked_stock` + `sold_stock` <> `total_stock`;


-- -----------------------------------------------------------------------------
-- CHECK-02 无负库存
-- 断言：任何一段库存都不为负
-- 意义：★ 这是「超卖」最直接的物理标志。
--       如果这条 FAIL，说明防超卖的 CAS 语句被绕过了。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-02 无负库存（超卖的直接标志）' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS：未发生超卖', CONCAT('❌ FAIL：', COUNT(*), ' 个SKU出现负库存 —— 已超卖！')) AS `结果`
FROM `shop_inventory`
WHERE `available_stock` < 0 OR `locked_stock` < 0 OR `sold_stock` < 0 OR `total_stock` < 0;


-- -----------------------------------------------------------------------------
-- CHECK-03 库存快照 = 台账流水累加
-- 断言：shop_inventory 的当前值，等于 shop_inventory_ledger 中所有 delta 的累加
-- 意义：证明「每一次库存变动都被完整记录」。
--       如果不相等，说明有代码绕过了台账直接改库存 —— 这种路径必须被消灭，
--       因为它一旦存在，幂等保证就失效了。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-03 库存快照与台账流水一致' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个SKU的快照与台账对不上')) AS `结果`
FROM `shop_inventory` i
LEFT JOIN (
    SELECT `sku_id`,
           SUM(`delta_available`) AS `sa`,
           SUM(`delta_locked`)    AS `sl`,
           SUM(`delta_sold`)      AS `ss`,
           SUM(`delta_total`)     AS `st`
      FROM `shop_inventory_ledger`
     GROUP BY `sku_id`
) l ON l.`sku_id` = i.`sku_id`
WHERE i.`available_stock` <> COALESCE(l.`sa`, 0)
   OR i.`locked_stock`    <> COALESCE(l.`sl`, 0)
   OR i.`sold_stock`      <> COALESCE(l.`ss`, 0)
   OR i.`total_stock`     <> COALESCE(l.`st`, 0);

-- 出问题时的明细
SELECT i.`sku_id`,
       i.`available_stock` AS `快照_可售`, COALESCE(l.`sa`,0) AS `台账_可售`,
       i.`locked_stock`    AS `快照_锁定`, COALESCE(l.`sl`,0) AS `台账_锁定`,
       i.`sold_stock`      AS `快照_已售`, COALESCE(l.`ss`,0) AS `台账_已售`,
       i.`total_stock`     AS `快照_总量`, COALESCE(l.`st`,0) AS `台账_总量`
  FROM `shop_inventory` i
  LEFT JOIN (
      SELECT `sku_id`, SUM(`delta_available`) sa, SUM(`delta_locked`) sl,
             SUM(`delta_sold`) ss, SUM(`delta_total`) st
        FROM `shop_inventory_ledger` GROUP BY `sku_id`
  ) l ON l.`sku_id` = i.`sku_id`
 WHERE i.`available_stock` <> COALESCE(l.`sa`,0)
    OR i.`locked_stock`    <> COALESCE(l.`sl`,0)
    OR i.`sold_stock`      <> COALESCE(l.`ss`,0)
    OR i.`total_stock`     <> COALESCE(l.`st`,0);


-- -----------------------------------------------------------------------------
-- CHECK-04 锁定库存 = 待支付订单的商品数
-- 断言：shop_inventory.locked_stock 等于所有 PENDING_PAYMENT 订单中该 SKU 的总数量
-- 意义：证明「下单锁库存」和「关单释放库存」两条路径都没有漏掉或重复执行。
--       ★ 压测场景 T-01「1000并发抢100件」之后，这里必须精确等于 100。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-04 锁定库存 = 待支付订单商品数' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个SKU的锁定量与订单对不上')) AS `结果`
FROM `shop_inventory` i
LEFT JOIN (
    SELECT oi.`sku_id`, SUM(oi.`quantity`) AS `qty`
      FROM `shop_order_item` oi
      JOIN `shop_order` o ON o.`id` = oi.`order_id`
     WHERE o.`status` = 'PENDING_PAYMENT'
     GROUP BY oi.`sku_id`
) t ON t.`sku_id` = i.`sku_id`
WHERE i.`locked_stock` <> COALESCE(t.`qty`, 0);


-- -----------------------------------------------------------------------------
-- CHECK-05 已售库存 = 已支付订单的净商品数（扣除已退货）
-- 断言：sold_stock = SUM(quantity - refunded_quantity) over 已支付类订单
-- 意义：证明「支付确认」和「退货回补」两条路径都正确。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-05 已售库存 = 已支付订单净商品数' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个SKU的已售量与订单对不上')) AS `结果`
FROM `shop_inventory` i
LEFT JOIN (
    SELECT oi.`sku_id`, SUM(oi.`quantity` - oi.`refunded_quantity`) AS `qty`
      FROM `shop_order_item` oi
      JOIN `shop_order` o ON o.`id` = oi.`order_id`
     WHERE o.`status` IN ('PAID','SHIPPED','COMPLETED','REFUNDING','PARTIAL_REFUNDED')
     GROUP BY oi.`sku_id`
) t ON t.`sku_id` = i.`sku_id`
WHERE i.`sold_stock` <> COALESCE(t.`qty`, 0);


-- -----------------------------------------------------------------------------
-- CHECK-06 每条台账自身守恒
-- 断言：单条流水的 delta_available + delta_locked + delta_sold = delta_total
-- 意义：这是 CHECK 约束的独立复核。如果某条流水自身不守恒，
--       说明写台账的代码算错了 delta，快照迟早会漂移。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-06 每条台账流水自身守恒' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 条流水不守恒')) AS `结果`
FROM `shop_inventory_ledger`
WHERE `delta_available` + `delta_locked` + `delta_sold` <> `delta_total`
   OR `after_available` + `after_locked` + `after_sold` <> `after_total`;


-- -----------------------------------------------------------------------------
-- CHECK-07 台账时序连续性
-- 断言：按时间排序，每条流水的 after_* 应该等于「上一条的 after_* + 本条的 delta_*」
-- 意义：这是最严格的一条校验。它能发现「有并发写入没走台账」这种隐蔽问题。
--       用 MySQL 8.0 的窗口函数 LAG() 取上一行的值。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-07 台账时序连续（after = 上一条after + 本条delta）' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 处时序断裂')) AS `结果`
FROM (
    SELECT
        `id`, `sku_id`,
        `after_available`,
        `delta_available`,
        LAG(`after_available`) OVER (PARTITION BY `sku_id` ORDER BY `id`) AS `prev_available`
    FROM `shop_inventory_ledger`
) t
WHERE `prev_available` IS NOT NULL
  AND `after_available` <> `prev_available` + `delta_available`;


-- #############################################################################
--  第二组：★ 订单与金额对账
-- #############################################################################

SELECT '--- 第二组：订单与金额对账 ---' AS ``;

-- -----------------------------------------------------------------------------
-- CHECK-08 订单商品总额 = 明细小计之和
-- 断言：shop_order.total_amount = SUM(shop_order_item.total_amount)
-- 意义：防止改价接口、优惠计算把订单金额算错。这是财务对账的第一条。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-08 订单商品总额 = 明细合计' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单金额与明细不符')) AS `结果`
FROM `shop_order` o
LEFT JOIN (
    SELECT `order_id`, SUM(`total_amount`) AS `sum_amt`, SUM(`quantity`) AS `sum_qty`
      FROM `shop_order_item` GROUP BY `order_id`
) t ON t.`order_id` = o.`id`
WHERE o.`total_amount` <> COALESCE(t.`sum_amt`, 0);

SELECT o.`order_no`, o.`total_amount` AS `订单金额`, COALESCE(t.`sum_amt`,0) AS `明细合计`,
       (o.`total_amount` - COALESCE(t.`sum_amt`,0)) AS `差额`
  FROM `shop_order` o
  LEFT JOIN (SELECT `order_id`, SUM(`total_amount`) sum_amt FROM `shop_order_item` GROUP BY `order_id`) t
    ON t.`order_id` = o.`id`
 WHERE o.`total_amount` <> COALESCE(t.`sum_amt`, 0);


-- -----------------------------------------------------------------------------
-- CHECK-09 订单商品件数 = 明细数量之和
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-09 订单件数 = 明细数量合计' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单件数不符')) AS `结果`
FROM `shop_order` o
LEFT JOIN (SELECT `order_id`, SUM(`quantity`) AS `q` FROM `shop_order_item` GROUP BY `order_id`) t
  ON t.`order_id` = o.`id`
WHERE o.`item_count` <> COALESCE(t.`q`, 0);


-- -----------------------------------------------------------------------------
-- CHECK-10 应付金额公式成立
-- 断言：pay_amount = total_amount + freight_amount - discount_amount
-- 意义：这个公式已经写成了 CHECK 约束，这里做独立复核。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-10 应付金额公式 (pay = total + freight - discount)' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单公式不成立')) AS `结果`
FROM `shop_order`
WHERE `pay_amount` <> `total_amount` + `freight_amount` - `discount_amount`;


-- -----------------------------------------------------------------------------
-- CHECK-11 支付金额 = 订单应付金额
-- 断言：成功的支付流水金额必须等于订单应付金额
-- 意义：★ 防金额篡改。如果攻击者把支付金额改成 0.01 元，这里会立刻暴露。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-11 成功支付金额 = 订单应付金额（防篡改）' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔支付金额与订单不符 —— 疑似金额篡改！')) AS `结果`
FROM `shop_payment` p
JOIN `shop_order` o ON o.`order_no` = p.`order_no`
WHERE p.`status` = 'SUCCESS' AND p.`amount` <> o.`pay_amount`;


-- -----------------------------------------------------------------------------
-- CHECK-12 一笔订单最多只有一条成功的支付流水
-- 意义：★ 防重复扣款。如果同一订单有两条 SUCCESS 支付，说明幂等失效，用户被多扣钱了。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-12 每笔订单至多一条成功支付（防重复扣款）' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单存在重复支付！')) AS `结果`
FROM (
    SELECT `order_no` FROM `shop_payment`
     WHERE `status` = 'SUCCESS'
     GROUP BY `order_no` HAVING COUNT(*) > 1
) t;


-- -----------------------------------------------------------------------------
-- CHECK-13 已支付的订单必须有成功的支付流水
-- 意义：反向校验。订单状态是 PAID 但找不到支付记录，说明状态被非法改动。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-13 已支付订单必有成功支付流水' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单状态已支付但无支付记录')) AS `结果`
FROM `shop_order` o
WHERE o.`status` IN ('PAID','SHIPPED','COMPLETED','REFUNDING','PARTIAL_REFUNDED','REFUNDED')
  AND NOT EXISTS (
      SELECT 1 FROM `shop_payment` p
       WHERE p.`order_no` = o.`order_no` AND p.`status` = 'SUCCESS'
  );


-- -----------------------------------------------------------------------------
-- CHECK-14 退款不超额
-- 断言：明细的 refunded_quantity <= quantity，refunded_amount <= total_amount
--       订单的 refunded_amount <= pay_amount
-- 意义：★ 防超退。已由 CHECK 约束保证，这里独立复核。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-14 退款数量与金额不超额' AS `校验项`,
    IF((SELECT COUNT(*) FROM `shop_order_item`
         WHERE `refunded_quantity` > `quantity` OR `refunded_amount` > `total_amount`)
     + (SELECT COUNT(*) FROM `shop_order` WHERE `refunded_amount` > `pay_amount`) = 0,
       '✅ PASS', '❌ FAIL：存在超额退款') AS `结果`;


-- -----------------------------------------------------------------------------
-- CHECK-15 订单已退金额 = 该订单成功退款单之和
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-15 订单已退金额 = 成功退款单合计' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单退款金额对不上')) AS `结果`
FROM `shop_order` o
LEFT JOIN (
    SELECT `order_no`, SUM(`refund_amount`) AS `amt`
      FROM `shop_refund` WHERE `status` = 'SUCCESS' GROUP BY `order_no`
) r ON r.`order_no` = o.`order_no`
WHERE o.`refunded_amount` <> COALESCE(r.`amt`, 0);


-- -----------------------------------------------------------------------------
-- CHECK-16 下单幂等：无重复的 idempotency_key
-- 意义：★ 压测场景 T-04 的断言。
--       已由 uk_order_user_idem 唯一索引保证，这里独立复核。
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-16 下单幂等：无重复 idempotency_key' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS：无重复下单', CONCAT('❌ FAIL：', COUNT(*), ' 组重复')) AS `结果`
FROM (
    SELECT `user_id`, `idempotency_key`
      FROM `shop_order` GROUP BY `user_id`, `idempotency_key` HAVING COUNT(*) > 1
) t;


-- -----------------------------------------------------------------------------
-- CHECK-17 支付回调幂等：无重复处理的 notify_id
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-17 支付回调幂等：无重复 notify_id' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 组重复回调被处理了多次')) AS `结果`
FROM (
    SELECT `channel`, `notify_id` FROM `shop_payment_notify_log`
     WHERE `handle_status` = 'SUCCESS'
     GROUP BY `channel`, `notify_id` HAVING COUNT(*) > 1
) t;


-- -----------------------------------------------------------------------------
-- CHECK-18 订单状态与时间字段自洽
-- 断言：已支付的订单必有 pay_time；已发货必有 ship_time；已关闭必有 close_time
-- -----------------------------------------------------------------------------
SELECT
    'CHECK-18 订单状态与时间字段自洽' AS `校验项`,
    IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 笔订单状态与时间不一致')) AS `结果`
FROM `shop_order`
WHERE (`status` IN ('PAID','SHIPPED','COMPLETED') AND `pay_time`   IS NULL)
   OR (`status` IN ('SHIPPED','COMPLETED')        AND `ship_time`  IS NULL)
   OR (`status` IN ('CANCELLED','CLOSED')         AND `close_time` IS NULL);


-- #############################################################################
--  第三组：★ 孤儿数据与引用完整性
--  说明：本项目已经用物理外键约束了大部分引用关系，
--        因此下面这些校验理论上永远 PASS。它们的价值在于：
--        ① 万一将来为了性能删掉了某个外键，这些查询就是替代的守卫；
--        ② 数据迁移期间外键检查是关闭的（SET FOREIGN_KEY_CHECKS=0），
--           迁移完成后必须用它们做一次全量验收。
-- #############################################################################

SELECT '--- 第三组：孤儿数据与引用完整性 ---' AS ``;

-- CHECK-19 评论指向的酒款存在
SELECT 'CHECK-19 评论→酒款 无孤儿' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 条孤儿评论')) AS `结果`
FROM `cocktail_review` r
LEFT JOIN `cocktail` c ON c.`id` = r.`cocktail_id`
WHERE c.`id` IS NULL;

-- CHECK-20 评论指向的用户存在
SELECT 'CHECK-20 评论→用户 无孤儿' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 条')) AS `结果`
FROM `cocktail_review` r
LEFT JOIN `sys_user` u ON u.`id` = r.`user_id`
WHERE u.`id` IS NULL;

-- CHECK-21 回复指向的帖子存在
SELECT 'CHECK-21 回复→帖子 无孤儿' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 条')) AS `结果`
FROM `story_reply` r
LEFT JOIN `story_post` p ON p.`id` = r.`post_id`
WHERE p.`id` IS NULL;

-- CHECK-22 楼中楼的父回复存在，且父子属于同一帖子
SELECT 'CHECK-22 楼中楼父子关系自洽' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 条')) AS `结果`
FROM `story_reply` c
JOIN `story_reply` p ON p.`id` = c.`parent_reply_id`
WHERE c.`post_id` <> p.`post_id`;

-- CHECK-23 订单明细指向的订单存在
SELECT 'CHECK-23 订单明细→订单 无孤儿' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 条')) AS `结果`
FROM `shop_order_item` oi
LEFT JOIN `shop_order` o ON o.`id` = oi.`order_id`
WHERE o.`id` IS NULL;

-- CHECK-24 每个在售 SKU 都有库存记录
SELECT 'CHECK-24 在售SKU都有库存记录' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个SKU缺库存记录')) AS `结果`
FROM `shop_sku` s
LEFT JOIN `shop_inventory` i ON i.`sku_id` = s.`id`
WHERE s.`status` = 1 AND i.`sku_id` IS NULL;

-- CHECK-25 每个上架商品至少有一个在售 SKU
SELECT 'CHECK-25 上架商品至少有一个在售SKU' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个商品无可售SKU')) AS `结果`
FROM `shop_product` p
WHERE p.`status` = 1
  AND NOT EXISTS (SELECT 1 FROM `shop_sku` s WHERE s.`product_id` = p.`id` AND s.`status` = 1);

-- CHECK-26 购物车不含已下架 SKU（这类条目应被标记失效并清理）
SELECT 'CHECK-26 购物车无已停售SKU' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('⚠️ WARN：', COUNT(*), ' 条购物车指向停售SKU，应提示用户清理')) AS `结果`
FROM `shop_cart_item` c
JOIN `shop_sku` s ON s.`id` = c.`sku_id`
WHERE s.`status` = 0;


-- #############################################################################
--  第四组：★ 迁移验收（从 Supabase Postgres 迁移完成后执行一次）
-- #############################################################################

SELECT '--- 第四组：迁移验收 ---' AS ``;

-- CHECK-27 配方材料条数在 2–12 之间
-- 这是 Postgres 原表 `cardinality(ingredients) between 2 and 12` 的等价校验。
-- MySQL 的 CHECK 无法表达跨行条件，所以只能靠这条查询 + 应用层校验。
SELECT 'CHECK-27 每款酒的配方材料在2-12条之间' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 款酒的材料条数越界')) AS `结果`
FROM (
    SELECT c.`id`
      FROM `cocktail` c
      LEFT JOIN `cocktail_ingredient` i ON i.`cocktail_id` = c.`id`
     WHERE c.`status` = 1
     GROUP BY c.`id`
    HAVING COUNT(i.`id`) < 2 OR COUNT(i.`id`) > 12
) t;

-- CHECK-28 配方材料序号连续无空洞（1..N）
SELECT 'CHECK-28 配方材料序号从1连续编号' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 款酒的材料序号不连续')) AS `结果`
FROM (
    SELECT `cocktail_id`
      FROM `cocktail_ingredient`
     GROUP BY `cocktail_id`
    HAVING MIN(`sort_no`) <> 1 OR MAX(`sort_no`) <> COUNT(*)
) t;

-- CHECK-29 迁移映射完整：每个带 legacy_uid 的实体都在映射表里
SELECT 'CHECK-29 UUID映射字典完整' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个实体缺映射记录')) AS `结果`
FROM (
    SELECT u.`legacy_uid` FROM `sys_user` u
     WHERE u.`legacy_uid` IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM `mig_uid_map` m WHERE m.`entity_type`='USER' AND m.`legacy_uid`=u.`legacy_uid`)
    UNION ALL
    SELECT c.`legacy_uid` FROM `cocktail` c
     WHERE c.`legacy_uid` IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM `mig_uid_map` m WHERE m.`entity_type`='COCKTAIL' AND m.`legacy_uid`=c.`legacy_uid`)
    UNION ALL
    SELECT p.`legacy_uid` FROM `story_post` p
     WHERE p.`legacy_uid` IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM `mig_uid_map` m WHERE m.`entity_type`='POST' AND m.`legacy_uid`=p.`legacy_uid`)
) t;

-- CHECK-30 用户投稿酒款必有作者，内置酒款必无作者
-- 已由 ck_cocktail_owner 约束保证，这里独立复核。
SELECT 'CHECK-30 酒款来源与作者字段自洽' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 款酒不自洽')) AS `结果`
FROM `cocktail`
WHERE (`source` = 1 AND `user_id` IS NOT NULL)
   OR (`source` = 2 AND `user_id` IS NULL);


-- #############################################################################
--  第五组：冗余计数校验
--  说明：冗余字段是有意的反范式。反范式的代价就是必须定期校验它没有失真。
--        这一组就是为反范式付出的「维护成本」的具体体现。
-- #############################################################################

SELECT '--- 第五组：冗余计数校验 ---' AS ``;

-- CHECK-31 帖子的点赞数/收藏数/回复数
SELECT 'CHECK-31 帖子冗余计数准确' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个帖子计数失真')) AS `结果`
FROM `story_post` p
WHERE p.`like_count`     <> (SELECT COUNT(*) FROM `story_post_like`     l WHERE l.`post_id` = p.`id`)
   OR p.`favorite_count` <> (SELECT COUNT(*) FROM `story_post_favorite` f WHERE f.`post_id` = p.`id`)
   OR p.`reply_count`    <> (SELECT COUNT(*) FROM `story_reply`         r WHERE r.`post_id` = p.`id` AND r.`status` = 1);

-- CHECK-32 回复与评论的点赞数
SELECT 'CHECK-32 回复/评论点赞数准确' AS `校验项`,
       IF((SELECT COUNT(*) FROM `story_reply` r
            WHERE r.`like_count` <> (SELECT COUNT(*) FROM `story_reply_like` l WHERE l.`reply_id` = r.`id`))
        + (SELECT COUNT(*) FROM `cocktail_review` cr
            WHERE cr.`like_count` <> (SELECT COUNT(*) FROM `cocktail_review_like` l WHERE l.`review_id` = cr.`id`)) = 0,
          '✅ PASS', '❌ FAIL：点赞计数失真') AS `结果`;

-- CHECK-33 酒款的评论数与平均分
SELECT 'CHECK-33 酒款评论数与平均分准确' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 款酒统计失真')) AS `结果`
FROM `cocktail` c
WHERE c.`review_count` <> (SELECT COUNT(*) FROM `cocktail_review` r
                            WHERE r.`cocktail_id` = c.`id` AND r.`status` = 1)
   OR c.`avg_rating`   <> COALESCE((SELECT ROUND(AVG(r.`rating`),1) FROM `cocktail_review` r
                            WHERE r.`cocktail_id` = c.`id` AND r.`status` = 1), 0.0);

-- CHECK-34 商品销量冗余字段
SELECT 'CHECK-34 商品销量冗余字段准确' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个商品销量失真')) AS `结果`
FROM `shop_product` p
WHERE p.`sale_count` <> COALESCE((
    SELECT SUM(oi.`quantity` - oi.`refunded_quantity`)
      FROM `shop_order_item` oi
      JOIN `shop_order` o ON o.`order_no` = oi.`order_no`
     WHERE oi.`product_id` = p.`id`
       AND o.`status` IN ('PAID','SHIPPED','COMPLETED','PARTIAL_REFUNDED')
), 0);

-- CHECK-35 每人至多一条默认收货地址
-- 已由 uk_addr_default 唯一索引 + 生成列保证，这里独立复核。
SELECT 'CHECK-35 每人至多一条默认地址' AS `校验项`,
       IF(COUNT(*) = 0, '✅ PASS', CONCAT('❌ FAIL：', COUNT(*), ' 个用户有多条默认地址')) AS `结果`
FROM (
    SELECT `user_id` FROM `shop_user_address`
     WHERE `is_default` = 1 AND `deleted` = 0
     GROUP BY `user_id` HAVING COUNT(*) > 1
) t;


-- #############################################################################
--  第六组：★ 压测专用汇总（跑完 T-01 后直接看这一屏）
-- #############################################################################

SELECT '--- 第六组：压测结果汇总（目标 SKU = 1001）---' AS ``;

SELECT
    (SELECT COUNT(*) FROM `shop_order` WHERE `status` = 'PENDING_PAYMENT')                     AS `成功下单数`,
    (SELECT COALESCE(SUM(`quantity`),0) FROM `shop_order_item` WHERE `sku_id` = 1001)          AS `订单商品总数`,
    (SELECT `total_stock`     FROM `shop_inventory` WHERE `sku_id` = 1001)                     AS `总库存`,
    (SELECT `available_stock` FROM `shop_inventory` WHERE `sku_id` = 1001)                     AS `剩余可售`,
    (SELECT `locked_stock`    FROM `shop_inventory` WHERE `sku_id` = 1001)                     AS `已锁定`,
    (SELECT `sold_stock`      FROM `shop_inventory` WHERE `sku_id` = 1001)                     AS `已售出`;

SELECT
    '★ 压测总判定' AS `校验项`,
    CASE WHEN
        -- 无负库存
        (SELECT COUNT(*) FROM `shop_inventory` WHERE `available_stock` < 0 OR `locked_stock` < 0 OR `sold_stock` < 0) = 0
        -- 三段守恒
    AND (SELECT COUNT(*) FROM `shop_inventory` WHERE `available_stock`+`locked_stock`+`sold_stock` <> `total_stock`) = 0
        -- 订单商品数 = 锁定量（对目标 SKU）
    AND (SELECT COALESCE(SUM(`quantity`),0) FROM `shop_order_item` WHERE `sku_id` = 1001)
      = (SELECT `locked_stock` FROM `shop_inventory` WHERE `sku_id` = 1001)
        -- 无重复下单
    AND (SELECT COUNT(*) FROM (SELECT `user_id`,`idempotency_key` FROM `shop_order`
          GROUP BY `user_id`,`idempotency_key` HAVING COUNT(*)>1) x) = 0
    THEN '✅✅✅ 全部通过：高并发下未发生超卖、未发生库存冗余、下单幂等生效'
    ELSE '❌❌❌ 存在一致性问题，请逐条查看上面的 CHECK 明细'
    END AS `结果`;


-- #############################################################################
--  库存健康快照（后台「一键对账」按钮直接调用这个视图）
-- #############################################################################
SELECT '--- 库存健康快照 ---' AS ``;
SELECT * FROM `v_inventory_health` ORDER BY `sku_id`;

SELECT '==================================================' AS ``;
SELECT '  校验报告结束' AS ``;
SELECT '==================================================' AS ``;

-- =============================================================================
--  ★ 答辩建议：对照实验
--
--  只展示「我的系统没超卖」说服力有限，老师无法判断你是真解决了问题，
--  还是并发压根没打上去。强烈建议做一次对照实验：
--
--  第一步：把库存扣减的 SQL 里的防超卖条件去掉
--          UPDATE shop_inventory SET available_stock = available_stock - ?
--           WHERE sku_id = ?;          -- ← 删掉 AND available_stock >= ?
--          同时临时删掉 CHECK 约束：
--          ALTER TABLE shop_inventory DROP CHECK ck_inv_available_nonneg;
--          ALTER TABLE shop_inventory DROP CHECK ck_inv_conservation;
--
--  第二步：重跑 1000 并发抢 100 件，执行本脚本
--          → CHECK-02 会报 FAIL，available_stock 变成负数（例如 -387）
--
--  第三步：把条件和约束加回来，重跑
--          → 成功订单恰好 100，所有 CHECK 全部 PASS
--
--  把这两次的截图并排放进报告，就完整证明了：
--  你不仅知道问题存在，而且知道是哪一行代码在解决它。
-- =============================================================================
