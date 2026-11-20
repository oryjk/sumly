# App Store & TestFlight 1.0.3（41）

- 源码分支：`main`，构建原始源码提交 SHA：`4fb77e453809f73804b7f797720ee741da64c5ca`（含 `174a253` `ChartRangeNavigator` 48pt 触控热区与手势优先级优化，以及 `11b0f94` / `c725164` / `755cb55` 黄金温度计、美国国债与宏观全景看板）。
- App Store 版本：`1.0.3`（当前线上在售版本为 `1.0.2`；`1.0.3` 为尚未发布的待审核版本，故沿用 `1.0.3` 并递增构建号至 `41`，高于线上最新构建 `40`），最低 iOS `17.0`。
- 对应生产后端：`peiqian` 主机 `sumly-go-api` 发布目录 `/data/sumly/releases/20261121-755cb55`（源码提交 `755cb551ba0e25015614fed3d1a0a4211e8001d3`，数据库迁移至 `00011_macro_indicators.sql`，47/47 宏观指标同步 `ok`，公网入口 `https://oryjk.cn/sumly`）。

## 构建与 TestFlight 内测通道

- 通过标准入口 `make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，本地 `Release` 归档 + 本地签名导出 + App Store Connect JWT API 上传）完成签名 IPA 上传。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b41/Sumly.ipa`，SHA-256：`94fd50bed79b46127160b21a0002ac9cb49edae5b9488ab20ebb3e85f3678306`。
- Apple Build ID / Upload Reservation ID：`8055796d-1440-41e7-afe6-de719dd3586a`。
- Apple 端核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未主动触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`，已确认包含构建 `41`（当前 2 名内部测试员）。

## App Store 线上版提审通道

- 复用同一有效构建 `8055796d-1440-41e7-afe6-de719dd3586a`（`1.0.3 (41)`），未重复打包或上传。
- 已撤回原构建 `39` 的审核单 `f3791f43-c8c8-40dc-b8e0-6baea2cc8f49`，将 App Store 版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）关联构建切换为 `41`。
- 同步更新简体中文 `whatsNew`（补充黄金温度计与操作指南针、美国国债与宏观全景看板、K 线区间滑块触控优化，保留 `1.0.3` 相对 `1.0.2` 的既有改进）及 `appStoreReviewDetails` 审核备注；沿用构建 `39` 已就绪的 iPhone 6.7"（4 张）与 iPad Pro 12.9"（4 张）商店截图。
- 北京时间 `2026-11-21 01:15:53`（`2026-11-20T17:15:53.186Z`）完成提审，新审核单 ID：`d217cae2-50cf-473f-b45f-fbcd31916f04`。
- App Store Connect 最终核实：版本 `1.0.3` 与审核单均为 `WAITING_FOR_REVIEW`，绑定构建 `41`，发布方式为 `AFTER_APPROVAL`（审核通过后自动发布）。

## 验证记录

- 单元测试：`cd sumly_ios && make generate && make build && make test`，226 项单测（3 个测试套件）全部通过；上传脚本离线单测 12/12 通过。
- 生产联调：iOS Simulator（iPhone 17）直连生产后端 `https://oryjk.cn/sumly`，目视确认实时金价、K 线与区间滑块、顶部黄金温度胶囊（`32°`）及底部黄金温度计/宏观入口渲染正常、无报错。
