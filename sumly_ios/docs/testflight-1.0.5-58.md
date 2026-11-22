# TestFlight 1.0.5（58）

- 日期：2026-11-22（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`2ea7a8a859868653086e51266a5837d1a8194706`（已于归档与上传前推送至 `origin/main`）。
  - 本次发布周期合并至 `main` 的相关提交：
    - `bd3861452495aa3919255ea6d921428f666c2445`（`sumly_ios`，cherry-pick 自 `0cc32c44b3bee9e30292a4b4cdcd66e8cc5cf674`）：修复 iOS 26 键盘工具栏「完成」按钮与底部主按钮留白冲突（同步更新 `AddHoldingSheet`、`GoldCalculatorSheet`、`GoldReturnComponents`、`HoldingAlertSheet`、`HoldingsSheets` 并新增 `GoldKeyboardDismissTests`）。
    - `ad0bde42c3942d7547f955b1517d18f7546466cb`（`sumly_ios`，cherry-pick 自 `574f80a0dc013a69b4a9da32288d729fb55b0355`）：非交易日/当日未收盘买入红点临时挂靠曲线最右端、Y 轴 ±25% 平滑微扩与视口外买入轻量提示（同步更新 `HoldingsInsights`、`ChartPurchaseMarkerSheet`、`HomeView`、`MarketHomeChartContent` 并补充 `ChartHoldingMarkerTests`）。
    - `2ea7a8a859868653086e51266a5837d1a8194706`（`sumly_ios`）：将 `Sumly` 与 `SumlyWidget` 两个 target 的版本与构建号更新为 `1.0.5 (58)`（同步 `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`）。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.5`，构建号：`58`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰已上架的 App Store `1.0.4 (54)` 与 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）一次性完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出、分片上传（2/2）与 Apple 处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b58/Sumly.ipa`，SHA-256：`2cf10caebc9f174823f3aa98560a0bff4a9c14386c3199b79dbada4b353c7a76`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.5 (58)`）。
- Apple Build ID / Upload Reservation ID：`168fcf02-1584-4c37-8e79-0aafd8274197`（上传时间 `2026-11-21T23:30:09-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认自动包含构建 `58`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），仍绑定构建 `54`（`6922a244-934c-4107-902d-8dd837f843f5`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 验证记录

- iOS 全量生成与构建：`cd sumly_ios && make generate && make build` 通过，零编译错误、零新增 Swift 6 编译警告。
- iOS 全量单元测试：`xcodebuild -project Sumly.xcodeproj -scheme Sumly -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test` 执行 12 个测试套件共 **372 项单测全部通过**（耗时 59.271 秒）。
