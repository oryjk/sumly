# 小程序持仓与计算 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 游客可离线完成 App 的记金、账本、赠卖、日历、收益拆解和测算功能。

**Architecture:** 云兼容文档是唯一持仓模型，持久化事务与纯 TS 收益/处置/日历内核独立，页面使用 store 编排。移植当前 Swift 算法和测试样例，不在页面重复计算。

**Tech Stack:** 既有 uni-app/Vue/TypeScript，Bun 测试，uni 同步存储。

**Spec:** `docs/superpowers/specs/2026-10-03-mini-app-parity-design.md`。

## Global Constraints

继承总计划所有约束。依赖 A1 的主题/导航、A2 的行情 API；金额核心沿用 Swift Double，云日期保存数字而不经 JS Date 丢失小数毫秒。

## Review Focus

零价/实付覆盖/纯度/非有限值（B1），部分处置守恒及多次拆分（B2），手工价保护（B3），日历去重与整数分溢出/半分舍入（B4）。

---

### B1：持仓模型与收益计算内核

**Files:** Create `src/types/holdings.ts`、`src/domain/holdings/{document,returns,presentation}.ts`、`tests/fixtures/holdings-parity.json`、`tests/{holding-document,gold-return}.test.ts`。

**Interfaces:** `HoldingRecord/HoldingAlert/HoldingDocument` 精确复制 OpenAPI 字段，dates 为 number，unknown assetType 为 string，record.id 为规范化 UUID string。`GoldReturnInput={grams,purity,unitPrice,laborFee,otherCost,totalCostOverride:number|null,rule:{perGramDeduction,discountRate,fixedFee}}`；产生 `validateDocument(value: unknown): HoldingDocument`、`returnInput(record): GoldReturnInput`、`calculateReturn(input,referencePrice:number|null): GoldReturnResult|null`、`aggregateReturn(inputs,referencePrice,previousPrice?:number|null): GoldPortfolioReturn|null`、`referencePrice(input,targetProceeds): number|null`、`formatMoney(value:number|null,hidden:boolean,signed?:boolean): string`。结果字段逐项对应 Swift 同名结构。

- [ ] 写同输入跨端样例与校验测试：10g/500/0.99/工费100/其他20/扣减10/折价0.02/固定费30/报价600，成本5120、到手5694.18、利润574.18；实付5200时成本恰为5200；缺报价利润null，NaN拒绝；零裸金价且正实付合法；UUID大小写重复拒绝、未知assetType保留、小数毫秒不改值。
- [ ] 运行 `bun test tests/holding-document.test.ts tests/gold-return.test.ts` 确认失败。
- [ ] 按 `GoldReturnCalculator.swift` 移植，包括到手零下限、零成本收益率null、每笔固定费、组合保本80轮二分和今日差额。文档校验实现服务端 100账本/1000记录/每记录4提醒、文本Unicode标量/NUL/日期范围/关联账本约束，金额隐藏统一格式化。
- [ ] 运行测试；将 fixture 输入实际送入 Swift 纯逻辑测试比较，不手抄未经验证的输出；对照接口序列化字段全覆盖。
- [ ] 只提交本任务变更：`feat(mini): port holdings contract and return calculations`。

### B2：工作区、账本、列表与部分赠卖

**Files:** Create `src/utils/holdingStorage.ts`、`src/domain/holdings/{disposal,selection}.ts`、`src/stores/holdings.ts`、`src/pages/holdings/index.vue`、`src/pages/holdings/components/{HoldingCard,BookPicker,BatchActions,DisposeHolding,DisposalHistory}.vue`、`tests/{holding-storage,holding-disposal,holding-selection}.test.ts`；Modify `src/pages.json`。

**Interfaces:** `WorkspaceKey='guest'|\`user:${number}\``；`HoldingWorkspace={schemaVersion:1;key:WorkspaceKey;document:HoldingDocument;sync:{revision:string;base:HoldingDocument}|null}`（revision 处理由 C3 定义）。产生 `loadWorkspace(key): HoldingWorkspace`、`saveWorkspace(workspace): void`、`disposeHolding(document,id,grams,proceeds,kind:'sold'|'gift',disposedAt,counterparty,now): HoldingDocument`、`selectHoldings(records,book,search,filter:'all'|'profit'|'loss',sort:'newest'|'oldest'|'heaviest'|'costliest',price): HoldingRecord[]`。store `useHoldingsStore()` 提供 `workspace/document/pendingSync/saveError`、`openWorkspace(key)`、`mutate(update:(doc)=>HoldingDocument):void`、`addBook(name)`、`moveRecords(ids,book)`、`deleteRecords(ids)`；mutate 成功落盘后才发布新状态。

- [ ] 写测试：10g成本5120卖4g后余6g成本3072/已售成本2048，总克数及成本守恒；再次拆分仍同purchaseID且总成本不变；赠送实收0、处置日期非法拒绝、已处置不再处置；卖出清空自身提醒、剩余提醒重置运行基线；存储失败不发布更改；盈利含零利润、搜索品牌备注、四种排序与全选只选可见记录。
- [ ] 运行 `bun test tests/holding-storage.test.ts tests/holding-disposal.test.ts tests/holding-selection.test.ts` 确认失败。
- [ ] 实现单存储槽工作区及纯处置算法（包括费用/实付按比例分摊，回收固定费按 App 原规则保留）；实现总览、账本、搜索筛选排序、金额隐藏、批量/单条迁移删除、左滑赠卖与记录页；确认前不实际删除。
- [ ] 运行目标测试和双平台构建；H5/微信操作多账本、连续部分卖出、赠送、失败落盘；重开页面/应用仍保留记录。
- [ ] 只提交本任务变更：`feat(mini): add local holdings and disposal workflows`。

### B3：添加编辑与日期参考价

**Files:** Create `src/domain/holdings/draft.ts`、`src/stores/purchaseReference.ts`、`src/pages/holdings/edit.vue`、`src/pages/holdings/components/{PurchaseFields,RecoveryFields}.vue`、`tests/{holding-draft,purchase-reference}.test.ts`；Modify `src/pages.json`、A1 添加导航。

**Interfaces:** `HoldingDraft` 对应当前 Swift draft 表单；产生 `draftToRecord(draft,existing:HoldingRecord|null,now:number): HoldingRecord`、`usePurchaseReference(basis,initialDay,initialPrice?)` 的 `reference/priceText/manual/issue/loading`、`selectDate(day:string)`、`editPrice(text)`、`useReference()`、`load(nowMs):Promise<void>`。参考价为 `{day:string;price:number;historical:boolean;exchangeRate:number|null}`，只读 A2 API/缓存。

- [ ] 写测试：工费按克/总额转换一致；克数/纯度/折价非法拒绝；选历史日不拿现价填；休市当日无收盘则missingDay；国际缺汇率错误；手动编辑后晚响应不覆盖；快速切日期只提交最后日期；编辑保留UUID/createdAt和处置关联。
- [ ] 运行 `bun test tests/holding-draft.test.ts tests/purchase-reference.test.ts` 确认失败。
- [ ] 实现全字段表单、手动/参考价状态、当天/历史切换、错误与重复提交保护；黄金类型枚举复制 `GoldAssetType`，未知历史类型编辑仍保留；人工输入上限沿用 App。编辑前后未变的提醒配置保留设备状态，影响收益输入的修改重置基线。
- [ ] 运行目标测试、类型检查与双平台构建；微信验证小数输入、日期时间、历史休市、编辑保存和底栏中央添加，结果与 App 对照。
- [ ] 只提交本任务变更：`feat(mini): add gold entry forms and historical references`。

### B4：详情、盈亏拆解、日历与测算

**Files:** Create `src/domain/holdings/{breakdown,calendar}.ts`、`src/utils/moneyCents.ts`、`src/pages/holdings/{detail,calendar,calculator,scenario}.vue`、`src/pages/holdings/components/{ProfitBreakdown,CalculationExplanation,CalendarSummary}.vue`、`tests/{profit-breakdown,holding-calendar,gold-scenarios}.test.ts`；Modify `src/pages.json`。

**Interfaces:** 产生 `estimateBreakdown(inputs,price): GoldProfitBreakdown|null`、`saleBreakdown(totalCost,proceeds): GoldProfitBreakdown|null`；分项 cents/totalCents 用十进制整数字符串避免 JS safe integer 丢精度，比较与累加封装于 moneyCents。`calendarEvents(records,filter): HoldingCalendarEvent[]`、`selectCalendarEvents(events,period:'day'|'month'|'year'|'all',dateMs): HoldingCalendarEvent[]`、`calendarSummary(events,records,price,now): HoldingCalendarSummary`、`scenarioReturn(input,price): GoldReturnResult|null`。事件/summary 字段逐项对应 Swift；测算保存调用 B3。

`moneyCents(value:number):string|null` 采用App已验证的十进制半偶舍入，超出Int64拒绝；`addCents(a:string,b:string):string`、`compareCents(a:string,b:string):-1|0|1`。固定fixture至少包括单笔参考900/买入899.875 => `profitCents:'12'`、买入900.125 => `'-12'`，以及App测试中的49478分详细费用样例。不能直接用JS Math.round替代Foundation格式化。

- [ ] 写测试：累计边界舍入的分项合计精确等于总盈亏分，手动总价只列unitemized、贡献记录同名仍分开、已卖出只用实收、Int64外金额拒绝而非错误展示；购入族分拆购入件数仍1、卖/赠按各事件日期、跨月/闰月/跨年与历史估值沿用 Swift 样例；±5/10%情景不修改记录，计算器转换保持输入。
- [ ] 运行 `bun test tests/profit-breakdown.test.ts tests/holding-calendar.test.ts tests/gold-scenarios.test.ts` 确认失败。
- [ ] 移植 `GoldProfitBreakdown` 累计边界/贡献舍入、`HoldingCalendarLogic` 及历史估值；完成详情、真实/账面金额、贡献下钻与说明、日/月/年/全部日历、农历、筛选、买前计算器、情景测算。农历使用能在微信运行的纯逻辑，不假定浏览器Intl可用；范围与 Swift fixture 校准。
- [ ] 运行全部持仓测试、类型检查/双构建；App/H5/微信用同一fixture逐页对比金额、拆解和事件；农历超出算法支持范围不能显示伪日期。
- [ ] 只提交本任务变更：`feat(mini): reproduce holding analysis calendar and calculators`。
