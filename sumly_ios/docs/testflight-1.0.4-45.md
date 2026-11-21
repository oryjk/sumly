# TestFlight 1.0.4（45）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`2ba8f15858293e33e55cabd2926888521c76c7ae`（已于打包上传前推送至 `origin/main`）。
  - 本构建包含以下核心提交：
    - `995977c2d5e93ba70ed0c98767c18e876edd5f69`（`ios-loading-fix`）：修复宏观页在 `URLError(.cancelled)` 与任务取消场景下未重置加载态标志的问题并补充回归单测。
    - `126d73d6054c8c5080ceea1274da966d0ab14ebb`（cherry-pick 自 `f5c1e01a1c99dc4ee2d75eec3d6968e99620f25e`）：黄金温度计 UI 拆分为「短期热度 × 长期宏观」双维度分栏展示及对应科普弹窗与 `MacroDualHorizonTests`。
    - `2ba8f15858293e33e55cabd2926888521c76c7ae`：递增构建号至 `1.0.4 (45)`。
- Bundle ID：`com.oryjk.sumly`，版本：`1.0.4`，构建号：`45`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰已上架的 App Store `1.0.3 (41)`，亦未主动触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `make upload`（`scripts/upload_app_store.sh`）完成本地 `Release` 归档与本地签名导出，并复用导出的单一签名 IPA 通过 `scripts/upload_app_store.sh --ipa`（`scripts/upload_signed_ipa.py`，App Store Connect JWT API）完成上传与处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b45/Sumly.ipa`，SHA-256：`c7f0c9b74237ee44785674a42b91b9eea9ed5012ecd5f27267c0882828c2ffee`。
- Apple Build ID / Upload Reservation ID：`fdb4eba6-156e-43cf-825e-97346b92635b`（上传时间 `2026-11-20T20:27:47-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `45`（当前 2 名内部测试员）。
- App Store 线上版本只读核对：版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`），未受影响。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，259 项单测（5 个测试套件，含 `MacroTests` 加载态取消回归与 `MacroDualHorizonTests`）全部通过，零新增 Swift 编译警告。
