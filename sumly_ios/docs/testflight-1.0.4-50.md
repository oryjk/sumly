# TestFlight 1.0.4（50）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`a74f8d4bd6a45b2179de46bafb894052f9a883d1`（已于打包上传前推送至 `origin/main`）。
  - 本构建包含以下核心提交：
    - `5df31f7cc49d584c36024e271b39a540ce6f6ff6`（0 冲突 cherry-pick 自 `493f76d1361e5df2f4a0b72d3d6c85a233347532`）：首页走势图买入点提示与多笔明细抽屉功能（含红点图例、单笔/多笔买入角标、滑查买入点浮窗与多笔明细半屏抽屉，新增 `ChartPurchaseMarkerSheet.swift` 与 `ChartHoldingMarkerTests.swift`，更新 `HoldingsInsights.swift`、`ChartGestureSurface.swift`、`HomeView.swift` 与 `MarketHomeChartContent.swift`）。
    - `a74f8d4bd6a45b2179de46bafb894052f9a883d1`：同步递增主 App `Sumly` 与扩展 `SumlyWidget` 的构建号至 `1.0.4 (50)`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.4`，构建号：`50`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰正在排队审核的 App Store `1.0.4 (47)` 与已上架的 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出与 App Store Connect JWT API 上传及处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b50/Sumly.ipa`，SHA-256：`70ee66d9f82c5dfd5c9469922337623b60a78475c47003564c2df8d6eac67a13`。
- Apple Build ID / Upload Reservation ID：`176c7c02-c778-4180-9e51-f49b351b95ed`（上传时间 `2026-11-21T03:44:40-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `50`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `WAITING_FOR_REVIEW`，仍绑定构建 `47`（`21af4582-71fc-4de9-9166-f8ad541a2b38`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，313 项单测（9 个测试套件）全部通过，零编译错误、零新增 Swift 6 警告。
