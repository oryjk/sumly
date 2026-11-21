# TestFlight 1.0.4（48）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`bc15e352a84e72f7b3f4306c971a4c01ddc3b766`（已于打包上传前推送至 `origin/main`）。
  - 本构建包含以下核心提交：
    - `e7821f3f3e4c15965b8a5d53e63ae95ed87d5db7`（0 冲突 cherry-pick 自 `229389da71ac06f81119aed7f2f22f18e8f45253`）：记账页补充细节随黄金形态深度联动与暗黑金 UI 重构（新增 `HoldingAssetFormProfile.swift`、`HoldingDetailsDrawerView.swift` 及 `HoldingAssetFormProfileTests.swift`）。
    - `2dce068ea23cca10229dbee6535485dfce5fdb79`（0 冲突 cherry-pick 自 `4c8da94a8a7ff2ae682b61295db6478227898943`）：替换积存金备注合规文案并避免重复点选同形态重置微调。
    - `bc15e352a84e72f7b3f4306c971a4c01ddc3b766`：同步递增主 App `Sumly` 与扩展 `SumlyWidget` 的构建号至 `1.0.4 (48)`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.4`，构建号：`48`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰正在排队审核的 App Store `1.0.4 (47)` 与已上架的 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出与 App Store Connect JWT API 上传及处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b48/Sumly.ipa`，SHA-256：`1112b933b6eea5352b2b2c8f36b78a9ea38fdbb0a24b076874f7cc8c752fd161`。
- Apple Build ID / Upload Reservation ID：`07a4d419-598b-48eb-8f28-8a0e9e6469ed`（上传时间 `2026-11-20T23:14:24-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `48`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `WAITING_FOR_REVIEW`，仍绑定构建 `47`（`21af4582-71fc-4de9-9166-f8ad541a2b38`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，296 项单测（8 个测试套件）全部通过，零编译错误、零警告。
