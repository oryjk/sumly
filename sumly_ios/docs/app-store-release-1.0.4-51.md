# App Store & TestFlight 1.0.4（51）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`dc67b8a7ebb6d957dbeace6ce5d39cea3e51a54a`（已于归档与上传前推送至 `origin/main`）。
  - 本版本叠加既有 `1.0.4 (47)`～`(50)` 全部功能（悬浮胶囊底栏与「持有」页重构、3 秒极简入库与黄金形态联动补充细节、「金豆」品类与金属质感图标、「我的攒金盒」里程碑卡片与入库纪念卡、攒金陪伴日历重构、首页走势图买入点红点虚线连接/角标/滑查浮窗/多笔明细抽屉、黄金温度计「短期热度 × 长期宏观」分栏客观解读及宏观线性/对数坐标切换、WidgetKit 桌面与锁屏小组件），并新增以下核心提交：
    - `0dc36e7`（0 冲突 cherry-pick 自 `81cfb0bd7acfe57cf5b3dbac91514eafab1c48d1`）：修复首页走势图买入点位明细与曲线滑查浮窗中「买入单价 vs 当日参考金价」差额的视觉配色与文案语义（买贵「多花」采用绿色 `GoldTheme.down`，买便宜「省」采用红色 `GoldTheme.up`，区分正常交易日与休市插值日文案）。
    - `f77bb16`（0 冲突 cherry-pick 自 `1a43588c73512e82423b0697f4f30969548ede75`）：可视化重构「怎么算的？」计算拆解页（新增 `GoldCalculationSheet.swift` 与 `GoldCalculationBreakdownTests.swift`，通过堆叠对比柱状图与每克保本价构成尺直观拆解克重价值、工费与回收费用构成，底部可折叠查看完整参数公式并支持隐私脱敏）。
    - `dc67b8a`（`dc67b8a7ebb6d957dbeace6ce5d39cea3e51a54a`）：同步主 App `Sumly` 与扩展 `SumlyWidget` 版本号与构建号至 `1.0.4 (51)`。
- Bundle ID：`com.oryjk.sumly`（主 App）+ `com.oryjk.sumly.widget`（WidgetKit 扩展），版本：`1.0.4`，构建号：`51`，最低 iOS `17.0`。

## 构建与 TestFlight 内测通道

- 通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，本地 `Release` 归档 + 本地手动签名导出 + App Store Connect JWT API 上传及处理轮询）完成单一签名 IPA 上传。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b51/Sumly.ipa`，SHA-256：`828c8de831e171f81c20d76e9ca53bfcaebc81027aa4c901a2593b52b90e85a9`。
- IPA 结构核验：同时包含 `Payload/Sumly.app`（`com.oryjk.sumly`，含 `Info.plist` 与 `embedded.mobileprovision`）及 `Payload/Sumly.app/PlugIns/SumlyWidget.appex`（`com.oryjk.sumly.widget`，含 `Info.plist` 与 `embedded.mobileprovision`），主 App 与小组件版本/构建号均为 `1.0.4 (51)`。
- Apple Build ID / Upload Reservation ID：`62cf065b-08d7-4654-96c1-d13dc9ea6cf0`（上传时间 `2026-11-21T04:58:57-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `buildAudienceType`：`APP_STORE_ELIGIBLE`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未主动触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `51`（当前 2 名内部测试员）。

## App Store 线上版提审通道

- 复用同一有效构建 `62cf065b-08d7-4654-96c1-d13dc9ea6cf0`（`1.0.4 (51)`），未重复打包或上传。
- 已撤回原 `1.0.4 (47)` 审核单 `cb222ecb-de9a-470d-b619-a38f15f9634f`，将 App Store 版本 `1.0.4`（版本 ID：`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`，`releaseType=AFTER_APPROVAL`）关联构建切换为 `51`。
- 同步更新全部现有本地化（简体中文 `zh-Hans`，本地化 ID：`9f287f2c-0577-4457-8011-ba5d3e767d40`）的 `whatsNew` 更新说明，以及审核说明 `appStoreReviewDetail`（ID：`4881f1c6-0438-4696-bb34-d103d1c9c0a4`）；沿用既有已就绪的 iPhone 6.7"（4 张）与 iPad Pro 12.9"（4 张）商店截图。
- `whatsNew` 摘要（100% 客观功能描述，无投顾/交易建议及付费社群内容）：
  - 悬浮胶囊底栏与「持有」页、3 秒极简入库与按黄金形态动态联动的记账补充细节；
  - 新增「金豆」品类、金属质感图标、「我的攒金盒」里程碑卡片与入库纪念卡分享；
  - 「怎么算的？」计算拆解页可视化升级（堆叠对比柱状图、每克保本价构成尺、折叠公式与隐私脱敏）；
  - 攒金陪伴日历重构（日收益热力图、年度总览、日账本卡片、支持隐私脱敏的月度/年度海报分享）；
  - 首页走势图买入记录可视化（红点垂直虚线连接、单/多笔角标、滑查浮窗、多笔明细抽屉及买入单价与参考金价差额对比）；
  - 黄金温度计「短期热度 × 长期宏观」分栏客观解读与线性/对数坐标切换；
  - 桌面与锁屏金价小组件。
- 北京时间 `2026-11-21 21:02:44`（`2026-11-21T13:02:44.185Z`）完成提审，新审核单 ID：`40e560a9-415a-406d-8e93-83c5fec5182f`。
- App Store Connect 最终核实：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）与审核单（`40e560a9-415a-406d-8e93-83c5fec5182f`）状态均为 **`WAITING_FOR_REVIEW`**，绑定构建 `51`（`62cf065b-08d7-4654-96c1-d13dc9ea6cf0`），发布方式 `AFTER_APPROVAL`（审核通过后自动发布）。
  - 在售版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）只读核对仍为 **`READY_FOR_SALE`**，绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`），未受影响。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，**321 项单测（10 个测试套件）全部通过**，零编译错误、零 Swift 6 编译警告。
