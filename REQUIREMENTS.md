# Luceria Cocktail Atelier —— 全站重构需求规格说明书

> **从 Supabase BaaS 全量迁移到 Java + MySQL + Redis 自研后端，并新增电商购物模块与账号中心**

| 项目 | 内容 |
| --- | --- |
| 文档名称 | Luceria Cocktail Atelier 全站重构需求规格说明书 |
| 文档版本 | **v2.0（全量迁移版）** |
| 编写日期 | 2026-09-03 |
| 关联课程 | 《数据库原理》《Java 程序设计》期末作品 |
| 现有系统 | Luceria Cocktail Atelier（Vue 3 + Supabase 内容社区站） |
| 本期目标 | ① **Supabase 整体退出**（含 Auth 与 Storage），全站改由自研 Java 后端 + MySQL 提供服务；② 新增电商购物模块与账号中心；③ 核心攻坚**高并发下的库存数据一致性** |
| 配套产出 | `database/` 目录下的 5 个 SQL 脚本 + 数据库设计说明（本文第 5 章与之一一对应） |
| 文档状态 | 三个关键决策已确认（见 [12.1 已确认的决策](#121-已确认的决策)） |

### v2.0 相对 v1.0 的变更摘要

| 章节 | 变更 |
| --- | --- |
| 全文 | 架构结论从「绞杀者模式共存」改为 **「全量迁移」**，Supabase 整体退出 |
| 第 2 章 | 范围扩大：新增「内容社区迁移」；`N-1`（不接真实支付）与 `N-5`（不迁移内容社区）两条**已废止** |
| 第 3 章 | 3.3 结论改写；**新增 3.4 自研鉴权体系、3.5 RLS→Java 权限改写、3.6 文件存储选型、3.7 数据迁移方案** 四节 |
| 第 4 章 | 新增 4.8～4.11 四个模块共 27 条内容社区功能需求 |
| 第 5 章 | 从 17 张购物表扩展为 **31 张全站表**，DDL 移入 `database/01_schema.sql` |
| 第 6 章 | 核心结论不变；**新增 6.13 全量迁移引入的新并发点** |
| 第 7 章 | 新增 7.8～7.12 共 5 组内容社区接口 |
| 第 8 章 | 从「新增购物页面」扩展为 **「全站 8 个文件去 Supabase 化」** |
| 第 9/10 章 | 新增鉴权安全需求与 **12 条越权测试用例** |
| 第 11 章 | 10 周计划重排，迁移工作插入；降级顺序重新给出 |
| 支付 | 从模拟网关改为 **支付宝沙箱**（推荐）/ 微信支付沙箱，新增第 4.4A 节对接细则 |

---

## 目录

- [1. 项目背景与现状分析](#1-项目背景与现状分析)
- [2. 目标与范围](#2-目标与范围)
- [3. 技术选型与架构决策](#3-技术选型与架构决策)
  - [3.3 ★ 架构主决策：全量迁移](#33--架构主决策全量迁移)
  - [3.4 自研鉴权体系（替代 Supabase Auth）](#34-自研鉴权体系替代-supabase-auth)
  - [3.5 ★ RLS 行级安全 → Java 服务层鉴权](#35--rls-行级安全--java-服务层鉴权最容易出安全漏洞的地方)
  - [3.6 文件存储选型（替代 Supabase Storage）](#36-文件存储选型替代-supabase-storage)
  - [3.7 ★ 存量数据迁移方案](#37--存量数据迁移方案)
- [4. 功能需求](#4-功能需求)
- [5. 数据库设计](#5-数据库设计)
- [6. 【重点】并发一致性设计](#6-重点并发一致性设计)
- [7. 接口设计](#7-接口设计)
- [8. 前端改造点](#8-前端改造点)
- [9. 非功能需求](#9-非功能需求)
- [10. 压力测试与验证方案](#10-压力测试与验证方案)
- [11. 开发计划与里程碑](#11-开发计划与里程碑)
- [12. 决策记录、风险与未决问题](#12-决策记录风险与未决问题)
- [附录 A：术语表](#附录-a术语表)
- [附录 B：错误码总表](#附录-b错误码总表)

---

## 1. 项目背景与现状分析

### 1.1 现有系统做了什么

Luceria Cocktail Atelier 是一个**鸡尾酒主题的内容社区网站**，中英双语、暖色调杂志风、CSS 全手写无 UI 组件库。当前已上线以下能力：

| 页面 | 路由 | 视图组件 | 主要能力 |
| --- | --- | --- | --- |
| 首页 | `/` | `src/views/HomeView.vue` | 品牌入口、氛围首屏 |
| 主菜单 | `/menu` | `src/views/MenuView.vue` | 酒杯图形导航 + **黑胶唱片音乐播放器**（本地 MP3/OGG 上传、进度条、循环、静音） |
| 调酒菜单 | `/cocktails` | `src/views/CocktailsView.vue` | 8 款内置酒谱（`src/data/cocktails.js`）+ 用户投稿酒款；评分评论、点赞 |
| 新增/编辑酒款 | `/cocktails/new`、`/cocktails/:id/edit` | `src/views/AddCocktailView.vue` | 用户投稿酒款完整 CRUD + 图片上传 |
| 账号页 | `/account` | `src/views/AccountView.vue` | 邮箱魔法链接/验证码登录、昵称头像编辑（每周限改 1 次）、头像上传 |
| 喝酒故事 | `/stories` | `src/views/StoriesView.vue` | 论坛帖子、嵌套回复、帖子点赞/收藏、回复点赞 |
| 摇骰子转盘 | `/games` | `src/views/DiceWheelView.vue` | 骰子与转盘小游戏 |
| 调酒器具 | `/tools` | `src/views/ToolsView.vue` | 器具科普 |

路由定义见 `src/router/index.js`，共 9 条，全部 `() => import()` 懒加载，无任何路由守卫。

### 1.2 现有技术栈

| 层次 | 技术 | 说明 |
| --- | --- | --- |
| 前端框架 | Vue 3.5.17 | 全量 `<script setup>` 组合式 API |
| 构建工具 | Vite 6.3.5 | `vite.config.js` 中配置 `@` → `./src` 别名 |
| 路由 | Vue Router 4.5.1 | `createWebHistory`，9 条懒加载路由 |
| 状态管理 | Pinia 3.0.3 | 目前**只有一个 store**：`src/stores/auth.js` |
| 样式 | 手写 CSS | `src/styles/styles.css` 单文件，无 Tailwind/Element 等 |
| 后端 | **无自研后端** | 浏览器通过 `@supabase/supabase-js` 2.50 直连 Supabase |
| 数据库 | Supabase Postgres | 通过 PostgREST 暴露，安全完全依赖 **RLS 行级安全策略** |
| 认证 | Supabase Auth | 邮箱 OTP / Magic Link，PKCE flow（`src/lib/supabase.js`） |
| 对象存储 | Supabase Storage | `avatars`（3MB 限制）、`cocktail-images`（5MB，仅 JPG/PNG） |
| 实时通信 | Supabase Realtime | 已建表但**未启用**（游戏房间） |
| 部署 | Cloudflare Workers | `wrangler.jsonc`，静态资产 + SPA fallback（`not_found_handling: single-page-application`） |
| 测试 | Vitest 4.1.10 | 仅覆盖 `src/lib/user-cocktails.test.js` 中的纯函数 |
| 代码规范 | ESLint 9 + eslint-plugin-vue 10 | `npm run lint` |

### 1.3 现有数据表清单（Supabase Postgres）

来源：`supabase/*.sql`（这些脚本需手工粘贴进 Supabase SQL Editor 执行，**不是**受版本管理的 migration）。

| 表名 | 定义脚本 | 说明 |
| --- | --- | --- |
| `public.reviews` | `supabase-setup.sql` | 酒款评分评论，`rating numeric(3,1)` 0–10 |
| `public.review_likes` | `supabase-setup.sql` | 评论点赞，`unique (review_id, user_id)` |
| `public.stories_posts` | `stories-forum-setup.sql` | 论坛帖子，category ∈ {bar, recipe, city, memory} |
| `public.stories_replies` | `stories-forum-setup.sql` | 回复，自引用 `parent_reply_id` 支持嵌套 |
| `public.stories_post_likes` | `stories-forum-setup.sql` | 帖子点赞，复合主键 `(post_id, user_id)` |
| `public.stories_post_favorites` | `stories-forum-setup.sql` | **帖子收藏**，复合主键 `(post_id, user_id)` |
| `public.stories_reply_likes` | `stories-forum-setup.sql` | 回复点赞，复合主键 `(reply_id, user_id)` |
| `public.user_cocktails` | `user-cocktails-setup.sql` | 用户投稿酒款，`lower(name)` 唯一索引 + `updated_at` 触发器 |
| `public.games_rooms` | `games-realtime-setup.sql` | **未启用**，游戏房间 |
| `public.games_room_members` | `games-realtime-setup.sql` | **未启用** |
| `public.games_room_messages` | `games-realtime-setup.sql` | **未启用** |

管理员身份由 `supabase/admin-moderation-setup.sql` 写入 `auth.users.raw_app_meta_data.role = 'admin'`，前端通过 `auth.user.app_metadata.role` 判定（`src/stores/auth.js` 的 `isAdmin`）。

### 1.4 已知技术债

| # | 问题 | 位置 | 影响 |
| --- | --- | --- | --- |
| D-1 | 死代码：斗地主/炸金花整套逻辑未挂路由 | `src/views/GamesView.vue`、`src/game/**`、`src/components/DouDizhuTable.vue`、`ZhaJinHuaTable.vue` | 打包体积、认知负担 |
| D-2 | 废弃脚本 | `supabase/supabase-schema.sql` | 与实际 schema 不一致，易误执行 |
| D-3 | 重构前备份目录 | `legacy/` | 与现行代码重复 |
| D-4 | **无路由守卫** | `src/router/index.js` | 未登录用户可直接进入 `/cocktails/new` 等页面，靠 RLS 兜底报错 |
| D-5 | 测试覆盖率低 | 仅 `src/lib/user-cocktails.test.js` | 组件与业务流程零测试 |
| D-6 | SQL 脚本无版本管理 | `supabase/` | 无法回滚，无法追踪线上 schema |
| D-7 | 无 CI | — | 依赖手工 `npm run lint` / `npm run test` |

### 1.5 与新需求的差距分析

| 新需求 | 现状 | 差距 |
| --- | --- | --- |
| Java 后端服务 | 零后端，浏览器直连 BaaS | **需从 0 搭建**：项目骨架、分层、鉴权、异常体系、日志、部署 |
| MySQL | Postgres（托管） | 需自建 MySQL、设计**全站** schema（31 张表）、写 migration |
| Redis | 无 | 需引入并明确职责边界（缓存 / 预扣减 / 分布式锁 / 延迟队列） |
| 购物 + 库存 + 下单 | 完全没有 | 全新模块：商品、库存、购物车、订单、支付、退款、后台 |
| 实时库存显示 | 无 | 需轮询或 SSE/WebSocket 推送 |
| 账号中心（Google 风格） | `AccountView.vue` 仅登录 + 改资料 | 需扩展为多 Tab：概览 / 收藏 / 点赞 / 订单 / 安全 |
| 收藏点赞聚合 | 数据分散在 4 张 Supabase 表，且**无跨表聚合查询** | 迁移后可用一条 `UNION ALL` 视图解决（见 `database/01_schema.sql` 的 `v_user_favorite` / `v_user_like`） |
| **高并发不超卖** | 无任何库存概念 | **本项目核心技术攻坚点**（见第 6 章） |
| ★ **自研邮箱验证码登录** | Supabase Auth 的 `signInWithOtp` / `verifyOtp` / PKCE 全托管 | **需完整自研**：验证码生成/存储/校验/限流、JWT 签发与刷新、服务端强制下线（见 3.4） |
| ★ **行级权限** | Postgres RLS 策略（8 张表约 20 条 policy） | **需全部改写成 Java Service 层代码**。这是**整个迁移最容易出安全漏洞的地方**（见 3.5） |
| ★ **文件存储** | Supabase Storage 两个桶（`avatars` 3MB、`cocktail-images` 5MB） | 需另选方案：本地磁盘 / MinIO / 云对象存储（见 3.6） |
| ★ **存量数据迁移** | 8 张 Postgres 表 + `auth.users` | 需处理 `uuid` / `text[]` / `timestamptz` 三个 Postgres 特有类型到 MySQL 的映射（见 3.7） |
| ★ **8 款内置酒谱** | 硬编码在前端 `src/data/cocktails.js`，**不在数据库里** | 需入库，否则评论表无法通过外键关联它们（见 5.3） |
| 用户 Java 基础 | 不熟悉 | 技术选型必须优先「学习曲线平缓 + 中文资料丰富 + 出错可诊断」 |

---

## 2. 目标与范围

### 2.1 项目目标

| 编号 | 目标 | 验收标准 |
| --- | --- | --- |
| G-1 | 建立可运行的 Java 后端服务 | 能本地 `java -jar` 启动，前端可完整走通下单流程 |
| G-2 | 完成 MySQL 电商库设计并落地 | 16 张表建表脚本可一键执行，含索引与约束 |
| G-3 | 引入 Redis 承担缓存/预扣减/锁/延迟队列 | 各职责有对应代码与压测数据佐证 |
| G-4 | 上线购物模块（浏览→加购→下单→支付→退款） | 端到端可演示 |
| G-5 | 上线账号中心 | 可查看账号状态、收藏、点赞、订单 |
| G-6 | **证明高并发下不超卖、不少卖** | 1000 并发抢 100 件库存，成功订单数恰为 100，库存恒等式校验 SQL 返回 0 行异常 |
| G-7 | 产出可提交的课程作品文档与压测报告 | 本文档 + 压测报告 + 演示视频 |

### 2.2 本期做（In Scope）

- 商品与 SKU 管理、库存管理（含库存流水台账）
- 购物车
- 订单（创建、取消、超时关闭、查询）
- 支付（**模拟支付网关**，不接真实微信/支付宝）
- 退货退款（申请、审核、退款、库存回滚）
- 账号中心（概览、收藏、点赞、订单、安全信息）
- 简易管理后台（商品上下架、补库存、退款审核、订单查询）
- Java 后端服务 + MySQL + Redis
- 前端 MenuView 改造 + 新增购物相关路由与视图
- 压力测试与一致性验证脚本

### 2.3 本期不做（Out of Scope）

| 编号 | 不做的事 | 理由 |
| --- | --- | --- |
| N-1 | 接入真实支付渠道（微信支付/支付宝） | 需要商户资质与备案，课程作品用**模拟支付网关**即可完整演示回调、幂等、对账逻辑 |
| N-2 | 真实物流对接 | 用「模拟发货 + 手填运单号」代替 |
| N-3 | 分布式部署 / 微服务拆分 / 分库分表 | 单体应用足够支撑课程压测量级；过度设计会拖垮进度 |
| N-4 | 优惠券、积分、拼团、秒杀活动系统 | 与「不超卖」核心目标无关，第二期考虑 |
| N-5 | 把 stories/reviews/user_cocktails 全部迁到 MySQL | 见 3.3 节架构决策，本期采取**共存**策略 |
| N-6 | 清理死代码 D-1/D-2/D-3 | 本期不修改现有业务代码；作为独立技术债任务排期 |
| N-7 | 后端渲染 SSR / SEO | 现有 SPA 架构保持不变 |
| N-8 | 多语言 i18n 框架化 | 沿用现有中英双语硬编码写法 |

---

## 3. 技术选型与架构决策

### 3.1 决策一：Java 后端框架 —— 推荐 **Spring Boot 3.x**

用户明确表示对 Java 不熟悉，因此选型的第一优先级是**学习曲线与可诊断性**，而不是性能极限。

| 候选 | 优点 | 缺点 | 对「Java 新手」的适配度 | 结论 |
| --- | --- | --- | --- | --- |
| **Spring Boot 3.2+** | 生态最全；`spring-boot-starter-*` 开箱即用；中文教程/博客/视频海量；报错信息可直接搜到答案；MyBatis-Plus / Spring Data JPA / Redisson / Spring Security 都有官方 starter；IDEA 社区版即可开发 | 注解多，「魔法」重，初学者容易不知道底层发生了什么；启动稍慢 | ★★★★★ | **✅ 推荐** |
| Solon | 启动快、内存小、国产文档中文 | 生态小，遇到问题搜不到答案，招聘/课程认可度低 | ★★★ | ❌ |
| Quarkus / Micronaut | 云原生、编译期注入、GraalVM 原生镜像 | 中文资料稀少，报错晦涩，学习成本高 | ★★ | ❌ |
| Jakarta EE + Tomcat 手搓 Servlet | 最贴近《Java Web》课程教材，能看清全过程 | 样板代码巨多，事务/连接池/JSON 全靠手写，进度风险极高 | ★★ | ❌（可作为理解原理的小实验，不作主线） |
| Vert.x / Netty 裸写 | 性能极高 | 异步回调模型对新手是灾难 | ★ | ❌ |

**最终技术栈：**

| 组件 | 选型 | 版本 | 选择理由 |
| --- | --- | --- | --- |
| JDK | **Eclipse Temurin JDK 17**（LTS） | 17 | Spring Boot 3 最低要求 17；21 也可，但 17 的教程与踩坑记录更多 |
| 框架 | Spring Boot | 3.2.x | 见上表 |
| Web | spring-boot-starter-web（内嵌 Tomcat） | — | 阻塞式 MVC 心智模型简单，`@RestController` 一看就懂；**不用 WebFlux**（响应式对新手不友好） |
| 持久层 | **MyBatis-Plus** 3.5.x | — | **关键选择**：数据库原理课程要考察 SQL，MyBatis 让你**亲手写 SQL**，`SELECT ... FOR UPDATE`、CAS `UPDATE` 都能原样写出来并在文档里展示；JPA/Hibernate 会把 SQL 藏起来，反而不利于课程展示。MyBatis-Plus 又能省掉单表 CRUD 的样板代码 |
| 连接池 | HikariCP（Spring Boot 默认） | — | 零配置 |
| 缓存/分布式协调 | **Redisson** 3.2x | — | 分布式锁、延迟队列（`RDelayedQueue`）、Lua 脚本执行封装成 Java API，比裸 Jedis/Lettuce 好用得多 |
| 参数校验 | spring-boot-starter-validation（Jakarta Bean Validation） | — | `@NotNull @Min(1)` 声明式校验 |
| 鉴权 | **手写 JWT 拦截器**（`HandlerInterceptor` + `nimbus-jose-jwt`） | — | **不用 Spring Security**：Security 的过滤器链对新手极难调试，而本项目鉴权逻辑只有「验 JWT → 取 userId」这一件事，40 行拦截器就够了，出问题能一眼看懂 |
| 定时任务 | Spring `@Scheduled` | — | 兜底扫描用 |
| API 文档 | springdoc-openapi（Swagger UI） | 2.x | 自动生成接口文档，方便前端联调与作业展示 |
| 数据库迁移 | **Flyway** | — | 解决现状 D-6：SQL 脚本纳入版本管理，`V1__init.sql`、`V2__add_xxx.sql` |
| 日志 | Logback（Spring Boot 默认）+ MDC traceId | — | 排查并发问题必备 |
| 单元/集成测试 | JUnit 5 + Testcontainers（可选） | — | 并发测试用 `CountDownLatch` + 线程池 |
| 构建 | **Maven** | 3.9+ | 比 Gradle 更好懂，`pom.xml` 是纯 XML 声明，IDEA 支持完善 |

> **给 Java 新手的提示**：本项目只需掌握 Spring Boot 的四个核心概念即可上手 —— ①`@RestController` 接收 HTTP 请求；②`@Service` 写业务；③`@Mapper` 写 SQL；④`@Transactional` 管事务。其余（自动配置、IoC 容器）在遇到问题时再深入。

### 3.2 决策二：MySQL 与 Redis 的职责划分

| 维度 | MySQL 8.0（InnoDB） | Redis 7.x |
| --- | --- | --- |
| **定位** | **唯一事实来源（Source of Truth）** | **性能加速层 + 并发协调层**，数据可丢失可重建 |
| 存储内容 | 商品、SKU、库存、购物车、订单、支付、退款、库存流水、用户影子表、收藏、点赞 | 库存预扣减计数、商品详情缓存、订单防重令牌、分布式锁、延迟队列、热点排行 |
| 一致性要求 | **强一致**，ACID 事务保证 | 最终一致，允许短暂不准 |
| 关键职责 | ① 事务与行锁；② 唯一索引保证幂等；③ CHECK 约束守护库存不为负；④ 库存流水台账用于对账审计 | ① Lua 脚本原子预扣减，把 99% 的无效请求挡在数据库之外；② 缓存商品/SKU 详情降低读压力；③ Redisson 分布式锁保护非幂等临界区；④ `RDelayedQueue` 实现订单超时自动关单 |
| **不允许做的事** | 不做高频计数器（如实时 PV） | **绝不允许作为库存的最终判定依据**。Redis 宕机 / 数据丢失时，系统降级为「直连 MySQL CAS 扣减」，仍然不会超卖，只是吞吐下降 |

**核心原则（贯穿第 6 章）：**

> **Redis 是漏斗，MySQL 是闸门。**
> Redis 负责「快速拒绝掉绝大多数注定失败的请求」，MySQL 负责「对通过漏斗的请求做最终的、不可能出错的裁决」。
> 即使 Redis 完全失效或数据错乱，MySQL 的 `UPDATE ... WHERE available_stock >= n` 也物理上不可能让库存变负。

### 3.3 决策三（最关键）：与现有 Vue 前端和 Supabase 的关系

这是本次架构最重要的取舍。三种方案对比：

#### 方案 A：完全替换 Supabase，全部迁移到 Java + MySQL

| 优点 | 缺点 |
| --- | --- |
| 架构统一、只有一套技术栈、只有一个数据源 | ① 要重写 Supabase Auth（邮箱 OTP、Magic Link、PKCE、JWT 签发/刷新），是**整个项目最容易出安全事故的部分**；② 要重写 Storage（头像 3MB、酒款图 5MB 的上传、公开 URL、删除），涉及对象存储或本地磁盘；③ 要迁移 8 张表的存量数据；④ 要重写 `StoriesView.vue`、`CocktailsView.vue`、`AddCocktailView.vue`、`AccountView.vue`、`ReviewPanel.vue` 的全部数据访问代码（约 14 处 `supabase.from(...)` 调用）；⑤ **工作量约为购物模块本身的 2 倍，且与「不超卖」这一核心课程目标完全无关** |

#### 方案 B：完全共存，两套系统互不相干

| 优点 | 缺点 |
| --- | --- |
| 改动最小 | 用户身份割裂，账号中心无法把「Supabase 的收藏点赞」和「MySQL 的订单」放在同一个页面上 —— 而这恰恰是需求 3 明确要求的 |

#### 方案 C（✅ **推荐**）：绞杀者模式（Strangler Fig）—— 购物模块走 Java，内容社区留在 Supabase，通过 **JWT 单点身份** 打通

**架构图：**

```
                    ┌─────────────────────────────────────────┐
                    │   Vue 3 SPA (Cloudflare Workers 托管)    │
                    │   src/lib/supabase.js  src/lib/api.js   │
                    └───────────┬─────────────────┬───────────┘
                                │                 │
              内容社区读写        │                 │  购物模块读写
        (stories/reviews/       │                 │  (商品/库存/订单/
         user_cocktails)        │                 │   支付/退款/账号中心聚合)
                                │                 │
                                │                 │  Authorization: Bearer <Supabase JWT>
                                ▼                 ▼
              ┌──────────────────────┐   ┌────────────────────────────┐
              │  Supabase (PostgREST)│   │  Java Spring Boot 3 服务    │
              │  + Auth + Storage    │   │  ┌──────────────────────┐  │
              │  + RLS 行级安全       │   │  │ JwtAuthInterceptor   │  │
              └──────────┬───────────┘   │  │ 用 Supabase JWKS 验签 │  │
                         │               │  └──────────┬───────────┘  │
                         │               │  Controller │ Service      │
                         │               │             │ Mapper       │
                         ▼               └──────┬──────┴──────┬───────┘
              ┌──────────────────────┐          │             │
              │ Supabase Postgres    │          ▼             ▼
              │ (内容社区数据)         │   ┌───────────┐  ┌──────────┐
              └──────────┬───────────┘   │  MySQL 8  │  │ Redis 7  │
                         │               │ (电商数据) │  │ (缓存/锁/ │
                         │  账号中心聚合    │           │  │  预扣减/ │
                         └──────────────►│           │  │  延迟队列)│
                        (Java 服务端携带    └───────────┘  └──────────┘
                         用户 JWT 反查 Supabase
                         REST API 拿收藏/点赞)
```

**为什么推荐 C：**

| 理由 | 说明 |
| --- | --- |
| R-1 | **把有限的时间投在课程真正考察的地方**：《数据库原理》考察事务/索引/范式/并发控制，《Java》考察后端工程能力 —— 这些全都在购物模块里。重写登录和图床拿不到任何加分 |
| R-2 | **身份天然统一**：Supabase 签发的 JWT 里 `sub` 字段就是用户 UUID。Java 后端只要用 Supabase 的公钥（JWKS）验签，就能免费获得一套经过实战检验的认证系统，且**前端一行登录代码都不用改** |
| R-3 | **风险隔离**：购物模块崩了，内容社区照常运行；反之亦然 |
| R-4 | **符合真实工业实践**：绞杀者模式正是大型系统渐进式改造的标准做法，写进文档是加分项而非减分项 |
| R-5 | **保留升级路径**：第二期若要迁移内容社区，只需按表逐张搬到 MySQL，架构不用推倒重来 |

**取舍与代价（必须在文档中诚实说明）：**

| 代价 | 缓解措施 |
| --- | --- |
| C-1：两个数据源，**无法做跨库 JOIN**（比如「查我收藏的帖子 + 我的订单」不能一条 SQL 搞定） | 账号中心采用 **BFF 聚合**：Java 后端并行调用「MySQL 查订单」和「Supabase REST 查收藏点赞」，在 Java 内存里拼装成一个响应。用 `CompletableFuture.allOf()` 并行，总耗时 ≈ max(两者) 而非之和 |
| C-2：用户表在两边都有 | MySQL 建 **`shop_user` 影子表**，`supabase_uid CHAR(36) UNIQUE` 作为外键锚点。首次访问购物模块时**懒初始化**（JIT provisioning）写入一行 |
| C-3：跨域（前端 → Java 后端不同域名） | Java 侧配置 `CorsConfigurationSource`，白名单前端域名，`allowCredentials=false`（用 Bearer Token 不用 Cookie，规避 CSRF） |
| C-4：Supabase 免费额度限制 | 账号中心的收藏/点赞聚合结果在 Redis 缓存 60s |
| C-5：本地开发要同时起 MySQL + Redis | 提供 `docker-compose.yml` 一键起环境 |

**JWT 打通的具体机制：**

1. 前端沿用 `src/stores/auth.js` 的登录流程不变，登录后 `supabase.auth.getSession()` 拿到 `access_token`（JWT）。
2. 前端新增 `src/lib/api.js`，所有请求 Java 后端的调用自动带 `Authorization: Bearer ${access_token}`。
3. Java 后端 `JwtAuthInterceptor`：
   - 从 Supabase 项目的 `https://<project>.supabase.co/auth/v1/.well-known/jwks.json` 拉取公钥（**缓存 12 小时**），用 RS256/ES256 验签；若项目仍使用 legacy HS256，则用 `SUPABASE_JWT_SECRET` 对称验签。
   - 校验 `exp`、`aud=authenticated`、`iss`。
   - 取 `sub` 作为 `supabaseUid`，取 `email`、`app_metadata.role`。
   - 调用 `UserService.ensureUser(supabaseUid, email, ...)` 懒创建 `shop_user` 行，把内部 `user_id (BIGINT)` 放进 `ThreadLocal`/`RequestAttribute` 供 Service 层使用。
4. 管理接口额外校验 `app_metadata.role == 'admin'`（与现有 `src/stores/auth.js` 的 `isAdmin` 判定口径完全一致）。

> **安全红线**：Java 后端**绝不信任前端传来的 `userId`**，一切用户身份只从验签通过的 JWT 中提取。

### 3.4 部署形态

| 环境 | 部署方式 |
| --- | --- |
| 本地开发 | 前端 `npm run dev`（:5173）；后端 `mvn spring-boot:run`（:8080）；MySQL/Redis 用 `docker-compose up` |
| 演示/答辩 | 前端保持 Cloudflare Workers；后端部署到一台 Linux 云服务器（1C2G 足够），Nginx 反代 + HTTPS；MySQL/Redis 同机 Docker 部署 |
| 备选 | 全部本地跑，用录屏 + 压测报告答辩（**若无云服务器，此为兜底方案，不影响任何功能演示**） |

---

## 4. 功能需求

编号规则：`FR-<模块代号>-<序号>`。优先级：P0 = 必须做，P1 = 应该做，P2 = 有余力再做。

### 4.1 商品与库存模块（PRD）

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PRD-01** | **商品列表查询** | P0 |
| 输入 | `categoryId?`、`keyword?`、`sortBy ∈ {default, priceAsc, priceDesc, saleDesc}`、`page`(默认1)、`size`(默认20，上限50) |
| 处理 | ① 先查 Redis 缓存 `shop:product:list:{hash(参数)}`（TTL 120s + 随机抖动）；② 未命中则查 MySQL `shop_product` 表，仅取 `status = 1`（上架）；③ 批量查询各 SPU 下 SKU 的最低价与**可售库存合计**；④ 回写缓存 |
| 输出 | 分页列表，每项含 `productId, name, zhName, coverImage, minPrice, totalAvailable, soldCount, stockStatus ∈ {IN_STOCK, LOW_STOCK, SOLD_OUT}` |
| 异常 | 参数越界 → `400 PARAM_INVALID`；数据库不可用 → `503 SERVICE_UNAVAILABLE`（不返回脏缓存） |
| 备注 | `LOW_STOCK` 阈值 = `safety_stock`，前端显示「仅剩 N 件」 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PRD-02** | **商品详情查询** | P0 |
| 输入 | `productId` |
| 处理 | ① 查 Redis `shop:product:detail:{id}`；② 未命中加**分布式锁**（Redisson `tryLock`，防缓存击穿）后回源 MySQL；③ 若 MySQL 也无此商品，**缓存空对象** `NULL_PLACEHOLDER`（TTL 60s，防缓存穿透）；④ 返回 SPU + 全部 SKU 列表 |
| 输出 | `productId, name, zhName, subtitle, detailHtml, images[], skus[{skuId, specName, price, image, availableStock, status}]` |
| 异常 | 商品不存在或已下架 → `404 PRODUCT_NOT_FOUND`；下架商品对管理员可见、对普通用户 404 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PRD-03** | **实时库存查询（批量）** | P0 |
| 输入 | `skuIds[]`（上限 50） |
| 处理 | **直接读 Redis 预扣减计数** `shop:stock:{skuId}`（这是最实时的可售数），Redis 缺失时回源 MySQL `shop_inventory.available_stock` 并重建 Redis key |
| 输出 | `[{skuId, availableStock, status}]` |
| 异常 | 超过 50 个 → `400 PARAM_INVALID` |
| 备注 | **前端商品详情页每 3 秒轮询此接口**实现「实时数量」展示。此接口**不加缓存**、必须极轻量（纯 Redis MGET，P99 < 10ms） |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PRD-04** | **管理员创建/编辑商品与 SKU** | P0 |
| 输入 | SPU 基本信息 + SKU 数组（规格名、价格、初始库存） |
| 处理 | 事务内写 `shop_product`、`shop_sku`、`shop_inventory`（初始化 `total_stock = available_stock = 初始值`，`locked_stock = sold_stock = 0`），并写一条 `shop_inventory_ledger`（`biz_type = INIT`）；提交后**删除**相关 Redis 缓存并重建 `shop:stock:{skuId}` |
| 输出 | `productId, skuIds[]` |
| 异常 | 非管理员 → `403 FORBIDDEN`；`sku_code` 重复 → `409 SKU_CODE_DUPLICATED`；价格 ≤ 0 → `400` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PRD-05** | **管理员补货 / 调整库存** | P0 |
| 输入 | `skuId, deltaQuantity`（可正可负）、`reason`、`bizNo`（幂等键，前端生成 UUID） |
| 处理 | 事务：① `UPDATE shop_inventory SET total_stock = total_stock + ?, available_stock = available_stock + ? WHERE sku_id = ? AND available_stock + ? >= 0`；② 影响行数为 0 则回滚报错；③ 插入 `shop_inventory_ledger`（`UNIQUE(biz_type, biz_no, sku_id)` 保证重复提交只生效一次）；④ 提交后**增量更新** Redis 计数（`INCRBY`） |
| 输出 | 更新后的四段库存快照 |
| 异常 | 扣减后可售为负 → `409 STOCK_NOT_ENOUGH`；重复 `bizNo` → 幂等返回上次结果 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PRD-06** | **商品上下架** | P1 |
| 输入 | `productId, status ∈ {0 下架, 1 上架}` |
| 处理 | 更新 `shop_product.status`；下架时**不清零库存**（避免与在途订单冲突），仅阻止新下单；删除缓存 |
| 输出 | 成功标识 |
| 异常 | 存在「已支付未发货」订单时下架 → 允许，但返回 `warning` 提示待处理订单数 |

### 4.2 购物车模块（CART）

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-CART-01** | **加入购物车** | P0 |
| 输入 | `skuId, quantity`（1–99） |
| 处理 | ① 校验 SKU 存在且上架；② **仅做「库存足够」的软提示校验，不锁库存**（购物车不占库存，这是电商通用设计）；③ `INSERT ... ON DUPLICATE KEY UPDATE quantity = quantity + ?`（依赖 `UNIQUE(user_id, sku_id)`），累加后上限 99 |
| 输出 | 购物车条目数 `cartCount` |
| 异常 | SKU 已下架 → `409 SKU_OFF_SHELF`；数量越界 → `400`；未登录 → `401 UNAUTHORIZED` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-CART-02** | **购物车列表** | P0 |
| 输入 | 无（从 JWT 取用户） |
| 处理 | JOIN `shop_cart_item` × `shop_sku` × `shop_product`，并**实时补充** Redis 中的可售库存；标记失效条目（下架 / 库存不足） |
| 输出 | `items[{cartItemId, skuId, productName, specName, price, quantity, selected, availableStock, invalid, invalidReason}]`、`selectedTotalAmount` |
| 异常 | — |

| 编号 | 名称 | 优先级 | 
| --- | --- | --- |
| **FR-CART-03** | **修改数量 / 勾选 / 删除 / 清空失效项** | P0 |
| 输入 | `cartItemId` + 操作参数 |
| 处理 | 更新时**必须带 `AND user_id = ?`** 条件，防止越权改他人购物车（水平越权防护） |
| 输出 | 更新后的购物车汇总 |
| 异常 | 条目不属于当前用户 → 影响行数 0 → `404 CART_ITEM_NOT_FOUND`（**不返回 403，避免探测他人数据存在性**） |

### 4.3 订单模块（ORD）

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ORD-01** | **创建订单（下单）** —— 全系统最核心接口 | P0 |
| 输入 | `items[{skuId, quantity}]`（1–20 项）、`receiverName, receiverPhone, receiverAddress`、`remark?`、**`idempotencyKey`（前端生成 UUID，进入结算页时生成一次）** |
| 处理 | 见 **[6.4 推荐方案完整执行流程](#64-推荐方案完整执行流程)**。摘要：Redis 幂等令牌 → Redis Lua 原子预扣减 → MySQL 事务（CAS 扣减 + 写订单 + 写明细 + 写库存流水） → 投递延迟关单任务 |
| 输出 | `orderNo, payAmount, expireAt`（下单成功，进入待支付） |
| 异常 | 库存不足 → `409 STOCK_NOT_ENOUGH`（**返回具体哪个 SKU 不足**）；SKU 下架 → `409 SKU_OFF_SHELF`；重复提交（同 `idempotencyKey`）→ **返回上一次的 `orderNo`，HTTP 200**；系统异常 → 事务回滚 + **Redis 库存回补**，返回 `500` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ORD-02** | **订单列表查询** | P0 |
| 输入 | `status?`、`page, size` |
| 处理 | `WHERE user_id = ? [AND status = ?] ORDER BY id DESC`，走 `idx_user_status_id` 覆盖索引 |
| 输出 | 订单摘要列表（订单号、状态、金额、创建时间、首个商品图与名称、商品总件数、剩余支付时间） |
| 异常 | — |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ORD-03** | **订单详情** | P0 |
| 输入 | `orderNo` |
| 处理 | `WHERE order_no = ? AND user_id = ?`；管理员可查任意订单；附带订单明细、支付流水、退款单、状态变更日志 |
| 输出 | 完整订单对象 |
| 异常 | 不存在或非本人 → `404 ORDER_NOT_FOUND` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ORD-04** | **用户主动取消订单** | P0 |
| 输入 | `orderNo` |
| 处理 | 状态机校验（仅 `PENDING_PAYMENT` 可取消）→ 事务内 `UPDATE shop_order SET status = 'CANCELLED' WHERE order_no = ? AND status = 'PENDING_PAYMENT'`（**CAS，影响行数 0 即说明并发已被支付或已关单，直接失败**）→ 释放库存（`locked → available`）→ 写流水 → 提交后回补 Redis |
| 输出 | 成功标识 |
| 异常 | 状态不允许 → `409 ORDER_STATUS_ILLEGAL`；并发冲突 → 同上（幂等：重复取消返回成功） |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ORD-05** | **超时未支付自动关单** | P0 |
| 输入 | 延迟队列消息（`orderNo`，延迟 15 分钟）；兜底为每分钟扫描 `expire_at < NOW() AND status = 'PENDING_PAYMENT'` |
| 处理 | 与 FR-ORD-04 同一段代码路径（复用 `closeOrder(orderNo, reason)`），保证幂等 |
| 输出 | — |
| 异常 | 消息重复消费 → CAS 保证只生效一次；消息丢失 → 定时任务兜底 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ORD-06** | **管理员发货 / 用户确认收货** | P1 |
| 输入 | `orderNo`、`trackingNo?` |
| 处理 | 状态机 CAS 流转：`PAID → SHIPPED`（管理员）、`SHIPPED → COMPLETED`（用户）；写 `shop_order_status_log` |
| 输出 | 成功标识 |
| 异常 | 状态非法 → `409 ORDER_STATUS_ILLEGAL` |

### 4.4 支付模块（PAY）

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PAY-01** | **发起支付** | P0 |
| 输入 | `orderNo`、`channel ∈ {MOCK_ALIPAY, MOCK_WECHAT, BALANCE}` |
| 处理 | ① 校验订单属于当前用户且状态为 `PENDING_PAYMENT` 且未过期；② `INSERT shop_payment`（`payment_no` 唯一，状态 `PENDING`）；③ 返回模拟收银台 URL / 二维码内容 |
| 输出 | `paymentNo, payAmount, payUrl, expireAt` |
| 异常 | 订单已过期 → `409 ORDER_EXPIRED`；订单已支付 → **幂等返回已有支付单**；重复发起 → 复用未过期的 `PENDING` 支付单，不重复创建 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PAY-02** | **支付结果回调（模拟网关 → 后端）** | P0 |
| 输入 | `channelTradeNo, outTradeNo(=paymentNo), amount, tradeStatus, notifyId, sign` |
| 处理 | ① **验签**（HMAC-SHA256，密钥配置在服务端）；② `INSERT shop_payment_notify_log`，`notify_id` **唯一索引**，插入冲突 = 重复通知 → 直接返回 `success` 不再处理；③ 校验 `amount == shop_payment.amount`（**防金额篡改**）；④ 事务：`UPDATE shop_payment SET status='SUCCESS' WHERE payment_no=? AND status='PENDING'` + `UPDATE shop_order SET status='PAID' WHERE order_no=? AND status='PENDING_PAYMENT'`，两条 CAS 都必须影响 1 行；⑤ **库存 `locked → sold`**；⑥ 写库存流水；⑦ 提交后取消延迟关单任务（取消失败也无妨，因为关单是 CAS 的） |
| 输出 | 网关约定的 `success` 字符串 |
| 异常 | 验签失败 → `400`（并记录安全日志）；金额不符 → `400 AMOUNT_MISMATCH` + 告警；订单已关闭却收到成功支付 → **进入「异常支付」人工处理队列，并自动发起原路退款**（这是真实电商必须处理的边界，文档中必须体现） |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-PAY-03** | **主动查询支付状态（对账兜底）** | P1 |
| 输入 | `paymentNo` |
| 处理 | 若本地为 `PENDING` 且创建超过 1 分钟，主动调用模拟网关查询接口，结果与回调走**同一段处理逻辑** |
| 输出 | 支付状态 |
| 异常 | — |

### 4.5 退货退款模块（RFD）

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-RFD-01** | **申请退款/退货** | P0 |
| 输入 | `orderNo, orderItemId, quantity, reason, type ∈ {REFUND_ONLY, RETURN_AND_REFUND}`、`idempotencyKey` |
| 处理 | ① 校验订单属于当前用户，状态 ∈ {`PAID`, `SHIPPED`, `COMPLETED`}；② 校验 `quantity <= orderItem.quantity - orderItem.refunded_quantity`（**部分退款支持**）；③ 计算退款金额（按单价 × 数量，末笔退款时补齐分摊尾差）；④ `INSERT shop_refund`（`refund_no` 唯一 + `UNIQUE(idempotency_key)`），状态 `APPLYING`；⑤ 订单状态流转到 `REFUNDING` |
| 输出 | `refundNo, refundAmount, status` |
| 异常 | 超出可退数量 → `409 REFUND_QUANTITY_EXCEED`；重复提交 → 幂等返回；订单状态不允许 → `409` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-RFD-02** | **管理员审核退款** | P0 |
| 输入 | `refundNo, approved(bool), auditRemark` |
| 处理 | CAS：`UPDATE shop_refund SET status = ? WHERE refund_no = ? AND status = 'APPLYING'`；拒绝则订单回到原状态；同意则进入 `AUDITED`，触发退款执行 |
| 输出 | 成功标识 |
| 异常 | 状态非法 → `409` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-RFD-03** | **执行退款 + 库存回滚** | P0 |
| 输入 | `refundNo` |
| 处理 | 见 **[6.9 退货退款的库存回滚](#69-退货退款的库存回滚正确姿势)**。摘要：调用模拟网关退款 → 收到成功回执后，在**一个事务**内：`shop_refund` CAS 置 `SUCCESS` + `shop_order_item.refunded_quantity/refunded_amount` 累加（带 CAS 上限校验）+ **库存 `sold → available`** + 写 `shop_inventory_ledger`（`biz_no = refundNo`，唯一索引兜底）+ 判断订单是否全额退完决定订单终态 |
| 输出 | 成功标识 |
| 异常 | 网关退款失败 → 状态置 `FAILED`，进人工队列，**不回滚库存**；重复执行 → 唯一索引拦截，幂等 |

### 4.6 账号中心模块（ACC）

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ACC-01** | **账号概览（Google 账号中心风格首屏）** | P0 |
| 输入 | 无（JWT） |
| 处理 | BFF 并行聚合：`CompletableFuture` 同时发起 ① MySQL 查订单统计（各状态数量、总消费金额）；② MySQL 查购物车条目数；③ Supabase REST 查内容统计（发帖数、投稿酒款数、评论数）；④ 从 JWT 取账号基本信息与 `profile_updated_at`。结果缓存 Redis 60s |
| 输出 | `profile{email, displayName, avatarUrl, role, registeredAt, profileNextEditableAt}`、`orderStats{pendingPayment, paid, shipped, completed, refunding, totalSpent}`、`contentStats{posts, replies, cocktails, reviews}`、`securityInfo{lastLoginAt, loginMethod: "Email OTP"}` |
| 异常 | Supabase 侧超时（>2s）→ **降级返回内容统计为 null 并标记 `partial: true`**，不影响订单数据展示 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ACC-02** | **我的收藏（聚合）** | P0 |
| 输入 | `type ∈ {ALL, POST, PRODUCT}`、`page, size` |
| 处理 | ① `POST` 类型：Java 后端携带用户 JWT 调用 Supabase REST `GET /rest/v1/stories_post_favorites?user_id=eq.<uid>&select=post_id,created_at,stories_posts(title,body,category,created_at)`（利用 PostgREST 的嵌入式资源，一次请求拿到帖子内容）；② `PRODUCT` 类型：查 MySQL `shop_favorite WHERE user_id=? AND target_type='PRODUCT'` JOIN 商品；③ 按 `created_at` 归并排序后分页 |
| 输出 | `items[{type, targetId, title, summary, coverImage, favoritedAt, link}]` |
| 异常 | Supabase 不可达 → 返回 MySQL 部分数据 + `partial: true` |
| 备注 | **与现有 `stories_post_favorites` 表完全兼容，不需要迁移任何数据**；新增的商品收藏走 MySQL `shop_favorite` |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ACC-03** | **近期点赞（聚合）** | P0 |
| 输入 | `days`（默认 30）、`page, size` |
| 处理 | 并行查询三个来源并归并：① Supabase `stories_post_likes`（嵌入 `stories_posts`）；② Supabase `stories_reply_likes`（嵌入 `stories_replies`）；③ Supabase `review_likes`（嵌入 `reviews`）。按 `created_at desc` 归并，取前 N 条 |
| 输出 | `items[{sourceType ∈ {POST, REPLY, REVIEW}, targetId, title, snippet, likedAt, link}]` |
| 异常 | 同上，支持部分降级 |
| 备注 | 现有 `review_likes` 表的主键是 `id uuid` + `unique(review_id, user_id)`，与 stories 三表的复合主键写法不同，聚合层需做字段映射适配 |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ACC-04** | **我的订单入口 / 我的地址簿** | P1 |
| 输入 | — |
| 处理 | 复用 FR-ORD-02；地址簿 CRUD 走 `shop_user_address`，支持设为默认（同一用户仅一条 `is_default = 1`，用**唯一索引 + 事务**保证） |
| 输出 | — |
| 异常 | — |

| 编号 | 名称 | 优先级 |
| --- | --- | --- |
| **FR-ACC-05** | **商品收藏 / 取消收藏** | P1 |
| 输入 | `productId` |
| 处理 | `INSERT IGNORE INTO shop_favorite`（依赖 `UNIQUE(user_id, target_type, target_id)` 天然幂等）/ `DELETE WHERE ...` |
| 输出 | `favorited: bool` |
| 异常 | 商品不存在 → `404` |

### 4.7 管理后台模块（ADM）

| 编号 | 名称 | 优先级 | 说明 |
| --- | --- | --- | --- |
| **FR-ADM-01** | 商品/SKU 管理 | P0 | 复用 FR-PRD-04/05/06 |
| **FR-ADM-02** | 订单查询与改价/备注 | P1 | 支持按订单号、用户、状态、时间范围检索 |
| **FR-ADM-03** | 退款审核 | P0 | 复用 FR-RFD-02 |
| **FR-ADM-04** | **库存流水台账查询与对账** | P0 | 按 SKU 查全部 `shop_inventory_ledger`，并提供**一键校验**：`SUM(delta)` 与当前库存快照是否一致 —— 这是向老师展示「数据没错乱」的最直观证据 |
| **FR-ADM-05** | 数据看板 | P2 | 今日订单数、GMV、退款率、热销 TOP10 |

---

## 5. 数据库设计

### 5.1 设计原则

| 原则 | 说明 |
| --- | --- |
| 引擎与字符集 | 全部 `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`（InnoDB 才有事务与行锁；utf8mb4 支持 emoji，酒评里会用到） |
| 主键 | 一律 `BIGINT UNSIGNED AUTO_INCREMENT`。**不用 UUID 做主键**：InnoDB 是聚簇索引，随机 UUID 主键会造成页分裂与二级索引膨胀（这是数据库原理课程的经典考点） |
| 业务主键 | 对外暴露 `order_no`、`refund_no` 等**有意义的业务号**，加唯一索引；内部关联仍用自增 ID |
| 金额 | 一律 `DECIMAL(10,2)`。**绝不用 FLOAT/DOUBLE**（浮点误差会导致对账不平） |
| 时间 | `DATETIME(3)`（毫秒精度），`created_at DEFAULT CURRENT_TIMESTAMP(3)`、`updated_at ... ON UPDATE CURRENT_TIMESTAMP(3)` |
| 逻辑删除 | 订单等关键数据**不物理删除**，用状态字段表达 |
| 外键 | **逻辑外键为主，物理外键仅在低频表上使用**。理由：物理外键在高并发写入时会加额外的意向锁与检查开销，且级联行为难以控制；但作为课程作品，会在 `shop_sku → shop_product`、`shop_order_item → shop_order` 等**低频写**关系上保留物理外键以体现参照完整性设计能力，而在 `shop_inventory`、`shop_inventory_ledger` 等高频写表上仅用逻辑外键 + 应用层校验。**此取舍在文档中明确记录** |

### 5.2 范式分析（数据库原理课程考察点）

| 表 | 满足范式 | 说明 |
| --- | --- | --- |
| `shop_user`、`shop_category`、`shop_product`、`shop_sku`、`shop_inventory` | **3NF / BCNF** | 每个非主属性完全函数依赖于主键，无传递依赖 |
| `shop_cart_item` | **3NF** | `(user_id, sku_id)` 候选键，`quantity` 完全依赖之 |
| **`shop_order`** | **有意反范式（2NF 违反）** | 冗余存储 `receiver_name/phone/address`，而非只存 `address_id`。**理由**：收货地址是**历史快照**，用户日后修改地址簿不能改变已下订单的历史事实。这是电商领域的标准做法 —— **快照优先于范式** |
| **`shop_order_item`** | **有意反范式** | 冗余 `product_name, sku_spec_name, sku_image, unit_price`。**理由**：商品改名、改价、下架后，历史订单必须仍能正确展示当时的成交信息。若只存 `sku_id` 做 JOIN，会出现「三年前买的酒现在显示成新品价格」的严重业务错误 |
| **`shop_inventory`** | **3NF，但独立于 `shop_sku`** | 库存字段**故意不放在 `shop_sku` 表里**。理由：SKU 表是读多写少（缓存友好），库存表是写极多（行锁热点）。分表可以让 SKU 行不被库存的行锁阻塞，也让库存表的行更窄、单页容纳更多行、Buffer Pool 命中率更高 |
| `shop_inventory_ledger` | **3NF，append-only** | 只增不改的事件流水表，天然满足范式 |

> **总结写法（可直接用于答辩）**：本设计以 3NF 为基线，仅在「历史快照」与「读写分离」两类场景下有意识地引入冗余，每一处反范式都有明确的业务理由和一致性维护策略（快照字段在写入后即不可变，因此不存在更新异常）。

### 5.3 完整建表 SQL

```sql
-- =====================================================================
-- Luceria Shop —— MySQL 8.0 建表脚本  V1__init_shop.sql
-- 字符集：utf8mb4 / 引擎：InnoDB / 隔离级别：READ-COMMITTED（见 6.11）
-- =====================================================================

CREATE DATABASE IF NOT EXISTS luceria_shop
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE luceria_shop;

-- ---------------------------------------------------------------------
-- 1. 用户影子表：与 Supabase auth.users 通过 supabase_uid 对齐
-- ---------------------------------------------------------------------
CREATE TABLE shop_user (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '内部用户ID',
  supabase_uid   CHAR(36)        NOT NULL                COMMENT 'Supabase auth.users.id (JWT sub)',
  email          VARCHAR(254)    NOT NULL DEFAULT ''      COMMENT '邮箱（冗余，便于后台检索）',
  display_name   VARCHAR(24)     NOT NULL DEFAULT 'Guest Bartender',
  avatar_url     VARCHAR(500)    NOT NULL DEFAULT '',
  role           VARCHAR(16)     NOT NULL DEFAULT 'user'  COMMENT 'user / admin',
  status         TINYINT         NOT NULL DEFAULT 1       COMMENT '1正常 0封禁',
  created_at     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_supabase_uid (supabase_uid),
  KEY idx_email (email)
) ENGINE=InnoDB COMMENT='购物模块用户影子表（JIT 懒创建）';

-- ---------------------------------------------------------------------
-- 2. 收货地址
-- ---------------------------------------------------------------------
CREATE TABLE shop_user_address (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id       BIGINT UNSIGNED NOT NULL,
  receiver_name VARCHAR(32)     NOT NULL,
  receiver_phone VARCHAR(20)    NOT NULL,
  province      VARCHAR(32)     NOT NULL DEFAULT '',
  city          VARCHAR(32)     NOT NULL DEFAULT '',
  district      VARCHAR(32)     NOT NULL DEFAULT '',
  detail        VARCHAR(200)    NOT NULL,
  is_default    TINYINT         NOT NULL DEFAULT 0,
  deleted       TINYINT         NOT NULL DEFAULT 0,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_user (user_id, deleted),
  CONSTRAINT fk_addr_user FOREIGN KEY (user_id) REFERENCES shop_user (id)
) ENGINE=InnoDB COMMENT='收货地址簿';

-- ---------------------------------------------------------------------
-- 3. 商品分类
-- ---------------------------------------------------------------------
CREATE TABLE shop_category (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name       VARCHAR(32)  NOT NULL,
  zh_name    VARCHAR(32)  NOT NULL,
  sort_order INT          NOT NULL DEFAULT 0,
  status     TINYINT      NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_name (name)
) ENGINE=InnoDB COMMENT='商品分类（基酒/器具/周边/礼盒）';

-- ---------------------------------------------------------------------
-- 4. 商品 SPU
-- ---------------------------------------------------------------------
CREATE TABLE shop_product (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_code VARCHAR(32)     NOT NULL COMMENT '商品编码',
  name         VARCHAR(60)     NOT NULL COMMENT '英文名',
  zh_name      VARCHAR(40)     NOT NULL COMMENT '中文名',
  subtitle     VARCHAR(120)    NOT NULL DEFAULT '',
  category_id  INT UNSIGNED    NOT NULL,
  cover_image  VARCHAR(500)    NOT NULL DEFAULT '',
  images       JSON            NULL     COMMENT '轮播图 URL 数组',
  detail       TEXT            NULL     COMMENT '详情富文本',
  min_price    DECIMAL(10,2)   NOT NULL DEFAULT 0.00 COMMENT '冗余：最低SKU价，用于列表排序',
  sale_count   INT UNSIGNED    NOT NULL DEFAULT 0    COMMENT '冗余：累计销量',
  status       TINYINT         NOT NULL DEFAULT 0    COMMENT '0下架 1上架',
  created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_product_code (product_code),
  KEY idx_category_status_sale (category_id, status, sale_count DESC),
  KEY idx_status_price (status, min_price),
  CONSTRAINT fk_product_category FOREIGN KEY (category_id) REFERENCES shop_category (id)
) ENGINE=InnoDB COMMENT='商品SPU';

-- ---------------------------------------------------------------------
-- 5. 商品 SKU（读多写少，缓存友好）
-- ---------------------------------------------------------------------
CREATE TABLE shop_sku (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_id BIGINT UNSIGNED NOT NULL,
  sku_code   VARCHAR(40)     NOT NULL,
  spec_name  VARCHAR(60)     NOT NULL COMMENT '规格名，如 "700ml / 单瓶装"',
  price      DECIMAL(10,2)   NOT NULL,
  image      VARCHAR(500)    NOT NULL DEFAULT '',
  status     TINYINT         NOT NULL DEFAULT 1 COMMENT '0停售 1在售',
  created_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_sku_code (sku_code),
  KEY idx_product (product_id, status),
  CONSTRAINT fk_sku_product FOREIGN KEY (product_id) REFERENCES shop_product (id),
  CONSTRAINT ck_sku_price CHECK (price > 0)
) ENGINE=InnoDB COMMENT='商品SKU';

-- ---------------------------------------------------------------------
-- 6. ★ 库存表（三段式模型，全系统最热的写入点）
--    恒等式：available_stock + locked_stock + sold_stock = total_stock
-- ---------------------------------------------------------------------
CREATE TABLE shop_inventory (
  sku_id          BIGINT UNSIGNED NOT NULL COMMENT '与 shop_sku.id 一对一，直接做主键',
  total_stock     INT             NOT NULL DEFAULT 0 COMMENT '总库存（入库总量）',
  available_stock INT             NOT NULL DEFAULT 0 COMMENT '★可售库存（可被下单占用）',
  locked_stock    INT             NOT NULL DEFAULT 0 COMMENT '★已锁定（下单未支付）',
  sold_stock      INT             NOT NULL DEFAULT 0 COMMENT '★已售出（已支付）',
  safety_stock    INT             NOT NULL DEFAULT 5 COMMENT '低库存预警阈值',
  version         BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本号（备用/审计用）',
  updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (sku_id),
  -- ★★★ 数据库层最后一道防线：任何路径都不可能把库存写成负数 ★★★
  CONSTRAINT ck_inv_available_nonneg CHECK (available_stock >= 0),
  CONSTRAINT ck_inv_locked_nonneg    CHECK (locked_stock    >= 0),
  CONSTRAINT ck_inv_sold_nonneg      CHECK (sold_stock      >= 0),
  CONSTRAINT ck_inv_total_nonneg     CHECK (total_stock     >= 0),
  -- ★★★ 恒等式约束：三段之和必须等于总量 ★★★
  CONSTRAINT ck_inv_conservation
    CHECK (available_stock + locked_stock + sold_stock = total_stock)
) ENGINE=InnoDB COMMENT='库存主表（三段式）';

-- ---------------------------------------------------------------------
-- 7. ★ 库存流水台账（append-only，用于对账与审计，也是幂等的载体）
-- ---------------------------------------------------------------------
CREATE TABLE shop_inventory_ledger (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sku_id         BIGINT UNSIGNED NOT NULL,
  biz_type       VARCHAR(24)     NOT NULL
                 COMMENT 'INIT/RESTOCK/ADJUST/ORDER_LOCK/ORDER_CANCEL/ORDER_EXPIRE/PAY_CONFIRM/REFUND_RETURN',
  biz_no         VARCHAR(64)     NOT NULL COMMENT '业务单号：orderNo / refundNo / adjustNo',
  delta_available INT            NOT NULL DEFAULT 0,
  delta_locked    INT            NOT NULL DEFAULT 0,
  delta_sold      INT            NOT NULL DEFAULT 0,
  delta_total     INT            NOT NULL DEFAULT 0,
  after_available INT            NOT NULL,
  after_locked    INT            NOT NULL,
  after_sold      INT            NOT NULL,
  after_total     INT            NOT NULL,
  operator_type  VARCHAR(16)     NOT NULL DEFAULT 'SYSTEM' COMMENT 'USER/ADMIN/SYSTEM',
  operator_id    BIGINT UNSIGNED NULL,
  remark         VARCHAR(200)    NOT NULL DEFAULT '',
  created_at     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  -- ★★★ 幂等核心：同一业务单对同一 SKU 的同类操作只能记一次 ★★★
  UNIQUE KEY uk_biz (biz_type, biz_no, sku_id),
  KEY idx_sku_time (sku_id, created_at),
  KEY idx_biz_no (biz_no)
) ENGINE=InnoDB COMMENT='库存变动流水台账（不可修改，只可追加）';

-- ---------------------------------------------------------------------
-- 8. 购物车
-- ---------------------------------------------------------------------
CREATE TABLE shop_cart_item (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  sku_id     BIGINT UNSIGNED NOT NULL,
  quantity   INT             NOT NULL DEFAULT 1,
  selected   TINYINT         NOT NULL DEFAULT 1,
  created_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  -- 保证同一用户同一 SKU 只有一行，支撑 INSERT ... ON DUPLICATE KEY UPDATE
  UNIQUE KEY uk_user_sku (user_id, sku_id),
  KEY idx_user_updated (user_id, updated_at DESC),
  CONSTRAINT ck_cart_qty CHECK (quantity BETWEEN 1 AND 99)
) ENGINE=InnoDB COMMENT='购物车（不占库存）';

-- ---------------------------------------------------------------------
-- 9. ★ 订单主表
-- ---------------------------------------------------------------------
CREATE TABLE shop_order (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_no         VARCHAR(32)     NOT NULL COMMENT '业务订单号 yyyyMMddHHmmss+机器码+序列',
  user_id          BIGINT UNSIGNED NOT NULL,
  status           VARCHAR(20)     NOT NULL DEFAULT 'PENDING_PAYMENT'
                   COMMENT 'PENDING_PAYMENT/PAID/SHIPPED/COMPLETED/CANCELLED/CLOSED/REFUNDING/REFUNDED',
  total_amount     DECIMAL(10,2)   NOT NULL COMMENT '商品总额',
  freight_amount   DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
  discount_amount  DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
  pay_amount       DECIMAL(10,2)   NOT NULL COMMENT '应付 = total + freight - discount',
  refunded_amount  DECIMAL(10,2)   NOT NULL DEFAULT 0.00 COMMENT '累计已退金额',
  item_count       INT             NOT NULL DEFAULT 0,
  -- 收货信息快照（有意反范式，见 5.2）
  receiver_name    VARCHAR(32)     NOT NULL,
  receiver_phone   VARCHAR(20)     NOT NULL,
  receiver_address VARCHAR(300)    NOT NULL,
  remark           VARCHAR(200)    NOT NULL DEFAULT '',
  tracking_no      VARCHAR(64)     NOT NULL DEFAULT '',
  idempotency_key  VARCHAR(64)     NOT NULL COMMENT '★下单幂等键（前端 UUID）',
  expire_at        DATETIME(3)     NOT NULL COMMENT '超时未支付关单时间',
  pay_time         DATETIME(3)     NULL,
  ship_time        DATETIME(3)     NULL,
  finish_time      DATETIME(3)     NULL,
  close_time       DATETIME(3)     NULL,
  close_reason     VARCHAR(64)     NOT NULL DEFAULT '',
  version          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  created_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_order_no (order_no),
  -- ★★★ 防重复下单的数据库级兜底 ★★★
  UNIQUE KEY uk_user_idem (user_id, idempotency_key),
  -- 覆盖「我的订单」列表查询：WHERE user_id=? AND status=? ORDER BY id DESC
  KEY idx_user_status_id (user_id, status, id DESC),
  -- 覆盖超时扫描兜底任务：WHERE status='PENDING_PAYMENT' AND expire_at < NOW()
  KEY idx_status_expire (status, expire_at),
  KEY idx_created (created_at),
  CONSTRAINT ck_order_amount CHECK (pay_amount >= 0 AND refunded_amount >= 0 AND refunded_amount <= pay_amount)
) ENGINE=InnoDB COMMENT='订单主表';

-- ---------------------------------------------------------------------
-- 10. ★ 订单明细（商品信息快照，有意反范式）
-- ---------------------------------------------------------------------
CREATE TABLE shop_order_item (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id          BIGINT UNSIGNED NOT NULL,
  order_no          VARCHAR(32)     NOT NULL COMMENT '冗余，便于按单号直查免 JOIN',
  user_id           BIGINT UNSIGNED NOT NULL COMMENT '冗余，便于按用户统计',
  product_id        BIGINT UNSIGNED NOT NULL,
  sku_id            BIGINT UNSIGNED NOT NULL,
  -- ↓↓↓ 成交时快照，写入后永不修改 ↓↓↓
  product_name      VARCHAR(60)     NOT NULL,
  product_zh_name   VARCHAR(40)     NOT NULL,
  sku_spec_name     VARCHAR(60)     NOT NULL,
  sku_image         VARCHAR(500)    NOT NULL DEFAULT '',
  unit_price        DECIMAL(10,2)   NOT NULL,
  quantity          INT             NOT NULL,
  total_amount      DECIMAL(10,2)   NOT NULL COMMENT '= unit_price * quantity',
  -- ↓↓↓ 退款累计（可变） ↓↓↓
  refunded_quantity INT             NOT NULL DEFAULT 0,
  refunded_amount   DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
  created_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_order (order_id),
  KEY idx_order_no (order_no),
  KEY idx_sku (sku_id),
  KEY idx_user_created (user_id, created_at DESC),
  CONSTRAINT fk_item_order FOREIGN KEY (order_id) REFERENCES shop_order (id),
  -- ★ 退款数量永远不能超过购买数量（数据库层兜底）
  CONSTRAINT ck_item_refund_qty CHECK (refunded_quantity >= 0 AND refunded_quantity <= quantity),
  CONSTRAINT ck_item_refund_amt CHECK (refunded_amount >= 0 AND refunded_amount <= total_amount)
) ENGINE=InnoDB COMMENT='订单明细（快照）';

-- ---------------------------------------------------------------------
-- 11. 支付流水
-- ---------------------------------------------------------------------
CREATE TABLE shop_payment (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_no       VARCHAR(32)     NOT NULL COMMENT '本地支付单号（= 网关 out_trade_no）',
  order_no         VARCHAR(32)     NOT NULL,
  user_id          BIGINT UNSIGNED NOT NULL,
  channel          VARCHAR(20)     NOT NULL COMMENT 'MOCK_ALIPAY/MOCK_WECHAT/BALANCE',
  amount           DECIMAL(10,2)   NOT NULL,
  status           VARCHAR(16)     NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/SUCCESS/FAILED/CLOSED',
  channel_trade_no VARCHAR(64)     NULL COMMENT '网关流水号',
  notify_payload   JSON            NULL,
  paid_at          DATETIME(3)     NULL,
  expire_at        DATETIME(3)     NOT NULL,
  created_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_payment_no (payment_no),
  -- ★ 同一笔网关流水只能对应一条支付记录（防重复入账）
  UNIQUE KEY uk_channel_trade_no (channel_trade_no),
  KEY idx_order_no (order_no),
  KEY idx_status_created (status, created_at)
) ENGINE=InnoDB COMMENT='支付流水';

-- ---------------------------------------------------------------------
-- 12. ★ 支付回调日志（防重复通知的幂等载体）
-- ---------------------------------------------------------------------
CREATE TABLE shop_payment_notify_log (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  channel       VARCHAR(20)     NOT NULL,
  notify_id     VARCHAR(64)     NOT NULL COMMENT '★网关通知唯一ID',
  payment_no    VARCHAR(32)     NOT NULL DEFAULT '',
  raw_body      TEXT            NOT NULL,
  handle_status VARCHAR(16)     NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/SUCCESS/IGNORED/FAILED',
  handle_remark VARCHAR(200)    NOT NULL DEFAULT '',
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  -- ★★★ 重复通知在这里被数据库直接拒绝 ★★★
  UNIQUE KEY uk_channel_notify (channel, notify_id),
  KEY idx_payment_no (payment_no)
) ENGINE=InnoDB COMMENT='支付回调原始日志';

-- ---------------------------------------------------------------------
-- 13. ★ 退款单
-- ---------------------------------------------------------------------
CREATE TABLE shop_refund (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  refund_no          VARCHAR(32)     NOT NULL,
  order_no           VARCHAR(32)     NOT NULL,
  order_item_id      BIGINT UNSIGNED NOT NULL,
  sku_id             BIGINT UNSIGNED NOT NULL,
  user_id            BIGINT UNSIGNED NOT NULL,
  refund_type        VARCHAR(20)     NOT NULL COMMENT 'REFUND_ONLY/RETURN_AND_REFUND',
  quantity           INT             NOT NULL COMMENT '退货数量',
  refund_amount      DECIMAL(10,2)   NOT NULL,
  reason             VARCHAR(200)    NOT NULL DEFAULT '',
  status             VARCHAR(20)     NOT NULL DEFAULT 'APPLYING'
                     COMMENT 'APPLYING/AUDITED/REJECTED/REFUNDING/SUCCESS/FAILED',
  restock            TINYINT         NOT NULL DEFAULT 1 COMMENT '是否回补库存（仅退款不退货且商品已损坏时=0）',
  idempotency_key    VARCHAR(64)     NOT NULL,
  channel_refund_no  VARCHAR(64)     NULL,
  audit_remark       VARCHAR(200)    NOT NULL DEFAULT '',
  apply_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  audit_at           DATETIME(3)     NULL,
  refund_at          DATETIME(3)     NULL,
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_refund_no (refund_no),
  -- ★ 防重复申请
  UNIQUE KEY uk_user_idem (user_id, idempotency_key),
  -- ★ 防重复入账
  UNIQUE KEY uk_channel_refund_no (channel_refund_no),
  KEY idx_order_no (order_no),
  KEY idx_status_apply (status, apply_at),
  CONSTRAINT ck_refund_qty CHECK (quantity > 0),
  CONSTRAINT ck_refund_amt CHECK (refund_amount >= 0)
) ENGINE=InnoDB COMMENT='退款单';

-- ---------------------------------------------------------------------
-- 14. 订单状态变更日志（审计 + 演示状态机）
-- ---------------------------------------------------------------------
CREATE TABLE shop_order_status_log (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_no      VARCHAR(32)     NOT NULL,
  from_status   VARCHAR(20)     NOT NULL,
  to_status     VARCHAR(20)     NOT NULL,
  event         VARCHAR(32)     NOT NULL COMMENT 'CREATE/PAY/CANCEL/EXPIRE/SHIP/CONFIRM/REFUND_APPLY/REFUND_DONE',
  operator_type VARCHAR(16)     NOT NULL DEFAULT 'SYSTEM',
  operator_id   BIGINT UNSIGNED NULL,
  remark        VARCHAR(200)    NOT NULL DEFAULT '',
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_order_no_time (order_no, created_at)
) ENGINE=InnoDB COMMENT='订单状态机流转日志';

-- ---------------------------------------------------------------------
-- 15. 收藏（商品收藏走 MySQL；帖子收藏仍在 Supabase stories_post_favorites）
-- ---------------------------------------------------------------------
CREATE TABLE shop_favorite (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED NOT NULL,
  target_type VARCHAR(16)     NOT NULL COMMENT 'PRODUCT / COCKTAIL / POST',
  target_id   VARCHAR(64)     NOT NULL COMMENT '兼容 BIGINT 与 Supabase UUID',
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  -- ★ 天然幂等：重复收藏靠唯一索引拦截（INSERT IGNORE）
  UNIQUE KEY uk_user_target (user_id, target_type, target_id),
  KEY idx_user_created (user_id, created_at DESC)
) ENGINE=InnoDB COMMENT='收藏（购物侧）';

-- ---------------------------------------------------------------------
-- 16. 点赞（同上）
-- ---------------------------------------------------------------------
CREATE TABLE shop_like (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED NOT NULL,
  target_type VARCHAR(16)     NOT NULL COMMENT 'PRODUCT / REVIEW / POST / REPLY',
  target_id   VARCHAR(64)     NOT NULL,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_target (user_id, target_type, target_id),
  KEY idx_user_created (user_id, created_at DESC)
) ENGINE=InnoDB COMMENT='点赞（购物侧）';

-- ---------------------------------------------------------------------
-- 17. 延迟任务兜底表（Redis 延迟队列丢消息时的最后保险）
-- ---------------------------------------------------------------------
CREATE TABLE shop_delay_task (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  task_type   VARCHAR(32)     NOT NULL COMMENT 'CLOSE_ORDER / AUTO_CONFIRM',
  biz_no      VARCHAR(64)     NOT NULL,
  execute_at  DATETIME(3)     NOT NULL,
  status      TINYINT         NOT NULL DEFAULT 0 COMMENT '0待执行 1已执行 2已取消',
  retry_count INT             NOT NULL DEFAULT 0,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_type_biz (task_type, biz_no),
  KEY idx_status_execute (status, execute_at)
) ENGINE=InnoDB COMMENT='延迟任务兜底表';
```

### 5.4 索引设计说明（数据库原理课程考察点）

| 索引 | 类型 | 支撑的查询 | 设计理由 |
| --- | --- | --- | --- |
| `shop_order.uk_order_no` | 唯一二级索引 | `WHERE order_no = ?` | 业务主键查询，唯一性同时保证订单号不重复 |
| `shop_order.uk_user_idem` | **唯一复合索引** | 防重复下单 | 数据库级幂等兜底；即使应用层 Redis 令牌失效，重复请求也会撞 `Duplicate entry` |
| `shop_order.idx_user_status_id` | 复合索引 `(user_id, status, id DESC)` | 「我的订单」列表 | **最左前缀原则**：`user_id` 等值 → `status` 等值 → `id` 排序，三段全部走索引，避免 `filesort`。若只建 `(user_id)`，`ORDER BY id DESC` 仍需回表排序 |
| `shop_order.idx_status_expire` | 复合索引 `(status, expire_at)` | 超时扫描 `WHERE status='PENDING_PAYMENT' AND expire_at < NOW()` | 待支付订单占全表比例小，此索引选择性高，扫描范围可控 |
| `shop_inventory` 主键 = `sku_id` | 聚簇索引 | 所有库存操作 | **主键即业务键**，扣减时 `WHERE sku_id = ?` 直接定位聚簇索引叶子页，**只加一把行锁，不产生二级索引回表和额外锁**，这是把库存表设计成「热点写入友好」的关键 |
| `shop_inventory_ledger.uk_biz` | **唯一复合索引** `(biz_type, biz_no, sku_id)` | 幂等 | 同一订单对同一 SKU 的同类库存操作物理上只能记录一次 |
| `shop_payment_notify_log.uk_channel_notify` | 唯一复合索引 | 支付回调防重 | 重复通知在 `INSERT` 时被数据库拒绝，应用层直接返回 success |
| `shop_cart_item.uk_user_sku` | 唯一复合索引 | `INSERT ... ON DUPLICATE KEY UPDATE` | 使「加购已存在商品则累加数量」成为一条原子 SQL，无需先查后写（消除 TOCTOU 竞态） |
| `shop_product.idx_category_status_sale` | 复合索引 | 分类页按销量排序 | 覆盖 `WHERE category_id=? AND status=1 ORDER BY sale_count DESC` |

**刻意不建的索引及理由：**

- `shop_inventory` 上**不建任何二级索引**。库存表只有一种访问方式（按 `sku_id` 主键），每多一个二级索引就多一份写入时的索引维护开销与锁范围，对最热的写入点是纯损失。
- `shop_order_item.product_name` 等快照字段**不建索引**，后台搜索走 `shop_product` 表。

---

## 6. 【重点】并发一致性设计

> 本章是整个项目的技术核心，回应用户的明确要求：**「你需要额外给我展示你的逻辑保证数据不会错乱」**。

### 6.1 问题定义：超卖是怎么产生的

假设 SKU #1001（"Whiskey Sour 礼盒装"）**只剩 1 件库存**，用户 A 和用户 B 在同一毫秒各自下单买 1 件。

#### 6.1.1 错误实现（先查后写，无任何并发控制）

```java
// ❌ 这是错误的代码，仅用于说明问题
public void createOrder(long skuId, int qty) {
    Inventory inv = inventoryMapper.selectById(skuId);   // (1) 读
    if (inv.getAvailableStock() < qty) {                 // (2) 判断
        throw new BizException("库存不足");
    }
    inv.setAvailableStock(inv.getAvailableStock() - qty);
    inventoryMapper.updateById(inv);                     // (3) 写回
    orderMapper.insert(buildOrder(skuId, qty));
}
```

#### 6.1.2 交错执行时序表（超卖如何发生）

| 时刻 | 线程 A（用户 A） | 线程 B（用户 B） | 数据库 `available_stock` | 说明 |
| --- | --- | --- | --- | --- |
| T1 | `SELECT available_stock` → 读到 **1** | — | 1 | |
| T2 | — | `SELECT available_stock` → 读到 **1** | 1 | **B 读到了 A 尚未写回的旧值** |
| T3 | 判断 `1 >= 1` ✅ 通过 | — | 1 | |
| T4 | — | 判断 `1 >= 1` ✅ 通过 | 1 | **两个线程都认为有货** |
| T5 | `UPDATE ... SET available_stock = 0` | — | 0 | A 扣减成功 |
| T6 | `INSERT` 订单 A | — | 0 | |
| T7 | — | `UPDATE ... SET available_stock = 0` | **0** | **B 用自己读到的旧值 1 计算出 0 并写回，覆盖了 A 的结果 —— 丢失更新（Lost Update）** |
| T8 | — | `INSERT` 订单 B | 0 | |
| **结果** | 订单 A 成立 | 订单 B 成立 | 库存显示 0 | **🔴 卖出 2 件，实际只有 1 件 → 超卖 1 件** |

若把 `UPDATE` 改成 `SET available_stock = available_stock - 1`（数据库端自减），库存会变成 **-1**，问题从「丢失更新」变成「库存为负」，本质仍是**缺少「检查」与「扣减」的原子性**。

#### 6.1.3 问题的本质

> 超卖的根源是 **TOCTOU（Time-Of-Check to Time-Of-Use）竞态**：
> 「检查库存是否充足」和「扣减库存」是两个分离的步骤，在两者之间存在时间窗口，其它事务可以插入并改变前提条件。
>
> **解决超卖的唯一正确思路：让「检查」和「扣减」在同一个原子操作内完成，或者在检查后持有锁直到扣减完成。**

#### 6.1.4 与超卖对偶的问题：库存冗余（少卖）

用户同样明确要求「不能出现库存冗余」。库存冗余（幽灵库存）指**实际有货但系统显示无货**，成因：

| 成因 | 场景 | 后果 |
| --- | --- | --- |
| 锁定后未释放 | 用户下单锁了库存，然后放弃支付，若无超时释放机制，这批库存永远被占 | 卖不出去 |
| 取消/退款时忘记回补 | 退款成功但库存没加回来 | 卖不出去 |
| 回补重复执行 | 退款回调重复 3 次，库存被加了 3 次 | **反向错乱：凭空多出库存，最终导致超卖** |
| Redis 预扣减成功但 MySQL 事务回滚，Redis 未回补 | 系统异常 | Redis 显示无货，MySQL 显示有货 |
| 定时任务与消息队列重复关单 | 双通道都执行了释放 | 库存被释放两次 |

> **因此，一致性设计必须同时满足「不多卖」和「不少卖」，其技术手段是：原子扣减（防多卖）+ 超时释放（防锁死）+ 幂等（防重复回补）+ 台账对账（可发现、可修复）。**

### 6.2 方案对比

以下 5 种方案，逐个分析。

---

#### 方案 1：悲观锁 `SELECT ... FOR UPDATE`

```sql
BEGIN;
SELECT available_stock FROM shop_inventory WHERE sku_id = 1001 FOR UPDATE;  -- 加排他行锁
-- 应用层判断 available_stock >= qty
UPDATE shop_inventory SET available_stock = available_stock - 1, locked_stock = locked_stock + 1
  WHERE sku_id = 1001;
INSERT INTO shop_order ...;
COMMIT;  -- 锁在此释放
```

| 维度 | 评价 |
| --- | --- |
| **正确性** | ✅ 绝对正确。InnoDB 对 `sku_id = 1001` 加 X 行锁，其它事务的 `FOR UPDATE` 会阻塞排队，检查与扣减之间没有任何窗口 |
| **优点** | ① 逻辑最直观，最好理解和讲解；② 可以在锁内做任意复杂的多步判断（比如同时校验多个 SKU、校验用户限购）；③ 天然支持多商品下单的一致性 |
| **缺点** | ① **锁持有时间 = 整个事务时长**。事务里还要 `INSERT` 订单、明细、流水，如果这中间有网络 IO 或慢 SQL，锁就一直不放；② 同一 SKU 的请求**完全串行化**，吞吐上限 ≈ 1 / 事务耗时。若事务 10ms，则该 SKU 最高 100 QPS；③ 高并发下大量线程阻塞在锁上，占满数据库连接池，**引发雪崩**；④ 多 SKU 下单时若不按固定顺序加锁，会**死锁** |
| **适用场景** | 中低并发（< 200 QPS/SKU）、业务逻辑复杂、正确性要求极高的场景（如金融）；或作为 Redis 失效时的**降级方案** |
| **死锁规避** | 多 SKU 必须**按 `sku_id` 升序**加锁（`ORDER BY sku_id` 后依次 `FOR UPDATE`），破坏死锁的「循环等待」条件 |

---

#### 方案 2：乐观锁 —— 版本号 vs 条件 CAS

**2a. 版本号乐观锁：**

```sql
-- 第 1 步：读出当前版本
SELECT available_stock, version FROM shop_inventory WHERE sku_id = 1001;   -- 得到 stock=1, version=57
-- 第 2 步：带版本号更新
UPDATE shop_inventory
   SET available_stock = available_stock - 1, locked_stock = locked_stock + 1, version = version + 1
 WHERE sku_id = 1001 AND version = 57;
-- 影响行数 = 0 → 说明期间被别人改过 → 重试或失败
```

**2b. 条件 CAS（推荐写法）：**

```sql
UPDATE shop_inventory
   SET available_stock = available_stock - #{qty},
       locked_stock    = locked_stock    + #{qty},
       version         = version + 1
 WHERE sku_id = #{skuId}
   AND available_stock >= #{qty};      -- ★★★ 检查与扣减合并成一条原子语句 ★★★
-- 影响行数 = 1 → 扣减成功；= 0 → 库存不足（或并发抢完了）
```

| 维度 | 评价 |
| --- | --- |
| **正确性** | ✅ **绝对正确**。这是本方案的关键洞察：InnoDB 执行 `UPDATE` 时会对匹配行加 X 锁，`WHERE available_stock >= qty` 的判断是在**持有行锁的状态下**、在存储引擎层完成的。所以「检查」和「扣减」天然原子，不存在 TOCTOU 窗口 |
| **2b 相比 2a 的优势** | 版本号方案在高并发下**重试率极高**（100 个并发只有 1 个成功，其余 99 个 version 都过期需重试，形成活锁）；条件 CAS **不需要重试** —— 影响行数 0 就直接返回「库存不足」，语义完全正确，因为库存确实在那一刻不足 |
| **优点** | ① 无显式锁等待，**锁只在这一条 UPDATE 语句执行期间持有（微秒级）**，远短于悲观锁的整个事务；② 单条 SQL，代码极简；③ 吞吐比悲观锁高一个数量级 |
| **缺点** | ① 所有请求仍然打到 MySQL，热点行仍是串行更新（InnoDB 行锁），**单行更新极限约 1000–3000 TPS**；② 万级并发时数据库仍会成为瓶颈；③ 无法在同一条语句里表达跨 SKU 的复合条件 |
| **适用场景** | **中高并发的通用最佳实践**。是本项目的**最终裁决者** |

> **重要结论（必须理解）**：`UPDATE ... WHERE available_stock >= n` 这一条语句，**本身就已经杜绝了超卖**。后面的 Redis、消息队列都只是为了**提升吞吐**，不是为了「保证正确」。把这个认知讲清楚，是本文档的核心价值。

---

#### 方案 3：Redis 预扣减 + 异步落库

```
用户请求 → Redis Lua 脚本原子 DECRBY（不足则返回 -1）→ 成功者写入消息队列 → 消费者异步写 MySQL 订单
```

| 维度 | 评价 |
| --- | --- |
| **正确性** | ⚠️ **Redis 单机是单线程执行命令的，Lua 脚本原子执行，所以 Redis 内部不会超卖**。但存在两类风险：① Redis 与 MySQL 的最终一致性问题（Redis 扣了，MySQL 落库失败）；② Redis 数据丢失（AOF 未刷盘时宕机）导致库存凭空恢复 |
| **优点** | ① **吞吐极高**，单机 Redis 轻松 10 万 QPS；② 把 99% 注定失败的请求（库存已抢空）挡在数据库之外，**这是它最大的价值**；③ 用户可以立刻得到「已抢到」的响应 |
| **缺点** | ① **完全异步落库会带来「用户看到下单成功但订单不存在」的体验灾难**；② 需要额外的对账补偿机制；③ Redis 宕机需要有降级预案；④ 架构复杂度显著上升 |
| **适用场景** | 秒杀、抢购等**瞬时超高并发**场景 |
| **本项目的取舍** | **采用 Redis 预扣减，但不采用完全异步落库**。改为「Redis 预扣减 + **同步** MySQL 事务」：Redis 只做流量漏斗，MySQL 事务在同一个请求里同步完成，用户拿到的就是真实的订单号。这样既获得了 Redis 的挡流量收益，又避免了异步落库的一致性噩梦 |

---

#### 方案 4：分布式锁（Redisson）

```java
RLock lock = redissonClient.getLock("lock:stock:" + skuId);
if (lock.tryLock(200, 3000, TimeUnit.MILLISECONDS)) {
    try { /* 查库存、扣减、下单 */ } finally { lock.unlock(); }
}
```

| 维度 | 评价 |
| --- | --- |
| **正确性** | ✅ 正确（Redisson 有看门狗自动续期，用 Lua 保证解锁的原子性，避免误删他人的锁） |
| **优点** | ① 可以保护「任意复杂的、无法用单条 SQL 表达的临界区」；② 多实例部署时依然有效；③ 相比数据库行锁，锁压力从 MySQL 转移到 Redis |
| **缺点** | ① **对单纯的库存扣减是过度设计** —— 既然一条 CAS SQL 就能原子完成，加分布式锁纯属多余开销；② 引入锁超时、续期、脑裂（Redis 主从切换时锁失效）等复杂问题；③ 同 SKU 请求仍然串行 |
| **适用场景** | **不用于库存扣减**。本项目仅在两处使用：① **缓存击穿防护**（热点商品缓存失效时，只放一个线程回源数据库）；② **定时任务防重**（多实例部署时保证只有一个实例执行超时扫描） |

---

#### 方案 5：消息队列削峰

| 维度 | 评价 |
| --- | --- |
| **正确性** | ⚠️ MQ 本身不保证不超卖，仍需在消费端做原子扣减。MQ 解决的是「流量峰值」而非「并发正确性」 |
| **优点** | ① 削峰填谷，保护下游数据库；② 天然的重试与死信队列；③ 系统解耦 |
| **缺点** | ① 引入 RocketMQ/Kafka/RabbitMQ 需要额外部署运维，**对不熟悉 Java 的用户是很重的负担**；② 异步化导致用户无法立即得到结果，前端要做轮询或推送；③ 消息重复投递需要消费端幂等 |
| **适用场景** | 真正的秒杀级流量（万级 QPS）；或跨服务解耦 |
| **本项目的取舍** | **不引入独立 MQ 中间件**（超出课程范围且增加环境复杂度）。但**保留 MQ 的两个核心能力**，用 Redis 实现：① **延迟队列**用 Redisson `RDelayedQueue` 实现超时关单；② **异步解耦**用 Spring `@Async` + `@TransactionalEventListener` 处理非关键路径（销量统计、缓存刷新）。这样既拿到了收益，又不增加部署负担。**在文档中说明：若未来流量提升，接入 RocketMQ 只需替换延迟队列实现，架构无需改动** |

---

#### 方案对比总表

| 方案 | 防超卖 | 吞吐量 | 实现复杂度 | 学习成本 | 运维成本 | 本项目采用 |
| --- | :---: | :---: | :---: | :---: | :---: | --- |
| 1. 悲观锁 `FOR UPDATE` | ✅ 绝对 | ★☆☆☆☆ | ★☆☆☆☆ | 低 | 无 | **降级备用**（Redis 不可用时） |
| 2b. 条件 CAS `WHERE stock >= n` | ✅ 绝对 | ★★★☆☆ | ★☆☆☆☆ | 低 | 无 | ✅ **最终裁决者（核心）** |
| 2a. 版本号乐观锁 | ✅ | ★★☆☆☆ | ★★☆☆☆ | 中 | 无 | ❌（高并发重试率过高）；`version` 字段保留用于审计 |
| 3. Redis 预扣减 | ⚠️ 需配合 | ★★★★★ | ★★★★☆ | 中高 | 中 | ✅ **前置漏斗**（同步落库版） |
| 4. Redisson 分布式锁 | ✅ | ★★☆☆☆ | ★★★☆☆ | 中 | 中 | ✅ 仅用于缓存击穿 + 定时任务防重 |
| 5. 消息队列削峰 | ❌ 不直接解决 | ★★★★★ | ★★★★★ | 高 | 高 | ❌ 不引入独立 MQ；用 Redis 延迟队列替代 |

### 6.3 ★ 推荐方案

> **「Redis 原子预扣减做漏斗 + MySQL 条件 CAS 做闸门 + 唯一索引做幂等 + 库存台账做对账 + 延迟队列做超时释放」**
>
> 一句话概括其正确性论证：
> **系统的正确性只依赖于 MySQL 的一条 SQL —— `UPDATE shop_inventory SET available_stock = available_stock - n WHERE sku_id = ? AND available_stock >= n`。这条语句在 InnoDB 行锁保护下把「检查」和「扣减」合并为原子操作，因此无论上游 Redis 是否准确、是否宕机、是否被绕过，可售库存都不可能被扣成负数。Redis 只影响吞吐量，不影响正确性。**

这个设计的**分层防御结构**：

```
第 0 层：前端防抖（按钮置灰 + idempotencyKey）      →  减少无效请求，不保证正确性
第 1 层：Redis Lua 原子预扣减                       →  挡掉 99% 注定失败的请求，不保证正确性
第 2 层：★ MySQL 条件 CAS UPDATE                    →  ★ 正确性的唯一来源，保证不超卖
第 3 层：MySQL CHECK 约束 (available_stock >= 0)    →  数据库物理兜底，任何 bug 都写不进负库存
第 4 层：唯一索引 (uk_biz / uk_user_idem)           →  保证幂等，防重复扣减/回补
第 5 层：库存流水台账 + 定时对账 SQL                  →  可发现、可审计、可修复
```

> 这就是回答「你怎么保证数据不会错乱」的完整答案：**不依赖任何单点，而是层层设防，且最关键的一层放在数据库内部 —— 因为数据库是唯一一个所有并发请求都必须经过、且自身具备锁与约束能力的组件。**

### 6.4 推荐方案完整执行流程

#### 6.4.1 下单（FR-ORD-01）完整时序

```mermaid
sequenceDiagram
    participant U as 用户浏览器
    participant C as OrderController
    participant S as OrderService
    participant R as Redis
    participant M as MySQL
    participant Q as Redisson 延迟队列

    U->>C: POST /api/v1/orders  {items, idempotencyKey}
    C->>C: JWT 验签 → userId
    C->>S: createOrder(userId, cmd)

    Note over S,R: ① 幂等令牌（防重复提交）
    S->>R: SET idem:order:{userId}:{key} "PROCESSING" NX EX 600
    alt 已存在
        R-->>S: false
        S->>M: SELECT order_no FROM shop_order WHERE user_id=? AND idempotency_key=?
        S-->>U: 200 返回已有 orderNo（幂等）
    end

    Note over S,M: ② 校验 SKU 有效性 + 计算金额（读缓存/DB）
    S->>R: MGET shop:sku:{id}...
    S->>S: 校验上架状态、计算 payAmount

    Note over S,R: ③ ★ Redis Lua 原子批量预扣减（全成功或全失败）
    S->>R: EVAL deduct_stock.lua KEYS=[stock:1001, stock:1002] ARGV=[2, 1, orderNo]
    alt 任一 SKU 不足
        R-->>S: {-1, skuId}
        S-->>U: 409 STOCK_NOT_ENOUGH (skuId)
    end
    R-->>S: {1, ...}  预扣成功

    Note over S,M: ④ ★★★ MySQL 事务（正确性的唯一来源）★★★
    S->>M: BEGIN
    loop 按 sku_id 升序（防死锁）
        S->>M: UPDATE shop_inventory SET available=available-n, locked=locked+n<br/>WHERE sku_id=? AND available>=n
        alt affectedRows = 0
            M-->>S: 0
            S->>M: ROLLBACK
            S->>R: EVAL rollback_stock.lua （回补 Redis）
            S-->>U: 409 STOCK_NOT_ENOUGH
        end
        S->>M: INSERT shop_inventory_ledger (ORDER_LOCK, orderNo, skuId, ...)
    end
    S->>M: INSERT shop_order (status=PENDING_PAYMENT, expire_at=NOW()+15min)
    S->>M: INSERT shop_order_item × N
    S->>M: INSERT shop_order_status_log (NULL→PENDING_PAYMENT, CREATE)
    S->>M: DELETE FROM shop_cart_item WHERE user_id=? AND sku_id IN (...)
    S->>M: COMMIT

    Note over S,Q: ⑤ 事务提交后（AFTER_COMMIT）才做的副作用
    S->>Q: offer(orderNo, 15分钟)  投递延迟关单
    S->>M: INSERT shop_delay_task (CLOSE_ORDER, orderNo, expire_at)  兜底
    S->>R: SET idem:order:{userId}:{key} = orderNo EX 86400

    S-->>U: 200 {orderNo, payAmount, expireAt}
```

#### 6.4.2 Redis Lua 原子预扣减脚本

```lua
-- deduct_stock.lua
-- KEYS[1..N]   : shop:stock:{skuId}   （Redis String，值为可售库存数）
-- ARGV[1..N]   : 对应的扣减数量
-- ARGV[N+1]    : orderNo（用于写入回滚追踪 key）
-- 返回: {1}            全部扣减成功
--       {-1, index}    第 index 个 SKU 库存不足（已回滚本次所有扣减）
--       {-2, index}    第 index 个 SKU 的库存 key 不存在（需回源 MySQL 重建）

local n = #KEYS
local orderNo = ARGV[n + 1]

-- 阶段一：只检查，不修改（避免部分扣减后回滚的开销）
for i = 1, n do
    local cur = redis.call('GET', KEYS[i])
    if cur == false then
        return {-2, i}
    end
    if tonumber(cur) < tonumber(ARGV[i]) then
        return {-1, i}
    end
end

-- 阶段二：全部扣减（Lua 脚本在 Redis 中单线程原子执行，
--          阶段一与阶段二之间不可能被其它命令插入）
for i = 1, n do
    redis.call('DECRBY', KEYS[i], ARGV[i])
end

-- 记录本次预扣详情，供异常回滚与对账使用（TTL 30 分钟 > 订单 15 分钟超时）
local trackKey = 'shop:deduct:' .. orderNo
for i = 1, n do
    redis.call('HSET', trackKey, KEYS[i], ARGV[i])
end
redis.call('EXPIRE', trackKey, 1800)

return {1}
```

**为什么阶段一和阶段二要分开？**
如果边检查边扣减，当第 3 个 SKU 库存不足时，前 2 个已经扣掉了，必须补偿回滚。分成两阶段后，因为 Lua 在 Redis 中是**原子执行**的（Redis 命令处理是单线程的，脚本执行期间不会有其它命令插入），检查阶段的结论在扣减阶段依然成立，所以「全成功或全不动」得到保证，无需补偿。

#### 6.4.3 MySQL 扣减 SQL（正确性的核心）

```xml
<!-- InventoryMapper.xml -->
<update id="lockStock">
    UPDATE shop_inventory
       SET available_stock = available_stock - #{qty},
           locked_stock    = locked_stock    + #{qty},
           version         = version + 1
     WHERE sku_id          = #{skuId}
       AND available_stock &gt;= #{qty}
</update>
```

**逐句解释它为什么绝对不会超卖：**

1. InnoDB 执行 `UPDATE` 时，会先通过主键 `sku_id` 定位到聚簇索引上的那一行，并对该行加 **X（排他）行锁**。
2. 加锁之后，才在**当前读（current read）**语义下读取该行的最新值，评估 `available_stock >= qty` 条件。
3. 条件成立才执行 SET，然后释放锁（事务提交时）。
4. 因此，从「读到 `available_stock` 的值」到「写回新值」之间，这一行被排他锁独占，**任何其它事务都无法在这个窗口内修改它**。
5. 并发的第二个事务会阻塞在行锁上，等第一个提交后才能执行，此时它读到的是**已经被扣减后的最新值**，条件判断自然失败，`affectedRows = 0`。
6. **即使写错了应用层代码，`CHECK (available_stock >= 0)` 约束也会在存储引擎层抛出错误并回滚整个事务。**

**多 SKU 下单的死锁防护：**

```java
// ★ 必须按 skuId 升序加锁，破坏死锁的「循环等待」条件
List<OrderItemCmd> sorted = cmd.getItems().stream()
        .sorted(Comparator.comparing(OrderItemCmd::getSkuId))
        .toList();
for (OrderItemCmd item : sorted) {
    int affected = inventoryMapper.lockStock(item.getSkuId(), item.getQuantity());
    if (affected == 0) {
        throw new StockNotEnoughException(item.getSkuId());   // 触发事务回滚
    }
    inventoryLedgerMapper.insert(Ledger.orderLock(item, orderNo));
}
```

> 若不排序：事务 A 锁 `sku=1001` 再等 `sku=1002`，事务 B 锁 `sku=1002` 再等 `sku=1001` → 循环等待 → InnoDB 死锁检测触发，其中一方被回滚（`Deadlock found when trying to get lock`）。排序后所有事务都按同一顺序申请锁，**数学上不可能形成环**。

#### 6.4.4 Redis 与 MySQL 不一致时的自愈

| 场景 | 现象 | 处理 |
| --- | --- | --- |
| Redis 扣了，MySQL CAS 失败 | Redis 比 MySQL 少（保守，不会超卖） | `catch` 块中执行 `rollback_stock.lua` 回补；即使回补失败，也只是少卖，由定时对账任务修正 |
| Redis 扣了，MySQL 成功，但返回给用户前服务崩溃 | 订单已存在，用户不知道 | 用户重试时命中 `uk_user_idem` 唯一索引 / Redis 幂等键，返回原订单 |
| Redis key 丢失（宕机重启） | 返回 `-2` | 服务侧加 Redisson 锁，回源 MySQL 用 `available_stock` 重建 key（`SET NX`），然后重试一次 |
| Redis 整体不可用 | Lua 调用抛异常 | **降级开关**：`stock.redis.enabled=false`，直接走 MySQL CAS 路径。**吞吐下降但正确性不变** |
| 长期漂移 | Redis 与 MySQL 数值不等 | 每 5 分钟定时任务：`SET shop:stock:{skuId} = (SELECT available_stock FROM shop_inventory WHERE sku_id=?)`，**以 MySQL 为准强制覆盖**（MySQL 才是 Source of Truth） |

```java
// 异常回滚必须放在 catch 里，且回滚失败不能影响主流程的异常抛出
try {
    orderTxService.doCreateOrderInTransaction(cmd, orderNo);   // @Transactional 方法
} catch (Exception e) {
    try {
        redisStockService.rollback(orderNo);   // 执行 rollback_stock.lua
    } catch (Exception re) {
        log.error("Redis 库存回补失败，等待定时对账修正. orderNo={}", orderNo, re);
        // 不 rethrow：MySQL 已回滚，数据是正确的，Redis 偏保守只会少卖
    }
    throw e;
}
```

```lua
-- rollback_stock.lua：按 orderNo 追踪 key 精确回补，天然幂等（回补后立即删除追踪 key）
local trackKey = 'shop:deduct:' .. ARGV[1]
local data = redis.call('HGETALL', trackKey)
if #data == 0 then return 0 end          -- 已回补过或从未扣减 → 幂等返回
for i = 1, #data, 2 do
    redis.call('INCRBY', data[i], tonumber(data[i + 1]))
end
redis.call('DEL', trackKey)              -- ★ 删除追踪 key 保证不会重复回补
return 1
```

### 6.5 库存字段的三段式模型

#### 6.5.1 模型定义

| 字段 | 含义 | 谁能消耗它 |
| --- | --- | --- |
| `total_stock` | 总库存 = 仓库里的实物总数 | 仅入库/报损改变 |
| `available_stock` | **可售库存**，能被新订单占用 | 下单锁定 |
| `locked_stock` | **已锁定**，已下单但未支付，实物还在但不能再卖 | 支付确认 / 取消释放 |
| `sold_stock` | **已售出**，已支付，等待发货或已发货 | 退货回补 |

**核心不变式（Invariant）：**

```
available_stock + locked_stock + sold_stock = total_stock
且  available_stock >= 0, locked_stock >= 0, sold_stock >= 0
```

这两条不变式**直接写成了 MySQL 的 `CHECK` 约束**（见 5.3 节表 6）。这意味着：**任何一次违反守恒的写入都会被数据库直接拒绝并回滚事务，无论代码里有什么 bug。** 这是本设计最有力的一道保险。

#### 6.5.2 状态流转表

| 操作 | 触发时机 | `available` | `locked` | `sold` | `total` | 台账 `biz_type` | 幂等键 |
| --- | --- | :---: | :---: | :---: | :---: | --- | --- |
| 初始入库 | 创建 SKU | `+N` | 0 | 0 | `+N` | `INIT` | skuId |
| 管理员补货 | 补货 | `+N` | 0 | 0 | `+N` | `RESTOCK` | adjustNo |
| **下单锁定** | 创建订单 | `-n` | `+n` | 0 | 不变 | `ORDER_LOCK` | orderNo |
| **支付确认** | 支付回调成功 | 0 | `-n` | `+n` | 不变 | `PAY_CONFIRM` | orderNo |
| **用户取消** | 主动取消 | `+n` | `-n` | 0 | 不变 | `ORDER_CANCEL` | orderNo |
| **超时关单** | 15 分钟未付 | `+n` | `-n` | 0 | 不变 | `ORDER_EXPIRE` | orderNo |
| **退货入库** | 退款成功且 `restock=1` | `+n` | 0 | `-n` | 不变 | `REFUND_RETURN` | refundNo |
| **仅退款不退货** | 退款成功且 `restock=0` | 0 | 0 | `-n` | `-n` | `REFUND_WRITEOFF` | refundNo |
| 报损 | 管理员操作 | `-n` | 0 | 0 | `-n` | `ADJUST` | adjustNo |

**验证守恒**：观察上表每一行，`Δavailable + Δlocked + Δsold` 恒等于 `Δtotal`。这不是巧合，而是设计约束 —— **每一个库存操作都必须是「在三段之间搬运」或「同时改变某一段和总量」，绝不允许单独改变某一段而不改总量。**

#### 6.5.3 为什么必须要有 `locked_stock`（而不是下单直接扣 `sold`）

| 若没有三段式（只有一个 `stock` 字段） | 三段式的解决 |
| --- | --- |
| 无法区分「卖掉了」和「有人下单还没付钱」 | `locked` 与 `sold` 分离，运营一眼看出有多少在途订单 |
| 超时关单时，只能 `stock = stock + n`，无法校验「这个 n 到底该不该加」 | `UPDATE ... SET locked = locked - n WHERE locked >= n`，**如果这个订单的库存本就没被锁定，`locked >= n` 会失败**，天然拒绝错误的回补 |
| 无法做「已支付待发货」的仓库拣货单 | 直接查 `sold_stock` |
| 无法审计「账实是否相符」 | 恒等式 + 台账双重校验 |

### 6.6 幂等性设计

> 幂等 = **同一个请求执行 1 次和执行 N 次，对系统状态的影响完全相同。**
> 分布式系统中「网络超时后重试」是常态，没有幂等就一定会数据错乱。

#### 6.6.1 订单号生成

不用 UUID（无序、不可读、做索引差），采用**改良版雪花算法（Snowflake）**：

```
订单号格式（20 位定长字符串）：
  yyyyMMddHHmmss (14位) + 机器码 (2位) + 当秒内自增序列 (4位)
  例：20260903143025 01 0007
```

```java
@Component
public class OrderNoGenerator {
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyyMMddHHmmss");
    @Value("${app.machine-id:01}") private String machineId;
    private final AtomicInteger seq = new AtomicInteger(0);
    private volatile String lastSecond = "";

    public synchronized String next() {
        String now = LocalDateTime.now().format(FMT);
        if (!now.equals(lastSecond)) { lastSecond = now; seq.set(0); }
        int s = seq.incrementAndGet();
        if (s > 9999) { sleepToNextSecond(); return next(); }
        return now + machineId + String.format("%04d", s);
    }
}
```

| 特性 | 说明 |
| --- | --- |
| **单调递增** | 作为 `uk_order_no` 二级索引时插入有序，减少 B+ 树页分裂 |
| **可读** | 客服能直接从订单号看出下单时间 |
| **不可枚举** | 加入机器码与序列，避免用户通过 `orderNo + 1` 遍历他人订单（**同时接口层强制 `AND user_id = ?`**） |
| **兜底** | 即使生成器有 bug 产生重复，`uk_order_no` 唯一索引会直接拒绝插入 |

#### 6.6.2 下单防重（三重防护）

| 层级 | 手段 | 说明 |
| --- | --- | --- |
| **前端** | 进入结算页时 `crypto.randomUUID()` 生成 `idempotencyKey`，请求期间按钮置灰 | 拦截误双击 |
| **Redis** | `SET idem:order:{userId}:{key} PROCESSING NX EX 600` | 分布式环境下拦截并发重复请求；成功后把值改为 `orderNo`，TTL 延长到 24h |
| **MySQL** | `UNIQUE KEY uk_user_idem (user_id, idempotency_key)` | **最终兜底**。Redis 宕机时，第二次请求 `INSERT` 会抛 `DuplicateKeyException`，捕获后查出已有订单返回 |

```java
try {
    orderMapper.insert(order);
} catch (DuplicateKeyException e) {
    // 并发重复提交，返回已存在的订单（幂等语义）
    Order exist = orderMapper.selectByUserIdAndIdemKey(userId, cmd.getIdempotencyKey());
    if (exist != null) return OrderVO.of(exist);
    throw e;
}
```

#### 6.6.3 支付回调重复通知

支付网关（真实的支付宝/微信也一样）会在**未收到 `success` 响应时按 2m/10m/10m/1h/2h/6h/15h 的策略重复通知**，因此重复回调是必然事件。

```java
@Transactional(rollbackFor = Exception.class)
public String handleNotify(PayNotifyDTO dto) {
    // ① 验签（防伪造）
    if (!signService.verify(dto)) { securityLog.warn(...); return "fail"; }

    // ② ★ 第一道幂等：唯一索引拦截重复通知
    try {
        notifyLogMapper.insert(NotifyLog.of(dto));     // uk_channel_notify (channel, notify_id)
    } catch (DuplicateKeyException e) {
        log.info("重复回调，忽略. notifyId={}", dto.getNotifyId());
        return "success";                              // ★ 必须返回 success，否则网关会一直重试
    }

    Payment payment = paymentMapper.selectByPaymentNo(dto.getOutTradeNo());
    if (payment == null) return "fail";

    // ③ ★ 防金额篡改
    if (payment.getAmount().compareTo(dto.getAmount()) != 0) {
        alertService.critical("支付金额不符", dto);
        return "fail";
    }

    // ④ ★ 第二道幂等：CAS 状态流转，只有 PENDING → SUCCESS 才生效
    int n = paymentMapper.markSuccess(payment.getPaymentNo(), dto.getChannelTradeNo());
    // UPDATE shop_payment SET status='SUCCESS', channel_trade_no=?, paid_at=NOW(3)
    //  WHERE payment_no=? AND status='PENDING'
    if (n == 0) { return "success"; }                  // 已处理过，幂等返回

    // ⑤ ★ 第三道幂等：订单状态 CAS
    int m = orderMapper.casStatus(payment.getOrderNo(), "PENDING_PAYMENT", "PAID");
    if (m == 0) {
        // 订单已被超时关闭却收到成功支付 → 异常支付，自动发起原路退款
        Order o = orderMapper.selectByOrderNo(payment.getOrderNo());
        if ("CANCELLED".equals(o.getStatus()) || "CLOSED".equals(o.getStatus())) {
            abnormalPayService.autoRefund(payment);
            return "success";
        }
        return "success";   // 已是 PAID，重复通知
    }

    // ⑥ 库存 locked → sold（幂等由 uk_biz 保证）
    inventoryService.confirmSold(payment.getOrderNo());

    // ⑦ 写状态日志
    statusLogMapper.insert(...);
    return "success";
}
```

> **关键设计**：三道幂等防护是**独立且冗余**的。任何一道单独生效都能保证正确，三道同时存在是为了**在不同的失败模式下都有兜底**（唯一索引防 SQL 级重复，CAS 防状态级重复，台账唯一键防库存级重复）。

#### 6.6.4 退款重复提交

| 环节 | 幂等手段 |
| --- | --- |
| 申请退款 | `UNIQUE KEY uk_user_idem (user_id, idempotency_key)` on `shop_refund` |
| 审核 | `UPDATE shop_refund SET status='AUDITED' WHERE refund_no=? AND status='APPLYING'`，CAS |
| 执行退款 | `UPDATE ... SET status='SUCCESS' WHERE refund_no=? AND status IN ('AUDITED','REFUNDING')`，CAS |
| 网关退款回调 | `UNIQUE KEY uk_channel_refund_no` |
| **库存回补** | `shop_inventory_ledger` 的 `UNIQUE KEY uk_biz (biz_type='REFUND_RETURN', biz_no=refundNo, sku_id)` —— **即使前面所有防护都失效，第二次回补也会在插入台账时被数据库拒绝，整个事务回滚，库存不会多加** |

#### 6.6.5 幂等实现的通用模式

```java
// 统一封装：先插台账（唯一索引），再改库存。顺序不能反！
@Transactional(rollbackFor = Exception.class)
public void applyStockChange(StockChangeCmd cmd) {
    // ★ 先插台账：如果是重复操作，这里直接 DuplicateKeyException，
    //   事务回滚，库存一行都不会被改动
    try {
        ledgerMapper.insert(cmd.toLedger());
    } catch (DuplicateKeyException e) {
        log.info("库存变更已执行过，幂等跳过. bizType={} bizNo={} skuId={}",
                 cmd.getBizType(), cmd.getBizNo(), cmd.getSkuId());
        return;
    }
    int n = inventoryMapper.applyDelta(cmd);   // 带条件 CAS 的 UPDATE
    if (n == 0) throw new StockOperationException("库存变更失败: " + cmd);
}
```

> **为什么必须「先插台账，后改库存」？**
> 如果反过来（先改库存再插台账），在重复请求时库存已经被改了，然后台账插入失败抛异常导致回滚 —— 结果虽然也正确（都回滚了），但会**产生不必要的行锁竞争**（热点行被无意义地锁住又释放）。先插台账则在重复场景下**完全不碰库存热点行**，性能更好，且语义更清晰：「台账是事实的记录，记录不上就不许改状态」。

### 6.7 订单状态机

#### 6.7.1 状态图

```mermaid
stateDiagram-v2
    [*] --> PENDING_PAYMENT : CREATE 下单成功<br/>(库存 available→locked)

    PENDING_PAYMENT --> PAID : PAY 支付成功<br/>(库存 locked→sold)
    PENDING_PAYMENT --> CANCELLED : CANCEL 用户取消<br/>(库存 locked→available)
    PENDING_PAYMENT --> CLOSED : EXPIRE 超时15min<br/>(库存 locked→available)

    PAID --> SHIPPED : SHIP 管理员发货
    PAID --> REFUNDING : REFUND_APPLY 申请退款

    SHIPPED --> COMPLETED : CONFIRM 确认收货<br/>(或发货后7天自动确认)
    SHIPPED --> REFUNDING : REFUND_APPLY 申请退货退款

    COMPLETED --> REFUNDING : REFUND_APPLY 售后期内(7天)申请

    REFUNDING --> REFUNDED : REFUND_DONE 全额退完<br/>(库存 sold→available)
    REFUNDING --> PARTIAL_REFUNDED : REFUND_DONE 部分退款<br/>(库存 sold→available 部分)
    REFUNDING --> PAID : REFUND_REJECT 审核驳回(回到原状态)
    REFUNDING --> SHIPPED : REFUND_REJECT 审核驳回(回到原状态)
    REFUNDING --> COMPLETED : REFUND_REJECT 审核驳回(回到原状态)

    PARTIAL_REFUNDED --> REFUNDING : 再次申请剩余部分

    CANCELLED --> [*]
    CLOSED --> [*]
    REFUNDED --> [*]
    COMPLETED --> [*]
```

#### 6.7.2 合法转移全表

| # | From | Event | To | 触发者 | 库存动作 | 前置校验 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `∅` | CREATE | `PENDING_PAYMENT` | 用户 | available→locked | 库存充足、SKU 上架 |
| 2 | `PENDING_PAYMENT` | PAY | `PAID` | 支付回调 | locked→sold | 金额一致、未过期 |
| 3 | `PENDING_PAYMENT` | CANCEL | `CANCELLED` | 用户 | locked→available | 本人订单 |
| 4 | `PENDING_PAYMENT` | EXPIRE | `CLOSED` | 系统 | locked→available | `expire_at < NOW()` |
| 5 | `PAID` | SHIP | `SHIPPED` | 管理员 | 无 | 有运单号 |
| 6 | `SHIPPED` | CONFIRM | `COMPLETED` | 用户/系统 | 无 | — |
| 7 | `PAID`/`SHIPPED`/`COMPLETED` | REFUND_APPLY | `REFUNDING` | 用户 | 无（申请阶段不动库存） | 在售后期内、可退数量足够 |
| 8 | `REFUNDING` | REFUND_REJECT | 回到申请前状态 | 管理员 | 无 | — |
| 9 | `REFUNDING` | REFUND_DONE（全额） | `REFUNDED` | 系统 | sold→available | 网关退款成功 |
| 10 | `REFUNDING` | REFUND_DONE（部分） | `PARTIAL_REFUNDED` | 系统 | sold→available（部分） | 网关退款成功 |

**非法转移示例（必须拒绝）：** `CLOSED → PAID`、`REFUNDED → SHIPPED`、`CANCELLED → CANCELLED`（第二次取消返回幂等成功而非报错）、`PENDING_PAYMENT → SHIPPED`（跳过支付）。

#### 6.7.3 状态机的代码实现

```java
public enum OrderStatus {
    PENDING_PAYMENT, PAID, SHIPPED, COMPLETED,
    CANCELLED, CLOSED, REFUNDING, PARTIAL_REFUNDED, REFUNDED;
}

@Component
public class OrderStateMachine {
    // Guava Table 或 Map<Pair<Status,Event>, Status>
    private static final Map<String, OrderStatus> TRANSITIONS = Map.ofEntries(
        Map.entry("PENDING_PAYMENT|PAY",    OrderStatus.PAID),
        Map.entry("PENDING_PAYMENT|CANCEL", OrderStatus.CANCELLED),
        Map.entry("PENDING_PAYMENT|EXPIRE", OrderStatus.CLOSED),
        Map.entry("PAID|SHIP",              OrderStatus.SHIPPED),
        Map.entry("SHIPPED|CONFIRM",        OrderStatus.COMPLETED)
        // ...
    );

    public OrderStatus next(OrderStatus from, OrderEvent event) {
        OrderStatus to = TRANSITIONS.get(from.name() + "|" + event.name());
        if (to == null) throw new IllegalStateTransitionException(from, event);
        return to;
    }
}
```

**所有状态流转都必须走 CAS UPDATE，而不是先查再改：**

```sql
UPDATE shop_order
   SET status = #{to}, pay_time = #{now}, version = version + 1
 WHERE order_no = #{orderNo}
   AND status = #{from}        -- ★ 期望的前置状态，并发冲突时影响行数为 0
```

> 这样做的意义：**状态机的合法性校验从「应用层的 if 判断」下沉到「数据库的原子 CAS」**。即使 10 个线程同时尝试把同一订单从 `PENDING_PAYMENT` 改成 `PAID`，也只有 1 个能成功（`affectedRows = 1`），其余 9 个得到 0 并走幂等返回分支。这消除了「先 SELECT 判断状态、再 UPDATE」之间的竞态窗口。

### 6.8 超时未支付订单的库存自动释放

#### 6.8.1 方案对比

| 方案 | 实时性 | 可靠性 | 复杂度 | 依赖 | 评价 |
| --- | --- | --- | --- | --- | --- |
| **A. 纯定时任务扫描** `WHERE status='PENDING_PAYMENT' AND expire_at < NOW()` | 差（取决于扫描周期，1 分钟粒度） | ✅ 高，服务重启后自动继续 | ★☆☆☆☆ | 无 | 简单可靠，但库存被多占最长 1 分钟 |
| **B. Redis 键过期监听** (`__keyevent@0__:expired`) | 中 | ❌ **不可靠**：Redis 过期事件是「惰性 + 定期采样」删除时才发布，可能延迟数分钟；且是 fire-and-forget，消费者宕机就永久丢失 | ★★☆☆☆ | Redis | **不推荐** |
| **C. Redis ZSet 时间轮** `ZADD delay:close {expireTs} {orderNo}` + 轮询 `ZRANGEBYSCORE` | 好（秒级） | ✅ 数据持久化在 ZSet 中，服务重启不丢 | ★★★☆☆ | Redis | 可行，需自己写轮询与多实例竞争处理 |
| **D. Redisson `RDelayedQueue`** | 好（秒级） | ✅ 底层就是 ZSet + 阻塞队列，Redisson 已处理好多实例分发 | ★★☆☆☆ | Redisson | ✅ **推荐主方案**：API 简单（`offer(msg, 15, MINUTES)`），可靠性好 |
| **E. RocketMQ 延迟消息** | 优 | ✅ 最高 | ★★★★★ | RocketMQ 集群 | 对本项目过重，见 6.2 方案 5 |
| **F. JDK `ScheduledExecutorService` / `DelayQueue`** | 优 | ❌ **纯内存，服务一重启全部丢失** | ★☆☆☆☆ | 无 | **绝不可单独使用** |

#### 6.8.2 ✅ 推荐：D + A 双保险

```
主通道：Redisson RDelayedQueue（秒级精度，覆盖 99.9% 场景）
兜底：  Spring @Scheduled 每 60 秒扫描一次 shop_order + shop_delay_task
        （覆盖 Redis 宕机、消息丢失、服务在投递前崩溃的场景）
```

**关键点：两个通道调用的是同一个幂等方法，重复执行完全无害。**

```java
@Component
@RequiredArgsConstructor
public class OrderCloseWorker {

    private final RedissonClient redisson;
    private final OrderService orderService;

    /* ---------- 主通道：延迟队列消费者 ---------- */
    @PostConstruct
    public void startConsumer() {
        RBlockingQueue<String> queue = redisson.getBlockingQueue("queue:order:close");
        redisson.getDelayedQueue(queue);            // 绑定延迟队列
        Thread worker = new Thread(() -> {
            while (!Thread.currentThread().isInterrupted()) {
                try {
                    String orderNo = queue.take();  // 阻塞直到有到期消息
                    orderService.closeExpiredOrder(orderNo, "TIMEOUT_DELAY_QUEUE");
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } catch (Exception e) {
                    log.error("延迟关单失败", e);    // 不中断循环，兜底任务会补
                }
            }
        }, "order-close-worker");
        worker.setDaemon(true);
        worker.start();
    }

    /* ---------- 兜底通道：定时扫描 ---------- */
    @Scheduled(fixedDelay = 60_000)
    public void scanExpired() {
        // 多实例部署时用分布式锁保证只有一个实例执行
        RLock lock = redisson.getLock("lock:job:scan-expired-order");
        if (!lock.tryLock()) return;
        try {
            List<String> orderNos = orderMapper.selectExpiredPendingOrders(500);  // 走 idx_status_expire
            for (String orderNo : orderNos) {
                try {
                    orderService.closeExpiredOrder(orderNo, "TIMEOUT_SCAN_FALLBACK");
                } catch (Exception e) {
                    log.error("兜底关单失败 orderNo={}", orderNo, e);
                }
            }
        } finally {
            lock.unlock();
        }
    }
}
```

```java
/* ---------- 幂等的关单逻辑（两个通道共用） ---------- */
@Transactional(rollbackFor = Exception.class)
public void closeExpiredOrder(String orderNo, String reason) {
    // ★ CAS：只有仍处于 PENDING_PAYMENT 才关单。
    //   如果用户刚好在这一瞬间支付成功，状态已变为 PAID，这里影响行数为 0，直接返回。
    //   这就消除了「关单」与「支付」的经典竞态。
    int n = orderMapper.casStatus(orderNo, "PENDING_PAYMENT", "CLOSED", reason);
    if (n == 0) {
        log.info("订单无需关闭（已支付或已关闭）. orderNo={}", orderNo);
        return;
    }
    // 释放库存：locked → available（幂等由 uk_biz(ORDER_EXPIRE, orderNo, skuId) 保证）
    inventoryService.releaseLocked(orderNo, BizType.ORDER_EXPIRE);
    statusLogMapper.insert(...);
    // 事务提交后回补 Redis
    TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
        @Override public void afterCommit() { redisStockService.incrByOrder(orderNo); }
    });
}
```

**「关单」与「支付」的竞态分析：**

| 时刻 | 关单线程 | 支付回调线程 | 结果 |
| --- | --- | --- | --- |
| T1 | `UPDATE ... SET status='CLOSED' WHERE status='PENDING_PAYMENT'` 获得行锁 | — | |
| T2 | — | `UPDATE ... SET status='PAID' WHERE status='PENDING_PAYMENT'` **阻塞在行锁上** | |
| T3 | COMMIT，释放锁 | — | 订单已 `CLOSED`，库存已释放 |
| T4 | — | 锁获得，重新读到 `status='CLOSED'`，条件不匹配，`affectedRows = 0` | 支付回调走「异常支付」分支 → **自动原路退款** |

反之若支付先执行，关单的 CAS 会失败，订单保持 `PAID`，库存保持在 `sold`。**无论谁先，结果都正确且唯一。**

> `expire_at` 设置为 `NOW() + 15分钟`，而延迟队列投递 `15分钟 + 5秒` 的延迟。多出的 5 秒缓冲避免「延迟消息比数据库时间早到」导致的误关（数据库与应用服务器时钟可能有毫秒级偏差）。

### 6.9 退货退款的库存回滚（正确姿势）

#### 6.9.1 ❌ 为什么不能简单写 `stock = stock + n`

```sql
-- ❌❌❌ 这行 SQL 有 6 个严重问题
UPDATE shop_inventory SET available_stock = available_stock + 2 WHERE sku_id = 1001;
```

| # | 问题 | 后果 | 具体场景 |
| --- | --- | --- | --- |
| **1** | **不幂等** | 库存凭空增加 | 退款回调重复通知 3 次 → 库存多加 6 件 → **后续超卖 6 件**。用户要求的「不能库存冗余」在这里被直接违反 |
| **2** | **破坏三段式恒等式** | `available + locked + sold ≠ total` | 退货的商品是从 `sold` 回来的，正确做法是 `sold -= n; available += n`（总量不变）。只加 `available` 会让总量凭空变大，`CHECK (available+locked+sold=total)` 约束会直接**报错回滚** —— 数据库替我们挡住了这个 bug |
| **3** | **无任何前置校验** | 可能回补超过实际售出量 | 若 `sold_stock` 只有 1，却回补 2 件，说明业务数据已错乱，但这条 SQL 会无声地执行下去 |
| **4** | **无审计痕迹** | 事后无法追查「这 2 件是哪一笔退款加回来的」 | 对账时发现库存对不上，完全无从查起 |
| **5** | **忽略了「是否应该回补」** | 商品已损坏/已拆封仍回补 | 「仅退款不退货」（`restock=0`）时，商品并没有回到仓库，此时应该是 `sold -= n; total -= n`（核销损失），而不是 `available += n` |
| **6** | **忽略部分退款** | 数量算错 | 一笔订单买了 5 件，只退 2 件；如果代码里写死用 `orderItem.quantity` 就会回补 5 件 |

#### 6.9.2 ✅ 正确实现

```java
@Transactional(rollbackFor = Exception.class)
public void completeRefund(String refundNo, String channelRefundNo) {

    Refund refund = refundMapper.selectForUpdate(refundNo);   // 悲观锁：退款是低频操作，可以用
    if (refund == null) throw new BizException("退款单不存在");

    /* ---------- ① 状态 CAS，防重复执行 ---------- */
    int n = refundMapper.casStatus(refundNo, List.of("AUDITED", "REFUNDING"), "SUCCESS", channelRefundNo);
    if (n == 0) {
        log.info("退款已完成，幂等跳过. refundNo={}", refundNo);
        return;
    }

    /* ---------- ② 累计退款量，带上限 CAS ---------- */
    // UPDATE shop_order_item
    //    SET refunded_quantity = refunded_quantity + #{qty},
    //        refunded_amount   = refunded_amount   + #{amt}
    //  WHERE id = #{itemId}
    //    AND refunded_quantity + #{qty} <= quantity      ★ 防超退
    //    AND refunded_amount   + #{amt} <= total_amount  ★ 防超额退款
    int m = orderItemMapper.accumulateRefund(
            refund.getOrderItemId(), refund.getQuantity(), refund.getRefundAmount());
    if (m == 0) throw new BizException("退款数量或金额超出可退范围");   // 触发整体回滚

    /* ---------- ③ ★ 库存回滚：先写台账（幂等），再改库存 ---------- */
    if (refund.getRestock() == 1) {
        // 退货入库：sold → available，total 不变
        StockChangeCmd cmd = StockChangeCmd.builder()
                .bizType(BizType.REFUND_RETURN)     // ★ 与 biz_no 组成唯一键
                .bizNo(refundNo)
                .skuId(refund.getSkuId())
                .deltaAvailable(+refund.getQuantity())
                .deltaSold(-refund.getQuantity())
                .deltaTotal(0)
                .build();
        inventoryService.applyStockChange(cmd);
    } else {
        // 仅退款不退货（商品已损耗）：核销 sold 和 total
        StockChangeCmd cmd = StockChangeCmd.builder()
                .bizType(BizType.REFUND_WRITEOFF)
                .bizNo(refundNo)
                .skuId(refund.getSkuId())
                .deltaSold(-refund.getQuantity())
                .deltaTotal(-refund.getQuantity())
                .build();
        inventoryService.applyStockChange(cmd);
    }

    /* ---------- ④ 累计订单已退金额，决定订单终态 ---------- */
    orderMapper.accumulateRefunded(refund.getOrderNo(), refund.getRefundAmount());
    Order order = orderMapper.selectByOrderNo(refund.getOrderNo());
    boolean fullyRefunded = order.getRefundedAmount().compareTo(order.getPayAmount()) >= 0;
    orderMapper.casStatus(order.getOrderNo(), "REFUNDING",
            fullyRefunded ? "REFUNDED" : "PARTIAL_REFUNDED");

    statusLogMapper.insert(...);

    /* ---------- ⑤ 事务提交后才回补 Redis ---------- */
    TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
        @Override public void afterCommit() {
            if (refund.getRestock() == 1) {
                redisStockService.incrBy(refund.getSkuId(), refund.getQuantity());
            }
        }
    });
}
```

对应的库存更新 SQL：

```xml
<update id="applyDelta">
    UPDATE shop_inventory
       SET available_stock = available_stock + #{deltaAvailable},
           locked_stock    = locked_stock    + #{deltaLocked},
           sold_stock      = sold_stock      + #{deltaSold},
           total_stock     = total_stock     + #{deltaTotal},
           version         = version + 1
     WHERE sku_id = #{skuId}
       <!-- ★ 每一段变动后都不能为负，条件与扣减在同一条语句内原子完成 -->
       AND available_stock + #{deltaAvailable} &gt;= 0
       AND locked_stock    + #{deltaLocked}    &gt;= 0
       AND sold_stock      + #{deltaSold}      &gt;= 0
       AND total_stock     + #{deltaTotal}     &gt;= 0
</update>
```

#### 6.9.3 正确 vs 错误对照

| 维度 | ❌ `stock = stock + n` | ✅ 本方案 |
| --- | --- | --- |
| 幂等 | 无 | 台账 `uk_biz(REFUND_RETURN, refundNo, skuId)` 唯一索引 |
| 守恒 | 破坏 | `Δavailable + Δlocked + Δsold = Δtotal`，且有 `CHECK` 约束强制 |
| 前置校验 | 无 | `sold_stock + delta >= 0` 在同一条 SQL 内原子校验 |
| 审计 | 无 | 每次变更都有台账行，含变更前后快照 |
| 退货 / 仅退款区分 | 无 | `restock` 字段控制走 `REFUND_RETURN` 还是 `REFUND_WRITEOFF` |
| 部分退款 | 算错 | 用 `refund.quantity`，并用 `refunded_quantity + qty <= quantity` CAS 兜底 |
| Redis 同步 | 时机随意 | 严格在 `afterCommit` 回调中执行 |

### 6.10 Redis 与 MySQL 的数据一致性

#### 6.10.1 三大缓存异常

| 问题 | 定义 | 场景 | 本项目的解决方案 |
| --- | --- | --- | --- |
| **缓存穿透** | 查询**根本不存在**的数据，缓存永远不命中，请求全部打到数据库 | 攻击者遍历 `productId=999999999` | ① **缓存空对象**：查不到时写入 `NULL_PLACEHOLDER`，TTL 60s；② **布隆过滤器**：启动时把全部有效 `productId` 装入 Redisson `RBloomFilter`（1000 万容量，误判率 0.01%），不存在的 ID 直接拒绝，**不消耗任何数据库资源** |
| **缓存击穿** | **某个热点 key** 恰好过期，瞬间大量请求同时回源数据库 | 首页推荐的爆款商品缓存到期 | ① **Redisson 分布式锁 + 双重检查**：只放 1 个线程回源，其余线程等待 50ms 后重读缓存；② **热点 key 逻辑过期**：value 里带 `expireAt` 字段，物理不过期，读到逻辑过期时异步刷新、同步返回旧值（**保证永不阻塞**） |
| **缓存雪崩** | **大量 key 在同一时刻集体过期**，或 Redis 集群整体宕机 | 系统启动时批量预热了缓存，TTL 都是 30 分钟 → 30 分钟后同时失效 | ① **TTL 随机抖动**：`ttl = 基准 + random(0, 基准 * 0.2)`，把过期时间打散；② **多级缓存**：Caffeine 本地缓存（1 分钟）作为 L1，Redis 作为 L2，Redis 挂了 L1 还能扛住一部分；③ **熔断降级**：Resilience4j / 手写开关，Redis 异常率超阈值时直连 MySQL 并限流 |

```java
/* 缓存击穿防护：分布式锁 + 双重检查 */
public ProductDetailVO getDetail(Long productId) {
    String key = "shop:product:detail:" + productId;
    String cached = redis.get(key);
    if (NULL_PLACEHOLDER.equals(cached)) throw new NotFoundException();   // 穿透防护
    if (cached != null) return JSON.parse(cached, ProductDetailVO.class);

    RLock lock = redisson.getLock("lock:product:detail:" + productId);
    try {
        if (!lock.tryLock(500, 3000, TimeUnit.MILLISECONDS)) {
            Thread.sleep(50);
            return getDetail(productId);       // 短暂等待后重读缓存
        }
        // ★ 双重检查：可能在等锁期间已被别的线程填充
        cached = redis.get(key);
        if (cached != null) return JSON.parse(cached, ProductDetailVO.class);

        ProductDetailVO vo = loadFromDb(productId);
        if (vo == null) {
            redis.setex(key, 60, NULL_PLACEHOLDER);            // 穿透防护
            throw new NotFoundException();
        }
        int ttl = 600 + ThreadLocalRandom.current().nextInt(120);  // ★ 雪崩防护：随机抖动
        redis.setex(key, ttl, JSON.toJSONString(vo));
        return vo;
    } finally {
        if (lock.isHeldByCurrentThread()) lock.unlock();
    }
}
```

#### 6.10.2 更新缓存的策略选择

| 策略 | 做法 | 问题 |
| --- | --- | --- |
| 先更新缓存，再更新数据库 | ❌ | 数据库更新失败会导致缓存脏数据，且缓存是易失的，不能作为写入的第一站 |
| 先更新数据库，再更新缓存 | ❌ | 两个写并发时可能后写的先落缓存，产生**写覆盖乱序** |
| 先删缓存，再更新数据库 | ⚠️ | 删缓存后、更新数据库前，若有读请求会把**旧值**重新加载进缓存 |
| **✅ 先更新数据库，再删除缓存（Cache-Aside）** | 推荐 | 仍有极小概率不一致（读线程读到旧值 → 写线程更库删缓存 → 读线程才写入旧值到缓存），概率极低但存在 |

#### 6.10.3 ✅ 本项目采用：Cache-Aside + 延迟双删 + 定时兜底

```java
@Transactional(rollbackFor = Exception.class)
public void updateProduct(ProductUpdateCmd cmd) {
    productMapper.updateById(cmd.toEntity());       // ① 更新数据库

    TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
        @Override public void afterCommit() {
            String key = "shop:product:detail:" + cmd.getProductId();
            redis.del(key);                          // ② 第一次删除（事务提交后）

            // ③ ★ 延迟双删：500ms 后再删一次
            //    覆盖「读线程在 ① 之前读到旧值、在 ② 之后才写回缓存」的极小概率窗口
            scheduler.schedule(() -> redis.del(key), 500, TimeUnit.MILLISECONDS);
        }
    });
}
```

**为什么删除而不是更新缓存？**

1. **Lazy 加载**：更新后不一定马上有人读，更新缓存是浪费；删除后由第一个读请求按需重建。
2. **避免写覆盖乱序**：两个并发写各自更新缓存时无法保证顺序；删除是幂等的，删两次和删一次效果相同。
3. **计算成本**：商品详情 VO 需要 JOIN 多张表拼装，更新时重算不划算。

**为什么必须在 `afterCommit` 里删？**
如果在事务内删缓存，事务还没提交时其它请求读数据库会读到**旧值**并写回缓存，事务提交后缓存里就是脏数据。`afterCommit` 保证「数据库已经是新值」之后才删。

**更强一致的备选方案（本期不实施，文档中说明升级路径）：**

| 方案 | 原理 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **Canal 订阅 binlog** | Canal 伪装成 MySQL Slave，解析 binlog，把变更事件推给缓存刷新服务 | ① **业务代码零侵入**（不用在每个写方法里写删缓存）；② 不会漏删（binlog 是数据库的真实变更记录）；③ 天然有序 | 需部署 Canal Server + MQ，运维成本高 |
| 本期选择 | Cache-Aside + 延迟双删 + **每 10 分钟全量对账刷新** | 零额外组件 | 极端情况下最长 10 分钟不一致 |

> **重要澄清（避免混淆）**：以上「缓存一致性」讨论的对象是**商品详情、分类列表等只读缓存**，容忍秒级不一致，因为它们不参与任何交易判定。
>
> **库存的 Redis 计数不属于「缓存」范畴**，它是「并发漏斗」，其一致性策略完全不同 —— Redis 库存数**永远只需要保证「不大于」MySQL 的真实可售库存**（偏保守），因为它只用来提前拒绝请求，最终裁决权在 MySQL 的 CAS SQL。这个「单向偏保守」的性质，使得 Redis 库存即使不准也**只会少卖不会超卖**，再由定时对账任务修正回来。

#### 6.10.4 库存对账任务

```java
@Scheduled(cron = "0 */5 * * * ?")   // 每 5 分钟
public void reconcileStock() {
    RLock lock = redisson.getLock("lock:job:reconcile-stock");
    if (!lock.tryLock()) return;
    try {
        // ★ 以 MySQL 为唯一事实来源，强制覆盖 Redis
        List<Inventory> all = inventoryMapper.selectAll();
        for (Inventory inv : all) {
            String key = "shop:stock:" + inv.getSkuId();
            String redisVal = redis.get(key);
            if (redisVal == null || Integer.parseInt(redisVal) != inv.getAvailableStock()) {
                log.warn("库存漂移修正 skuId={} redis={} mysql={}",
                         inv.getSkuId(), redisVal, inv.getAvailableStock());
                redis.set(key, String.valueOf(inv.getAvailableStock()));
                metrics.counter("stock.drift").increment();
            }
        }
    } finally { lock.unlock(); }
}
```

> 覆盖时机的考量：直接 `SET` 可能覆盖掉「正在进行中的预扣减」，导致极短时间内 Redis 偏乐观。缓解方式：修正时用 `available_stock - (当前进行中订单锁定数)` 作为写入值，或选择在低峰期执行。**由于最终裁决在 MySQL，即使这一瞬间 Redis 偏乐观，也只会让多余请求穿透到 MySQL 后被 CAS 拒绝，不会超卖。**

### 6.11 事务边界与隔离级别

#### 6.11.1 隔离级别的选择

MySQL InnoDB 默认是 **REPEATABLE READ（RR）**，本项目**显式设置为 READ COMMITTED（RC）**。

```yaml
# application.yml
spring:
  datasource:
    hikari:
      transaction-isolation: TRANSACTION_READ_COMMITTED
```

```sql
-- 或在 my.cnf 中
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW      -- RC 下必须用 ROW 格式，否则主从复制可能不一致
```

| 隔离级别 | 脏读 | 不可重复读 | 幻读 | 对本项目的影响 |
| --- | :---: | :---: | :---: | --- |
| READ UNCOMMITTED | ✅会 | ✅会 | ✅会 | ❌ 绝不使用，会读到未提交的库存 |
| **READ COMMITTED（✅ 采用）** | ❌ | ✅会 | ✅会 | **不可重复读与幻读对本项目无害**，理由见下 |
| REPEATABLE READ（默认） | ❌ | ❌ | ❌（InnoDB 用间隙锁避免） | 间隙锁范围大，并发下**死锁概率显著上升** |
| SERIALIZABLE | ❌ | ❌ | ❌ | 全表串行，吞吐无法接受 |

**为什么选 RC 而不是默认的 RR：**

| # | 理由 | 说明 |
| --- | --- | --- |
| 1 | **RR 的间隙锁（Gap Lock）会大幅增加死锁概率** | RR 下 `UPDATE ... WHERE status='PENDING_PAYMENT' AND expire_at < NOW()` 这类范围条件会锁住一整段索引间隙，阻塞其它事务的插入。RC 下只锁**真正匹配到的行**（严格说是先锁扫描到的行，不匹配的立即释放），锁范围小得多 |
| 2 | **RC 的加锁范围更小 → 并发度更高** | 库存扣减是热点操作，锁范围越小越好 |
| 3 | **本项目的正确性不依赖「可重复读」** | 库存扣减用的是 `UPDATE ... WHERE stock >= n` 这种**当前读（current read）**语义。当前读**在任何隔离级别下都会读取最新已提交数据并加锁**，与快照读的 MVCC 版本无关。所以 RR 提供的「同一事务内多次快照读结果一致」这个特性，对我们的扣减逻辑毫无帮助 |
| 4 | **幻读对本项目无危害** | 我们没有「在同一事务内两次范围查询要求结果集相同」的业务需求 |
| 5 | **主流互联网公司实践** | 阿里、腾讯等大厂的 MySQL 规范普遍要求 RC + ROW binlog |

**必须澄清的一个常见误解：**

> ❌ 误解：「用了 REPEATABLE READ 就不会超卖了。」
> ✅ 事实：**隔离级别与超卖没有直接关系。** RR 保护的是**快照读**（普通 `SELECT`）的一致性视图，而超卖的根源在于「快照读的结果被用于决策，然后再写入」。即使在 SERIALIZABLE 下，如果代码是「先 SELECT 再 UPDATE」，在 MySQL 中也可能因为锁升级而死锁或串行化失败。
>
> **防超卖的正确手段是「原子的条件更新」或「显式加锁」，而不是调隔离级别。** 本项目选 RC 是为了**性能与死锁规避**，正确性由 CAS SQL 独立保证。

#### 6.11.2 事务边界原则

| 原则 | 说明 | 反例 |
| --- | --- | --- |
| **P1：事务要短** | 事务内只做数据库操作，总耗时控制在 **50ms 以内** | ❌ 在 `@Transactional` 方法里调用支付网关 HTTP 接口（网络超时 3s，行锁被占 3s，热点 SKU 直接瘫痪） |
| **P2：外部调用必须移出事务** | HTTP 调用、发消息、发邮件、写 Redis 一律放到事务外或 `afterCommit` | ❌ 事务内 `redis.set(...)`：事务回滚了 Redis 却已经改了 |
| **P3：先做无锁校验，后进事务** | 参数校验、权限校验、金额计算在事务外完成 | ❌ 在事务内做 20 次 SKU 有效性查询 |
| **P4：按固定顺序加锁** | 多 SKU 按 `sku_id` 升序 | ❌ 按用户购物车的原始顺序 → 死锁 |
| **P5：不要在事务内做循环远程调用** | — | — |
| **P6：注意 `@Transactional` 自调用失效** | Spring AOP 基于代理，同类内部方法调用不会走代理，事务注解失效 | ❌ `this.doInTransaction()`；✅ 抽到独立的 `OrderTxService` 类，或用 `AopContext.currentProxy()` |
| **P7：`rollbackFor = Exception.class`** | Spring 默认只对 `RuntimeException` 回滚，**受检异常不回滚** | ❌ `@Transactional`（不写 rollbackFor）方法抛 `IOException` → 事务提交了一半的数据 |

**下单接口的事务边界划分：**

```java
public OrderVO createOrder(Long userId, CreateOrderCmd cmd) {

    /* ===== 事务外（无锁，可以慢） ===== */
    checkIdempotency(userId, cmd);                    // Redis
    List<SkuInfo> skus = skuService.batchGet(cmd);    // 读缓存
    validateSkus(skus, cmd);                          // 纯内存计算
    BigDecimal payAmount = calcAmount(skus, cmd);     // 纯内存计算
    String orderNo = orderNoGenerator.next();
    redisStockService.tryDeduct(cmd, orderNo);        // Redis Lua

    /* ===== 事务内（有锁，必须快 —— 目标 < 50ms） ===== */
    try {
        orderTxService.persist(userId, cmd, orderNo, payAmount);   // ★ 独立 Bean，避免自调用失效
    } catch (Exception e) {
        redisStockService.rollback(orderNo);
        throw e;
    }

    /* ===== 事务后（副作用） ===== */
    delayQueue.offer(orderNo, 15 * 60 + 5, TimeUnit.SECONDS);
    redis.setex("idem:order:" + userId + ":" + cmd.getIdempotencyKey(), 86400, orderNo);
    eventPublisher.publish(new OrderCreatedEvent(orderNo));        // 异步刷新销量等

    return OrderVO.of(orderNo, payAmount);
}
```

### 6.12 一致性验证：三条对账 SQL

这三条 SQL 是向老师证明「数据没有错乱」的**最直接证据**，应在压测后立即执行，并在管理后台提供一键运行（FR-ADM-04）。

```sql
-- ============================================================
-- 校验 1：库存守恒 —— 三段之和必须等于总量
-- 期望结果：0 行
-- ============================================================
SELECT sku_id, total_stock, available_stock, locked_stock, sold_stock,
       (available_stock + locked_stock + sold_stock) AS sum_three,
       (available_stock + locked_stock + sold_stock - total_stock) AS diff
  FROM shop_inventory
 WHERE available_stock + locked_stock + sold_stock <> total_stock;

-- ============================================================
-- 校验 2：库存快照与台账流水一致 —— 快照必须等于所有流水的累加
-- 期望结果：0 行
-- ============================================================
SELECT i.sku_id,
       i.available_stock                        AS snapshot_available,
       COALESCE(l.sum_available, 0)             AS ledger_available,
       i.locked_stock                           AS snapshot_locked,
       COALESCE(l.sum_locked, 0)                AS ledger_locked,
       i.sold_stock                             AS snapshot_sold,
       COALESCE(l.sum_sold, 0)                  AS ledger_sold
  FROM shop_inventory i
  LEFT JOIN (
        SELECT sku_id,
               SUM(delta_available) AS sum_available,
               SUM(delta_locked)    AS sum_locked,
               SUM(delta_sold)      AS sum_sold
          FROM shop_inventory_ledger
         GROUP BY sku_id
  ) l ON l.sku_id = i.sku_id
 WHERE i.available_stock <> COALESCE(l.sum_available, 0)
    OR i.locked_stock    <> COALESCE(l.sum_locked, 0)
    OR i.sold_stock      <> COALESCE(l.sum_sold, 0);

-- ============================================================
-- 校验 3：订单与库存对得上 —— 已支付订单的商品数必须等于 sold_stock
--         （扣除已退货部分）
-- 期望结果：0 行
-- ============================================================
SELECT i.sku_id,
       i.sold_stock AS inventory_sold,
       COALESCE(o.order_sold, 0) AS order_sold
  FROM shop_inventory i
  LEFT JOIN (
        SELECT oi.sku_id,
               SUM(oi.quantity - oi.refunded_quantity) AS order_sold
          FROM shop_order_item oi
          JOIN shop_order od ON od.order_no = oi.order_no
         WHERE od.status IN ('PAID', 'SHIPPED', 'COMPLETED', 'PARTIAL_REFUNDED', 'REFUNDING')
         GROUP BY oi.sku_id
  ) o ON o.sku_id = i.sku_id
 WHERE i.sold_stock <> COALESCE(o.order_sold, 0);

-- ============================================================
-- 校验 4（红线）：任何一段库存为负 —— 若 CHECK 约束生效，永远查不出
-- 期望结果：0 行
-- ============================================================
SELECT * FROM shop_inventory
 WHERE available_stock < 0 OR locked_stock < 0 OR sold_stock < 0 OR total_stock < 0;
```

---

## 7. 接口设计

**统一约定：**

- Base URL：`/api/v1`
- 认证：`Authorization: Bearer <Supabase JWT>`（除公开接口外均必填）
- Content-Type：`application/json; charset=utf-8`
- 统一响应包装：

```json
{
  "code": 0,
  "message": "success",
  "data": { },
  "traceId": "a1b2c3d4e5f6"
}
```

- `code = 0` 表示成功；非 0 为业务错误码（见附录 B）。HTTP 状态码同时也是语义化的（400/401/403/404/409/429/500）。
- 分页响应：`{ "list": [...], "total": 128, "page": 1, "size": 20 }`

### 7.1 商品与库存

| # | 方法 | 路径 | 鉴权 | 说明 |
| --- | --- | --- | --- | --- |
| 1 | GET | `/api/v1/products` | 公开 | 商品列表。Query：`categoryId, keyword, sortBy, page, size` |
| 2 | GET | `/api/v1/products/{productId}` | 公开 | 商品详情（含 SKU 列表） |
| 3 | POST | `/api/v1/skus/stocks/query` | 公开 | **实时库存批量查询**。Body：`{"skuIds":[1001,1002]}` |
| 4 | GET | `/api/v1/categories` | 公开 | 分类列表 |
| 5 | POST | `/api/v1/admin/products` | Admin | 创建商品 + SKU |
| 6 | PUT | `/api/v1/admin/products/{productId}` | Admin | 编辑商品 |
| 7 | PATCH | `/api/v1/admin/products/{productId}/status` | Admin | 上下架 |
| 8 | POST | `/api/v1/admin/skus/{skuId}/stock` | Admin | 补货/调整。Body：`{"delta":50,"reason":"补货","bizNo":"uuid"}` |
| 9 | GET | `/api/v1/admin/skus/{skuId}/ledger` | Admin | 库存流水台账 |
| 10 | GET | `/api/v1/admin/stock/reconcile` | Admin | **一键对账**（执行 6.12 的四条校验 SQL） |

**接口 3 请求/响应示例：**

```http
POST /api/v1/skus/stocks/query
Content-Type: application/json

{ "skuIds": [1001, 1002] }
```

```json
{
  "code": 0, "message": "success",
  "data": [
    { "skuId": 1001, "availableStock": 37, "status": "IN_STOCK" },
    { "skuId": 1002, "availableStock": 3,  "status": "LOW_STOCK" }
  ],
  "traceId": "7f3a9c"
}
```

### 7.2 购物车

| # | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 11 | POST | `/api/v1/cart/items` | 加入购物车 `{"skuId":1001,"quantity":2}` |
| 12 | GET | `/api/v1/cart` | 购物车列表（含实时库存与失效标记） |
| 13 | PUT | `/api/v1/cart/items/{cartItemId}` | 修改数量 `{"quantity":3}` |
| 14 | PATCH | `/api/v1/cart/items/{cartItemId}/selected` | 勾选 `{"selected":true}` |
| 15 | DELETE | `/api/v1/cart/items/{cartItemId}` | 删除条目 |
| 16 | DELETE | `/api/v1/cart/invalid` | 清空失效条目 |

### 7.3 订单

| # | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 17 | **POST** | **`/api/v1/orders`** | **★ 创建订单（核心接口）** |
| 18 | GET | `/api/v1/orders` | 我的订单列表。Query：`status, page, size` |
| 19 | GET | `/api/v1/orders/{orderNo}` | 订单详情 |
| 20 | POST | `/api/v1/orders/{orderNo}/cancel` | 取消订单 |
| 21 | POST | `/api/v1/orders/{orderNo}/confirm` | 确认收货 |
| 22 | POST | `/api/v1/admin/orders/{orderNo}/ship` | Admin 发货 `{"trackingNo":"SF123456"}` |
| 23 | GET | `/api/v1/admin/orders` | Admin 订单检索 |

**接口 17 完整定义：**

```http
POST /api/v1/orders
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
Content-Type: application/json

{
  "items": [
    { "skuId": 1001, "quantity": 2 },
    { "skuId": 1002, "quantity": 1 }
  ],
  "receiverName": "秦野",
  "receiverPhone": "13800138000",
  "receiverAddress": "天津市南开区XX路XX号",
  "remark": "请在晚上7点后配送",
  "idempotencyKey": "3f2b8c1e-9d47-4a6f-8b21-7e0c5a9d1234"
}
```

成功（HTTP 200）：

```json
{
  "code": 0, "message": "success",
  "data": {
    "orderNo": "20260903143025010007",
    "payAmount": 328.00,
    "expireAt": "2026-09-03T14:45:25.000+08:00",
    "items": [
      { "skuId": 1001, "productZhName": "威士忌酸礼盒", "specName": "700ml", "unitPrice": 129.00, "quantity": 2 },
      { "skuId": 1002, "productZhName": "波士顿摇酒壶", "specName": "550ml 银色", "unitPrice": 70.00, "quantity": 1 }
    ]
  },
  "traceId": "7f3a9c1b"
}
```

库存不足（HTTP 409）：

```json
{
  "code": 40901,
  "message": "库存不足",
  "data": { "skuId": 1001, "requested": 2, "available": 1, "productZhName": "威士忌酸礼盒" },
  "traceId": "7f3a9c1b"
}
```

重复提交（HTTP 200，幂等返回）：

```json
{
  "code": 0, "message": "success（幂等返回已有订单）",
  "data": { "orderNo": "20260903143025010007", "payAmount": 328.00, "idempotent": true },
  "traceId": "7f3a9c1c"
}
```

### 7.4 支付

| # | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 24 | POST | `/api/v1/payments` | 发起支付 `{"orderNo":"...","channel":"MOCK_ALIPAY"}` |
| 25 | GET | `/api/v1/payments/{paymentNo}` | 查询支付状态（前端轮询） |
| 26 | **POST** | **`/api/v1/payments/notify/{channel}`** | **支付回调（公开，签名校验）** |
| 27 | POST | `/api/v1/mock-gateway/pay` | 模拟收银台「确认支付」按钮（仅开发/演示环境启用） |

### 7.5 退货退款

| # | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 28 | POST | `/api/v1/refunds` | 申请退款 |
| 29 | GET | `/api/v1/refunds` | 我的退款单列表 |
| 30 | GET | `/api/v1/refunds/{refundNo}` | 退款详情 |
| 31 | POST | `/api/v1/admin/refunds/{refundNo}/audit` | Admin 审核 `{"approved":true,"restock":true,"remark":"同意"}` |
| 32 | POST | `/api/v1/refunds/notify/{channel}` | 退款回调（公开，签名校验） |

### 7.6 账号中心

| # | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 33 | GET | `/api/v1/account/overview` | **账号概览**（聚合 MySQL + Supabase） |
| 34 | GET | `/api/v1/account/favorites` | 我的收藏（聚合）。Query：`type, page, size` |
| 35 | GET | `/api/v1/account/likes` | 近期点赞（聚合）。Query：`days, page, size` |
| 36 | GET | `/api/v1/account/addresses` | 地址簿 |
| 37 | POST/PUT/DELETE | `/api/v1/account/addresses[/{id}]` | 地址簿 CRUD |
| 38 | POST | `/api/v1/products/{productId}/favorite` | 收藏/取消收藏商品（toggle） |

**接口 33 响应示例：**

```json
{
  "code": 0, "message": "success",
  "data": {
    "profile": {
      "email": "user@example.com",
      "displayName": "Luceria Bartender",
      "avatarUrl": "https://xxx.supabase.co/storage/v1/object/public/avatars/uuid/avatar.png",
      "role": "user",
      "registeredAt": "2026-03-14T10:22:00+08:00",
      "profileNextEditableAt": "2026-09-08T21:15:00+08:00"
    },
    "orderStats": {
      "pendingPayment": 1, "paid": 0, "shipped": 2,
      "completed": 7, "refunding": 0, "totalSpent": 2145.00
    },
    "contentStats": { "posts": 4, "replies": 19, "cocktails": 2, "reviews": 11 },
    "engagementStats": { "favorites": 13, "likes": 46 },
    "securityInfo": { "loginMethod": "Email OTP (Supabase)", "lastLoginAt": "2026-09-03T09:10:00+08:00" },
    "partial": false
  }
}
```

### 7.7 CORS 与安全头

```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {
    @Value("${app.cors.allowed-origins}")
    private String[] allowedOrigins;   // 生产：https://drink-app.xxx.workers.dev；开发：http://localhost:5173

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins(allowedOrigins)         // ★ 白名单，绝不用 "*"
                .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
                .allowedHeaders("Authorization", "Content-Type", "X-Request-Id")
                .exposedHeaders("X-Trace-Id")
                .allowCredentials(false)                // ★ 用 Bearer Token，不用 Cookie → 天然免疫 CSRF
                .maxAge(3600);
    }
}
```

---

## 8. 前端改造点

> **本章描述的是「计划要做的改动」。按任务要求，本阶段不修改任何现有业务代码。**

### 8.1 `src/views/MenuView.vue` 改造（用户明确要求）

**现状**：`.menu-turntable-panel` 区块（模板第 15–83 行）包含唱片机图片 + 完整音乐播放器，配套 script 中约 130 行播放器逻辑（`placeholderAudio`、`togglePlay`、`handleSeek`、`toggleMute`、`toggleLoop`、`handleAudioUpload` 等）。

**改造方案（推荐「保留 + 折叠」而非「直接删除」）：**

| 方案 | 做法 | 评价 |
| --- | --- | --- |
| M-1：直接删除播放器，改成购物入口 | 删掉整个 `.menu-turntable-panel` | ❌ 播放器是现有站点的特色，删了可惜；且改动大，回滚困难 |
| **M-2（✅ 推荐）：抽出播放器为独立组件 + 面板可切换** | ① 把播放器整块抽成 `src/components/VinylPlayer.vue`（**纯搬运，不改逻辑**）；② `.menu-turntable-panel` 改为一个可切换的双面板：默认显示**「Luceria 酒品商店」**购物入口卡片，右上角提供一个小唱片图标按钮切回音乐播放器；③ 用 `<KeepAlive>` 包裹，切换时播放器状态不丢失 | ✅ 满足「把音乐那块改造成购物入口」的需求，同时保留特色功能，改动可控 |
| M-3：把播放器移到全局悬浮迷你播放器 | 提升到 `App.vue` | 工作量大，本期不做，作为 P2 |

**购物入口卡片的内容设计：**

```
┌──────────────────────────────────────┐
│  Luceria Boutique      [♪ 切换到唱片机] │
│  酒品商店                              │
│                                       │
│  ┌────────┐  今日推荐                  │
│  │ 商品图  │  Whiskey Sour 礼盒        │
│  └────────┘  ¥129.00  仅剩 3 件 ⚡     │
│                                       │
│  ┌────────┐  ┌────────┐  ┌────────┐   │
│  │ 基酒    │  │ 器具    │  │ 礼盒   │   │
│  └────────┘  └────────┘  └────────┘   │
│                                       │
│  [ 进入商店 → ]        🛒 购物车 (3)   │
└──────────────────────────────────────┘
```

- 「仅剩 N 件」的数字通过 `POST /api/v1/skus/stocks/query` 每 5 秒轮询刷新（**页面不可见时用 `document.visibilityState` 暂停轮询**，节省资源）。
- 购物车角标从 Pinia `useCartStore().count` 读取。

### 8.2 新增路由（`src/router/index.js`）

在现有 9 条路由基础上追加，**保持 `() => import()` 懒加载风格一致**：

```js
// 追加到 routes 数组
{ path: "/shop",                 name: "shop",           component: () => import("@/views/ShopView.vue") },
{ path: "/shop/products/:id",    name: "product-detail", component: () => import("@/views/ProductDetailView.vue") },
{ path: "/shop/cart",            name: "cart",           component: () => import("@/views/CartView.vue"),          meta: { requiresAuth: true } },
{ path: "/shop/checkout",        name: "checkout",       component: () => import("@/views/CheckoutView.vue"),      meta: { requiresAuth: true } },
{ path: "/shop/pay/:orderNo",    name: "payment",        component: () => import("@/views/PaymentView.vue"),       meta: { requiresAuth: true } },
{ path: "/orders",               name: "orders",         component: () => import("@/views/OrderListView.vue"),     meta: { requiresAuth: true } },
{ path: "/orders/:orderNo",      name: "order-detail",   component: () => import("@/views/OrderDetailView.vue"),   meta: { requiresAuth: true } },
{ path: "/orders/:orderNo/refund", name: "refund-apply", component: () => import("@/views/RefundApplyView.vue"),   meta: { requiresAuth: true } },
{ path: "/account/center",       name: "account-center", component: () => import("@/views/AccountCenterView.vue"), meta: { requiresAuth: true } },
{ path: "/admin/shop",           name: "admin-shop",     component: () => import("@/views/admin/AdminShopView.vue"), meta: { requiresAuth: true, requiresAdmin: true } },
```

**同时补上现状 D-4 缺失的路由守卫：**

```js
router.beforeEach(async (to) => {
  if (!to.meta.requiresAuth && !to.meta.requiresAdmin) return true;
  const auth = useAuthStore();
  if (!auth.user) await auth.refreshSession();
  if (!auth.isLoggedIn) return { name: "account", query: { redirect: to.fullPath } };
  if (to.meta.requiresAdmin && !auth.isAdmin) return { name: "home" };
  return true;
});
```

> 注意：`useAuthStore()` 必须在 `beforeEach` 回调**内部**调用，不能在模块顶层，否则 Pinia 实例尚未创建（`src/main.js` 中 `app.use(pinia)` 的时机）。

### 8.3 新增视图组件

| 文件 | 说明 |
| --- | --- |
| `src/views/ShopView.vue` | 商店首页：分类筛选、商品网格、库存标签、加购 |
| `src/views/ProductDetailView.vue` | 商品详情：轮播图、SKU 规格选择器、**实时库存徽章**、数量步进器、加购/立即购买 |
| `src/views/CartView.vue` | 购物车：勾选、改数量、删除、失效提示、结算 |
| `src/views/CheckoutView.vue` | 结算页：收货地址选择、订单确认、**生成 `idempotencyKey`**、提交下单 |
| `src/views/PaymentView.vue` | 模拟收银台：倒计时、支付方式选择、支付状态轮询 |
| `src/views/OrderListView.vue` | 订单列表：状态 Tab、倒计时、取消/去支付/确认收货 |
| `src/views/OrderDetailView.vue` | 订单详情：明细、金额构成、**状态时间轴**（用 `shop_order_status_log`） |
| `src/views/RefundApplyView.vue` | 退款申请：选择明细行、部分退数量、原因 |
| `src/views/AccountCenterView.vue` | **账号中心**：多 Tab（概览 / 我的订单 / 我的收藏 / 近期点赞 / 地址簿 / 安全） |
| `src/views/admin/AdminShopView.vue` | 管理后台：商品管理、补货、退款审核、**库存台账与一键对账** |
| `src/components/VinylPlayer.vue` | 从 `MenuView.vue` 抽出的播放器（纯搬运） |
| `src/components/ShopEntryPanel.vue` | MenuView 中的购物入口卡片 |
| `src/components/StockBadge.vue` | 库存徽章（充足/紧张/售罄三态 + 实时轮询） |
| `src/components/SkuSelector.vue` | SKU 规格选择器 |
| `src/components/CountdownTimer.vue` | 支付倒计时 |

**AccountCenterView 与现有 AccountView 的关系（用户明确关注点）：**

| 页面 | 定位 | 处理方式 |
| --- | --- | --- |
| `AccountView.vue`（`/account`） | **登录 + 基础资料编辑**（发送邮件、验证码、改昵称头像、退出） | **保持不变**，仅在底部 `.account-actions` 区域**新增一个 `<RouterLink to="/account/center">进入账号中心</RouterLink>`** |
| `AccountCenterView.vue`（`/account/center`） | **Google 账号中心风格的信息聚合页**，只读为主 | 全新页面。若用户未登录，路由守卫跳回 `/account` |

这样职责清晰：`/account` 管「登录与身份」，`/account/center` 管「我的数据全景」。避免把一个已经 212 行的登录页撑成 800 行的巨型组件。

### 8.4 新增 Pinia Store

现状只有 `src/stores/auth.js`。新增 4 个，**全部沿用 setup-store 写法保持风格一致**：

| 文件 | State | Actions |
| --- | --- | --- |
| `src/stores/cart.js` | `items`, `loading`, `count`(computed), `selectedTotal`(computed) | `fetch()`, `add(skuId, qty)`, `updateQty()`, `toggleSelect()`, `remove()`, `clearInvalid()` |
| `src/stores/shop.js` | `products`, `categories`, `currentProduct`, `stockMap`, `filters` | `fetchProducts()`, `fetchDetail()`, `startStockPolling(skuIds)`, `stopStockPolling()` |
| `src/stores/order.js` | `orders`, `currentOrder`, `submitting` | `create(cmd)`, `fetchList()`, `fetchDetail()`, `cancel()`, `confirm()`, `pollPaymentStatus()` |
| `src/stores/account.js` | `overview`, `favorites`, `likes`, `addresses` | `fetchOverview()`, `fetchFavorites()`, `fetchLikes()`, `address CRUD` |

**实时库存轮询的实现要点（放在 `shop.js`）：**

```js
let pollTimer = null;

function startStockPolling(skuIds, intervalMs = 3000) {
  stopStockPolling();
  const tick = async () => {
    // 页面不可见时跳过，避免后台标签页浪费流量与后端 QPS
    if (document.visibilityState !== "visible") return;
    try {
      const list = await api.post("/skus/stocks/query", { skuIds });
      list.forEach((s) => { stockMap.value[s.skuId] = s; });
    } catch { /* 轮询失败静默，下次重试 */ }
  };
  tick();
  pollTimer = setInterval(tick, intervalMs);
}

function stopStockPolling() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
}
```

组件中必须在 `onUnmounted` 里调用 `stopStockPolling()`，否则路由切走后定时器泄漏。

> **为什么用轮询而不是 WebSocket/SSE？** 库存展示对实时性的要求是「秒级」而非「毫秒级」，3 秒轮询完全够用；而 WebSocket 需要后端维护长连接、处理心跳与断线重连，对 Java 新手是额外负担，且 Cloudflare Workers 前的网络链路对长连接不友好。**若答辩需要炫技，可作为 P2 用 SSE（`text/event-stream`）升级，Spring 的 `SseEmitter` 实现比 WebSocket 简单得多。**

### 8.5 API 客户端（新建 `src/lib/api.js`）

```js
import { supabase } from "@/lib/supabase";

const BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:8080/api/v1";

async function getAccessToken() {
  if (!supabase) return "";
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token || "";
}

async function request(method, path, body, { auth = true, retryOn401 = true } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (auth) {
    const token = await getAccessToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  // ★ Token 过期时自动刷新一次再重试（Supabase JWT 默认 1 小时有效）
  if (res.status === 401 && retryOn401 && supabase) {
    await supabase.auth.refreshSession();
    return request(method, path, body, { auth, retryOn401: false });
  }

  const json = await res.json().catch(() => ({ code: -1, message: "响应解析失败" }));
  if (!res.ok || json.code !== 0) {
    throw new ApiError(json.code, json.message, json.data, res.status);
  }
  return json.data;
}

export class ApiError extends Error {
  constructor(code, message, data, httpStatus) {
    super(message);
    this.code = code; this.data = data; this.httpStatus = httpStatus;
  }
}

export const api = {
  get:    (p, opt)    => request("GET", p, null, opt),
  post:   (p, b, opt) => request("POST", p, b, opt),
  put:    (p, b, opt) => request("PUT", p, b, opt),
  patch:  (p, b, opt) => request("PATCH", p, b, opt),
  delete: (p, opt)    => request("DELETE", p, null, opt),
};
```

**环境变量新增**（`.env.example` 追加）：

```
VITE_API_BASE_URL=http://localhost:8080/api/v1
```

生产环境在 Cloudflare 的构建变量中配置为后端域名。

### 8.6 下单按钮的前端防重

```vue
<script setup>
const submitting = ref(false);
// ★ 进入结算页时生成一次，整个页面生命周期复用同一个 key。
//   用户点 10 次「提交订单」，10 次请求带的是同一个 key → 后端幂等 → 只产生 1 个订单
const idempotencyKey = crypto.randomUUID();

async function submitOrder() {
  if (submitting.value) return;          // ① 内存标志位防抖
  submitting.value = true;               // ② 按钮 :disabled
  try {
    const order = await orderStore.create({ ...form, idempotencyKey });
    router.push({ name: "payment", params: { orderNo: order.orderNo } });
  } catch (e) {
    if (e.code === 40901) {
      // 库存不足：高亮对应商品，并立即刷新实时库存
      highlightSku(e.data.skuId);
      await shopStore.refreshStock([e.data.skuId]);
    }
    toast.error(e.message);
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <button :disabled="submitting" @click="submitOrder">
    {{ submitting ? "提交中..." : "提交订单" }}
  </button>
</template>
```

### 8.7 样式

沿用现有 `src/styles/styles.css` 的手写 CSS 与暖色调杂志风，**不引入任何 UI 组件库**（保持项目一致性）。新增购物模块相关的 class 前缀统一为 `shop-`、`cart-`、`order-`、`account-center-`，并追加到同一文件末尾，或按现有组织方式拆分。

---

## 9. 非功能需求

### 9.1 性能指标

| 编号 | 接口 | 目标 QPS | P95 响应时间 | P99 响应时间 | 备注 |
| --- | --- | --- | --- | --- | --- |
| NFR-P-01 | 商品列表 `GET /products` | ≥ 500 | < 100ms | < 200ms | 缓存命中率 > 90% |
| NFR-P-02 | 商品详情 `GET /products/{id}` | ≥ 800 | < 50ms | < 120ms | 缓存命中率 > 95% |
| NFR-P-03 | **实时库存 `POST /skus/stocks/query`** | ≥ 2000 | **< 10ms** | **< 30ms** | 纯 Redis MGET |
| NFR-P-04 | **下单 `POST /orders`** | **≥ 300** | **< 200ms** | **< 500ms** | 含 Redis + MySQL 事务 |
| NFR-P-05 | 购物车 `GET /cart` | ≥ 300 | < 80ms | < 150ms | |
| NFR-P-06 | 账号中心概览 | ≥ 100 | < 300ms | < 800ms | 含跨 Supabase 调用，缓存 60s |
| NFR-P-07 | 支付回调 | ≥ 200 | < 100ms | < 300ms | |

**测试环境基准**：单机 4 核 8G，MySQL / Redis / 应用同机 Docker 部署。若资源不足，指标可按比例下调并在压测报告中说明。

**数据库层指标：**

| 指标 | 目标 |
| --- | --- |
| 慢查询（> 100ms）比例 | < 0.1%（开启 `slow_query_log`，`long_query_time = 0.1`） |
| 单行库存扣减 TPS | ≥ 1000（同一 SKU 热点行） |
| 数据库连接池 | HikariCP `maximum-pool-size = 20`（≈ CPU核数 × 2 + 磁盘数），`connection-timeout = 3000ms` |
| InnoDB Buffer Pool | ≥ 1GB（约为数据量的 1.5 倍） |
| 死锁次数 | 压测期间 `SHOW ENGINE INNODB STATUS` 中 `LATEST DETECTED DEADLOCK` 为空 |

### 9.2 安全需求

| 编号 | 要求 | 实现 |
| --- | --- | --- |
| NFR-S-01 | **所有接口鉴权基于服务端 JWT 验签** | 绝不信任前端传的 `userId`；一切用户身份从验签后的 JWT `sub` 提取 |
| NFR-S-02 | **防水平越权** | 所有涉及用户数据的 SQL 强制携带 `AND user_id = #{currentUserId}`；查不到返回 404 而非 403（不泄露资源存在性） |
| NFR-S-03 | **防垂直越权** | `/api/v1/admin/**` 统一拦截，校验 `app_metadata.role == 'admin'`，与现有 `src/stores/auth.js` 口径一致 |
| NFR-S-04 | **防金额篡改** | 订单金额**一律服务端根据 `sku_id` 从数据库重新计算**，前端传的价格只用于展示对比，不参与任何计算；支付回调校验 `amount` 与 `shop_payment.amount` 严格相等 |
| NFR-S-05 | **防 SQL 注入** | MyBatis 一律使用 `#{}` 预编译占位符，禁止 `${}`（除非是经过白名单校验的排序字段名） |
| NFR-S-06 | **支付回调验签** | HMAC-SHA256，密钥存放在环境变量，不入代码库；回调接口做 IP 白名单（模拟网关同机时限 127.0.0.1） |
| NFR-S-07 | **接口限流** | 基于 Redis 的滑动窗口：下单接口 **10 次/分钟/用户**，全局 **1000 QPS**；超出返回 `429 TOO_MANY_REQUESTS` |
| NFR-S-08 | **敏感信息脱敏** | 日志中手机号中间 4 位打码、地址只记录省市、不记录 JWT 原文 |
| NFR-S-09 | **HTTPS** | 生产环境 Nginx 配置 TLS 1.2+，HSTS |
| NFR-S-10 | **CSRF** | 使用 Bearer Token 而非 Cookie，`allowCredentials=false`，天然免疫 |
| NFR-S-11 | **XSS** | 商品详情富文本入库前用白名单过滤（jsoup `Safelist`）；前端**禁止对用户内容使用 `v-html`** |
| NFR-S-12 | **密钥管理** | 数据库密码、JWT Secret、支付密钥全部走环境变量；`.gitignore` 已包含 `.env`（现状已正确） |

### 9.3 可用性与可维护性

| 编号 | 要求 | 实现 |
| --- | --- | --- |
| NFR-A-01 | **Redis 故障不影响正确性** | 降级开关 `stock.redis.enabled=false`，直连 MySQL CAS。吞吐从 300 QPS 降到约 80 QPS，但**不超卖** |
| NFR-A-02 | **Supabase 故障不影响购物** | 账号中心内容聚合超时 2s 后降级返回 `partial: true`；下单流程完全不依赖 Supabase（JWT 公钥已缓存 12 小时） |
| NFR-A-03 | 全链路 traceId | 拦截器生成 `traceId` 放入 MDC，日志格式含 traceId，响应头返回 `X-Trace-Id` |
| NFR-A-04 | 健康检查 | `/actuator/health`（含 MySQL、Redis 探活） |
| NFR-A-05 | 关键指标监控 | Micrometer + `/actuator/prometheus`：下单成功率、库存不足率、库存漂移次数、死锁次数、缓存命中率 |
| NFR-A-06 | 数据备份 | MySQL 每日 `mysqldump` 全量备份 + binlog 保留 7 天 |
| NFR-A-07 | 数据库迁移可回滚 | Flyway 管理，每个 `V*.sql` 配套 `U*.sql` 回滚脚本（解决现状 D-6） |
| NFR-A-08 | 代码规范 | 后端 Alibaba P3C / Checkstyle；前端沿用现有 ESLint 配置 |
| NFR-A-09 | 日志分级 | 库存变更、订单状态流转、支付回调一律 INFO 级别记录完整上下文，便于事后追查 |

---

## 10. 压力测试与验证方案

> 这一章的目标只有一个：**用可复现的数据证明「在高并发下不会超卖、不会少卖」。**

### 10.1 测试场景设计

| 编号 | 场景 | 并发 | 库存 | 期望结果 |
| --- | --- | --- | --- | --- |
| **T-01** | **极限抢购（核心）** | 1000 并发，每人抢 1 件 | 100 件 | 成功订单**恰好 100** 单；失败 900 单全部返回 `40901 STOCK_NOT_ENOUGH`；`available_stock = 0`，`locked_stock = 100`；四条对账 SQL 全部 0 行 |
| **T-02** | **超发抢购** | 5000 并发 | 100 件 | 同上，成功恰好 100；服务不崩溃；P99 < 1s |
| **T-03** | **多 SKU 混合下单（死锁验证）** | 500 并发，每单随机 2–3 个 SKU（乱序） | 各 200 件 | 无死锁（`SHOW ENGINE INNODB STATUS` 无死锁记录）；库存守恒 |
| **T-04** | **重复提交幂等** | 同一 `idempotencyKey` 并发 100 次 | 充足 | **只产生 1 个订单**；库存只扣 1 次 |
| **T-05** | **支付回调重复通知** | 同一 `notifyId` 并发 50 次 | — | 订单只从 `PENDING_PAYMENT` 变 `PAID` 一次；`locked → sold` 只发生一次 |
| **T-06** | **下单 + 取消混合** | 300 并发下单，同时 300 并发取消 | 500 件 | 库存守恒；不出现负库存；不出现「取消了但库存没回来」 |
| **T-07** | **超时关单与支付竞态** | 订单在 `expire_at` 前后 100ms 内并发支付 | — | 要么 `PAID`（库存在 `sold`），要么 `CLOSED`（库存在 `available`），**绝不出现「已关单但库存在 sold」或「已支付但库存在 available」** |
| **T-08** | **退款重复提交** | 同一退款单并发执行 20 次退款 | — | 库存只回补 1 次；`refunded_quantity` 只累加 1 次 |
| **T-09** | **Redis 宕机降级** | 压测中途 `docker stop redis` | 100 件 | 服务自动降级到 MySQL CAS；**仍不超卖**；QPS 下降但可接受 |
| **T-10** | **长时间稳定性** | 200 并发持续 30 分钟 | 充足 | 无内存泄漏、无连接池耗尽、无库存漂移累积 |

### 10.2 测试前准备脚本

```sql
-- reset_test_data.sql —— 每轮压测前执行，保证起点一致
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE shop_order;
TRUNCATE TABLE shop_order_item;
TRUNCATE TABLE shop_order_status_log;
TRUNCATE TABLE shop_payment;
TRUNCATE TABLE shop_payment_notify_log;
TRUNCATE TABLE shop_refund;
TRUNCATE TABLE shop_inventory_ledger;
TRUNCATE TABLE shop_cart_item;
TRUNCATE TABLE shop_delay_task;
SET FOREIGN_KEY_CHECKS = 1;

-- 重置目标 SKU 库存为 100
UPDATE shop_inventory
   SET total_stock = 100, available_stock = 100, locked_stock = 0, sold_stock = 0, version = 0
 WHERE sku_id = 1001;

INSERT INTO shop_inventory_ledger
  (sku_id, biz_type, biz_no, delta_available, delta_total, after_available, after_locked, after_sold, after_total, remark)
VALUES
  (1001, 'INIT', CONCAT('TEST-', UNIX_TIMESTAMP()), 100, 100, 100, 0, 0, 100, '压测重置');
```

```bash
# 同步重置 Redis 库存
redis-cli SET shop:stock:1001 100
redis-cli --scan --pattern 'shop:deduct:*' | xargs -r redis-cli DEL
redis-cli --scan --pattern 'idem:order:*'  | xargs -r redis-cli DEL
```

### 10.3 wrk + Lua 压测脚本（推荐，轻量）

```lua
-- order_bench.lua
-- 用法: wrk -t8 -c1000 -d30s -s order_bench.lua http://localhost:8080/api/v1/orders

local counter = 0
local threadId = 0

function setup(thread)
    threadId = threadId + 1
    thread:set("tid", threadId)
end

function init(args)
    tid = tonumber(wrk.thread:get("tid"))
    -- 预置 200 个测试用户的 JWT（脚本外提前生成，避免压测时产生鉴权开销）
    tokens = {}
    local f = io.open("tokens.txt", "r")
    for line in f:lines() do tokens[#tokens + 1] = line end
    f:close()
end

function request()
    counter = counter + 1
    local token = tokens[(counter % #tokens) + 1]
    -- ★ 每次请求用不同的 idempotencyKey，模拟不同用户的真实独立下单
    local idem = string.format("bench-%d-%d-%d", tid, counter, os.time())
    local body = string.format([[{
        "items":[{"skuId":1001,"quantity":1}],
        "receiverName":"压测用户","receiverPhone":"13800000000",
        "receiverAddress":"测试地址","idempotencyKey":"%s"
    }]], idem)

    return wrk.format("POST", "/api/v1/orders", {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. token
    }, body)
end

-- 统计各状态码分布
local statusCount = {}
function response(status, headers, body)
    statusCount[status] = (statusCount[status] or 0) + 1
end

function done(summary, latency, requests)
    io.write("\n===== 结果统计 =====\n")
    io.write(string.format("总请求: %d\n", summary.requests))
    for st, cnt in pairs(statusCount) do
        io.write(string.format("HTTP %d : %d\n", st, cnt))
    end
    io.write(string.format("P50: %.2fms  P95: %.2fms  P99: %.2fms\n",
        latency:percentile(50)/1000, latency:percentile(95)/1000, latency:percentile(99)/1000))
end
```

### 10.4 JMeter 方案（可视化，适合答辩演示）

| 元件 | 配置 |
| --- | --- |
| 线程组 | 线程数 1000，Ramp-up **0 秒**（★ 必须为 0，才是真正的瞬时并发），循环 1 次 |
| **Synchronizing Timer** | Number of Simulated Users to Group by = **1000**，Timeout = 10000ms。★ **这是模拟「同一瞬间」的关键**：让 1000 个线程在集合点等齐后同时释放 |
| CSV Data Set Config | `tokens.csv`（预生成的 JWT），`Recycle on EOF = true` |
| HTTP 请求 | POST `/api/v1/orders`，Body 用 `${__UUID()}` 生成 `idempotencyKey` |
| HTTP 信息头管理器 | `Authorization: Bearer ${token}` |
| **JSR223 断言** | 校验：`code == 0` 或 `code == 40901`（**出现任何其它错误码即视为失败**） |
| 聚合报告 / 汇总报告 | 收集 TPS、P95、P99、错误率 |
| JDBC Request（tearDown 线程组） | 压测结束后自动执行 6.12 的四条校验 SQL，任一返回非 0 行则**整个测试标红失败** |

### 10.5 ★ 断言脚本：证明库存守恒

```sql
-- verify_after_bench.sql —— 压测后立即执行，这是最终的证据
SELECT '========== 压测一致性校验报告 ==========' AS report;

-- ① 成功订单数 vs 库存扣减量（必须严格相等）
SELECT
  (SELECT COUNT(*) FROM shop_order WHERE status = 'PENDING_PAYMENT')                          AS success_orders,
  (SELECT COALESCE(SUM(quantity), 0) FROM shop_order_item WHERE sku_id = 1001)                AS ordered_qty,
  (SELECT locked_stock    FROM shop_inventory WHERE sku_id = 1001)                            AS locked_stock,
  (SELECT available_stock FROM shop_inventory WHERE sku_id = 1001)                            AS available_stock,
  (SELECT total_stock     FROM shop_inventory WHERE sku_id = 1001)                            AS total_stock,
  CASE WHEN
       (SELECT COALESCE(SUM(quantity),0) FROM shop_order_item WHERE sku_id = 1001)
       = (SELECT locked_stock FROM shop_inventory WHERE sku_id = 1001)
  THEN '✅ PASS：订单量 = 锁定量' ELSE '❌ FAIL：订单与库存不符' END                            AS check_order_vs_stock;

-- ② 库存三段守恒
SELECT CASE WHEN COUNT(*) = 0
            THEN '✅ PASS：库存三段守恒 available+locked+sold=total'
            ELSE CONCAT('❌ FAIL：', COUNT(*), ' 个 SKU 守恒被破坏') END AS check_conservation
  FROM shop_inventory
 WHERE available_stock + locked_stock + sold_stock <> total_stock;

-- ③ 无负库存（超卖的直接标志）
SELECT CASE WHEN COUNT(*) = 0
            THEN '✅ PASS：无负库存，未发生超卖'
            ELSE CONCAT('❌ FAIL：', COUNT(*), ' 个 SKU 出现负库存 —— 超卖！') END AS check_no_oversell
  FROM shop_inventory
 WHERE available_stock < 0 OR locked_stock < 0 OR sold_stock < 0;

-- ④ 快照与台账一致
SELECT CASE WHEN COUNT(*) = 0
            THEN '✅ PASS：库存快照与流水台账完全一致'
            ELSE CONCAT('❌ FAIL：', COUNT(*), ' 个 SKU 台账对不上') END AS check_ledger
  FROM shop_inventory i
  LEFT JOIN (SELECT sku_id, SUM(delta_available) sa, SUM(delta_locked) sl, SUM(delta_sold) ss
               FROM shop_inventory_ledger GROUP BY sku_id) l ON l.sku_id = i.sku_id
 WHERE i.available_stock <> COALESCE(l.sa,0)
    OR i.locked_stock    <> COALESCE(l.sl,0)
    OR i.sold_stock      <> COALESCE(l.ss,0);

-- ⑤ 无重复订单（幂等验证）
SELECT CASE WHEN COUNT(*) = 0
            THEN '✅ PASS：无重复下单'
            ELSE CONCAT('❌ FAIL：', COUNT(*), ' 组重复的 idempotencyKey') END AS check_idempotent
  FROM (SELECT user_id, idempotency_key
          FROM shop_order GROUP BY user_id, idempotency_key HAVING COUNT(*) > 1) t;

-- ⑥ Redis 与 MySQL 一致（需在应用层比对，此处输出 MySQL 侧基准值）
SELECT sku_id, available_stock AS mysql_available FROM shop_inventory WHERE sku_id = 1001;
-- 对比：redis-cli GET shop:stock:1001
```

### 10.6 Java 单元级并发测试（更快的回归验证）

```java
@SpringBootTest
class StockConcurrencyTest {

    @Autowired private OrderService orderService;
    @Autowired private InventoryMapper inventoryMapper;

    @Test
    @DisplayName("1000 线程并发抢 100 件库存，成功数必须恰好为 100")
    void shouldNotOversell() throws InterruptedException {
        final long SKU_ID = 1001L;
        final int STOCK = 100, THREADS = 1000;
        resetStock(SKU_ID, STOCK);

        // ★ CountDownLatch 做发令枪：1000 个线程在同一瞬间被释放
        CountDownLatch startGun = new CountDownLatch(1);
        CountDownLatch finish   = new CountDownLatch(THREADS);
        AtomicInteger success   = new AtomicInteger();
        AtomicInteger stockFail = new AtomicInteger();
        AtomicInteger otherFail = new AtomicInteger();
        ExecutorService pool = Executors.newFixedThreadPool(200);

        for (int i = 0; i < THREADS; i++) {
            final long userId = 10000L + i;
            pool.submit(() -> {
                try {
                    startGun.await();                          // 等发令枪
                    orderService.createOrder(userId, cmdOf(SKU_ID, 1));
                    success.incrementAndGet();
                } catch (StockNotEnoughException e) {
                    stockFail.incrementAndGet();
                } catch (Exception e) {
                    otherFail.incrementAndGet();
                } finally {
                    finish.countDown();
                }
            });
        }
        startGun.countDown();                                  // 发令
        assertTrue(finish.await(120, TimeUnit.SECONDS));
        pool.shutdown();

        Inventory inv = inventoryMapper.selectById(SKU_ID);

        // ★★★ 核心断言 ★★★
        assertEquals(STOCK, success.get(),            "成功订单数必须恰好等于库存数");
        assertEquals(THREADS - STOCK, stockFail.get(), "其余请求必须全部因库存不足失败");
        assertEquals(0, otherFail.get(),               "不应有任何其它异常");
        assertEquals(0,     inv.getAvailableStock(),   "可售库存必须为 0");
        assertEquals(STOCK, inv.getLockedStock(),      "锁定库存必须等于成功订单数");
        assertEquals(0,     inv.getSoldStock());
        assertEquals(inv.getTotalStock(),
                inv.getAvailableStock() + inv.getLockedStock() + inv.getSoldStock(),
                "★ 库存守恒不变式必须成立");
    }
}
```

### 10.7 压测报告模板

答辩材料应包含：

| 内容 | 形式 |
| --- | --- |
| 测试环境说明 | CPU / 内存 / MySQL 版本 / Redis 版本 / JVM 参数 |
| 各场景的 TPS / P50 / P95 / P99 / 错误率 | 表格 + JMeter 聚合报告截图 |
| **T-01 的 SQL 校验输出截图** | **最重要的证据 —— 五行 `✅ PASS`** |
| **对照实验：故意关闭 CAS 条件后的超卖复现** | 把 `AND available_stock >= #{qty}` 去掉，重跑 T-01，展示 `available_stock = -387` 的截图。**「能复现问题」比「没出问题」更有说服力** |
| 优化前后对比 | 例如：无 Redis 漏斗时 MySQL CPU 100% / QPS 80；加漏斗后 CPU 30% / QPS 320 |
| 死锁分析 | 展示「不排序加锁」时的死锁日志，与「排序后」无死锁的对比 |

> **强烈建议做 10.7 中的对照实验。** 只展示「我的系统没超卖」，老师无法判断你是真的解决了问题还是并发压根没打上去。展示「去掉这一行 SQL 条件立刻就超卖 387 件，加回来就恰好 100 件」，才能证明你**理解并真正解决了**这个问题。

---

## 11. 开发计划与里程碑

**总周期：10 周（约 2.5 个月）。** 计划显式为「Java 零基础」预留了学习时间，并把风险最高的部分（并发）安排在中段，留出充足的返工余量。

| 阶段 | 周次 | 主要任务 | 交付物 | 对 Java 新手的提示 |
| --- | --- | --- | --- | --- |
| **M0 环境与入门** | 第 1 周 | ① 安装 JDK 17 + IntelliJ IDEA + Maven；② `docker-compose` 起 MySQL 8 + Redis 7；③ 用 Spring Initializr 生成骨架，跑通「Hello World」`@RestController`；④ 跑通 MyBatis-Plus 单表查询 | 可访问 `GET /api/v1/ping` 返回 JSON | **本周唯一目标是「环境能跑起来」**。不要试图理解 Spring 的全部原理。推荐资料：Spring 官方 Guides、《Spring Boot 实战》前 3 章 |
| **M1 数据库落地** | 第 2 周 | ① 执行第 5 章全部建表 SQL；② 配置 Flyway；③ 用 MyBatis-Plus 代码生成器生成 Entity/Mapper；④ 造 20 个商品 + 40 个 SKU 的种子数据；⑤ 手写并验证第 6.12 章的对账 SQL | 完整数据库 + 种子数据 + Flyway 脚本 | **这周是你最擅长的（数据库原理课的内容）**，可以快速建立信心。重点验证 `CHECK` 约束是否真的能拒绝负库存（手动 `UPDATE` 试一下） |
| **M2 基础框架** | 第 3 周 | ① JWT 拦截器 + Supabase JWKS 验签；② `shop_user` JIT 懒创建；③ 统一响应包装 `Result<T>` + 全局异常处理 `@RestControllerAdvice`；④ CORS 配置；⑤ Swagger；⑥ traceId 日志 | 前端能用真实 Supabase JWT 调通一个受保护接口 | **JWT 验签是本周唯一难点**。建议先用对称密钥（HS256）跑通，再切 JWKS。用 jwt.io 手工解码 token 辅助调试 |
| **M3 商品与购物车** | 第 4 周 | ① 商品/分类/SKU 的 CRUD 与查询接口；② Redis 商品缓存（含穿透/击穿/雪崩三防）；③ **实时库存查询接口**；④ 购物车全套接口；⑤ 管理员补货与库存台账 | 接口 1–16 全部可用 | 这一周基本都是 CRUD，是**熟悉 Spring Boot 手感**的最佳阶段。写完商品接口后，购物车接口会快很多 |
| **M4 ★ 订单与并发核心** | **第 5–6 周（2 周）** | ① 订单号生成器；② **Redis Lua 预扣减脚本**；③ **MySQL CAS 扣减 + 三段式流转**；④ 库存台账幂等；⑤ 订单状态机；⑥ **Redisson 延迟队列关单 + 定时兜底**；⑦ 事务边界重构（`OrderTxService` 拆分） | **接口 17–23，本项目的技术核心** | **★ 这是全项目最难、最重要的两周，请预留全部精力。** 建议：先写「只有 MySQL CAS」的最简版本并跑通 10.6 的单元测试（此时已经不会超卖了），**再**加 Redis 漏斗优化性能。**千万不要一开始就写复杂版本** |
| **M5 支付与退款** | 第 7 周 | ① 模拟支付网关（独立 `@RestController`，含签名与异步回调）；② 支付流水与回调幂等；③ 退款申请/审核/执行；④ **退货库存回滚（6.9 节）**；⑤ 异常支付自动退款 | 接口 24–32 | 支付回调的三道幂等要逐个测试。用 Postman 手工重放同一个回调 10 次，验证只生效一次 |
| **M6 账号中心与后台** | 第 8 周 | ① 账号中心聚合接口（`CompletableFuture` 并行 + 降级）；② Supabase REST 客户端封装；③ 收藏点赞聚合；④ 管理后台接口 | 接口 33–38 + Admin 接口 | `CompletableFuture` 是本周新知识点，但只需用到 `supplyAsync` + `allOf` 两个方法 |
| **M7 前端对接** | 第 9 周 | ① `src/lib/api.js`；② 4 个 Pinia store；③ **MenuView 改造（抽出 `VinylPlayer.vue` + 购物入口）**；④ 10 个新视图组件；⑤ 路由守卫；⑥ 样式打磨 | 完整可演示的前端 | 前端是你熟悉的领域，可以适当加速。**建议在 M4 结束后就开始并行做前端的商品与购物车页面**，避免第 9 周堆积 |
| **M8 压测与交付** | 第 10 周 | ① 执行 T-01 ~ T-10 全部场景；② **对照实验（去掉 CAS 复现超卖）**；③ 性能调优；④ 补单元测试；⑤ 撰写压测报告；⑥ 录制演示视频；⑦ 部署上线 | **压测报告 + 演示视频 + 完整文档** | 留足 3 天缓冲。压测一定会暴露问题（连接池不够、慢 SQL、内存溢出），这是正常的 |

**并行建议：**

- 第 4 周起前后端可并行（前端先用 Mock 数据）。
- 第 5–6 周（M4）**不要同时做别的**，专注攻坚。
- 文档随开发同步更新，不要留到最后。

**每周最低时间投入建议：** 15–20 小时。M4 阶段建议 25 小时以上。

**如果时间不够的降级顺序（从后往前砍）：**

1. 砍掉 FR-ADM-05 数据看板（P2）
2. 砍掉退货退款的「部分退款」，只做整单退（但**必须保留库存回滚的正确实现**，这是文档重点）
3. 砍掉管理后台前端页面，改用 Swagger UI 演示管理接口
4. 砍掉 SKU 多规格，每个商品只有一个 SKU
5. **绝对不能砍的：库存三段式、CAS 扣减、幂等设计、超时释放、压测验证**（这些是全部核心分值所在）

---

## 12. 风险与未决问题

### 12.1 风险登记册

| 编号 | 风险 | 概率 | 影响 | 应对措施 |
| --- | --- | :---: | :---: | --- |
| **R-01** | **Java 学习曲线导致进度延误** | **高** | **高** | ① 技术选型已全面向「易学」倾斜（见 3.1）；② M0/M1 阶段刻意安排简单任务建立信心；③ M4 预留 2 周并采取「先简单版本再优化」策略；④ 计划留有 3 天缓冲 |
| R-02 | 并发问题难以调试（偶发、难复现） | 中 | 高 | ① 关键路径全部打 INFO 日志 + traceId；② 用 10.6 的 `CountDownLatch` 单元测试稳定复现；③ 依赖数据库 `CHECK` 约束把错误暴露在第一现场而不是事后 |
| R-03 | 两个数据源导致账号中心开发复杂 | 中 | 中 | 用 BFF 聚合 + 降级；先做 MySQL 侧（订单），Supabase 侧作为增强 |
| R-04 | 本地机器性能不足，压不出真实并发 | 中 | 中 | ① 用 `wrk`（比 JMeter 轻得多）；② 降低并发量到 500，在报告中说明环境限制；③ **重点展示「对照实验」而非绝对 QPS 数字** |
| R-05 | Supabase 免费额度耗尽 | 低 | 中 | 账号中心聚合结果缓存 60s；压测**只压 Java 后端**，不打 Supabase |
| R-06 | Redis / MySQL 环境配置踩坑 | 中 | 低 | 提供 `docker-compose.yml`，避免手工安装 |
| R-07 | 需求变更（老师提出新要求） | 中 | 中 | 文档模块化，购物模块与内容社区解耦，改动影响面可控 |
| R-08 | Supabase JWT 验签方式变更（HS256 → RS256 迁移） | 低 | 中 | 拦截器同时支持两种算法，通过配置切换 |
| R-09 | 无云服务器，无法线上演示 | 中 | 低 | 本地录屏 + 内网穿透（frp / ngrok）演示，不影响任何功能评分 |

### 12.2 ★ 需要用户确认的开放性问题

以下问题会实质影响设计，**请在开发启动前逐条确认**：

| # | 问题 | 我的默认建议 | 影响 |
| --- | --- | --- | --- |
| **Q-01** | **架构方案确认**：接受 3.3 节的「方案 C 共存」吗？还是坚持要把 Supabase 完全替换掉？ | **强烈建议方案 C**。完全替换会额外增加 3–4 周工作量，且与课程考察点无关 | ★★★ 决定整体工作量 |
| **Q-02** | **卖什么商品？** 是「实体酒品 + 调酒器具」，还是「虚拟商品（酒谱、课程）」？ | 建议**实体商品**（酒品礼盒 + 器具），可复用现有的 8 款鸡尾酒素材与 `ToolsView` 的器具内容 | ★★ 决定商品表字段（是否需要发货、物流） |
| **Q-03** | **是否需要 SKU 多规格？** 还是每个商品只有一个规格？ | 建议**保留 SKU 表但初期每商品 1–2 个 SKU**。表结构留好扩展性，前端做简单些 | ★★ 影响前端复杂度 |
| **Q-04** | **支付用模拟网关可以吗？** | **强烈建议模拟**。真实支付需要商户资质、备案、回调公网域名，且沙箱环境也很折腾。模拟网关能完整演示回调、验签、幂等、对账的全部逻辑 | ★★★ 决定第 7 周工作量 |
| **Q-05** | **订单超时时间设为多少？** | 建议 **15 分钟**（行业惯例）。**演示时可通过配置改为 60 秒**，方便当场展示自动关单 | ★ |
| **Q-06** | **是否需要用户余额/钱包功能？** | 建议**不做**。会引入「余额扣减」这第二个并发热点，成倍增加复杂度 | ★★ |
| **Q-07** | **管理后台要做完整的前端页面吗？** | 建议**做一个简化版单页**（表格 + 表单），或直接用 Swagger UI 演示。管理后台不是评分重点 | ★★ 决定第 9 周工作量 |
| **Q-08** | **是否要引入真正的消息队列（RocketMQ）？** | 建议**不引入**，用 Redisson 延迟队列（见 6.2 方案 5）。但**在文档中说明升级路径**，答辩时可以讲「为什么现在不需要、什么时候需要」 | ★★ |
| **Q-09** | **服务器资源**：有云服务器吗？配置多少？ | 若无，全本地 Docker + 录屏演示即可 | ★ 影响部署与压测指标 |
| **Q-10** | **课程的具体评分标准是什么？** 数据库课更看重 SQL/范式/索引，还是并发控制？Java 课更看重设计模式，还是功能完整度？ | **请提供评分细则**，我可以据此调整文档与实现的侧重点 | ★★★ 影响精力分配 |
| **Q-11** | **是否需要清理现有死代码**（`GamesView.vue`、`src/game/**`、`legacy/`、`supabase-schema.sql`）？ | 建议**本期不动**（避免引入回归风险），作为独立任务在项目结束后处理 | ★ |
| **Q-12** | **内容社区的收藏/点赞，将来要迁到 MySQL 吗？** | 本期不迁。若确定要迁，我会在 `shop_favorite` / `shop_like` 表中预留 `source` 字段并提供迁移脚本 | ★★ |
| **Q-13** | **是否需要「秒杀」这种更极端的场景？** | 建议不做独立秒杀模块。当前的「1000 并发抢 100 件」压测已经完全覆盖了秒杀的技术要点 | ★ |
| **Q-14** | **答辩时长与形式？** | 影响演示脚本设计。若时间短，重点演示「下单 → 库存实时变化 → 并发压测 → 对账 SQL 全绿」这条主线 | ★ |

### 12.3 建议优先确认的 3 个问题

如果时间有限，请**至少先回答这三个**：

1. **Q-01（架构方案）** —— 决定整个项目的工作量基线。
2. **Q-04（模拟支付）** —— 决定是否会在第三方资质上卡壳。
3. **Q-10（评分标准）** —— 决定精力往哪里投。

---

## 附录 A：术语表

| 术语 | 英文 / 缩写 | 含义 |
| --- | --- | --- |
| SPU | Standard Product Unit | 标准商品单元，如「威士忌酸礼盒」 |
| SKU | Stock Keeping Unit | 库存量单位，如「威士忌酸礼盒 / 700ml / 单瓶装」，**库存挂在 SKU 上** |
| 超卖 | Oversell | 卖出的数量超过实际库存 |
| 库存冗余 / 幽灵库存 | Phantom Stock | 实际有货但系统显示无货，或系统库存凭空增加 |
| CAS | Compare And Swap | 比较并交换。本文指 `UPDATE ... WHERE <期望条件>` 这种「条件更新」 |
| TOCTOU | Time-Of-Check to Time-Of-Use | 检查时刻与使用时刻之间的竞态窗口，超卖的根本成因 |
| 丢失更新 | Lost Update | 两个事务并发写同一行，后写的覆盖了先写的结果 |
| 幂等 | Idempotence | 同一操作执行 1 次和 N 次，对系统状态的影响相同 |
| 三段式库存 | — | `available_stock` / `locked_stock` / `sold_stock` 的库存模型 |
| 库存台账 | Inventory Ledger | 只增不改的库存变更流水，用于审计与对账 |
| BFF | Backend For Frontend | 为前端定制的聚合层，本项目用于聚合 MySQL 与 Supabase 数据 |
| 绞杀者模式 | Strangler Fig Pattern | 渐进式替换遗留系统的架构模式 |
| JIT Provisioning | Just-In-Time Provisioning | 用户首次访问时才创建本地账号记录 |
| RLS | Row Level Security | Postgres 行级安全策略，Supabase 的核心安全机制 |
| 缓存穿透 | Cache Penetration | 查询不存在的数据，缓存永不命中 |
| 缓存击穿 | Cache Breakdown | 单个热点 key 过期，大量请求同时回源 |
| 缓存雪崩 | Cache Avalanche | 大量 key 同时过期或缓存服务整体宕机 |
| 延迟双删 | Delayed Double Delete | 更新数据库后删两次缓存（立即 + 延迟 500ms） |
| RC / RR | Read Committed / Repeatable Read | MySQL 事务隔离级别 |
| 当前读 | Current Read | `SELECT ... FOR UPDATE`、`UPDATE`、`DELETE` 读取最新已提交数据并加锁 |
| 快照读 | Snapshot Read | 普通 `SELECT`，基于 MVCC 读取事务开始时的一致性视图 |
| 间隙锁 | Gap Lock | InnoDB 在 RR 下用于防止幻读的锁，会锁住索引记录之间的间隙 |

## 附录 B：错误码总表

| 错误码 | HTTP | 含义 | 前端处理建议 |
| --- | --- | --- | --- |
| 0 | 200 | 成功 | — |
| 40000 | 400 | `PARAM_INVALID` 参数校验失败 | 展示具体字段错误 |
| 40100 | 401 | `UNAUTHORIZED` 未登录或 Token 无效 | 刷新 Token，仍失败则跳登录页 |
| 40101 | 401 | `TOKEN_EXPIRED` Token 过期 | 自动 `refreshSession()` 后重试一次 |
| 40300 | 403 | `FORBIDDEN` 无权限 | 提示「无权访问」 |
| 40400 | 404 | `NOT_FOUND` 资源不存在 | — |
| 40401 | 404 | `PRODUCT_NOT_FOUND` 商品不存在或已下架 | 返回商店首页 |
| 40402 | 404 | `ORDER_NOT_FOUND` 订单不存在 | — |
| 40403 | 404 | `CART_ITEM_NOT_FOUND` 购物车条目不存在 | 刷新购物车 |
| **40901** | **409** | **`STOCK_NOT_ENOUGH` 库存不足** | **高亮对应 SKU + 立即刷新实时库存 + Toast 提示** |
| 40902 | 409 | `SKU_OFF_SHELF` 商品已下架 | 标记失效，从购物车移除 |
| 40903 | 409 | `ORDER_STATUS_ILLEGAL` 订单状态不允许此操作 | 刷新订单状态 |
| 40904 | 409 | `ORDER_EXPIRED` 订单已超时关闭 | 提示重新下单 |
| 40905 | 409 | `REFUND_QUANTITY_EXCEED` 退款数量超出可退范围 | 展示可退上限 |
| 40906 | 409 | `SKU_CODE_DUPLICATED` SKU 编码重复 | Admin 提示 |
| 40907 | 409 | `AMOUNT_MISMATCH` 金额不匹配 | 记录安全日志，提示联系客服 |
| 42900 | 429 | `TOO_MANY_REQUESTS` 触发限流 | 展示「操作过于频繁，请稍后再试」+ 倒计时 |
| 50000 | 500 | `INTERNAL_ERROR` 服务器内部错误 | 展示 traceId 便于排查 |
| 50300 | 503 | `SERVICE_UNAVAILABLE` 服务暂时不可用（如数据库故障） | 展示降级页面 |

---

**文档结束**

> 本文档基于对 `C:\Users\qinye\Desktop\q program\drink` 现有代码的实际阅读编写，引用的文件路径（`src/router/index.js`、`src/views/MenuView.vue`、`src/views/AccountView.vue`、`src/stores/auth.js`、`src/lib/supabase.js`、`src/lib/user-cocktails.js`、`supabase/*.sql`、`package.json`、`wrangler.jsonc`、`vite.config.js`）与表名（`reviews`、`review_likes`、`stories_posts`、`stories_replies`、`stories_post_likes`、`stories_post_favorites`、`stories_reply_likes`、`user_cocktails`、`games_rooms` 等）均与项目实际情况一致。
>
> 本阶段仅产出需求文档，**未修改任何现有业务代码**。
