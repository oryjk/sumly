# 记金小程序完整功能对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 小程序对齐当前 App 全部功能与深色金色界面，Apple 登录替换为微信登录。

**Architecture:** 在既有 uni-app 工程分模块移植 Swift 业务规则，共用 Go 行情和账户持仓契约。后端补微信统一会话与微信通知适配；不重写既有行情/持仓服务。四份子计划分别有可运行的交付与验证，共同组成完整验收。

**Tech Stack:** uni-app、Vue 3、TypeScript 4.9、Vite、Bun 1.3.10 测试、Go 1.26.5、Gin、PostgreSQL、sqlc。

**Spec:** `docs/superpowers/specs/2026-10-03-mini-app-parity-design.md`（2026-10-03 用户已确认）。

## Global Constraints

- 界面沿用 App 的深色金色风格；唯一明确的功能替换是 Apple 原生登录改为小程序微信登录，手机号与邮箱认证保留。
- 迁移基准是本次检查的 `sumly_ios/Sumly/Sources/` 工作区代码，包含尚未提交的现有功能；现有 iOS 与 Go 工作区改动须保留，不能重置或用旧提交覆盖。
- 背景 `#1B1B1D`、卡片 `#282523`、强调金色 `#F2C512`、红涨 `#FF5D5D`、绿跌 `#3DD68C`，集中在设计令牌。
- 运行时组件直接从 `.vue` 导入；使用 `uni.*`，禁止浏览器 DOM API；微信专属能力条件编译并提供 H5 路径。
- 金额展示才舍入，核心计算与云文档保留原精度；云文档日期使用 Unix 毫秒 Double，兼容已有小数毫秒。
- 复用 `/holdings` 的 `schemaVersion: 1` 文档和全部字段；记录状态使用 `holding/sold/gift`；UUID 大小写无关比较；历史 assetType 原样保留。
- 登录不自动上传游客数据；退出、换号、注销后的旧响应不得写入缓存；注销保留独立游客数据。
- mock 全有或全无；构建成功不能替代微信运行验证；实际模板、授权未就绪则系统提醒验收未完成。
- Go 保持六边形架构；认证身份不得按可编辑资料自动合并；数据库集成仅使用显式 TEST_DATABASE_URL 随机 schema。
- 本计划授权代码实现和本地验证，不包含上线后端、发布微信版本或对真实用户执行注销。

## Review Focus

1. 购入拆成多笔处置后又在另一设备编辑：克数/成本不增加，购入族整体解决冲突（B2、C3）。
2. 登录/刷新/同步尚未返回时退出或换号：旧响应不能复活会话、清掉新凭据或改写其他账户（C2、C3）。
3. 稀疏休市数据、分钟采样、跨午夜与历史手选日期：显示真实时间和空缺，手工买入价不被晚到响应覆盖（A2、A3、B3）。
4. 存储满、超大 revision、小数毫秒、半分舍入和未知资产类型：原值保持、写失败可见、展示拆解分项之和等于总盈亏（B1、B4、C3）。
5. 订阅弹窗 success 但模板结果 reject/ban、通知响应未知或失败：不能宣称授权/送达成功，不丢触发事件、不重复发同一事件（D2）。

---

## 计划与依赖

| 顺序 | 子计划 | 独立可验证交付 | 前置依赖 |
| --- | --- | --- | --- |
| A | [行情与界面](2026-10-03-mini-market.md) | 游客可浏览完整国内/国际行情与交互图表 | 无 |
| B | [持仓与计算](2026-10-03-mini-holdings.md) | 游客可离线完成完整记金、分析与日历流程 | A 的类型、主题与导航 |
| C | [账户与云同步](2026-10-03-mini-accounts.md) | 微信/手机/邮箱会话和跨设备持仓 | B 文档模型，A 导航 |
| D | [提醒与完整验收](2026-10-03-mini-alerts-verification.md) | 真实提醒适配与逐项对齐证据 | A–C |

每份子计划继承上面的约束与 Review Focus；执行时同时读取本文件和已批准规格。按 A1–A3、B1–B4、C1–C3、D1–D3 顺序推进。任何依赖接口调整同时修正消费者及对应测试。

## 执行准备与当前证据

- 2026-10-03：`cd sumly_mini && bun run type-check` 成功，Bun 版本 1.3.10；这只证明迁移前类型检查通过。
- `sumly_mini` 当前没有 test 脚本。A1 添加 `test: bun test ./tests`，纯逻辑测试使用 Bun 内置 runner，避免为业务测试另装框架。
- 当前最高数据库迁移编号为 00008。C1 使用 `00009_wechat_sessions.sql`，D2 使用 `00010_holding_notifications.sql`；实施前再检查是否被其他工作占用，若占用只调整新增迁移编号。
- 工作区存在大量既有未提交改动；执行前按 using-git-worktrees 技能检查现有 checkout/附件。不得从 HEAD 建立丢失这些基准改动的实现环境；需要隔离时先完整保留基准，不能 stash/reset 用户代码。
- 每任务只提交自己的明确文件或改动片段；已有修改文件必须核对任务 diff，不得顺带提交基准中不属于本任务的更改。

## 最终完成门槛

- [ ] 四个子计划的任务完成，新增纯逻辑/竞态测试及受影响 Go 测试通过。
- [ ] 小程序 `bun run test`、`bun run type-check`、`bun run build:h5`、`bun run build:mp-weixin` 通过。
- [ ] 后端 `make test`、`make vet`、`make build` 通过；没有 TEST_DATABASE_URL 时数据库验证明确记为未运行。
- [ ] H5、微信开发者工具及真机检查完成，并逐项填入 `docs/mini-app-parity-verification.md`，附截图、配置依赖与失败项。
- [ ] 与当前 App 对比，规格第 3 节每一行都有行为与证据；系统提醒配置未齐不能标记整项完成。
- [ ] 执行 verification-before-completion 和 requesting-code-review 技能；独立审查的实现方式以用户选择的执行方法为准。

计划审阅与执行方法选择前，不写产品代码、不安装产品依赖、不变更后端运行环境。
