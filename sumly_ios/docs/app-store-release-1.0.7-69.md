# 记金 1.0.7（69）内测发布

2026-11-27，北京时间。

- 源码分支为 `main`，功能与版本提交为 `b71bde412f7b29249354e4c4e98bc268a63c6152`。
- 本次变更：Wave 1 性能/可靠性止血修复与国内实时分时方案 A 修复。
  - **iOS 客户端**：`HoldingsCloud` 引入内存态 `hasPendingLocalChanges` / `guestRecordCount` 缓存以消除账户状态与徽章路径的同步 SwiftData 查询，拆分 `LiveGoldQuoteStore` 按口径属性并做全路径相等短路去重，`SumlyApp` 通过 `isActive` 与 `LiveQuoteSyncBridge` 隔离非激活 Tab 刷新，`HomeView` 消除双重报价轮询并拆分子视图；国内实时分时轴调整为连续日盘 `09:00–15:30` + 夜盘 `20:00–02:30`（780 槽位），保留 `11:31–13:29` 连续数据并移除午休误判，后端降级仅返回夜盘时自动切换 390 槽位 `.domesticNightSession` 消除左半屏空白，并通过 `domesticDayPlusNightAnchor` 统一顶部涨跌与分时较昨收基准价。
  - **Go 服务端与 Android 同步提交**：后端修复 `wechatclient` / `bootstrap` 超时客户端兜底、持仓提醒双口径（`domestic`/`international`）评估与用户鉴权、显式 `pgxpool` 连接池配置及优雅停机排空，分时采集改为集金号双页抓取与事务内 48h 合并去重并支持 `window=day` 全日盘+夜盘及昨收基准；Android 端下沉顶层页面状态订阅作用域、隔离行情页重组并同步适配国内无午休 24h 分时与 `window=day` 降级链路。
- 签名 IPA 的主 App 与小组件均为 `1.0.7 (69)`。IPA SHA-256 为 `5d54ccc8f8fbabbde6719c0315f9add964bf5563f6e182ba300752cfda717aab`。
- App Store Connect 构建 ID 为 `0cfce157-c708-4416-a65e-01070790afbd`。构建为 `VALID / IN_BETA_TESTING`，内部「测试」组（`f079109b-a665-463e-add4-5359f91dbe47`）含构建 69，自动分发已开启（`hasAccessToAllBuilds=true`）；未分发外部测试组，未提交 App Store 正式审核。
- 验证：iOS 端 `make test-auth`（35/35）与 `make test`（iPhone 17 模拟器核心单测全绿，`GoldKeyboardDismissTests` 单独复跑 7/7 通过），Go 后端 `go test -count=1 ./...` / `-race` / `go vet ./...` 通过，Android 端 `:app:testDebugUnitTest` 通过；签名 IPA 经 `upload_app_store.sh` → `upload_signed_ipa.py`（JWT API）上传并由 Apple 完成处理与内部 TestFlight 自动分发核验。
