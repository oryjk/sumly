# TestFlight 1.0.4（53）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`7036ba4bf08eb3bbed4040746e1bfdffd1d1e66e`（已于归档与上传前推送至 `origin/main`）。
  - 本次发布周期合并至 `main` 的相关提交：
    - `fcb6e1c16b31b8e99b70a046ee6f190fb3aae689`（`sumly_go`）：实时行情 90s 时钟容差钳制、新增东财 `AU9999` 1m 分时源（`internal/market/adapters/eastmoney`）与休市残缺样本回退逻辑。
    - `b88b95f263418b736f85a9657dbea1785987903d`（`sumly_ios`）：新增美债财政压力表与宏观全景温度计双仪表盘卡片及 6 板块联动：
      - `sumly_ios/Sumly/Sources/Features/Macro/MacroSupplementaryGauges.swift`：新增美债财政压力表（Treasury Fiscal Pressure Gauge）与宏观全景温度计（Macro Panorama Thermometer）仪表盘卡片组件及 6 板块联动交互。
      - `sumly_ios/Sumly/Sources/Features/Macro/MacroDashboardViewModel.swift`：扩展仪表盘视图状态与 6 板块联动数据装配逻辑。
      - `sumly_ios/Sumly/Sources/Features/Macro/MacroDashboardView.swift`：将美债财政压力表与宏观全景温度计卡片接入宏观总览视图。
      - `sumly_ios/Tests/MacroTests.swift`：新增 7 项 Swift Testing 单元测试（总计扩展至 11 个测试套件、330 项单测），覆盖双仪表盘评分/状态映射与 6 板块联动行为。
    - `7036ba4bf08eb3bbed4040746e1bfdffd1d1e66e`（`sumly_ios`）：更新 `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`，同步递增主 App `Sumly` 与小组件扩展 `SumlyWidget` 的构建号至 `1.0.4 (53)`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.4`，构建号：`53`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰正在排队审核的 App Store `1.0.4 (51)` 与已上架的 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出与 App Store Connect JWT API 上传及处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b53/Sumly.ipa`，SHA-256：`d0dec12d5717028b12aea2687a675fc6ebe85aac71093adc6cc5b0876421eaf3`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.4 (53)`）。
- Apple Build ID / Upload Reservation ID：`d4777615-422d-4af6-aa5c-df485fe680a7`（上传时间 `2026-11-21T06:38:29-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `53`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `WAITING_FOR_REVIEW`，仍绑定构建 `51`（`62cf065b-08d7-4654-96c1-d13dc9ea6cf0`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`，仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 同步完成的 `sumly_go` 生产部署与公网实测

- 源码分支与提交：`main` @ `7036ba4bf08eb3bbed4040746e1bfdffd1d1e66e`（包含后端提交 `fcb6e1c16b31b8e99b70a046ee6f190fb3aae689`）。
- 生产发布路径（`peiqian`，`linux/amd64`）：`/data/sumly/releases/20261121-7036ba4`，软链 `/data/sumly/current -> /data/sumly/releases/20261121-7036ba4`，`sumly-go-api.service` 已重启并处于 `active (running)` 状态。
- 公网接口与日志实测：
  - `GET https://oryjk.cn/sumly/api/v1/app/market/gold/realtime`（国际 `XAUUSD`）：正常返回 241 个点，覆盖 `2026-11-20T21:35:00Z ~ 2026-11-20T21:55:00Z`（北京时间 `05:35~05:55`），`interval_seconds=5, window_seconds=1200`，价格区间 `755.79 ~ 758.20`（89 个不同价位）。
  - 服务日志检查：重启后服务健康，无 `timestamped intraday history unavailable` 报错。
  - `GET https://oryjk.cn/sumly/api/v1/app/market/gold/instruments/au9999/realtime`（国内 `AU9999`）现网阻塞项记录：
    - 重启后 `peiqian` 上 `eastmoney.Client` 请求 `https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=118.AU9999...` 持续遭遇东财上游主动断连（`EOF` / `Empty reply from server`；实测 `/data/sumly/.env` 的 `NO_PROXY` 未包含 `.eastmoney.com`，且直连与代理均触发东财高频/IP 连接中断，本地直连同接口亦出现 `Empty reply from server`）。
    - 因此休市期间 `AU9999` 东财 1m 分时数据尚未落库，当前 `au9999/realtime` 仍返回 2 个收盘样本点（`2026-11-20T18:29:55Z` 与 `18:30:00Z`，价格 `755.01`，`interval_seconds=5, window_seconds=1200`），待后续单独更换/调整国内分时采集策略并回归验证。

## 验证记录

- Go 后端全量测试与静态检查：`cd sumly_go && go test -race ./... && go vet ./...` 全部通过。
- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，330 项单测（11 个测试套件）全部通过，零编译错误、零 Swift 6 编译警告。
