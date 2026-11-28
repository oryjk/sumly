# 记金 1.0.7（69）内测发布

2026-11-27，北京时间。

- 源码分支为 `main`，功能与版本提交为 `b71bde412f7b29249354e4c4e98bc268a63c6152`。
- 本次变更：Wave 1 性能/可靠性止血修复与国内实时分时方案 A 修复。
  - **iOS 客户端**：`HoldingsCloud` 引入内存态 `hasPendingLocalChanges` / `guestRecordCount` 缓存以消除账户状态与徽章路径的同步 SwiftData 查询，拆分 `LiveGoldQuoteStore` 按口径属性并做全路径相等短路去重，`SumlyApp` 通过 `isActive` 与 `LiveQuoteSyncBridge` 隔离非激活 Tab 刷新，`HomeView` 消除双重报价轮询并拆分子视图；国内实时分时轴调整为连续日盘 `09:00–15:30` + 夜盘 `20:00–02:30`（780 槽位），保留 `11:31–13:29` 连续数据并移除午休误判，后端降级仅返回夜盘时自动切换 390 槽位 `.domesticNightSession` 消除左半屏空白，并通过 `domesticDayPlusNightAnchor` 统一顶部涨跌与分时较昨收基准价。
  - **Go 服务端与 Android 同步提交**：后端修复 `wechatclient` / `bootstrap` 超时客户端兜底、持仓提醒双口径（`domestic`/`international`）评估与用户鉴权、显式 `pgxpool` 连接池配置及优雅停机排空，分时采集改为集金号双页抓取与事务内 48h 合并去重并支持 `window=day` 全日盘+夜盘及昨收基准；Android 端下沉顶层页面状态订阅作用域、隔离行情页重组并同步适配国内无午休 24h 分时与 `window=day` 降级链路。
- 签名 IPA 的主 App 与小组件均为 `1.0.7 (69)`。IPA SHA-256 为 `5d54ccc8f8fbabbde6719c0315f9add964bf5563f6e182ba300752cfda717aab`。
- App Store Connect 构建 ID 为 `0cfce157-c708-4416-a65e-01070790afbd`。构建为 `VALID / IN_BETA_TESTING`，内部「测试」组（`f079109b-a665-463e-add4-5359f91dbe47`）含构建 69，自动分发已开启（`hasAccessToAllBuilds=true`）；未分发外部测试组。
- 验证：iOS 端 `make test-auth`（35/35）与 `make test`（iPhone 17 模拟器核心单测全绿，`GoldKeyboardDismissTests` 单独复跑 7/7 通过），Go 后端 `go test -count=1 ./...` / `-race` / `go vet ./...` 通过，Android 端 `:app:testDebugUnitTest` 通过；签名 IPA 经 `upload_app_store.sh` → `upload_signed_ipa.py`（JWT API）上传并由 Apple 完成处理与内部 TestFlight 自动分发核验。

## App Store 1.0.7（69）正式提审准备与阻断记录

- 操作时间：2026-11-28 01:19（北京时间）。
- 复用构建：直接复用已上传且 `VALID` 的构建 `69`（`0cfce157-c708-4416-a65e-01070790afbd`，源码分支 `main`，源码提交 SHA `b71bde412f7b29249354e4c4e98bc268a63c6152`，`buildAudienceType=APP_STORE_ELIGIBLE`、`usesNonExemptEncryption=false`、`expired=false`），未重新打包或重复上传 IPA。
- App ID：`6813884595`
- App Store 版本 `1.0.7`（版本 ID：`dd07ba0e-e993-4e6a-885b-63d83888d580`）：
  - 当前状态：`appStoreState=PREPARE_FOR_SUBMISSION`、`appVersionState=PREPARE_FOR_SUBMISSION`、`releaseType=AFTER_APPROVAL`
  - 已绑定构建：已由旧构建 `66` 替换为构建 **`69`**（`0cfce157-c708-4416-a65e-01070790afbd`）
  - 审核说明 `appStoreReviewDetail`：`d1b4331f-cd0a-449d-b338-f2eb4308258c`（已更新为 `1.0.7 (build 69)` 审核说明，`demoAccountRequired=false`）
  - 6 语种 `appStoreVersionLocalizations` 的 `whatsNew` 已全部更新保存（覆盖家人持仓与定制头像、全天实时分时走势图与连续性修复、性能/渲染流畅度优化、多线路连接稳定性增强）：
    - `zh-Hans`：`7fa186f1-a981-4faa-a929-0490ca76be29`
    - `en-US`：`dfa4e503-bcee-4f37-affa-5b47dd1abe98`
    - `es-ES`：`dcc26dde-b23c-4c3e-b433-1f734f5e319b`
    - `fr-FR`：`2e168402-d83a-45df-acad-8d4b78ce8cf6`
    - `pt-BR`：`6f62d64f-0989-404c-892f-834c02f805bc`
    - `ja`：`5928dba5-5ab2-49e5-8e76-8d02287c8f13`
- **正式提交阻断（Apple 后台 ICP 备案主体名核验，需网页端人工确认）**：
  - 草稿审核单 `reviewSubmission` ID：`8d246dfc-67ff-435c-9a6a-e4134f6b19a2`（`platform=IOS`、`state=READY_FOR_REVIEW`、`submittedDate=null`、`items=0`）
  - 调用 `POST /v1/reviewSubmissionItems` 关联 `appStoreVersion` `dd07ba0e-e993-4e6a-885b-63d83888d580` 时，Apple 返回 `HTTP 409`：
    - 顶层错误：`STATE_ERROR.ENTITY_STATE_INVALID` — `appStoreVersions with id 'dd07ba0e-e993-4e6a-885b-63d83888d580' is not in valid state.`
    - 关联错误路径：`/v1/appIcpNumberDetails/6813884595`
    - 关联错误码：`STATE_ERROR.ICP_NUMBER_MIIT_PROVIDER_NAME_MISMATCH`
    - 关联错误原文：`Provider name mismatch.` / `Your developer name does not match MIIT's records.`
  - 原因与后续操作：与 `1.0.6 (61)` 提审时遇到的 Apple 后台限制一致，App Store Connect 公开 REST API 不提供 `/v1/appIcpNumberDetails` 的人工确认接口。`1.0.7 (69)` 的构建关联、6 语种更新说明与审核备注均已保存就绪，需开发者登录 App Store Connect 网页端确认中国大陆 ICP 备案提示后，在 `1.0.7` 版本页面点击「添加以供审核 / 提交以供审核」（或网页端确认后重新通过 API 提交审核单 `8d246dfc-67ff-435c-9a6a-e4134f6b19a2`）。
- 线上在售版本核对：版本 `1.0.6`（`8a52f4ba-749a-4d27-a469-23507217cf3c`）保持 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），未受影响。

## App Store 1.0.7（69）正式提审结果

- 提交时间为 2026-11-28 12:25（北京时间），以 App Store Connect 审核详情为准。
- 版本 `1.0.7`，构建 `69`。复用 `main` 分支源码提交 `b71bde412f7b29249354e4c4e98bc268a63c6152` 的签名构建。提审前已核实 `origin/main`（`bf2b43ccf2005434697400e3b986f2e4546f4b79`）包含该源码提交与提审准备记录。
- 在 App Store Connect 网页端将版本添加至现有 iOS 草稿并提交。此前的 ICP 提供商名称不符提示未再阻断提审。
- Apple 确认已提交 1 个项目。审核单 `8d246dfc-67ff-435c-9a6a-e4134f6b19a2` 中仅包含 iOS `1.0.7 (69)`，审核单和版本项目均显示「等待审核」。
