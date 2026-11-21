# TestFlight 1.0.4（49）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`4fa1f6f421cb08f72958412a8224283e6a995bdc`（已于打包上传前推送至 `origin/main`）。
  - 本构建包含以下核心提交：
    - `dae72f1d44d5f75f48975465200e8f81f9c7360d`（0 冲突 cherry-pick 自 `211e64db86a1f0e7147aa946f9bd8fccbd33a243`）：点击记一笔参数胶囊时平滑展开并滚动定位补充细节与高亮反馈（`AddHoldingSheet.swift`）。
    - `cd011f87bcabc93da866ffd3db888bf996d65236`（0 冲突 cherry-pick 自 `dbe65267eb1df74b7bb5af4aaaa45a8bf189f5c9`）：攒金陪伴日历完整重构（含日收益热力图、年度总览、日账本卡片及可分享海报，新增 `GoldCalendarEngine.swift`、`GoldCalendarPosterSheet.swift`、`HoldingsCalendarComponents.swift`、`HoldingsCalendarViewModel.swift`、`MacroTemperatureHistoryCache.swift` 与 `GoldCalendarEngineTests.swift` 并重构 `HoldingsCalendarSheet.swift`）。
    - `1b7547f57a1740fcbd5210b9ce27310b2bea96f1`（0 冲突 cherry-pick 自 `393bdd5de1e00a0463ee76c148ee2d5f62ea888b`）：海报隐私脱敏边界修复（年/月海报在年盈亏为 `nil` 时同样隐藏买入克重并补充单测）。
    - `4fa1f6f421cb08f72958412a8224283e6a995bdc`：同步递增主 App `Sumly` 与扩展 `SumlyWidget` 的构建号至 `1.0.4 (49)`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.4`，构建号：`49`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰正在排队审核的 App Store `1.0.4 (47)` 与已上架的 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出与 App Store Connect JWT API 上传及处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b49/Sumly.ipa`，SHA-256：`5c78e1e6c6364bb7a8cc22ce7f5dd9276e92dfb4f4c4b082dab728cfdf592a51`。
- Apple Build ID / Upload Reservation ID：`7b81ce94-6237-42dd-b9a5-275cb19879a4`（上传时间 `2026-11-21T00:04:33-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `49`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `WAITING_FOR_REVIEW`，仍绑定构建 `47`（`21af4582-71fc-4de9-9166-f8ad541a2b38`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，308 项单测（9 个测试套件）全部通过，零编译错误、零新增警告。
