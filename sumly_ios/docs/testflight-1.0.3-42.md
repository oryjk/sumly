# TestFlight 1.0.3（42）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`59934b6b21647644c1a220027d14f5c1a90a592f`（已于打包上传前推送至 `origin/main`；合入 `c4fabf4` 宏观图表线性/对数坐标刻度切换与 `8943001` 窄区间刻度精度及多序列单点对数边界修复，来源于 `swarm-ios-logscale-21ba7515` 的 `d348cb7` 与 `00a2229`）。
- Bundle ID：`com.oryjk.sumly`，版本：`1.0.3`，构建号：`42`（在 Apple 线上最新构建 `41` 基础上递增），最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰/撤回/替换 App Store 待审核的 `1.0.3 (41)` 审核单，亦未主动触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 通过标准入口 `make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，本地 `Release` 归档 + 本地签名导出 + App Store Connect JWT API 上传）完成签名 IPA 上传。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b42/Sumly.ipa`，SHA-256：`f560b28a201ab9a8e037af438ba56921ce340e70145437943736460dd245a41d`。
- Apple Build ID / Upload Reservation ID：`60cec526-d601-47e2-bdc9-93c4ab769bb7`（上传时间 `2026-11-20T09:41:05-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `42`（当前 2 名内部测试员）。
- App Store 线上待审版本只读核对：版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）状态仍为 `WAITING_FOR_REVIEW`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`），未受影响。

## 验证记录

- 单元测试：`cd sumly_ios && make generate && make build && make test`，236 项单测（3 个测试套件）全部通过；上传脚本离线单测 12/12 通过。
- 模拟器核验：iPhone 17（iOS 26.5）安装并启动 `1.0.3 (42)`，目视确认主行情页渲染与对数刻度切换入口正常、无报错。
