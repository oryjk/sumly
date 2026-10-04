# 小程序行情与界面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 游客可使用与 App 一致的主题、导航、国内/国际行情和完整图表交互。

**Architecture:** API 适配、纯逻辑图表模型、持久化缓存、页面编排与 canvas 绘制分离。复用 Go quote/realtime/sync 接口，原始数据用于查价/统计，抽样只影响绘制。

**Tech Stack:** 既有 uni-app/Vue/TypeScript，Bun 内置测试，跨 H5/微信 canvas。

**Spec:** `docs/superpowers/specs/2026-10-03-mini-app-parity-design.md`。

## Global Constraints

继承 `2026-10-03-mini-app-parity.md` 的全部约束；本计划不修改 Go 行情行为。Intl/浏览器特性不能作为未经微信真机验证的运行依赖。

## Review Focus

重点验证稀疏休市、跨午夜、过期报价、五秒/分钟采样、换口径晚到响应及缓存写入失败，分别归属 A2/A3。

---

### A1：主题、导航和测试入口

**Files:** Modify `sumly_mini/src/uni.css`、`src/pages.json`、`src/App.vue`、`src/components/NeoInput/NeoInput.vue`、`package.json`、`AGENTS.md`；Create `src/components/GoldTabBar/GoldTabBar.vue`、`src/components/GoldInput/GoldInput.vue`、`src/stores/navigation.ts`、`tests/navigation.test.ts`。旧 NeoInput 过渡引用新控件，避免双主题。

**Interfaces:** 产生 `TabKey = 'market' | 'holdings' | 'account'`、`tabPath(tab: TabKey): string`、`openAddHolding(): void`、`GoldInput` 的 `modelValue/update:modelValue`、`GoldTabBar` 的 `active` 属性及 `add` 事件。路径分别为 `/pages/home/index`、`/pages/holdings/index`、`/pages/user/index`；添加页 `/pages/holdings/edit` 在 B3 注册后启用。

A1 先创建/注册 `src/pages/holdings/index.vue` 的可导航空状态页面，B2 改为真实持仓编排；添加操作在B3前显示功能建设状态，不跳转不存在页面。最终验收不保留此过渡状态。

- [x] 写 `tests/navigation.test.ts`：`expect(tabPath('account')).toBe('/pages/user/index')`；三个 Tab 能映射到注册页面，添加操作复用同一表单。缺少 B3 时不注册不存在的页面链接。
- [ ] 运行 `cd sumly_mini && bun test tests/navigation.test.ts`，确认因接口未实现失败。
- [x] 实现上述文件，统一 `--gold-*` 令牌、移除粗黑阴影；自定义导航/底栏处理安全区与微信胶囊；AGENTS 视觉规定改为批准主题，原登录入口移至“我的”。保持未开放记账提示，首页订阅入口由 A3 恢复。
- [ ] 运行目标测试、`bun run type-check` 和两个平台构建；H5 核对深色、安全区和底栏，微信编译产物检查 `usingComponents`。低风险视觉值不另写样式快照测试。
- [x] 只提交本任务变更：`feat(mini): align gold theme and navigation`。

### A2：真实行情契约、缓存和增量同步

**Files:** Create `src/types/market.ts`、`src/api/market.ts`、`src/domain/market/{sync,conversion,timing}.ts`、`src/utils/marketStorage.ts`、`src/stores/market.ts`、`tests/{market-sync,market-store,market-timing}.test.ts`；Modify `src/mock/handlers.ts`。

**Interfaces:** `MarketBasis = 'domestic' | 'international'`、`MarketSeries = 'au9999' | 'xauusd'`。quote/realtime DTO 按 OpenAPI 原始 snake_case 定义；`ChartPoint = { time: number; price: number; granularity: 'annual'|'daily'|'realtime'; source: string }`。产生 `getGoldQuote(basis): Promise<GoldQuote>`、`getGoldRealtime(basis): Promise<GoldRealtime>`、`getMarketSync(series, cursor?): Promise<MarketSyncPage>`、`mergeMarketSync(previous: MarketCache|null, page: MarketSyncPage): MarketCache`、`toCnyPoints(cache: MarketCache, quote: GoldQuote|null): ChartPoint[]`、`realtimeState(sampleMs: number|null, quoteMs: number|null, intervalSeconds: number, nowMs: number): 'live'|'paused'|'empty'`、`useMarketStore()` 的 `basis/quote/points/error/status`、`switchBasis(next): Promise<boolean>`、`start()/stop()/clearCache()`。

`MarketCache={series:MarketSeries;unit:'CNY/g'|'USD/troy_oz';cursor:string;points:MarketSyncPoint[]}`，MarketSyncPoint字段复制 `MarketSyncService.swift`，缓存中不保留deleted tombstone。store lifecycle 明确为 `start(owner:'market'|'holdings'):void`、`stop(owner:'market'|'holdings'):void`、`clearCache():void`；市场报价/实时5秒、历史60秒，持仓报价3秒；每条流独立调度，慢历史不阻塞实时，没有活动owner则暂停。

- [x] 写契约/状态测试：reset 替换、增量删除与修正、空增量仍更新 cursor、品种/单位错配拒绝；`expect(realtimeState(now-21000, now, 5, now)).toBe('paused')`、分钟样本 119 秒 live/121 秒 paused、报价 181 秒 paused；国际按 `USD * usd_cny / 31.1034768`，无有效汇率为空值；慢国内请求不得覆盖已切换国际；缓存写失败不推进 cursor。
- [x] 运行 `bun test tests/market-sync.test.ts tests/market-store.test.ts tests/market-timing.test.ts` 确认失败。
- [x] 实现接口：国内 `/market/gold/instruments/au9999/{quote,realtime}`、国际 `/market/gold/{quote,realtime}`、历史 `/market/gold/sync?series=...&cursor=...`。cache 一次保存 points/cursor/unit/series；date 键严格解析，年度只允许国际 1900–2015。刷新周期从当前 `MarketHomeViewModel.start()`/HoldingsViewModel 实现提取并在测试固定，不按旧 README 猜测。生命周期只持有一个轮询器；切换等待目标数据后提交。补所有 mock 路径，去掉 mock 中依赖浏览器 `URL` 的解析。
- [ ] 运行目标测试与类型检查；关闭 mock 联调两种口径，核对字段、单位、来源、原时间及缓存恢复。记录网络验证证据，不把缓存标为实时。
- [x] 只提交本任务变更：`feat(mini): add gold market services and durable history`。

### A3：行情页面与交互图表

**Files:** Modify `src/pages/home/index.vue`；Create `src/domain/market/{viewport,sampling,statistics,ranges,scale}.ts`、`src/pages/home/components/{GoldChart,ChartNavigator,ChartDateRange,QuoteHeader,MarketSources}.vue`、`tests/{chart-viewport,chart-statistics,chart-sampling}.test.ts`。

**Interfaces:** 消费 A2；产生 `MarketRange = 'realtime'|'month'|'quarter'|'yearToDate'|'year'|'twoYears'|'threeYears'|'fiveYears'|'tenYears'|'history'`、`ChartWindow={start:number;end:number}`、`rangeWindow(range,points,now): ChartWindow|null`、`moveWindow(bounds,window,part:'start'|'end'|'window',fraction): ChartWindow`、`zoomWindow(bounds,window,anchorMs,factor): ChartWindow`、`nearestPoint(points,time): ChartPoint|null`、`windowStatistics(points,window): ChartStatistics|null`、`sampleForDrawing(points,maxPoints): ChartPoint[]`、`priceScale(points): {min:number;max:number}`。组件 GoldChart 接收 `points/window`、发出 `select/window-change`；ChartNavigator 接收 `points/bounds/window`、发出 `window-change`。

`ChartStatistics={first:ChartPoint|null;last:ChartPoint|null;high:ChartPoint|null;low:ChartPoint|null;change:number|null;percent:number|null}`；只有至少两个有效原始点才显示change/percent，最高/最低同价时取最早真实时间。

- [x] 写测试：拖缩不越界/不反转；窄窗口仍可操作；跨午夜标签含日期；休市不补点；稀疏数据最近点匹配原时间；抽样保留首尾/极值，查价/统计仍按原数据；固定微小波动不会放大整图，精确刻度沿用 Swift `ChartPriceScale`。按 Swift 测试迁移具体输出样例。
- [x] 运行三个目标测试文件确认失败。
- [x] 移植 Swift viewport/statistics/sampling/scale 算法，完成报价、暂停时间、十种范围、缩略导航、日期选择、加载/失败/重试/说明/订阅暂未开放等所有展示。canvas 绘制按 `uni` 能力封装，触摸逻辑不依赖 DOM；国内历史可用起点限制与国际年度标签沿用 App，不合成国内百年数据。
- [ ] 运行全部 market/chart 测试、类型检查与双平台构建；微信开发者工具/真机操作单指查价、双指缩放、范围手柄、口径切换与返回前台，核对 App 截图和时间统计。
- [x] 只提交本任务变更：`feat(mini): reproduce interactive market dashboard`。
