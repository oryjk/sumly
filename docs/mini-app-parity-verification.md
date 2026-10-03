# 小程序与 App 功能对齐验收记录

日期：2026-10-04（Asia/Shanghai）
范围：`docs/superpowers/specs/2026-10-03-mini-app-parity-design.md` 第 3 节的 20 个模块

**status 取值**：通过 / 失败 / 未运行。**不把「需要配置」记为通过。**

## 自动验证汇总（2026-10-04）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 小程序单测 | `cd sumly_mini && bun run test` | 416 passed / 0 failed（30 文件） |
| 小程序类型 | `cd sumly_mini && bun run type-check` | 通过，无输出 |
| H5 构建 | `cd sumly_mini && bun run build:h5` | Build complete |
| 微信构建 | `cd sumly_mini && bun run build:mp-weixin` | Build complete |
| 后端单测 | `cd sumly_go && go test ./...` | 25 个包全部 ok |
| 后端静态检查 | `cd sumly_go && go vet ./...` | 通过 |
| 后端构建 | `cd sumly_go && go build ./...` | 通过 |
| **数据库集成测试** | 需显式 `TEST_DATABASE_URL` | **未运行**——环境未设置；`TestCASIsolationAndDeletion` 等用例按设计跳过 |

微信产物已核对：4 个页面注册、`usingComponents` 覆盖 GoldTabBar / GoldChart /
QuoteHeader / MarketSources / ChartNavigator / HoldingCard / DisposeHolding /
PurchaseFields / RecoveryFields / ProfitBreakdown / HoldingAlerts /
GoldInput / SyncStatus / AuthenticationForm / AccountActions。

## 逐项验收

| 功能 | App 基准 | 自动验证 | H5 | 微信 | 真机 | 状态 | 阻塞 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 全局主题与导航 | `GoldTheme.swift`、`GoldTabBarShape` | uni.css `--gold-*` 令牌；GoldTabBar 中央添加按钮 | 未运行 | 未运行 | 未运行 | 未运行 | 需 H5/微信开发者工具/真机通道 |
| 国内/国际口径与记忆 | `MarketHomeViewModel` | market-store 覆盖代际隔离与切换失败保留原口径 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 报价展示与真实时间 | `HomeView.swift` | QuoteHeader 组件；market-timing 覆盖 300 秒/180 秒规则 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 实时走势图与手势 | `RealtimeChartCompaction/Timing` | chart-sampling 覆盖缺口两端保留与跳变 | 未运行 | 未运行 | 未运行 | 未运行 | canvas 手势必须真机 |
| 历史走势图十种范围 | `PriceRange`、`MarketHomeViewModel` | chart-viewport 覆盖拖缩边界 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 缩略导航与区间统计 | `ChartRangeNavigator`、`ChartWindowStatistics` | chart-statistics 覆盖同价取最早 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 行情状态与缓存 | `MarketHistoryCache` | market-sync 覆盖增量/墓碑/游标推进 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 持仓总览 | `HoldingsView`、`GoldReturnCalculator` | gold-return 覆盖成本口径与零下限 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 盈亏拆解 | `GoldProfitBreakdown` | profit-breakdown 覆盖 49478/71600/142270 样例 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 多账本 | `HoldingsView` | holdings-store 覆盖迁移与去重 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 列表搜索筛选排序 | `HoldingsSelection` | holding-selection 覆盖盈利含零与四种排序 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 添加与编辑 | `AddHoldingSheet`、`HoldingDraft` | holding-draft 覆盖工费换算与总价模式 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 日期参考价 | `HoldingPurchasePriceModel` | purchase-reference 覆盖历史不取现价、手动不被覆盖 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 部分赠卖与守恒 | `HoldingDisposal` | holding-disposal 覆盖 3072+2048=5120 守恒 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 详情与计算说明 | `HoldingDetailView` | 无独立纯逻辑测试（由拆解与收益测试覆盖） | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 记金日历 | `HoldingCalendarLogic` | holding-calendar 覆盖 purchaseID 去重与闰月 | 未运行 | 未运行 | 未运行 | 未运行 | 农历需真实月份核对 |
| 买前计算器与情景 | `GoldCalculatorSheet`、`GoldScenarioSheet` | gold-scenarios 覆盖档位与不改记录 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 持仓目标提醒 | `HoldingAlert`、`HoldingAlertMonitor` | holding-alerts 27 + lifecycle 13 用例全通过 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |
| 微信订阅消息送达 | iOS 无此能力（本次新增） | Go 侧 capability/grant/幂等/越权用例通过 | 不适用 | 未运行 | 未运行 | **未运行** | **需真实 appid + 订阅模板 ID + 字段映射**；未配置时 `capabilities.available=false`，小程序不请求授权 |
| 认证（微信/手机/邮箱） | `AuthenticationSheet` | auth-session 16 + auth-forms 11 用例通过 | 未运行 | 未运行 | 未运行 | 未运行 | 真实短信/邮件服务未配置 |
| 账户生命周期与注销 | `AccountView` | auth-session 覆盖代际与删除意图 | 未运行 | 未运行 | 未运行 | 未运行 | 需隔离测试账户，勿操作真实用户 |
| 云同步与冲突 | `HoldingCloudMerge` | holding-wire 12 + holding-merge 17 + holding-sync 14 | 未运行 | 未运行 | 未运行 | 未运行 | 需两个客户端制造真实 409 |
| 收藏/授权来源与换算说明 | `MarketSources` | conversion 覆盖 31.1034768 折算 | 未运行 | 未运行 | 未运行 | 未运行 | 同上 |

## 未通过与环境阻塞

### 1. 微信订阅消息（D2）— 环境阻塞

计划要求「真实模板与平台授权未就绪时，这一验收项保持未完成」。当前状态：

- 后端 `GET /notifications/holding/capabilities` 在未配置
  `HOLDING_NOTIFICATION_TEMPLATE_ID` 时返回 `available: false`，
  小程序据此**不请求订阅授权**——这是设计行为，不是缺陷。
- 已实现并通过自动验证的部分：授权令牌只存 hash、15 分钟到期、
  专属 header、换设备拒绝、游客配置白名单校验、账户从云文档重读、
  报价 300 秒新鲜度、requestID 幂等、成功前不消耗冷却、超时记 unknown。
- **缺真实模板**：需要在微信公众平台申请订阅消息模板，并把模板 ID 与
  各 `thing` 字段名填入 `.env`。字段名不能猜——实施前须重新核对
  官方发送接口文档。
- **未验证**：真实授权弹窗、真机收信、模板字段渲染、耗尽与拒收状态。

**因此不能宣称「除 Apple 外全部一致」。**

### 2. 数据库集成测试 — 未运行

`TEST_DATABASE_URL` 未设置，`TestCASIsolationAndDeletion`、
`TestNativeDeleteRemovesHoldingsAtomically` 等用例按设计跳过。
CAS 隔离、原子删除、微信身份迁移的**真实数据库行为未经验证**，
只有纯逻辑层测试通过。需要指向一个可丢弃的测试库后重跑。

### 3. 全部 UI 与真机项 — 未运行

本次为无人值守执行，没有 H5 浏览器、微信开发者工具与真机通道。
以下必须人工核对，不能以「构建成功」替代：

- canvas 单指查价、双指缩放、范围手柄
- 深色表单与系统键盘、日期时间选择器
- 安全区与微信胶囊避让
- 前后台切换、弱网与离线
- 微信登录与订阅授权
- 农历月份与跨月边界

### 4. 微信服务端文档未重新核对

D2 计划要求「实施前须重新核对官方发送接口文档」。本轮实现按已知的
`cgi-bin/message/subscribe/send` 契约编写，但**未在本次会话中联网
重新核对**。接入真实模板前必须先核对，否则字段映射可能有误。

## 跨端一致性

`tests/fixtures/holdings-parity.json` 是唯一的跨端样例源，由 TS 测试实际
驱动（`holdings-parity.test.ts`）。同一份样例应送入 Swift 端
`GoldReturnCalculatorTests` 对照。

**尚未执行该对照**——iOS 侧没有新增对应的 fixture 读取用例。
已逐位对齐的是 Swift 现有测试中的样例值：

| 样例 | Swift 期望 | 小程序实测 |
| --- | --- | --- |
| 计划固定样例 | 成本 5120 / 到手 5694.18 / 利润 574.18 | 一致 |
| 盈亏拆解总盈亏 | 49478 分 | 一致 |
| 固定费用贡献 | −71600 分 | 一致 |
| 分组合计 | +142270 / −59512 分 | 一致 |
| 半分舍入 | 0.125 元 → 12 分；−0.125 元 → −12 分 | 一致 |

## 已知实现差异

**处置状态校验**：iOS `HoldingCloudDocument.isValid` 只在
`disposition != "holding"` 时校验 `disposedAt`，持有中记录若带一个早于
购入时间的脏 `disposedAt` 会漏过。小程序侧已补全为「`disposedAt`
一旦存在就必须合法且不早于购入时间」。

**该差异尚未在 iOS 侧修正**，因此两端校验严格性目前不一致。
若要求两端完全一致，需在 Swift 侧同步补上。
