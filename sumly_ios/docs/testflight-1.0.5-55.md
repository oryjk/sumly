# TestFlight 1.0.5（55）

- 日期：2026-11-22（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`6eb314d778285d6d9b6dc720c08dbb1ff96b89a1`（已于归档与上传前推送至 `origin/main`）。
  - 本次发布周期合并至 `main` 的相关提交：
    - `46cdfc446fe558a3544c9d7154c1350cde602f7c`（`sumly_ios`，cherry-pick 自 `43c90ed790c0c3a186f8e0d3e0f5e038abfaf30e`）：首页行情休市/休盘/收盘/暂无新成交状态文案优化，新增 `GoldMarketSessionStatus` 纯逻辑（按 `Asia/Shanghai` 与 `America/New_York` 自动兼容夏冬令时），彻底去除「更新暂停」，同步更新行情说明弹窗并补齐国内/国际时段与历史周期 Swift Testing 单测（总计 11 个测试套件、344 项单测）。
    - `6eb314d778285d6d9b6dc720c08dbb1ff96b89a1`（`sumly_ios`）：发布前通过 App Store Connect JWT API 只读查询确认线上 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）已变为 `READY_FOR_SALE`（绑定构建 `54`），按发布约定启用版本号 `1.0.5` 与构建号 `55`，同步更新 `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.5`，构建号：`55`，最低 iOS `17.0`。
- 本次发布**仅面向 TestFlight 内部测试**，未触碰已上架的 App Store `1.0.4 (54)` 与 `1.0.3 (41)`，亦未触发外部测试组分发。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）完成本地 `Release` 归档（含 `SumlyWidget.appex`）与本地签名导出；首次 `POST buildUploadFiles` 遭遇瞬时网络中断后，先通过 ASC JWT API 只读对账确认预留 `d71fb753-f0ba-4ed0-ab06-937f20230675` 处于 `AWAITING_UPLOAD` 且无已创建文件预留，随后使用 `bash scripts/upload_app_store.sh --ipa build/ipa-b55/Sumly.ipa` 复用同一签名 IPA 与同一上传预留完成分片上传及 Apple 处理等待（未重新归档，未创建重复上传任务）。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b55/Sumly.ipa`，SHA-256：`72aecf2fa04ba4f36672a2955dd9ff46150c45fd46c72f172be6a8b2156ee34e`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.5 (55)`）。
- Apple Build ID / Upload Reservation ID：`d71fb753-f0ba-4ed0-ab06-937f20230675`（上传时间 `2026-11-21T19:06:40-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认自动包含构建 `55`（当前 2 名内部测试员）。
- App Store 线上版本只读核对（均未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），仍绑定构建 `54`（`6922a244-934c-4107-902d-8dd837f843f5`）。
  - 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）：状态为 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），仍绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`）。

## 验证记录

- iOS 全量生成与构建：`cd sumly_ios && make generate && make build` 通过，零编译错误、零新增 Swift 6 编译警告。
- iOS 全量单元测试：11 个测试套件共 **344 项单测全部通过**（注：iOS 26.5 模拟器默认并发执行时，既有的 `HoldingsCloudTests` 落盘保存与 SwiftUI `@Query` 渲染快照测试存在进程内 `_SwiftData_SwiftUI` 通知竞态；使用 `-parallel-testing-enabled NO` 串行执行全量 344 项单测在 54.926 秒内 100% 通过）。
