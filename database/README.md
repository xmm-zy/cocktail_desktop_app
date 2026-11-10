# Luceria Cocktail Atelier —— 数据库设计说明

> 本目录是《数据库原理》课程期末作品的核心产出。
> 配套需求文档见项目根目录的 `REQUIREMENTS.md`（第 5 章「数据库设计」与本目录一一对应）。

---

## 目录

1. [环境要求](#1-环境要求)
2. [文件清单与执行顺序](#2-文件清单与执行顺序)
3. [如何重置数据库](#3-如何重置数据库)
4. [字符集与排序规则](#4-字符集与排序规则)
5. [表清单（31 张）](#5-表清单31-张)
6. [关键设计决策与理由](#6-关键设计决策与理由)
7. [范式分析：设计到第几范式，哪里刻意反范式](#7-范式分析)
8. [索引清单与设计理由](#8-索引清单与设计理由)
9. [CHECK 约束清单](#9-check-约束清单)
10. [数据字典（核心表逐字段）](#10-数据字典)
11. [Postgres → MySQL 类型映射（迁移用）](#11-postgres--mysql-类型映射)
12. [常见问题排查](#12-常见问题排查)

---

## 1. 环境要求

| 项目 | 要求 | 说明 |
|---|---|---|
| MySQL 版本 | **>= 8.0.16** | 8.0.16 之前的 MySQL 只**解析**但**不执行** `CHECK` 约束（当注释处理）。本设计大量依赖 CHECK 保证库存守恒，版本不够整套正确性保证就是空的。用 `SELECT VERSION();` 确认 |
| 存储引擎 | **InnoDB** | 唯一支持事务和行级锁的引擎。MyISAM 只有表锁且无事务，完全无法满足并发下单场景 |
| 字符集 | `utf8mb4` | 见第 4 节 |
| 排序规则 | `utf8mb4_0900_ai_ci` | 见第 4 节 |
| SQL 模式 | 含 `STRICT_TRANS_TABLES` | 严格模式下，插入超长字符串或非法值会直接报错而不是静默截断 |
| 事件调度器 | `event_scheduler = ON`（可选） | 只有要启用 `04_procedures_triggers.sql` 里的定时事件才需要 |
| 全文索引分词 | `ngram_token_size = 2`（默认值） | 中文全文搜索需要 |

检查命令：

```sql
SELECT VERSION();
SELECT @@sql_mode;
SELECT @@event_scheduler;
SHOW VARIABLES LIKE 'ngram_token_size';
```

---

## 2. 文件清单与执行顺序

**必须按序号顺序执行。** 后面的脚本依赖前面创建的对象。

| 顺序 | 文件 | 内容 | 是否必需 |
|---|---|---|---|
| 1 | `01_schema.sql` | 建库 + 31 张表 DDL + 3 个视图。索引、外键、CHECK 全部内联在建表语句里 | ✅ 必需 |
| 2 | `02_indexes.sql` | 中文全文索引（ngram）+ 索引清单统计 + 14 条 EXPLAIN 验证 | 建议执行 |
| 3 | `03_seed_data.sql` | 初始化数据：8 款内置鸡尾酒（含 41 条配方材料）、6 个测试用户、8 个商品 / 10 个 SKU / 库存、论坛帖子、一笔完整示例订单 | ✅ 必需 |
| 4 | `04_procedures_triggers.sql` | 5 个完整性守护触发器 + 10 个计数维护触发器 + 6 个存储过程 + 3 个定时事件 | 建议执行 |
| 5 | `05_verification.sql` | 35 条数据一致性断言查询（压测后 / 答辩时执行） | 建议执行 |

### 命令行执行

```bash
cd database

mysql -u root -p < 01_schema.sql
mysql -u root -p luceria < 02_indexes.sql
mysql -u root -p luceria < 03_seed_data.sql
mysql -u root -p luceria < 04_procedures_triggers.sql
mysql -u root -p luceria < 05_verification.sql > verify_report.txt
```

### Windows PowerShell

```powershell
cd database
Get-Content 01_schema.sql | mysql -u root -p
Get-Content 03_seed_data.sql | mysql -u root -p luceria
```

> **注意 Windows 下的编码问题**：如果导入后中文变成乱码，说明客户端编码不对。
> 用 `mysql --default-character-set=utf8mb4 -u root -p` 显式指定，
> 或直接用 Navicat / DBeaver 打开文件执行（它们默认按文件的 UTF-8 编码读取）。

### 图形化工具

Navicat / DBeaver / MySQL Workbench 都可以直接打开 `.sql` 文件后整体执行。
`04_procedures_triggers.sql` 里有 `DELIMITER $$`，**MySQL Workbench 和 Navicat 都支持**，
但如果你的工具报「DELIMITER 语法错误」，说明它不支持这个客户端命令，请改用命令行执行该文件。

---

## 3. 如何重置数据库

### 方式一：完全重建（推荐，最干净）

`01_schema.sql` 开头就有 `DROP DATABASE IF EXISTS luceria`，所以重跑一遍全套脚本即可：

```bash
mysql -u root -p < 01_schema.sql && \
mysql -u root -p luceria < 02_indexes.sql && \
mysql -u root -p luceria < 03_seed_data.sql && \
mysql -u root -p luceria < 04_procedures_triggers.sql
```

### 方式二：只重置数据，保留表结构

`03_seed_data.sql` 开头会 `TRUNCATE` 所有表，可以单独重复执行：

```bash
mysql -u root -p luceria < 03_seed_data.sql
```

### 方式三：只重置压测目标的库存（最快，压测中反复用）

```sql
CALL sp_reset_bench(1001, 100);
```

> ⚠️ **重置数据库后一定要同步清空 Redis**，否则 Redis 里残留的库存计数会和 MySQL 对不上：
>
> ```bash
> redis-cli --scan --pattern "shop:stock:*" | xargs redis-cli DEL
> redis-cli --scan --pattern "shop:order:idem:*" | xargs redis-cli DEL
> # 或者开发环境直接 redis-cli FLUSHDB
> ```

---

## 4. 字符集与排序规则

### 为什么必须是 `utf8mb4` 而不是 `utf8`

MySQL 历史上的 `utf8`（准确名称 `utf8mb3`）**每个字符最多只用 3 字节**，
而 UTF-8 标准允许最多 4 字节。落在 4 字节区间的字符包括：

- 全部 emoji（😀🍸🥃）
- 部分生僻汉字（𠮷、𡃁 等扩展区汉字）

本项目是内容社区，用户在帖子、评论、昵称里打 emoji 是必然的。
如果用 `utf8mb3`，插入 emoji 会直接报 `Incorrect string value: '\xF0\x9F\x8D\xB8'`。

MySQL 8.0 已经把 `utf8mb4` 设为默认，`utf8` 这个别名也被标记为废弃。

### 为什么选 `utf8mb4_0900_ai_ci`

| 排序规则 | 说明 | 是否采用 |
|---|---|---|
| `utf8mb4_0900_ai_ci` | 基于 Unicode 9.0，MySQL 8.0 默认。**ai** = accent insensitive（不区分重音，`é` = `e`），**ci** = case insensitive（不区分大小写，`A` = `a`）。用了 MySQL 8.0 重写的比较算法，比旧的 `utf8mb4_general_ci` **快约 20%** | ✅ 采用 |
| `utf8mb4_general_ci` | MySQL 5.x 时代的老规则，比较逻辑不完全符合 Unicode 标准（例如把 `ß` 当成 `s` 而不是 `ss`） | ❌ 遗留方案 |
| `utf8mb4_bin` | 按字节二进制比较，区分大小写。查询精确但用户体验差（搜 `whiskey` 找不到 `Whiskey`） | ❌ |
| `utf8mb4_0900_as_cs` | 区分重音和大小写 | ❌ 不适合搜索场景 |

选 `ai_ci` 的直接业务收益：
搜索酒名时，用户输入 `whiskey sour`、`Whiskey Sour`、`WHISKEY SOUR` 都能命中同一条记录，
不需要在应用层做大小写归一化。

### 一个由排序规则引发的坑

`cocktail.name_lower` 是生成列，专门用来做大小写不敏感的唯一约束。
既然排序规则已经是 `ci`（不区分大小写），为什么还要多此一举？

因为 **`ci` 只影响比较和排序，唯一索引在 `ci` 规则下确实会把 `Mojito` 和 `mojito` 判为重复**。
所以严格来说 `name_lower` 在这里是冗余的。保留它的理由有两个：

1. **明确表达意图**。看到 `name_lower` + 唯一索引，任何人都能立刻明白「酒名大小写不敏感唯一」是一条业务规则，而不是排序规则的副作用。
2. **防止排序规则被改动后规则失效**。如果将来有人为了别的需求把某个字段改成 `utf8mb4_bin`，唯一性会悄无声息地失效；有了生成列，规则就和排序规则解耦了。

这也对应原 Postgres 的写法 `create unique index on user_cocktails (lower(name))`——Postgres 默认是区分大小写的，必须显式 `lower()`。

---

## 5. 表清单（31 张）

### 模块 A：系统与鉴权（6 张）

> 整体替代 Supabase Auth + Supabase Storage

| # | 表名 | 中文名 | 说明 |
|---|---|---|---|
| 1 | `sys_config` | 系统配置字典 | 订单超时时长等运行期参数，改配置不重启 |
| 2 | `sys_user` | 用户主表 | 替代 `auth.users`，含 `legacy_uid` 保留原 UUID |
| 3 | `sys_auth_code` | 邮箱验证码 | 替代 `signInWithOtp`，只存 SHA-256 哈希 |
| 4 | `sys_refresh_token` | 刷新令牌 | 支撑服务端强制下线 |
| 5 | `sys_login_log` | 登录日志 | 安全审计 + 账号中心「最近登录」 |
| 6 | `sys_file` | 文件元数据 | 替代 `avatars` / `cocktail-images` 两个 Storage 桶 |

### 模块 B：内容社区（9 张）

> 从 Supabase Postgres 全量迁移，共 8 张原表 → 9 张新表（`user_cocktails` 拆成 `cocktail` + `cocktail_ingredient`）

| # | 表名 | 中文名 | 原 Postgres 表 |
|---|---|---|---|
| 7 | `cocktail` | 酒款主表 | `public.user_cocktails` + 前端硬编码的 8 款内置酒谱 |
| 8 | `cocktail_ingredient` | 配方材料子表 | `user_cocktails.ingredients text[]` 拆表而来 |
| 9 | `cocktail_review` | 酒款评论 | `public.reviews` |
| 10 | `cocktail_review_like` | 评论点赞 | `public.review_likes` |
| 11 | `story_post` | 故事帖子 | `public.stories_posts` |
| 12 | `story_reply` | 帖子回复 | `public.stories_replies` |
| 13 | `story_post_like` | 帖子点赞 | `public.stories_post_likes` |
| 14 | `story_post_favorite` | 帖子收藏 | `public.stories_post_favorites` |
| 15 | `story_reply_like` | 回复点赞 | `public.stories_reply_likes` |

### 模块 C：电商购物（15 张）

> 全新模块

| # | 表名 | 中文名 | 说明 |
|---|---|---|---|
| 16 | `shop_user_address` | 收货地址簿 | 生成列 + 唯一索引强制「每人一条默认地址」 |
| 17 | `shop_category` | 商品分类 | |
| 18 | `shop_product` | 商品 SPU | 可通过 `cocktail_id` 关联酒款 |
| 19 | `shop_sku` | 商品 SKU | 价格在这里，库存不在这里 |
| 20 | **`shop_inventory`** | **库存主表** | ★ 三段式模型 + 守恒 CHECK。全系统最热的写入点 |
| 21 | **`shop_inventory_ledger`** | **库存流水台账** | ★ append-only，幂等载体 + 审计证据链 |
| 22 | `shop_cart_item` | 购物车 | 不占库存 |
| 23 | `shop_order` | 订单主表 | 含收货信息快照（有意反范式） |
| 24 | `shop_order_item` | 订单明细 | 含商品名/价格快照（有意反范式） |
| 25 | `shop_payment` | 支付流水 | 对接支付宝 / 微信沙箱 |
| 26 | `shop_payment_notify_log` | 支付回调日志 | ★ 重复通知的第一道幂等闸 |
| 27 | `shop_refund` | 退款单 | `restock` 字段区分「退货退款」和「仅退款」 |
| 28 | `shop_order_status_log` | 订单状态流转日志 | 状态机的可视化数据源 |
| 29 | `shop_product_favorite` | 商品收藏 | |
| 30 | `shop_delay_task` | 延迟任务兜底表 | Redis 挂了之后的最后保险 |

### 模块 D：迁移辅助（1 张）

| # | 表名 | 中文名 | 说明 |
|---|---|---|---|
| 31 | `mig_uid_map` | UUID 映射字典 | Postgres UUID → MySQL BIGINT 的换算表 |

### 视图（3 个）

| 视图 | 用途 |
|---|---|
| `v_user_favorite` | 账号中心「我的收藏」，`UNION ALL` 聚合帖子收藏 + 商品收藏 |
| `v_user_like` | 账号中心「近期点赞」，聚合帖子/回复/评论三种点赞 |
| `v_inventory_health` | 后台「一键对账」，含守恒差额与台账差额 |

> 这三个视图是**全量迁移最直观的收益**：
> 在原来的 Supabase + MySQL 共存方案下，帖子收藏在 Postgres、商品收藏在 MySQL，
> 「我的收藏」只能在 Java 里查两次再内存合并、内存排序、内存分页——
> 一旦数据量上来，分页就会出错（无法跨库做全局 ORDER BY + LIMIT）。
> 统一到一个库之后，一条 SQL 就解决了。

---

## 6. 关键设计决策与理由

### 6.1 主键类型：自增 BIGINT vs UUID

**结论：全部业务表用 `BIGINT UNSIGNED AUTO_INCREMENT`，另设 `legacy_uid CHAR(36)` 保存原 Postgres UUID。**

| 维度 | 自增 BIGINT | UUID (CHAR(36)) |
|---|---|---|
| 存储 | 8 字节 | 36 字节（字符串形式） |
| 插入性能 | 顺序追加，页利用率接近 100%，几乎不页分裂 | 随机分布，频繁页分裂，写放大严重 |
| 二级索引体积 | InnoDB 每个二级索引叶子都存主键，8 字节 | 36 字节，**索引体积是前者的 4.5 倍** |
| Buffer Pool 效率 | 高 | 低（同样内存装不下那么多索引页） |
| 范围查询 | `WHERE id > 1000` 天然按时间有序 | 无序，做不了 |
| 分布式生成 | 需要中心化（本项目单库，不是问题） | 天然分布式 |
| 暴露业务信息 | 会（能推算总量） | 不会 |

**为什么这个选择在本项目里格外重要**：`shop_inventory_ledger` 是高频追加表，
压测时几秒钟能写入几万行。用 UUID 主键的话，每次插入都可能落在已满数据页的中间，
触发页分裂和大量随机 I/O，压测吞吐会直接掉一个数量级。

**「暴露业务信息」怎么解决**：对外接口不暴露自增 ID，而是用 `order_no`（业务单号）
和 `product_code`（商品编码）。这些字段有自己的唯一索引，安全性和可读性都更好。

**迁移期怎么办**：从 Supabase 导出的数据里所有外键都是 UUID。
处理办法是主表带 `legacy_uid` 导入，MySQL 分配新的自增 ID，
然后把 `(legacy_uid, new_id)` 写进 `mig_uid_map`，导从表时 JOIN 这张字典做翻译。
详见第 11 节。

---

### 6.2 时间类型：DATETIME vs TIMESTAMP

**结论：全部用 `DATETIME(3)`（毫秒精度）。**

| 维度 | `DATETIME(3)` | `TIMESTAMP(3)` |
|---|---|---|
| 取值范围 | 1000-01-01 ~ 9999-12-31 | **1970-01-01 ~ 2038-01-19** |
| 存储 | 5 字节 + 2 字节（毫秒）= 7 字节 | 4 字节 + 2 字节 = 6 字节 |
| 时区行为 | 存什么读什么，不做转换 | 写入时按 `time_zone` 转成 UTC，读取时再转回来 |
| 改服务器时区的后果 | 无影响 | **所有历史数据的显示值集体偏移** |

选 `DATETIME` 的三个理由：

1. **2038 问题是真实的**。`TIMESTAMP` 底层是 32 位 Unix 时间戳，2038-01-19 03:14:07 之后会溢出。订单表要保存多年，不能埋这个雷。
2. **时区隐式转换是事故来源**。`TIMESTAMP` 的自动转换看起来贴心，但只要有人改了数据库或连接的 `time_zone`，所有历史时间的显示值就集体漂移，而且**没有任何报错**——这类 bug 极难排查。
3. **只省 1 字节，不值得**。

**时区策略**：数据库统一存 **UTC+8（Asia/Shanghai）** 的本地时间，
Java 端 `spring.jackson.time-zone=GMT+8`，JDBC 连接串加 `serverTimezone=Asia/Shanghai`。
本项目面向国内用户，无跨时区需求。若将来要国际化，
方案是「统一存 UTC + 前端按浏览器时区渲染」，届时只需改 Java 侧配置，DDL 不用动。

**为什么要毫秒精度 `(3)`**：订单超时判断、验证码有效期这些场景，
秒级精度在压测时会出现「同一秒内的多个事件无法排序」的问题，
`shop_inventory_ledger` 的时序校验（CHECK-07）也需要更细的粒度。

---

### 6.3 金额类型：DECIMAL，绝不用浮点

**结论：所有金额字段用 `DECIMAL(10,2)`。**

`FLOAT` / `DOUBLE` 是二进制浮点数，无法精确表示大部分十进制小数。经典演示：

```sql
-- 用 DOUBLE 的灾难
SELECT 0.1 + 0.2 = 0.3;                              -- 返回 0（false）
SELECT CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE);    -- 0.30000000000000004

-- 用 DECIMAL 就是对的
SELECT CAST(0.1 AS DECIMAL(10,2)) + CAST(0.2 AS DECIMAL(10,2)) = 0.3;  -- 返回 1（true）
```

在电商系统里这直接意味着**对不上账**：
一笔订单三条明细各 33.33 元，用 `DOUBLE` 累加可能得到 99.99000000000001，
和订单总额 99.99 比对时判定为不相等，`CHECK-08` 金额对账会莫名其妙地失败。

`DECIMAL(10,2)` 的含义：总共 10 位有效数字，其中小数 2 位，
即最大 `99999999.99`（约 1 亿元），对本项目远远够用。
`DECIMAL` 内部是定点存储（每 9 位十进制数用 4 字节），运算精确无误差。

**评分字段 `rating` 也用了 `DECIMAL(3,1)`**（范围 0.0–10.0），同样的理由：
用 `FLOAT` 的话，`AVG(rating)` 的结果和 CHECK-33 的重算结果可能因为浮点误差判定为不相等。

---

### 6.4 枚举字段：VARCHAR + CHECK，而不是 ENUM

**结论：所有状态、类型字段用 `VARCHAR(n)` + `CHECK (col IN (...))`。**

MySQL 的 `ENUM` 看起来更省空间（1–2 字节），但有几个实际问题：

| 问题 | 说明 |
|---|---|
| 加值要 `ALTER TABLE` | 订单状态加一个 `PRESALE`，就要改表结构。大表 `ALTER` 会锁表（8.0 的 Online DDL 也不是完全无锁） |
| 排序是按定义顺序不是字面值 | `ORDER BY status` 的结果是按 ENUM 定义的先后顺序排，不是按字符串字典序。这个行为极其反直觉，常年制造 bug |
| 数字与字符串混淆 | `WHERE status = 1` 会匹配 ENUM 的**第一个值**而不是字面量 `'1'` |
| 跨 ORM/框架兼容差 | MyBatis-Plus、JPA 映射 ENUM 都需要额外配置 |

用 `VARCHAR + CHECK` 的好处：加值只要改 CHECK（`ALTER TABLE ... DROP CHECK / ADD CHECK`，
不涉及数据重组，很快），排序符合直觉，Java 侧直接用字符串常量或自定义枚举映射。
代价是每行多几个字节，在本项目规模下完全可以接受。

这个选择也和原 Postgres 保持一致——原表用的就是 `text` + `check (category in (...))`。

---

### 6.5 库存为什么单独建表

`shop_sku` 和 `shop_inventory` 是一对一关系，完全可以合并成一张表。**故意不合并**：

| 维度 | `shop_sku` | `shop_inventory` |
|---|---|---|
| 访问模式 | 读多写极少（改价才写） | **写极多**（每次下单都写） |
| 缓存策略 | 可长时间缓存 | 不能长缓存 |
| 索引 | 有多个二级索引 | **零二级索引** |
| 行宽 | 宽（含名称、图片 URL） | 窄（6 个整数列） |

拆开之后的三个收益：

1. **锁隔离**。下单时对库存行加 X 锁，不会阻塞商品详情页读取 SKU 信息。
2. **热点行常驻内存**。库存表每行只有几十字节，一个 16KB 的数据页能放几百行，10 个 SKU 的库存全在同一个页里，几乎永远命中 Buffer Pool。如果和 SKU 合表，行宽好几百字节，一页装不了几行，缓存效率大幅下降。
3. **写入无索引维护开销**。库存表主键就是 `sku_id`，没有任何二级索引，`UPDATE` 时不需要维护额外的索引结构。

这是一次**为性能刻意做的表拆分**，不是范式要求。在报告里应该明确说明这是权衡而非规范。

---

## 7. 范式分析

### 7.1 整体结论

**本设计的绝大部分表满足 BCNF（BC 范式）**，即：

- **1NF**：所有字段都是原子值。★ 特别地，Postgres 的 `ingredients text[]` 数组违反 1NF，本次迁移把它拆成了 `cocktail_ingredient` 子表来修复。
- **2NF**：不存在非主属性对候选键的部分依赖。所有非主键字段都完全依赖于整个主键。
- **3NF**：不存在非主属性对候选键的传递依赖。
- **BCNF**：所有函数依赖的决定因素都是候选键。

**四张表刻意停留在较低范式（反范式）**，理由见 7.3。

### 7.2 逐表范式核查（举例）

**`cocktail_ingredient`（1NF 修复的成果）**

- 候选键：`{id}`，另有 `{cocktail_id, sort_no}` 也是候选键（有唯一索引）
- 函数依赖：`id → cocktail_id, sort_no, content`；`{cocktail_id, sort_no} → content`
- 所有决定因素都是候选键 → **BCNF** ✅

**`story_post_like`（复合主键的典型）**

- 候选键：`{post_id, user_id}`
- 唯一的非主属性 `created_at` 完全依赖于整个复合键，不存在部分依赖 → **BCNF** ✅

**`cocktail_review`（迁移中修复的表）**

原 Postgres 表结构：

```
reviews(id, cocktail_name, cocktail_zh_name, user_id, user_email, user_name, user_avatar, rating, content, created_at)
```

存在两个问题：

1. `cocktail_name → cocktail_zh_name`：中文名传递依赖于英文名（英文名不是候选键）→ **违反 3NF**
2. `user_id → user_email, user_name, user_avatar`：用户信息传递依赖于用户 ID → **违反 3NF**，直接后果是用户改昵称后历史评论仍显示旧昵称（**更新异常**）

迁移后：

```
cocktail_review(id, cocktail_id, user_id, rating, content, like_count, status, created_at)
```

酒款信息通过 `cocktail_id` 外键 JOIN 获取，用户信息通过 `user_id` 外键 JOIN 获取，
两个传递依赖都被消除 → **3NF/BCNF** ✅

> **为什么原来非要冗余？** 不是原设计者水平不够，是 Supabase 架构的硬约束：
> PostgREST 受 RLS 限制无法安全地 JOIN `auth.users` 表，
> 只能在写入时把用户昵称头像冗余进业务表。
> 这是一个「架构限制倒逼数据库设计退化」的真实案例，很值得写进报告。

### 7.3 刻意的反范式：四处，各有不同理由

#### 反范式 1：订单明细的商品快照 —— **必须冗余**

`shop_order_item` 冗余了 `product_name`、`product_zh_name`、`sku_spec_name`、`sku_image`、`unit_price`。

**为什么必须**：这些不是「商品的属性」，而是「这笔交易发生时的事实」。
如果只存 `sku_id` 靠 JOIN 取，那么商品改名、调价、下架之后，
用户打开三年前的订单会看到当前的商品名和当前的价格——这是严重的业务错误，
在真实电商里会引发客诉甚至法律纠纷。

**为什么安全**（这是判断反范式风险的关键）：
经典的反范式风险是「更新异常」——同一份数据存两处，改了一处忘了另一处就不一致。
但这里的快照字段**写入后永不修改**，所以根本不存在「改了一处」的场景。
`04_procedures_triggers.sql` 里的 `trg_order_item_snapshot_immutable` 触发器
把这条规则变成了数据库强制约束，任何 UPDATE 尝试都会被拒绝。

**严格地说这属于什么**：这些字段依赖的不是 `sku_id`，而是 `(sku_id, 成交时刻)`。
由于成交时刻由 `order_id` 唯一确定，所以它们其实完全依赖于本表主键——
**从这个角度看它甚至没有违反 3NF**，只是"看起来像"冗余。这个论证在答辩时很加分。

#### 反范式 2：订单的收货信息快照 —— **必须冗余**

`shop_order` 冗余了 `receiver_name` / `receiver_phone` / `receiver_address`，理由同上。
用户删掉地址簿里的地址，历史订单的收货信息不能跟着消失。

#### 反范式 3：各种计数字段 —— **性能优化，需要定期校验**

`story_post.like_count / favorite_count / reply_count`、
`cocktail.review_count / avg_rating`、`cocktail_review.like_count`、
`shop_product.sale_count / min_price`。

**为什么冗余**：论坛列表页一次要展示 20 个帖子，
如果每个帖子的点赞数都实时 `COUNT(*)`，就是 20 次聚合查询。
列表页是最高频的接口，这个开销无法接受。

**风险与对策**：这类冗余**确实有失真风险**——如果某条代码路径改了点赞表却没改计数，
数字就错了。三道防线：

1. `04_procedures_triggers.sql` 的触发器在数据库层维护，无论从哪条路径写入都不会漏
2. `05_verification.sql` 的 CHECK-31/32/33/34 定期校验并可一键修复
3. 计数失真的业务影响可接受（点赞数少 1 不影响交易），这也是它和"库存"的本质区别

**判据总结**：
一个冗余字段是否安全，看它**会不会因为无关操作而失真**。
`like_count` 只会被点赞/取消点赞改变（路径封闭）→ 可控；
`user_name` 会被"用户改昵称"这个完全无关的操作弄脏（路径开放）→ 危险，必须去掉。
这两个例子放在一起对比，就把「反范式什么时候可以做」讲清楚了。

#### 反范式 4：`shop_order_item` 冗余 `order_no` 和 `user_id` —— **查询便利**

`order_no` 可以从 `order_id` JOIN 得到，`user_id` 也是。
冗余它们是为了让「按订单号直查明细」和「统计某用户买过什么」免去一次 JOIN。
这两个字段同样写入后不变，所以安全。

### 7.4 一处刻意的表拆分（不是范式要求）

`shop_sku` / `shop_inventory` 一对一拆表，理由见 6.5。
这是**为性能做的物理设计**，与范式无关，在报告里要区分清楚：
范式讨论的是逻辑设计（消除冗余与异常），拆表这里讨论的是物理设计（锁粒度与缓存效率）。

---

## 8. 索引清单与设计理由

### 8.1 索引设计的四条原则

1. **每个索引都要能指名道姓地说出它支撑哪条查询**。说不出来的索引就是纯粹的写入负担。
2. **联合索引遵循「等值列在前、范围/排序列在后」**（最左前缀原则）。
3. **能用覆盖索引就用**，避免回表。判断标准：`EXPLAIN` 的 `Extra` 出现 `Using index`。
4. **不为低区分度的单列建索引**。例如单独给 `status`（只有 0/1 两个值）建索引，
   优化器多半会放弃使用它（因为回表成本高于全表扫描），白白增加写入开销。

### 8.2 全部索引清单

#### 模块 A：系统与鉴权

| 表 | 索引 | 类型 | 支撑的查询 |
|---|---|---|---|
| `sys_user` | `PRIMARY(id)` | 聚簇 | 主键查找 |
| | `uk_user_email(email)` | 唯一 | 登录 `WHERE email=?`；同时保证账号唯一 |
| | `uk_user_legacy_uid(legacy_uid)` | 唯一 | 迁移时防止同一 Supabase 用户被重复导入 |
| | `idx_user_role_status(role,status)` | 联合 | 后台管理员列表 |
| `sys_auth_code` | `idx_authcode_email_purpose(email,purpose,created_at DESC)` | 联合 | ★ 取最新验证码 + 60 秒重发冷却判定。三列全命中，`ORDER BY created_at DESC LIMIT 1` 直接读索引首行，无 filesort |
| | `idx_authcode_expires(expires_at)` | 普通 | 定时清理过期验证码 |
| `sys_refresh_token` | `uk_token_hash(token_hash)` | 唯一 | 刷新时按哈希定位 |
| | `idx_token_user_expires(user_id,expires_at)` | 联合 | 「我的登录设备」列表 + 批量吊销 |
| `sys_login_log` | `idx_loginlog_user_time(user_id,created_at DESC)` | 联合 | 账号中心「最近登录」 |
| | `idx_loginlog_email_time(email,created_at DESC)` | 联合 | 风控：某邮箱近期失败次数 |
| `sys_file` | `uk_file_object_key(object_key)` | 唯一 | 防止覆盖他人文件 |
| | `idx_file_sha_biz(sha256,biz_type)` | 联合 | 秒传去重 |
| | `idx_file_status_created(status,created_at)` | 联合 | 清理孤儿文件 |
| | `idx_file_uploader(uploader_id,biz_type)` | 联合 | 注销账号时清理该用户全部文件 |

#### 模块 B：内容社区

| 表 | 索引 | 类型 | 支撑的查询 |
|---|---|---|---|
| `cocktail` | `uk_cocktail_name_lower(name_lower)` | 唯一 | 酒名大小写不敏感唯一（对应原 Postgres 的 `lower(name)` 索引） |
| | `idx_cocktail_cat_base_time(category,base,created_at DESC)` | 联合 | ★ 酒单页「分类+基酒筛选，时间倒序」。两个等值 + 一个排序，最左前缀全命中，`Extra` 里没有 `Using filesort` |
| | `idx_cocktail_user_time(user_id,created_at DESC)` | 联合 | 账号中心「我的投稿」 |
| | `idx_cocktail_status_rating(status,avg_rating DESC)` | 联合 | 首页高分推荐 |
| | `ft_cocktail_search(name,zh_name,profile)` | 全文(ngram) | 酒单搜索框 |
| `cocktail_ingredient` | `uk_ingredient_cocktail_sort(cocktail_id,sort_no)` | 唯一 | 顺序稳定 + 防重复插入；同时支撑「取某酒款全部材料」 |
| | `idx_ingredient_content(content(32))` | 前缀 | 「找出所有用金酒的酒款」。只索引前 32 字符控制体积 |
| `cocktail_review` | `idx_review_cocktail_status_id(cocktail_id,status,id DESC)` | 联合 | ★ 酒款详情页评论列表。两等值 + 主键排序，无 filesort |
| | `idx_review_user_time(user_id,created_at DESC)` | 联合 | 账号中心「我的评论」 |
| `cocktail_review_like` | `PRIMARY(review_id,user_id)` | 复合主键 | ★ 既是并发去重的物理保证，也让「我是否点过赞」成为覆盖索引查询 |
| | `idx_reviewlike_user_time(user_id,created_at DESC)` | 联合 | 账号中心「我点赞过的评论」（反向查询） |
| `story_post` | `idx_post_status_cat_id(status,category,id DESC)` | 联合 | 论坛首页分类筛选 |
| | `idx_post_user_time(user_id,created_at DESC)` | 联合 | 「我的帖子」 |
| | `idx_post_status_like(status,like_count DESC)` | 联合 | 热门排行 |
| | `ft_post_title_body(title,body)` | 全文(ngram) | 论坛搜索 |
| `story_reply` | `idx_reply_post_status_id(post_id,status,id)` | 联合 | 帖子详情页拉全部回复 |
| | `idx_reply_parent(parent_reply_id)` | 普通 | 父子关系查询 |
| | `idx_reply_root(root_reply_id)` | 普通 | 一次取出整个楼中楼 |
| | `idx_reply_user_time(user_id,created_at DESC)` | 联合 | 「我的回复」 |
| `story_post_like`<br>`story_post_favorite`<br>`story_reply_like` | `PRIMARY(x_id,user_id)` | 复合主键 | ★ 并发去重 |
| | `idx_*_user_time(user_id,created_at DESC)` | 联合 | 账号中心反向聚合 |

#### 模块 C：电商

| 表 | 索引 | 类型 | 支撑的查询 |
|---|---|---|---|
| `shop_user_address` | `uk_addr_default(default_flag)` | 唯一+生成列 | ★ 数据库层强制「每人至多一条默认地址」 |
| | `idx_addr_user_deleted(user_id,deleted)` | 联合 | 地址簿列表 |
| `shop_product` | `idx_product_cat_status_sale(category_id,status,sale_count DESC)` | 联合 | 分类页按销量排序 |
| | `idx_product_status_price(status,min_price)` | 联合 | 全站按价格排序 |
| | `idx_product_cocktail(cocktail_id)` | 普通 | 酒款详情页反查关联商品 |
| | `ft_product_search(name,zh_name,subtitle)` | 全文(ngram) | 商城搜索 |
| `shop_sku` | `uk_sku_code(sku_code)` | 唯一 | |
| | `idx_sku_product_status(product_id,status)` | 联合 | 商品详情页拉在售 SKU |
| **`shop_inventory`** | `PRIMARY(sku_id)` | 聚簇 | ★★ **本表故意零二级索引**。扣减语句 `WHERE sku_id=?` 直接命中聚簇索引叶子页，只加一把行锁、无回表、无额外索引维护。这是热点写入的最优形态 |
| **`shop_inventory_ledger`** | `uk_ledger_biz(biz_type,biz_no,sku_id)` | 唯一 | ★★ **幂等的物理保证**。同一业务单对同一 SKU 的同类操作只能记录一次 |
| | `idx_ledger_sku_time(sku_id,created_at DESC)` | 联合 | 某 SKU 的变动历史 |
| | `idx_ledger_biz_no(biz_no)` | 普通 | 按订单号追溯 |
| `shop_cart_item` | `uk_cart_user_sku(user_id,sku_id)` | 唯一 | ★ 支撑 `INSERT ... ON DUPLICATE KEY UPDATE` 的原子加购，消除 TOCTOU |
| | `idx_cart_user_updated(user_id,updated_at DESC)` | 联合 | 购物车列表 |
| `shop_order` | `uk_order_no(order_no)` | 唯一 | 按单号查 |
| | `uk_order_user_idem(user_id,idempotency_key)` | 唯一 | ★★ **防重复下单的数据库级兜底** |
| | `idx_order_user_status_id(user_id,status,id DESC)` | 联合 | ★ 「我的订单」列表，三段全命中无 filesort |
| | `idx_order_status_expire(status,expire_at)` | 联合 | ★ 超时关单扫描。待支付订单占比小，选择性高 |
| | `idx_order_created(created_at)` | 普通 | 后台按时间检索、统计 GMV |
| `shop_order_item` | `idx_item_order(order_id)` | 普通 | 订单详情拉明细 |
| | `idx_item_order_no(order_no)` | 普通 | 按单号直查 |
| | `idx_item_sku(sku_id)` | 普通 | 销量统计、库存对账 |
| | `idx_item_user_created(user_id,created_at DESC)` | 联合 | 「我买过的商品」 |
| `shop_payment` | `uk_payment_no(payment_no)` | 唯一 | |
| | `uk_payment_channel_trade_no(channel_trade_no)` | 唯一 | ★ 同一渠道流水只能入账一次（NULL 不参与唯一性，所以多条待支付记录可共存） |
| | `idx_payment_status_created(status,created_at)` | 联合 | 对账任务扫描长期 PENDING 的支付单 |
| `shop_payment_notify_log` | `uk_notify(channel,notify_id)` | 唯一 | ★★ **回调重复通知的第一道闸** |
| | `idx_notify_verified_time(sign_verified,created_at DESC)` | 联合 | 安全审计：查验签失败的回调 |
| `shop_refund` | `uk_refund_user_idem(user_id,idempotency_key)` | 唯一 | ★ 防重复申请 |
| | `uk_refund_channel_no(channel_refund_no)` | 唯一 | ★ 防重复入账 |
| | `idx_refund_status_apply(status,apply_at)` | 联合 | 后台待审核列表 |
| `shop_delay_task` | `uk_task_type_biz(task_type,biz_no)` | 唯一 | 同一业务单同类任务只登记一次 |
| | `idx_task_status_execute(status,execute_at)` | 联合 | 任务扫描 |

### 8.3 刻意**不**建索引的地方，以及理由

| 位置 | 为什么不建 |
|---|---|
| `shop_inventory` 的任何二级索引 | 这是全系统最热的写入点。每多一个二级索引，每次 UPDATE 就多一次索引维护。主键查询已经够用 |
| 单独的 `shop_order(status)` | 状态只有 9 个取值，区分度极低。已支付订单可能占 80%，优化器会因为回表成本过高而放弃使用它。已被 `idx_order_status_expire` 覆盖 |
| 单独的 `cocktail(category)` | 只有 3 个取值。已被 `idx_cocktail_cat_base_time` 的最左前缀覆盖 |
| `story_post(body)` 的 B+ 树索引 | 长文本用 B+ 树索引没有意义（`LIKE '%kw%'` 用不上前缀索引）。用全文索引 `ft_post_title_body` 解决 |
| 各种 `remark` / `detail` 字段 | 从不作为查询条件 |
| `sys_login_log(ip)` | 只在极少的安全排查场景用到，可接受全表扫描 |

`02_indexes.sql` 的第 2.3 节提供了「冗余索引自检」查询，
可以自动发现「索引 A 是索引 B 的最左前缀」这类冗余，用于回归验证。

---

## 9. CHECK 约束清单

> **前提**：MySQL **8.0.16 之前**只解析不执行 CHECK。版本不够的话下面这些全是摆设。

### 9.1 ★ 库存守恒（最核心的三条）

| 约束 | 表达式 | 意义 |
|---|---|---|
| `ck_inv_conservation` | `available + locked + sold = total` | ★★★ 库存三段式不变式。任何代码 bug 只要破坏守恒，事务立刻回滚 |
| `ck_inv_available_nonneg` 等 4 条 | `available >= 0` / `locked >= 0` / `sold >= 0` / `total >= 0` | ★★★ **物理上不可能超卖**。即使 CAS 条件被误删，负库存也会在这里被拦下 |
| `ck_ledger_conservation` | `delta_available + delta_locked + delta_sold = delta_total` | 每条流水自身守恒 |
| `ck_ledger_after_conservation` | `after_available + after_locked + after_sold = after_total` | 每条流水的快照守恒 |

### 9.2 金额与数量

| 约束 | 表达式 |
|---|---|
| `ck_order_amount_formula` | `pay_amount = total_amount + freight_amount - discount_amount` |
| `ck_order_refunded` | `0 <= refunded_amount <= pay_amount`（防超退） |
| `ck_item_amount_formula` | `total_amount = unit_price * quantity` |
| `ck_item_refund_qty` | `0 <= refunded_quantity <= quantity`（防超退） |
| `ck_sku_price` | `price > 0` |
| `ck_cart_quantity` | `1 <= quantity <= 99` |
| `ck_payment_amount` | `amount > 0` |

### 9.3 枚举取值

`ck_order_status`（9 个状态）、`ck_refund_status`（6 个）、`ck_payment_status`（4 个）、
`ck_payment_channel`、`ck_ledger_biz_type`（9 种）、`ck_cocktail_category`、`ck_cocktail_base`、
`ck_post_category`、`ck_user_role`、`ck_file_biz`、`ck_file_storage` 等。

### 9.4 长度与格式（逐条对应原 Postgres 的 `char_length` 检查）

| 约束 | 表达式 | 原 Postgres 对应 |
|---|---|---|
| `ck_cocktail_name` | `CHAR_LENGTH(name) BETWEEN 2 AND 60` | `char_length(name) between 2 and 60` |
| `ck_cocktail_zh_name` | `BETWEEN 1 AND 40` | ✓ |
| `ck_cocktail_naming` | `BETWEEN 10 AND 300` | ✓ |
| `ck_cocktail_story` | `BETWEEN 20 AND 800` | ✓ |
| `ck_cocktail_profile` | `BETWEEN 5 AND 200` | ✓ |
| `ck_cocktail_method` | `BETWEEN 2 AND 80` | ✓ |
| `ck_ingredient_content` | `BETWEEN 2 AND 120` | 原为数组元素的 check |
| `ck_review_rating` | `rating >= 0 AND rating <= 10` | `check (rating >= 0 and rating <= 10)` |
| `ck_review_content` | `BETWEEN 1 AND 500` | ✓ |
| `ck_post_title` | `BETWEEN 1 AND 60` | ✓ |
| `ck_post_body` | `BETWEEN 1 AND 500` | ✓ |
| `ck_reply_body` | `BETWEEN 1 AND 280` | ✓ |
| `ck_user_email` | `BETWEEN 5 AND 254 AND email LIKE '%@%.%'` | 新增 |

### 9.5 业务规则

| 约束 | 表达式 | 意义 |
|---|---|---|
| `ck_cocktail_owner` | `(source=1 AND user_id IS NULL) OR (source=2 AND user_id IS NOT NULL)` | 内置酒款无作者，用户投稿必有作者 |
| `ck_reply_no_self` | `parent_reply_id IS NULL OR parent_reply_id <> id` | 防止回复指向自己形成环 |
| `ck_file_size` | `0 < size_bytes <= 5242880` | 对应原 `cocktail-images` 桶的 5MB 上限 |

### 9.6 CHECK 表达不了的约束，以及替代方案

| 业务规则 | 为什么 CHECK 做不到 | 替代方案 |
|---|---|---|
| 每款酒的配方材料 2–12 条 | CHECK 只能作用于单行，无法跨行聚合 | 应用层校验 + `sp_check_ingredient_count()` 巡检 + `CHECK-27` |
| 配方材料序号从 1 连续编号 | 同上 | `CHECK-28` |
| 库存台账不可修改 | CHECK 不能阻止 UPDATE/DELETE | `trg_ledger_no_update` / `trg_ledger_no_delete` 触发器 |
| 订单明细快照不可修改 | 同上 | `trg_order_item_snapshot_immutable` 触发器 |
| 每人至多一条默认地址 | CHECK 无法跨行 | 生成列 `default_flag` + 唯一索引（很优雅，无需触发器） |
| 订单状态机的合法转移 | CHECK 无法访问 OLD 值 | Java Service 层 CAS：`UPDATE ... WHERE status = '预期原状态'` |

> 「哪些约束数据库能保证、哪些必须靠应用层」是《数据库原理》的核心考点之一。
> 这张表把边界说清楚了，答辩时可以直接用。

---

## 10. 数据字典

> 完整 31 张表的逐字段说明已经以 `COMMENT` 形式写在 `01_schema.sql` 里。
> 需要导出成表格时执行下面这条查询即可（结果可直接粘进 Word 报告）：
>
> ```sql
> SELECT TABLE_NAME AS '表名', ORDINAL_POSITION AS '序号', COLUMN_NAME AS '字段名',
>        COLUMN_TYPE AS '类型', IS_NULLABLE AS '可空', COLUMN_DEFAULT AS '默认值',
>        COLUMN_KEY AS '键', EXTRA AS '扩展', COLUMN_COMMENT AS '说明'
>   FROM information_schema.COLUMNS
>  WHERE TABLE_SCHEMA = 'luceria'
>  ORDER BY TABLE_NAME, ORDINAL_POSITION;
> ```

下面列出**五张核心表**的完整字段说明。

### 10.1 `sys_user` —— 用户主表

| 字段 | 类型 | 空 | 默认 | 键 | 说明 |
|---|---|---|---|---|---|
| `id` | BIGINT UNSIGNED | 否 | 自增 | PK | 用户 ID |
| `legacy_uid` | CHAR(36) | 是 | NULL | UK | 原 Supabase `auth.users.id`，迁移追溯用 |
| `email` | VARCHAR(254) | 否 | | UK | 登录账号，触发器强制小写 |
| `email_verified` | TINYINT | 否 | 0 | | 0 未验证 / 1 已验证 |
| `password_hash` | VARCHAR(100) | 是 | NULL | | 预留，本期 OTP 登录不用；启用须 BCrypt |
| `display_name` | VARCHAR(24) | 否 | 'Guest Bartender' | | 昵称，1–24 字符 |
| `avatar_url` | VARCHAR(500) | 否 | '' | | 头像 URL |
| `avatar_file_id` | BIGINT UNSIGNED | 是 | NULL | | 逻辑外键 → `sys_file.id` |
| `role` | VARCHAR(16) | 否 | 'user' | IDX | `user` / `admin` |
| `status` | TINYINT | 否 | 1 | IDX | 0 封禁 / 1 正常 / 2 注销 |
| `profile_updated_at` | DATETIME(3) | 是 | NULL | | 资料最后修改时间，7 天冷却判定用 |
| `last_login_at` | DATETIME(3) | 是 | NULL | | |
| `last_login_ip` | VARCHAR(45) | 否 | '' | | 45 字符可容纳 IPv6 |
| `created_at` | DATETIME(3) | 否 | CURRENT_TIMESTAMP(3) | | 注册时间 |
| `updated_at` | DATETIME(3) | 否 | 自动更新 | | |

### 10.2 `cocktail` —— 酒款主表

| 字段 | 类型 | 空 | 默认 | 键 | 说明 |
|---|---|---|---|---|---|
| `id` | BIGINT UNSIGNED | 否 | 自增 | PK | |
| `legacy_uid` | CHAR(36) | 是 | NULL | UK | 原 `user_cocktails.id` |
| `source` | TINYINT | 否 | 2 | | 1 内置酒谱 / 2 用户投稿 |
| `name` | VARCHAR(60) | 否 | | | 英文名，2–60 字符 |
| `name_lower` | VARCHAR(60) | — | 生成列 | UK | `LOWER(name)`，大小写不敏感唯一 |
| `zh_name` | VARCHAR(40) | 否 | | | 中文名，1–40 |
| `category` | VARCHAR(20) | 否 | | IDX | `classic` / `signature` / `nonalcoholic` |
| `base` | VARCHAR(20) | 否 | | IDX | `whiskey`/`tequila`/`gin`/`rum`/`vodka`/`none` |
| `image_url` | VARCHAR(500) | 否 | '' | | |
| `image_file_id` | BIGINT UNSIGNED | 是 | NULL | | → `sys_file.id` |
| `naming` | VARCHAR(300) | 否 | | | 命名由来，10–300 |
| `story` | VARCHAR(800) | 否 | | | 背景故事，20–800 |
| `profile` | VARCHAR(200) | 否 | | | 风味描述，5–200 |
| `method` | VARCHAR(80) | 否 | | | 调制手法，2–80 |
| `user_id` | BIGINT UNSIGNED | 是 | NULL | FK,IDX | 投稿人，内置为 NULL |
| `review_count` | INT UNSIGNED | 否 | 0 | | 冗余：评论数 |
| `avg_rating` | DECIMAL(3,1) | 否 | 0.0 | IDX | 冗余：平均分 0.0–10.0 |
| `status` | TINYINT | 否 | 1 | IDX | 0 已删除 / 1 正常 |
| `created_at` / `updated_at` | DATETIME(3) | 否 | | IDX | |

### 10.3 ★ `shop_inventory` —— 库存主表

| 字段 | 类型 | 空 | 默认 | 键 | 说明 |
|---|---|---|---|---|---|
| `sku_id` | BIGINT UNSIGNED | 否 | | PK,FK | 与 `shop_sku` 一对一，直接做主键 |
| `total_stock` | INT | 否 | 0 | | 总库存 = 仓库实物总数 |
| `available_stock` | INT | 否 | 0 | | ★ 可售：可被新订单占用 |
| `locked_stock` | INT | 否 | 0 | | ★ 已锁定：已下单未支付 |
| `sold_stock` | INT | 否 | 0 | | ★ 已售出：已支付 |
| `safety_stock` | INT | 否 | 5 | | 低库存预警阈值 |
| `version` | BIGINT UNSIGNED | 否 | 0 | | 变更次数，审计用 |
| `updated_at` | DATETIME(3) | 否 | 自动更新 | | |

**约束**：`available + locked + sold = total`，且四者均 `>= 0`。
**索引**：只有主键，故意不建任何二级索引。

### 10.4 ★ `shop_inventory_ledger` —— 库存流水台账

| 字段 | 类型 | 空 | 键 | 说明 |
|---|---|---|---|---|
| `id` | BIGINT UNSIGNED | 否 | PK | |
| `sku_id` | BIGINT UNSIGNED | 否 | FK,IDX | |
| `biz_type` | VARCHAR(24) | 否 | UK | 9 种：`INIT`/`RESTOCK`/`ADJUST`/`ORDER_LOCK`/`ORDER_CANCEL`/`ORDER_EXPIRE`/`PAY_CONFIRM`/`REFUND_RETURN`/`REFUND_WRITEOFF` |
| `biz_no` | VARCHAR(64) | 否 | UK,IDX | 订单号 / 退款单号 |
| `delta_available` / `delta_locked` / `delta_sold` / `delta_total` | INT | 否 | | 四段变化量，可正可负 |
| `after_available` / `after_locked` / `after_sold` / `after_total` | INT | 否 | | 变更后的四段快照 |
| `operator_type` | VARCHAR(16) | 否 | | `USER`/`ADMIN`/`SYSTEM` |
| `operator_id` | BIGINT UNSIGNED | 是 | | |
| `remark` | VARCHAR(200) | 否 | | |
| `created_at` | DATETIME(3) | 否 | IDX | |

**唯一约束**：`(biz_type, biz_no, sku_id)` ← 幂等的物理保证
**触发器**：禁止 UPDATE 和 DELETE（append-only）

### 10.5 `shop_order` —— 订单主表

| 字段 | 类型 | 空 | 默认 | 键 | 说明 |
|---|---|---|---|---|---|
| `id` | BIGINT UNSIGNED | 否 | 自增 | PK | |
| `order_no` | VARCHAR(32) | 否 | | UK | `yyyyMMddHHmmss` + 机器码 2 位 + 序列 4 位 |
| `user_id` | BIGINT UNSIGNED | 否 | | FK,IDX | |
| `status` | VARCHAR(20) | 否 | 'PENDING_PAYMENT' | IDX | 9 种状态，见第 9.3 节 |
| `total_amount` | DECIMAL(10,2) | 否 | | | 商品总额 |
| `freight_amount` | DECIMAL(10,2) | 否 | 0.00 | | 运费 |
| `discount_amount` | DECIMAL(10,2) | 否 | 0.00 | | 优惠 |
| `pay_amount` | DECIMAL(10,2) | 否 | | | 应付 = 总额 + 运费 − 优惠（CHECK 强制） |
| `refunded_amount` | DECIMAL(10,2) | 否 | 0.00 | | 累计已退，`<= pay_amount` |
| `item_count` | INT | 否 | 0 | | 商品总件数 |
| `receiver_name` / `receiver_phone` / `receiver_address` | VARCHAR | 否 | | | ★ 下单时快照（有意反范式） |
| `remark` | VARCHAR(200) | 否 | '' | | 买家留言 |
| `tracking_no` | VARCHAR(64) | 否 | '' | | 物流单号 |
| `idempotency_key` | VARCHAR(64) | 否 | | UK | ★ 防重复下单 |
| `expire_at` | DATETIME(3) | 否 | | IDX | 超时关单时间 |
| `pay_time` / `ship_time` / `finish_time` / `close_time` | DATETIME(3) | 是 | NULL | | |
| `close_reason` | VARCHAR(64) | 否 | '' | | |
| `version` | BIGINT UNSIGNED | 否 | 0 | | |
| `created_at` / `updated_at` | DATETIME(3) | 否 | | IDX | |

---

## 11. Postgres → MySQL 类型映射

从 Supabase 导出数据并导入 MySQL 时的完整对照表。

| Postgres 类型 | 出现位置 | MySQL 8.0 对应 | 转换要点 |
|---|---|---|---|
| `uuid` | 全部主键、`user_id` 外键 | `BIGINT UNSIGNED AUTO_INCREMENT` + `legacy_uid CHAR(36)` | ★ 主键换成自增（理由见 6.1）；原 UUID 存进 `legacy_uid`；外键通过 `mig_uid_map` 翻译。**这是整个迁移最麻烦的一步** |
| `text` | 大部分文本字段 | `VARCHAR(n)` 或 `TEXT` | ★ Postgres 的 `text` 无长度上限，MySQL 必须定长。长度取自原表的 `char_length` CHECK；无 CHECK 的字段按实测最大值的 2 倍取整 |
| **`text[]`** | `user_cocktails.ingredients` | **拆成 `cocktail_ingredient` 子表** | ★★ 见下方专门说明 |
| `timestamptz` | 所有 `created_at` / `updated_at` | `DATETIME(3)` | ★ 导出时先转时区：`SELECT created_at AT TIME ZONE 'Asia/Shanghai' FROM ...`。否则会差 8 小时 |
| `jsonb` | 本项目未使用 | `JSON` | MySQL 的 `JSON` 也是二进制存储，功能大体对应，但**不支持 GIN 索引**，需要用生成列 + 普通索引替代 |
| `boolean` | RLS 策略里 | `TINYINT(1)` | `true`→1，`false`→0 |
| `numeric(3,1)` | `reviews.rating` | `DECIMAL(3,1)` | 直接对应 |
| `integer` | 各计数字段 | `INT` / `INT UNSIGNED` | |
| `gen_random_uuid()` | 主键默认值 | `AUTO_INCREMENT` | 不再需要 |
| `now()` | 时间默认值 | `CURRENT_TIMESTAMP(3)` | |
| `cardinality(arr) BETWEEN 2 AND 12` | ingredients 的 CHECK | 无对应 | MySQL CHECK 不能跨行，改由应用层 + `CHECK-27` 保证 |
| `create unique index on t (lower(name))` | 酒名唯一 | 生成列 + 唯一索引 | 见第 4 节末尾 |
| `on delete cascade` | 各外键 | `ON DELETE CASCADE` | 直接对应 |
| RLS 策略 | 8 张表的行级权限 | **无对应** | ★★★ MySQL 没有 RLS，全部要改写成 Java Service 层的鉴权代码。详见 `REQUIREMENTS.md` 第 3 章 |

### ★★ `text[]` 的处理：为什么拆子表而不用 JSON

原字段：

```sql
ingredients text[] NOT NULL CHECK (cardinality(ingredients) BETWEEN 2 AND 12)
```

MySQL 没有数组类型，两条路：

| 方案 | 写法 | 评价 |
|---|---|---|
| JSON 列 | `ingredients JSON` | ❌ 不推荐 |
| **拆子表** | `cocktail_ingredient(cocktail_id, sort_no, content)` | ✅ **本项目采用** |

**选拆子表的五个理由**：

1. **1NF 的直接要求**。第一范式要求每个字段是不可再分的原子值。
   数组和 JSON 本质上都是把一个「重复组」塞进一列，直接违反 1NF。
   这是范式理论里最基础的一条，也是最容易在报告里讲清楚的一条。

2. **能用 SQL 查询**。业务上真实存在「找出所有用到金酒的酒款」这个需求：

   ```sql
   -- 拆子表：可读，可走前缀索引
   SELECT DISTINCT c.* FROM cocktail c
     JOIN cocktail_ingredient i ON i.cocktail_id = c.id
    WHERE i.content LIKE '金酒%';

   -- JSON 方案：写法晦涩，且几乎无法索引
   SELECT * FROM cocktail
    WHERE JSON_SEARCH(ingredients, 'one', '%金酒%') IS NOT NULL;
   ```

3. **能对单条材料加约束**。`CHECK (CHAR_LENGTH(content) BETWEEN 2 AND 120)`
   作用在每一行材料上。JSON 方案只能校验整个数组，管不到数组内的每个元素。

4. **引用完整性**。子表有外键 + `ON DELETE CASCADE`，删酒款自动清材料。
   JSON 列做不到任何引用完整性。

5. **可扩展**。将来要拆出 `amount` / `unit` 字段做「按分量计算成本」，
   子表加两列即可；JSON 方案要写脚本改所有历史数据，是场灾难。

**诚实说明代价**：查酒款详情要多一次查询（或一次 JOIN）。
但酒款详情页 QPS 很低且可整页缓存，这个代价可以忽略。

**什么时候 JSON 是合理的**：`shop_product.images`（商品轮播图 URL 数组）就用了 JSON。
区别在于——图片列表**只整体读写，从不做条件查询、从不做约束、从不单独更新某一张**。
这种「纯展示用的附属数据」用 JSON 是合适的。
判据是：**这个集合里的元素会不会成为查询条件或约束对象？** 会 → 拆表；不会 → JSON 可以。

### 迁移执行步骤

```bash
# 1) 从 Supabase 导出（在 Supabase SQL Editor 里执行，或用 pg_dump）
COPY (
  SELECT id, email, raw_user_meta_data->>'display_name' AS display_name,
         created_at AT TIME ZONE 'Asia/Shanghai' AS created_at
  FROM auth.users
) TO STDOUT WITH CSV HEADER;

# 2) 导入 MySQL（临时关闭外键检查，因为导入顺序无法完全满足依赖）
SET FOREIGN_KEY_CHECKS = 0;
LOAD DATA LOCAL INFILE 'users.csv' INTO TABLE sys_user
  FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
  IGNORE 1 LINES (legacy_uid, email, display_name, created_at);
SET FOREIGN_KEY_CHECKS = 1;

# 3) 生成 UUID → BIGINT 映射
INSERT INTO mig_uid_map (entity_type, legacy_uid, new_id)
SELECT 'USER', legacy_uid, id FROM sys_user WHERE legacy_uid IS NOT NULL;

# 4) 导入从表时翻译外键
UPDATE cocktail_review r
  JOIN mig_uid_map m ON m.entity_type='USER' AND m.legacy_uid = r.legacy_user_uid
   SET r.user_id = m.new_id;

# 5) 全量验收 —— 必须全部 PASS
mysql -u root -p luceria < 05_verification.sql
```

> ⚠️ **步骤 2 关闭了外键检查**，所以导入过程中可能产生孤儿数据。
> 这正是 `05_verification.sql` 第三组「孤儿数据检查」存在的意义 ——
> 迁移完成后必须跑一遍，CHECK-19 到 CHECK-26 全部 PASS 才算验收通过。

---

## 12. 常见问题排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `Check constraint 'ck_inv_conservation' is violated` | 库存三段不守恒 | ★ **这是好事**，说明约束正在保护你。检查是不是漏更新了某一段，或 delta 算错了 |
| `Duplicate entry 'xxx' for key 'uk_ledger_biz'` | 同一业务单重复扣减 | ★ **这也是好事**，幂等生效了。应用层捕获这个异常后应视为「已处理」返回成功，而不是报错 |
| `Duplicate entry for key 'uk_notify'` | 支付回调重复通知 | 正常现象。捕获后直接返回 `success` 给支付宝 |
| CHECK 约束不生效，能插入负库存 | MySQL < 8.0.16 | `SELECT VERSION();` 确认，必须升级 |
| 插入 emoji 报 `Incorrect string value` | 字符集不是 utf8mb4 | 检查库/表/字段/**连接**四层字符集，尤其别忘了 JDBC 连接串 |
| 时间差 8 小时 | JDBC 时区没配 | 连接串加 `?serverTimezone=Asia/Shanghai&characterEncoding=utf8mb4` |
| `DELIMITER` 语法错误 | 图形化工具不支持这个客户端命令 | 用命令行执行 `04_procedures_triggers.sql` |
| 定时事件不执行 | 事件调度器没开 | `SET GLOBAL event_scheduler = ON;` |
| 全文索引查不到中文 | ngram 分词器未启用或词太短 | 检查 `ngram_token_size`（默认 2）；单字搜索需要设为 1 并重建索引 |
| `EXPLAIN` 显示走了全表扫描 | 表里数据太少 | 正常。几十行的表走索引比全表扫描更慢，优化器的选择是对的。灌入上万行数据后再看 |
| 压测时大量 `Lock wait timeout exceeded` | 事务太长或有锁冲突 | 检查是否在事务里做了 HTTP 调用；`SHOW ENGINE INNODB STATUS` 看锁等待链 |
| 重置数据库后库存对不上 | Redis 里有残留 | `redis-cli FLUSHDB`（仅开发环境） |

---

## 附：给答辩准备的三个演示

### 演示一：CHECK 约束物理上阻止超卖

```sql
-- 当前库存 100
SELECT * FROM shop_inventory WHERE sku_id = 1001;

-- 尝试直接扣成负数（模拟应用层 bug）
UPDATE shop_inventory SET available_stock = available_stock - 200 WHERE sku_id = 1001;
-- ERROR 3819: Check constraint 'ck_inv_available_nonneg' is violated.
-- ★ 即使代码写错了，数据库也不允许超卖
```

### 演示二：唯一索引物理上阻止重复扣减

```sql
CALL sp_lock_stock(1001, 2, 'DEMO-001', 2, @r); SELECT @r;  -- 1（成功）
CALL sp_lock_stock(1001, 2, 'DEMO-001', 2, @r); SELECT @r;  -- 2（幂等命中，库存没有再扣）
SELECT * FROM shop_inventory WHERE sku_id = 1001;           -- 只扣了一次
```

### 演示三：台账不可篡改

```sql
DELETE FROM shop_inventory_ledger WHERE id = 1;
-- ERROR 1644: 库存台账为只增不改的审计记录，禁止 DELETE。

UPDATE shop_inventory_ledger SET delta_available = 999 WHERE id = 1;
-- ERROR 1644: 库存台账为只增不改的审计记录，禁止 UPDATE。
```

三个演示合起来说明一件事：
**数据正确性不依赖于「程序员不犯错」，而是由数据库约束在物理层面强制保证的。**
