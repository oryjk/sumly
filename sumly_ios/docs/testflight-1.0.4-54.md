# TestFlight 1.0.4（54）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`2393edb4a631b5b0fd063a110f8be589f3de0caa`（已于归档与上传前推送至 `origin/main`）。
  - 本次发布周期合并至 `main` 的相关提交：
    - `e13aea931d95399a25e7ff051557a7394f28d2a1`（`sumly_go`，cherry-pick 自 `af18093`）：新增 `?window=session` 完整最近交易时段分时图支持（覆盖国内 `AU9999` 与国际 `XAUUSD`，保留默认 `window_seconds=1200` 兼容老版本客户端）。
    - `a06499af968d02536fa6048d0ff3c0112efc4f91`（`sumly_ios`，cherry-pick 自 `369a8f179223d4951068d8d17cccf5518b16ea4a`）：首页实时行情升级为完整交易时段分时图（`?window=session`）与休市降频逻辑，新增 5 项 Swift Testing 单元测试（总计扩展至 11 个测试套件、335 项单测）。
    - `2393edb4a631b5b0fd063a110f8be589f3de0caa`（`sumly_ios`）：更新 `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`，同步递增主 App `Sumly` 与小组件扩展 `SumlyWidget` 的构建号至 `1.0.4 (54)`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.4`，构建号：`54`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰正在排队审核的 App Store `1.0.4 (51)` 与已上架的 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出与 App Store Connect JWT API 上传及处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b54/Sumly.ipa`，SHA-256：`ee57e847fe558d2bff9347b7d582ec1edcb07cfb6d9fcd65c559fe0a3ebfd8bd`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.4 (54)`）。
- Apple Build ID / Upload Reservation ID：`6922a244-934c-4107-902d-8dd837f843f5`（上传时间 `2026-11-21T07:50:12-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `54`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `WAITING_FOR_REVIEW`，仍绑定构建 `51`（`62cf065b-08d7-4654-96c1-d13dc9ea6cf0`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 同步完成的 `sumly_go` 生产部署与 4 条公网链路实测

- 源码分支与提交：`main` @ `2393edb4a631b5b0fd063a110f8be589f3de0caa`（基于干净 `git archive` 交叉编译 `linux/amd64`，包含后端提交 `e13aea931d95399a25e7ff051557a7394f28d2a1`）。
- 生产发布路径（`peiqian`，`linux/amd64`）：`/data/sumly/releases/20261121-2393edb`（`sumly-go-api` SHA-256：`afa52af2fc10e5d9498287d6d41c3b0e25c1e6b66e877b4eb4a9e5c7da96de03`），原子切换软链 `/data/sumly/current -> /data/sumly/releases/20261121-2393edb`，`sumly-go-api.service` 已重启并处于 `active (running)` 状态。
- 4 条公网接口全量实测结果（全部 HTTP `200`）：
  1. 国内新版：`GET https://oryjk.cn/sumly/api/v1/app/market/gold/instruments/au9999/realtime?window=session`
     - 返回 `257` 个数据点、`68` 个不同价位；`window_start=2026-11-20T20:00:00+08:00`、`window_end=2026-11-21T02:30:00+08:00`；数据点覆盖 `2026-11-20 20:03:00+08:00 ~ 2026-11-21 02:30:00+08:00`；首末价 `770.50 → 755.01`，价格区间 `755.01 ~ 773.48`（涵盖 `773.48 → 755.01` 回落过程）；`interval_seconds=60`、`window_seconds=23400`。
  2. 国际新版：`GET https://oryjk.cn/sumly/api/v1/app/market/gold/realtime?window=session`
     - 返回 `361` 个数据点、`339` 个不同价位；覆盖收盘前 6 小时（`2026-11-20 23:55:00+08:00 ~ 2026-11-21 05:55:00+08:00`）；首末价 `761.30 → 758.20`，价格区间 `751.54 ~ 762.66`；`interval_seconds=60`、`window_seconds=21600`。
  3. 国内老版兼容：`GET https://oryjk.cn/sumly/api/v1/app/market/gold/instruments/au9999/realtime`
     - 返回 `21` 个数据点、`2` 个不同价位；`window_start=2026-11-21T02:10:00+08:00`、`window_end=2026-11-21T02:30:00+08:00`；首末价 `760.00 → 755.01`；`interval_seconds=60`、`window_seconds=1200`。
  4. 国际老版兼容：`GET https://oryjk.cn/sumly/api/v1/app/market/gold/realtime`
     - 返回 `241` 个数据点、`89` 个不同价位；覆盖 `2026-11-21 05:35:00+08:00 ~ 2026-11-21 05:55:00+08:00`；价格区间 `755.79 ~ 758.20`；`interval_seconds=5`、`window_seconds=1200`。

## 验证记录

- Go 后端全量测试与静态检查：`cd sumly_go && go test -count=1 -race ./... && go vet ./...` 全部通过。
- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，335 项单测（11 个测试套件）全部通过，零编译错误、零新增 Swift 6 编译警告。
