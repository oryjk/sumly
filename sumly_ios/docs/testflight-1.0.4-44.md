# TestFlight 1.0.4（44）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`a86a04fb818982b9855962d4ea4bdbe70cc4a58b`（已于打包上传前推送至 `origin/main`；包含 `a86beca` `GoldTemperatureGauge` 圆点几何对齐修复 + 宏观客观合规文案与 `?` 科普弹窗、`246b097` `sumly_go` 宏观温度公网去投顾化与内网策略映射接口、`a86a04f` 递增版本号至 `1.0.4 (44)`）。
- Bundle ID：`com.oryjk.sumly`，版本：`1.0.4`，构建号：`44`，最低 iOS `17.0`。
  - 说明：因 App Store 线上版本 `1.0.3`（绑定构建 `41`）已审核通过并处于 `READY_FOR_SALE`，Apple 关闭了 `1.0.3` 预发布列车（`1.0.3 (43)` 对应 reservation `ca8e8fcd-01c2-43ee-b342-f52b3bac6dfb` 处理返回 `90062` / `90186`），经确认递增至 `1.0.4 (44)` 并完成发布。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰已上架的 App Store `1.0.3 (41)`，亦未主动触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 通过标准入口 `make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，本地 `Release` 归档 + 本地签名导出 + App Store Connect JWT API 上传）完成签名 IPA 上传。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b44/Sumly.ipa`，SHA-256：`8e68fab22c3efdd6f79e033644242e68437cdaf7ff62771118e4e2de5e61b6b6`。
- Apple Build ID / Upload Reservation ID：`2eac3304-a3c0-488c-89dc-0e6c52aab511`（上传时间 `2026-11-20T18:49:04-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `44`（当前 2 名内部测试员）。
- App Store 线上版本只读核对：版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`），未受影响。

## 后端同步部署（`peiqian`）

- 部署版本：`/data/sumly/releases/20261121-1765216`（源码 `main` 提交 `176521672be426abce4aeba5ba11412eeda83cff`，含 `246b097` 后端合规与内网策略简报接口；`/data/sumly/current` 已切换并重启 `sumly-go-api.service` 为 `active`）。
- 线上核验：
  - 公网严格 HTTPS（无 `-k`）请求 `https://oryjk.cn/sumly/api/v1/app/macro/temperature` 返回 HTTP `200`（`code=0`），`score=27.8`、`level=cool`，`action_guide` 全为纯客观表述（不含“逢低/定投/加仓/止盈/追高”等投顾用语），`guide_help.official_account_name == "何止编程"`。
  - 公网 `https://oryjk.cn/sumly/api/v1/internal/macro/strategy-brief` 无 token 返回 HTTP `401`。
  - `peiqian` 本机 `http://10.8.10.2:18090/api/v1/internal/macro/strategy-brief`：无 token 返回 `401`，携带 `/data/sumly/.env` 中 `MACRO_INTERNAL_TOKEN`（`Authorization: Bearer <token>` 或 `X-Macro-Internal-Token: <token>`）返回 HTTP `200`（`code=0`），包含 `official_account_reply`（246 字）与 `community_brief`（1279 字）。

## 验证记录

- 后端验证：`cd sumly_go && go test -count=1 ./... && go vet ./... && go build -o /tmp/sumly-go-api ./cmd/api` 全绿。
- iOS 单元测试：`cd sumly_ios && make generate && make build && make test`，247 项单测（4 个测试套件）全部通过；上传脚本离线单测 12/12 通过。
