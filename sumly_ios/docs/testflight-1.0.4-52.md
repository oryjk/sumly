# TestFlight 1.0.4（52）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`27d2bbdcb5df0e4659f80ed8a8c8b1151c7034a1`（已于归档与上传前推送至 `origin/main`）。
  - 本构建包含以下改动：
    - `sumly_ios/Sumly/Sources/Features/Macro/MacroModels.swift`：在 `MacroPresentation` 新增纯函数 `sourceLabel(_ raw: String) -> String` 与 `unitLabel(_ raw: String) -> String`（大小写不敏感、自动去首尾空白、空串返回 `"—"`、未知值原样回退），全覆盖后端 `catalog.go` 全部 9 种数据来源与 11 种计量单位；保持现有 `formatValue` / `formatDelta` 继续使用原始 `displayUnit` 不受影响。
    - `sumly_ios/Sumly/Sources/Features/Macro/MacroIndicatorDetailView.swift`：更新「指标档案」中的「数据来源」与「计量单位」展示，统一改用 `MacroPresentation.sourceLabel` 与 `MacroPresentation.unitLabel`（核查宏观模块其余视图均无直接展示原始英文 `source`/`unit` 枚举）。
    - `sumly_ios/Tests/MacroTests.swift`：新增 `sourceLabelLocalizesAllSourcesWithNormalizationAndFallbacks` 与 `unitLabelLocalizesAllUnitsWithNormalizationAndFallbacks` 两项 Swift Testing 单元测试，覆盖全部 9 种来源、11 种单位（含 `%` 与混合大小写 `CNY/USD`/`CNY/g`）、大小写与空白归一化、空串与未知值回退。
    - `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`：同步递增主 App `Sumly` 与小组件扩展 `SumlyWidget` 的构建号至 `1.0.4 (52)`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.4`，构建号：`52`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰正在排队审核的 App Store `1.0.4 (51)` 与已上架的 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出与 App Store Connect JWT API 上传及处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b52/Sumly.ipa`，SHA-256：`56ee5891be4bac7352742a8b23ef09eaa40a361f7f6dfbfcfc8956eef56fcc3a`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.4 (52)`）。
- Apple Build ID / Upload Reservation ID：`551477c3-d3a1-4189-bb23-3775fd3a9758`（上传时间 `2026-11-21T05:48:00-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `52`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `WAITING_FOR_REVIEW`，仍绑定构建 `51`（`62cf065b-08d7-4654-96c1-d13dc9ea6cf0`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，323 项单测（10 个测试套件）全部通过，零编译错误、零 Swift 6 编译警告。
