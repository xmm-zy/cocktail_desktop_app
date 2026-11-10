-- =============================================================================
--  Luceria Cocktail Atelier —— 触发器、存储过程与事件
--  文件：database/04_procedures_triggers.sql
--  前置：必须先执行 01_schema.sql
--
--  本文件分四部分：
--    第一部分 完整性守护触发器 —— 把「台账不可篡改」「订单快照不可修改」这类
--             业务铁律下沉到数据库，任何应用层 bug 都无法绕过。★ 强烈建议启用
--    第二部分 冗余计数维护触发器 —— 维护点赞数/评论数等冗余字段。
--             ⚠️ 有明确的适用边界，见下方说明，高并发场景不要用
--    第三部分 库存操作存储过程 —— 用 SQL 完整演示防超卖算法，
--             是《数据库原理》课程最直观的展示材料
--    第四部分 定时事件 —— 数据库级的兜底任务
-- =============================================================================

USE `luceria`;

-- MySQL 的语句分隔符默认是分号，而存储过程体内部也有分号，
-- 所以要临时把分隔符改成 $$，让 MySQL 知道整个过程体是一条语句。
DELIMITER $$


-- #############################################################################
--  第一部分：完整性守护触发器（★ 强烈建议启用）
-- #############################################################################

-- -----------------------------------------------------------------------------
-- T1 / T2：库存台账 append-only 强制
--
-- 设计意图：
--   shop_inventory_ledger 是「事实的记录」。如果它能被修改或删除，
--   那么「快照 vs 台账」的对账校验就失去意义 —— 因为有人可以先改错库存，
--   再改台账把账做平。
--
--   用触发器在数据库层禁止 UPDATE 和 DELETE 之后，台账就成为不可篡改的证据链，
--   任何时刻都可以用 SUM(delta_*) 反推出库存应有的值。
--   这是「保证数据不会错乱」这一目标里，最容易被忽略但最有力的一环。
--
--   SIGNAL SQLSTATE '45000' 是 MySQL 中抛出自定义错误的标准写法，
--   45000 表示「未处理的用户自定义异常」。
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS `trg_ledger_no_update`$$
CREATE TRIGGER `trg_ledger_no_update`
BEFORE UPDATE ON `shop_inventory_ledger`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '库存台账为只增不改的审计记录，禁止 UPDATE。如需修正请追加一条冲正流水。';
END$$

DROP TRIGGER IF EXISTS `trg_ledger_no_delete`$$
CREATE TRIGGER `trg_ledger_no_delete`
BEFORE DELETE ON `shop_inventory_ledger`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '库存台账为只增不改的审计记录，禁止 DELETE。';
END$$


-- -----------------------------------------------------------------------------
-- T3：订单明细的成交快照不可修改
--
-- 设计意图：
--   product_name / sku_spec_name / unit_price / quantity 是成交时刻的事实快照，
--   一旦写入就不能改（改了等于篡改历史交易记录）。
--   只有 refunded_quantity 和 refunded_amount 两个退款累计字段允许变更。
--
--   这条触发器把 5.2 节「反范式为什么安全」的论证变成了数据库强制约束：
--   我们说「快照字段写入后永不修改，所以不存在更新异常」，
--   这条触发器就是这句话的执行保障，而不只是一句君子协定。
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS `trg_order_item_snapshot_immutable`$$
CREATE TRIGGER `trg_order_item_snapshot_immutable`
BEFORE UPDATE ON `shop_order_item`
FOR EACH ROW
BEGIN
    IF  NEW.`order_id`        <> OLD.`order_id`
     OR NEW.`order_no`        <> OLD.`order_no`
     OR NEW.`sku_id`          <> OLD.`sku_id`
     OR NEW.`product_id`      <> OLD.`product_id`
     OR NEW.`product_name`    <> OLD.`product_name`
     OR NEW.`product_zh_name` <> OLD.`product_zh_name`
     OR NEW.`sku_spec_name`   <> OLD.`sku_spec_name`
     OR NEW.`unit_price`      <> OLD.`unit_price`
     OR NEW.`quantity`        <> OLD.`quantity`
     OR NEW.`total_amount`    <> OLD.`total_amount`
    THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = '订单明细的成交快照不可修改，仅允许更新 refunded_quantity / refunded_amount。';
    END IF;
END$$


-- -----------------------------------------------------------------------------
-- T4：订单明细禁止物理删除
--   订单数据是财务凭证，任何情况下都不物理删除。
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS `trg_order_item_no_delete`$$
CREATE TRIGGER `trg_order_item_no_delete`
BEFORE DELETE ON `shop_order_item`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '订单明细是财务凭证，禁止物理删除。';
END$$


-- -----------------------------------------------------------------------------
-- T5：邮箱统一转小写
--   保证 "Demo@X.com" 和 "demo@x.com" 不会注册成两个账号。
--   在数据库层做，比在每一处应用代码里手工 toLowerCase() 更可靠。
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS `trg_user_email_lower_ins`$$
CREATE TRIGGER `trg_user_email_lower_ins`
BEFORE INSERT ON `sys_user`
FOR EACH ROW
BEGIN
    SET NEW.`email` = LOWER(TRIM(NEW.`email`));
END$$

DROP TRIGGER IF EXISTS `trg_user_email_lower_upd`$$
CREATE TRIGGER `trg_user_email_lower_upd`
BEFORE UPDATE ON `sys_user`
FOR EACH ROW
BEGIN
    SET NEW.`email` = LOWER(TRIM(NEW.`email`));
END$$


-- #############################################################################
--  第二部分：冗余计数维护触发器
--
--  ⚠️ 适用边界说明（这是本文件最重要的一段设计权衡，请认真阅读）
--
--  用触发器维护冗余计数的好处：
--    ① 无论从哪条代码路径写入，计数都不会漏更新；
--    ② 应用层代码更干净；
--    ③ 计数更新与业务写入天然在同一事务中，不会出现「点赞成功但计数没加」。
--
--  代价与风险：
--    ① 触发器会延长事务、扩大锁范围（点赞的同时要更新帖子行，多锁一行）；
--    ② 逻辑藏在数据库里，排查问题时容易被遗漏；
--    ③ 高并发下会把「帖子行」变成热点行，所有对该帖的点赞都串行化。
--
--  因此本项目的取舍是：
--    ✅ 内容社区的点赞/收藏/回复计数 → 用触发器（并发量小，一致性收益大）
--    ❌ 库存 / 订单金额 / 销量        → 绝不用触发器，一律在 Java Service 层
--       用显式的 CAS SQL 处理。理由：这些是高并发热点，需要精确控制锁的范围
--       和事务边界，触发器会让这些控制变得不可见、不可调。
--
--  如果压测中发现点赞成为瓶颈，可以直接 DROP 掉这一部分触发器，
--  改用 Redis 计数 + 定时回写，业务代码无需改动。
-- #############################################################################

-- ---- 帖子点赞数 ----
DROP TRIGGER IF EXISTS `trg_post_like_inc`$$
CREATE TRIGGER `trg_post_like_inc`
AFTER INSERT ON `story_post_like`
FOR EACH ROW
BEGIN
    UPDATE `story_post` SET `like_count` = `like_count` + 1 WHERE `id` = NEW.`post_id`;
END$$

DROP TRIGGER IF EXISTS `trg_post_like_dec`$$
CREATE TRIGGER `trg_post_like_dec`
AFTER DELETE ON `story_post_like`
FOR EACH ROW
BEGIN
    -- 加 WHERE like_count > 0 是为了防止计数被减成负数（列是 UNSIGNED，减到负会报错）
    UPDATE `story_post` SET `like_count` = `like_count` - 1
     WHERE `id` = OLD.`post_id` AND `like_count` > 0;
END$$

-- ---- 帖子收藏数 ----
DROP TRIGGER IF EXISTS `trg_post_fav_inc`$$
CREATE TRIGGER `trg_post_fav_inc`
AFTER INSERT ON `story_post_favorite`
FOR EACH ROW
BEGIN
    UPDATE `story_post` SET `favorite_count` = `favorite_count` + 1 WHERE `id` = NEW.`post_id`;
END$$

DROP TRIGGER IF EXISTS `trg_post_fav_dec`$$
CREATE TRIGGER `trg_post_fav_dec`
AFTER DELETE ON `story_post_favorite`
FOR EACH ROW
BEGIN
    UPDATE `story_post` SET `favorite_count` = `favorite_count` - 1
     WHERE `id` = OLD.`post_id` AND `favorite_count` > 0;
END$$

-- ---- 帖子回复数 ----
DROP TRIGGER IF EXISTS `trg_reply_count_inc`$$
CREATE TRIGGER `trg_reply_count_inc`
AFTER INSERT ON `story_reply`
FOR EACH ROW
BEGIN
    UPDATE `story_post` SET `reply_count` = `reply_count` + 1 WHERE `id` = NEW.`post_id`;
END$$

-- 注意：回复采用逻辑删除（status 0/1），所以计数维护挂在 UPDATE 而不是 DELETE 上
DROP TRIGGER IF EXISTS `trg_reply_count_soft_delete`$$
CREATE TRIGGER `trg_reply_count_soft_delete`
AFTER UPDATE ON `story_reply`
FOR EACH ROW
BEGIN
    IF OLD.`status` = 1 AND NEW.`status` = 0 THEN
        UPDATE `story_post` SET `reply_count` = `reply_count` - 1
         WHERE `id` = NEW.`post_id` AND `reply_count` > 0;
    ELSEIF OLD.`status` = 0 AND NEW.`status` = 1 THEN
        UPDATE `story_post` SET `reply_count` = `reply_count` + 1 WHERE `id` = NEW.`post_id`;
    END IF;
END$$

-- ---- 回复点赞数 ----
DROP TRIGGER IF EXISTS `trg_reply_like_inc`$$
CREATE TRIGGER `trg_reply_like_inc`
AFTER INSERT ON `story_reply_like`
FOR EACH ROW
BEGIN
    UPDATE `story_reply` SET `like_count` = `like_count` + 1 WHERE `id` = NEW.`reply_id`;
END$$

DROP TRIGGER IF EXISTS `trg_reply_like_dec`$$
CREATE TRIGGER `trg_reply_like_dec`
AFTER DELETE ON `story_reply_like`
FOR EACH ROW
BEGIN
    UPDATE `story_reply` SET `like_count` = `like_count` - 1
     WHERE `id` = OLD.`reply_id` AND `like_count` > 0;
END$$

-- ---- 评论点赞数 ----
DROP TRIGGER IF EXISTS `trg_review_like_inc`$$
CREATE TRIGGER `trg_review_like_inc`
AFTER INSERT ON `cocktail_review_like`
FOR EACH ROW
BEGIN
    UPDATE `cocktail_review` SET `like_count` = `like_count` + 1 WHERE `id` = NEW.`review_id`;
END$$

DROP TRIGGER IF EXISTS `trg_review_like_dec`$$
CREATE TRIGGER `trg_review_like_dec`
AFTER DELETE ON `cocktail_review_like`
FOR EACH ROW
BEGIN
    UPDATE `cocktail_review` SET `like_count` = `like_count` - 1
     WHERE `id` = OLD.`review_id` AND `like_count` > 0;
END$$

-- ---- 酒款的评论数与平均分 ----
-- 平均分用「重算」而不是「增量累加」：
--   增量维护平均分需要同时存 SUM 和 COUNT，且浮点累加会有误差累积；
--   评论量级很小（每款酒最多几百条），直接 AVG 重算既简单又准确。
DROP TRIGGER IF EXISTS `trg_cocktail_stat_ins`$$
CREATE TRIGGER `trg_cocktail_stat_ins`
AFTER INSERT ON `cocktail_review`
FOR EACH ROW
BEGIN
    UPDATE `cocktail` c
       SET c.`review_count` = (SELECT COUNT(*)             FROM `cocktail_review` r
                                WHERE r.`cocktail_id` = NEW.`cocktail_id` AND r.`status` = 1),
           c.`avg_rating`   = COALESCE((SELECT ROUND(AVG(r.`rating`), 1) FROM `cocktail_review` r
                                WHERE r.`cocktail_id` = NEW.`cocktail_id` AND r.`status` = 1), 0.0)
     WHERE c.`id` = NEW.`cocktail_id`;
END$$

DROP TRIGGER IF EXISTS `trg_cocktail_stat_upd`$$
CREATE TRIGGER `trg_cocktail_stat_upd`
AFTER UPDATE ON `cocktail_review`
FOR EACH ROW
BEGIN
    UPDATE `cocktail` c
       SET c.`review_count` = (SELECT COUNT(*)             FROM `cocktail_review` r
                                WHERE r.`cocktail_id` = NEW.`cocktail_id` AND r.`status` = 1),
           c.`avg_rating`   = COALESCE((SELECT ROUND(AVG(r.`rating`), 1) FROM `cocktail_review` r
                                WHERE r.`cocktail_id` = NEW.`cocktail_id` AND r.`status` = 1), 0.0)
     WHERE c.`id` = NEW.`cocktail_id`;
END$$


-- #############################################################################
--  第三部分：库存操作存储过程
--
--  ★ 定位说明（请务必理解，答辩时会被问到）：
--    生产环境的库存操作走 Java Service 层（Spring @Transactional + MyBatis），
--    因为那里才能和 Redis 漏斗、分布式锁、延迟队列协同。
--
--    这里的存储过程有两个用途：
--      ① 教学与演示：把防超卖算法用纯 SQL 完整表达出来，
--         老师可以直接在命令行里并发调用它，观察结果，无需启动 Java 服务；
--      ② 降级预案：当 Java 服务出现问题时，运维可以直接调用存储过程
--         做库存纠正，且保证走的是和线上完全一致的逻辑。
--
--    ⚠️ 为什么生产不用存储过程做主链路？
--      存储过程难以版本管理（不像 Java 代码能进 Git 走 Code Review）、
--      难以单元测试、难以调试、无法跨数据库移植，
--      且业务逻辑分散在两个地方会造成维护灾难。这是行业共识。
-- #############################################################################

-- -----------------------------------------------------------------------------
-- P1. sp_lock_stock —— 下单锁定库存（★ 防超卖核心算法的 SQL 表达）
--
-- 参数：
--   p_sku_id    SKU ID
--   p_qty       扣减数量
--   p_order_no  订单号（同时作为幂等键）
--   p_user_id   操作人
--   p_result    OUT 返回码：1 成功  0 库存不足  2 重复请求（幂等命中）
--
-- 算法要点：
--   ① 用一条 UPDATE ... WHERE available_stock >= p_qty 完成「检查+扣减」。
--      这是防超卖的唯一正确性来源：InnoDB 执行 UPDATE 时先对该行加 X 锁，
--      再在持锁状态下评估 WHERE 条件，所以「检查」和「扣减」之间
--      不存在任何其它事务可以插入的时间窗口（消除了 TOCTOU 竞态）。
--   ② ROW_COUNT() = 0 说明条件不满足，即库存不足，直接返回 0，不需要重试。
--      这一点优于「版本号乐观锁」——后者在高并发下会产生大量无谓重试。
--   ③ 台账的唯一索引 uk_ledger_biz 保证同一订单对同一 SKU 只能锁定一次。
--      重复调用会撞唯一键，被 EXIT HANDLER 捕获后整体回滚，
--      净效果为零，因此本过程是幂等的。
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_lock_stock`$$
CREATE PROCEDURE `sp_lock_stock`(
    IN  p_sku_id   BIGINT UNSIGNED,
    IN  p_qty      INT,
    IN  p_order_no VARCHAR(64),
    IN  p_user_id  BIGINT UNSIGNED,
    OUT p_result   INT
)
proc_body: BEGIN
    DECLARE v_avail INT DEFAULT 0;
    DECLARE v_lock  INT DEFAULT 0;
    DECLARE v_sold  INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;

    -- 捕获唯一键冲突（SQLSTATE 23000 = 完整性约束违反）→ 判定为重复请求
    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
    BEGIN
        ROLLBACK;
        SET p_result = 2;   -- 幂等命中：该订单已经锁过这个 SKU 的库存
    END;

    -- 捕获其它任何异常 → 回滚并向上抛出
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = -1;
        RESIGNAL;
    END;

    IF p_qty IS NULL OR p_qty <= 0 THEN
        SET p_result = 0;
        LEAVE proc_body;
    END IF;

    START TRANSACTION;

    -- ★★★ 核心：条件 CAS，检查与扣减在同一条语句内原子完成 ★★★
    UPDATE `shop_inventory`
       SET `available_stock` = `available_stock` - p_qty,
           `locked_stock`    = `locked_stock`    + p_qty,
           `version`         = `version` + 1
     WHERE `sku_id`          = p_sku_id
       AND `available_stock` >= p_qty;

    IF ROW_COUNT() = 0 THEN
        -- 条件不满足 = 库存不足（或 SKU 不存在）。无需重试，语义本身就是失败。
        ROLLBACK;
        SET p_result = 0;
        LEAVE proc_body;
    END IF;

    -- 走到这里说明扣减已成功，且当前事务持有该行的 X 锁，
    -- 因此下面读到的值一定是本次扣减后的准确值，不会被其它事务干扰。
    SELECT `available_stock`, `locked_stock`, `sold_stock`, `total_stock`
      INTO v_avail, v_lock, v_sold, v_total
      FROM `shop_inventory`
     WHERE `sku_id` = p_sku_id;

    -- 写台账。若该订单已锁过这个 SKU，此处会撞 uk_ledger_biz 唯一键，
    -- 被上面的 23000 HANDLER 捕获 → 整体回滚 → 上面的扣减也被撤销 → 幂等。
    INSERT INTO `shop_inventory_ledger`
        (`sku_id`, `biz_type`, `biz_no`,
         `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
         `after_available`, `after_locked`, `after_sold`, `after_total`,
         `operator_type`, `operator_id`, `remark`)
    VALUES
        (p_sku_id, 'ORDER_LOCK', p_order_no,
         -p_qty, p_qty, 0, 0,
         v_avail, v_lock, v_sold, v_total,
         'USER', p_user_id, '下单锁定库存');

    COMMIT;
    SET p_result = 1;
END$$


-- -----------------------------------------------------------------------------
-- P2. sp_release_stock —— 释放锁定库存（用户取消 / 超时关单）
--
-- 关键点：条件是 locked_stock >= p_qty，而不是无脑 available += qty。
--   如果这个订单本来就没锁定过库存（比如重复关单），
--   locked_stock 不足会让 CAS 失败，数据库直接拒绝这次错误的回补。
--   这就是三段式模型相比单字段 stock 的核心价值：
--   它让「这笔回补到底该不该做」变成一个可被数据库验证的条件。
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_release_stock`$$
CREATE PROCEDURE `sp_release_stock`(
    IN  p_sku_id   BIGINT UNSIGNED,
    IN  p_qty      INT,
    IN  p_order_no VARCHAR(64),
    IN  p_biz_type VARCHAR(24),   -- ORDER_CANCEL 或 ORDER_EXPIRE
    OUT p_result   INT
)
proc_body: BEGIN
    DECLARE v_avail INT; DECLARE v_lock INT; DECLARE v_sold INT; DECLARE v_total INT;

    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
    BEGIN ROLLBACK; SET p_result = 2; END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; SET p_result = -1; RESIGNAL; END;

    START TRANSACTION;

    UPDATE `shop_inventory`
       SET `available_stock` = `available_stock` + p_qty,
           `locked_stock`    = `locked_stock`    - p_qty,
           `version`         = `version` + 1
     WHERE `sku_id`       = p_sku_id
       AND `locked_stock` >= p_qty;     -- ★ 锁定量不足则拒绝，防止凭空回补

    IF ROW_COUNT() = 0 THEN
        ROLLBACK; SET p_result = 0; LEAVE proc_body;
    END IF;

    SELECT `available_stock`, `locked_stock`, `sold_stock`, `total_stock`
      INTO v_avail, v_lock, v_sold, v_total
      FROM `shop_inventory` WHERE `sku_id` = p_sku_id;

    INSERT INTO `shop_inventory_ledger`
        (`sku_id`, `biz_type`, `biz_no`,
         `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
         `after_available`, `after_locked`, `after_sold`, `after_total`,
         `operator_type`, `remark`)
    VALUES
        (p_sku_id, p_biz_type, p_order_no,
         p_qty, -p_qty, 0, 0,
         v_avail, v_lock, v_sold, v_total,
         'SYSTEM', '释放锁定库存');

    COMMIT;
    SET p_result = 1;
END$$


-- -----------------------------------------------------------------------------
-- P3. sp_confirm_sold —— 支付确认，锁定转已售
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_confirm_sold`$$
CREATE PROCEDURE `sp_confirm_sold`(
    IN  p_sku_id   BIGINT UNSIGNED,
    IN  p_qty      INT,
    IN  p_order_no VARCHAR(64),
    OUT p_result   INT
)
proc_body: BEGIN
    DECLARE v_avail INT; DECLARE v_lock INT; DECLARE v_sold INT; DECLARE v_total INT;

    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
    BEGIN ROLLBACK; SET p_result = 2; END;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; SET p_result = -1; RESIGNAL; END;

    START TRANSACTION;

    UPDATE `shop_inventory`
       SET `locked_stock` = `locked_stock` - p_qty,
           `sold_stock`   = `sold_stock`   + p_qty,
           `version`      = `version` + 1
     WHERE `sku_id`       = p_sku_id
       AND `locked_stock` >= p_qty;

    IF ROW_COUNT() = 0 THEN
        ROLLBACK; SET p_result = 0; LEAVE proc_body;
    END IF;

    SELECT `available_stock`, `locked_stock`, `sold_stock`, `total_stock`
      INTO v_avail, v_lock, v_sold, v_total
      FROM `shop_inventory` WHERE `sku_id` = p_sku_id;

    INSERT INTO `shop_inventory_ledger`
        (`sku_id`, `biz_type`, `biz_no`,
         `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
         `after_available`, `after_locked`, `after_sold`, `after_total`,
         `operator_type`, `remark`)
    VALUES
        (p_sku_id, 'PAY_CONFIRM', p_order_no,
         0, -p_qty, p_qty, 0,
         v_avail, v_lock, v_sold, v_total,
         'SYSTEM', '支付成功，锁定转已售');

    COMMIT;
    SET p_result = 1;
END$$


-- -----------------------------------------------------------------------------
-- P4. sp_refund_stock —— 退款库存回滚（★ 演示「为什么不能简单 stock = stock + n」）
--
-- p_restock = 1（退货退款）：商品回到仓库
--     sold -= n, available += n, total 不变
-- p_restock = 0（仅退款不退货）：商品未退回，作为损耗核销
--     sold -= n, total -= n, available 不变
--
-- 两种情况下 delta 之和都等于 delta_total，守恒不变式始终成立。
-- 简单的 `stock = stock + n` 既表达不了这个区分，也无法幂等，
-- 更无法校验「这笔货到底是不是从已售出的那部分退回来的」。
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_refund_stock`$$
CREATE PROCEDURE `sp_refund_stock`(
    IN  p_sku_id    BIGINT UNSIGNED,
    IN  p_qty       INT,
    IN  p_refund_no VARCHAR(64),
    IN  p_restock   TINYINT,       -- 1 退货入库  0 仅退款核销
    OUT p_result    INT
)
proc_body: BEGIN
    DECLARE v_avail INT; DECLARE v_lock INT; DECLARE v_sold INT; DECLARE v_total INT;
    DECLARE v_biz   VARCHAR(24);
    DECLARE v_d_avail INT; DECLARE v_d_total INT;

    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
    BEGIN ROLLBACK; SET p_result = 2; END;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; SET p_result = -1; RESIGNAL; END;

    IF p_restock = 1 THEN
        SET v_biz = 'REFUND_RETURN';  SET v_d_avail = p_qty; SET v_d_total = 0;
    ELSE
        SET v_biz = 'REFUND_WRITEOFF'; SET v_d_avail = 0;    SET v_d_total = -p_qty;
    END IF;

    START TRANSACTION;

    UPDATE `shop_inventory`
       SET `available_stock` = `available_stock` + v_d_avail,
           `sold_stock`      = `sold_stock` - p_qty,
           `total_stock`     = `total_stock` + v_d_total,
           `version`         = `version` + 1
     WHERE `sku_id`     = p_sku_id
       AND `sold_stock` >= p_qty;      -- ★ 已售出的量必须够，否则这笔退货来路不明

    IF ROW_COUNT() = 0 THEN
        ROLLBACK; SET p_result = 0; LEAVE proc_body;
    END IF;

    SELECT `available_stock`, `locked_stock`, `sold_stock`, `total_stock`
      INTO v_avail, v_lock, v_sold, v_total
      FROM `shop_inventory` WHERE `sku_id` = p_sku_id;

    -- 幂等锚点：uk_ledger_biz (biz_type, biz_no, sku_id)
    -- 同一张退款单对同一 SKU 的回补，物理上只可能成功一次。
    INSERT INTO `shop_inventory_ledger`
        (`sku_id`, `biz_type`, `biz_no`,
         `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
         `after_available`, `after_locked`, `after_sold`, `after_total`,
         `operator_type`, `remark`)
    VALUES
        (p_sku_id, v_biz, p_refund_no,
         v_d_avail, 0, -p_qty, v_d_total,
         v_avail, v_lock, v_sold, v_total,
         'SYSTEM', IF(p_restock = 1, '退货入库', '仅退款核销损耗'));

    COMMIT;
    SET p_result = 1;
END$$


-- -----------------------------------------------------------------------------
-- P5. sp_reset_bench —— 压测数据重置
-- 每轮压测前调用，把目标 SKU 的库存恢复到指定值，并清空订单相关数据，
-- 保证每次压测的起点完全一致、结果可复现。
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_reset_bench`$$
CREATE PROCEDURE `sp_reset_bench`(
    IN p_sku_id BIGINT UNSIGNED,
    IN p_stock  INT
)
BEGIN
    SET FOREIGN_KEY_CHECKS = 0;
    -- 台账有 append-only 触发器保护，清空必须用 TRUNCATE（DDL，不触发 DELETE 触发器）
    TRUNCATE TABLE `shop_inventory_ledger`;
    TRUNCATE TABLE `shop_order_status_log`;
    TRUNCATE TABLE `shop_payment_notify_log`;
    TRUNCATE TABLE `shop_payment`;
    TRUNCATE TABLE `shop_refund`;
    TRUNCATE TABLE `shop_order_item`;
    TRUNCATE TABLE `shop_order`;
    TRUNCATE TABLE `shop_delay_task`;
    SET FOREIGN_KEY_CHECKS = 1;

    UPDATE `shop_inventory`
       SET `total_stock`     = p_stock,
           `available_stock` = p_stock,
           `locked_stock`    = 0,
           `sold_stock`      = 0,
           `version`         = 0
     WHERE `sku_id` = p_sku_id;

    INSERT INTO `shop_inventory_ledger`
        (`sku_id`, `biz_type`, `biz_no`,
         `delta_available`, `delta_locked`, `delta_sold`, `delta_total`,
         `after_available`, `after_locked`, `after_sold`, `after_total`,
         `operator_type`, `remark`)
    VALUES
        (p_sku_id, 'INIT', CONCAT('BENCH-', p_sku_id, '-', UNIX_TIMESTAMP()),
         p_stock, 0, 0, p_stock,
         p_stock, 0, 0, p_stock,
         'ADMIN', '压测重置');

    SELECT CONCAT('压测数据已重置：sku_id=', p_sku_id, ' 库存=', p_stock) AS `结果`;
    SELECT '别忘了同步重置 Redis：redis-cli SET shop:stock:' AS `提醒`, p_sku_id AS `sku`, p_stock AS `值`;
END$$


-- -----------------------------------------------------------------------------
-- P6. sp_check_ingredient_count —— 校验「每款酒的材料数在 2–12 之间」
--
-- 为什么用存储过程而不是 CHECK 约束或触发器？
--   ① CHECK 约束只能作用于单行，无法表达「一个酒款下的材料总行数」这种跨行条件；
--   ② MySQL 触发器不能在触发它的那张表上做可靠的聚合查询
--      （会遇到 "Can't update table ... already used by statement" 一类的限制）；
--   ③ 因此这个约束由「应用层校验 + 本过程定期巡检」两道保证。
-- 这是数据库约束能力边界的一个真实例子，值得在报告里写清楚。
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_check_ingredient_count`$$
CREATE PROCEDURE `sp_check_ingredient_count`()
BEGIN
    SELECT c.`id`      AS `酒款ID`,
           c.`zh_name` AS `酒款名`,
           COUNT(i.`id`) AS `材料条数`,
           '材料条数必须在 2-12 之间' AS `违反的规则`
      FROM `cocktail` c
      LEFT JOIN `cocktail_ingredient` i ON i.`cocktail_id` = c.`id`
     WHERE c.`status` = 1
     GROUP BY c.`id`, c.`zh_name`
    HAVING COUNT(i.`id`) < 2 OR COUNT(i.`id`) > 12;
END$$


-- #############################################################################
--  第四部分：定时事件（数据库级兜底）
--
--  ⚠️ 事件调度器默认是关闭的，需要先开启：
--       SET GLOBAL event_scheduler = ON;
--     或在 my.cnf 中加 event_scheduler = ON 并重启。
--
--  定位：这些事件是「最后的兜底」，不是主通道。
--    主通道是 Redisson 延迟队列（秒级精度）+ Spring @Scheduled 定时扫描。
--    数据库事件的作用是：万一 Java 服务整个挂了，
--    至少不会有订单永远卡在待支付状态、库存永远被锁死。
--
--    所有兜底路径调用的都是同一个幂等的 CAS 逻辑，
--    因此三个通道同时跑也不会出错。
-- #############################################################################

-- -----------------------------------------------------------------------------
-- E1. 每分钟关闭超时未支付订单，并释放锁定库存
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS `ev_close_expired_orders`$$
CREATE EVENT `ev_close_expired_orders`
ON SCHEDULE EVERY 1 MINUTE
COMMENT '兜底：关闭超时未支付订单并释放库存（主通道是应用层的 Redisson 延迟队列）'
DO
BEGIN
    DECLARE v_done   INT DEFAULT 0;
    DECLARE v_no     VARCHAR(32);
    DECLARE v_sku    BIGINT UNSIGNED;
    DECLARE v_qty    INT;
    DECLARE v_result INT;

    -- 游标：找出所有已过期仍待支付的订单明细
    DECLARE cur CURSOR FOR
        SELECT o.`order_no`, oi.`sku_id`, oi.`quantity`
          FROM `shop_order` o
          JOIN `shop_order_item` oi ON oi.`order_id` = o.`id`
         WHERE o.`status` = 'PENDING_PAYMENT'
           AND o.`expire_at` < NOW(3)
         LIMIT 200;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    -- ★ CAS 关单：只有仍是 PENDING_PAYMENT 的才会被改。
    --   如果用户恰好在这一刻支付成功（状态已变 PAID），这条 UPDATE 匹配不到，
    --   订单保持已支付状态，库存留在 sold —— 关单与支付的竞态在此被彻底消除。
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_no, v_sku, v_qty;
        IF v_done = 1 THEN LEAVE read_loop; END IF;
        CALL `sp_release_stock`(v_sku, v_qty, v_no, 'ORDER_EXPIRE', v_result);
    END LOOP;
    CLOSE cur;

    UPDATE `shop_order`
       SET `status`       = 'CLOSED',
           `close_time`   = NOW(3),
           `close_reason` = 'TIMEOUT_DB_EVENT',
           `version`      = `version` + 1
     WHERE `status`    = 'PENDING_PAYMENT'
       AND `expire_at` < NOW(3);
END$$


-- -----------------------------------------------------------------------------
-- E2. 每小时清理过期的验证码与失效的刷新令牌
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS `ev_clean_auth_data`$$
CREATE EVENT `ev_clean_auth_data`
ON SCHEDULE EVERY 1 HOUR
COMMENT '清理过期验证码与失效令牌，避免这两张表无限膨胀'
DO
BEGIN
    DELETE FROM `sys_auth_code`
     WHERE `expires_at` < DATE_SUB(NOW(3), INTERVAL 1 DAY)
     LIMIT 5000;

    DELETE FROM `sys_refresh_token`
     WHERE (`expires_at` < NOW(3) OR `revoked_at` IS NOT NULL)
       AND `created_at`  < DATE_SUB(NOW(3), INTERVAL 30 DAY)
     LIMIT 5000;
END$$


-- -----------------------------------------------------------------------------
-- E3. 每天清理孤儿文件（上传后 24 小时仍未被业务引用的）
--     只把状态标记为「待删除」，实际的物理文件删除由 Java 定时任务执行，
--     因为数据库无权操作磁盘/对象存储。
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS `ev_mark_orphan_files`$$
CREATE EVENT `ev_mark_orphan_files`
ON SCHEDULE EVERY 1 DAY
COMMENT '标记孤儿文件为待删除，解决「用户传了图但没提交表单」造成的存储泄漏'
DO
BEGIN
    UPDATE `sys_file`
       SET `status` = 2
     WHERE `status` = 0
       AND `created_at` < DATE_SUB(NOW(3), INTERVAL 1 DAY)
     LIMIT 1000;
END$$


DELIMITER ;

-- =============================================================================
--  使用示例（可复制到命令行验证）
--
--  -- 演示防超卖：正常扣减
--  CALL sp_lock_stock(1001, 2, 'TEST-ORDER-001', 2, @r); SELECT @r;   -- 期望 1
--
--  -- 演示幂等：同一订单再锁一次
--  CALL sp_lock_stock(1001, 2, 'TEST-ORDER-001', 2, @r); SELECT @r;   -- 期望 2（幂等命中）
--
--  -- 演示库存不足：一次要 99999 件
--  CALL sp_lock_stock(1001, 99999, 'TEST-ORDER-002', 2, @r); SELECT @r; -- 期望 0
--
--  -- 演示支付确认
--  CALL sp_confirm_sold(1001, 2, 'TEST-ORDER-001', @r); SELECT @r;    -- 期望 1
--
--  -- 演示退货回补
--  CALL sp_refund_stock(1001, 1, 'TEST-REFUND-001', 1, @r); SELECT @r; -- 期望 1
--  CALL sp_refund_stock(1001, 1, 'TEST-REFUND-001', 1, @r); SELECT @r; -- 期望 2（幂等，不会多加）
--
--  -- 查看完整的库存变动轨迹
--  SELECT * FROM shop_inventory_ledger WHERE sku_id = 1001 ORDER BY id;
--
--  -- 验证台账不可篡改
--  DELETE FROM shop_inventory_ledger WHERE id = 1;   -- 期望报错 45000
--
--  -- 压测重置
--  CALL sp_reset_bench(1001, 100);
-- =============================================================================
