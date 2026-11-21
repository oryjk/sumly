# App Store & TestFlight 1.0.4（47）

- 日期：2026-11-21（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`b56a3ca47ec85b65d80a6a570247844cf1a5e922`（已于归档与上传前推送至 `origin/main`）。
  - 本版本包含以下核心提交（叠加既有 `1.0.4` 悬浮胶囊底部导航与「持有」页重构、`MacroDualHorizon`「短期热度 × 长期宏观」分栏温度计与科普弹窗、宏观图表线性/对数切换及加载稳定性优化）：
    - `5e7ef60`（0 冲突 cherry-pick 自 `d8c1c2cb6c3a941546e659e3cd89e1db3c15e64a`）：走势图买入成本红点垂直虚线连接大盘曲线及落点锚点、统一两排控制条同心圆角视觉（`ChartHoldingMarkerTests`）。
    - `a769ff9`（0 冲突 cherry-pick 自 `ecb9c9633c44ae4da36113348467e738ae469a78`）：3 秒极简入库、新增「金豆」品类与暗金金属质感矢量图标、「我的攒金盒」里程碑卡片与入库纪念卡 PNG 分享（`GoldVaultTests`）。
    - `ba7b83a`（0 冲突 cherry-pick 自 `86f7055d270a52853c7775cba013d23b6f18a860`）：WidgetKit 桌面与锁屏金价小组件扩展 `SumlyWidget.appex`（`GoldWidgetSnapshotTests`）。
    - `b56a3ca`（`b56a3ca47ec85b65d80a6a570247844cf1a5e922`）：同步主 App 与 `SumlyWidget` 版本号为 `1.0.4 (47)`、补充 `ExportOptions-upload.plist` 扩展描述文件配置并更新 `docs/app-store-metadata-zh-Hans.json`。
- Bundle ID：`com.oryjk.sumly`（主 App）+ `com.oryjk.sumly.widget`（WidgetKit 扩展），版本：`1.0.4`，构建号：`47`，最低 iOS `17.0`。

## WidgetKit 扩展分发签名配置

- Bundle ID：`com.oryjk.sumly.widget`（ASC ID `AJVY886S6T`，名称 `Sumly Widget`，平台 `IOS`）。
- 共享分发证书：`873P622YG3`（`Apple Distribution: RUI WANG (237PA3LEYJ)`，到期时间 `2027-09-30T05:54:57Z`，与主 App 保持一致）。
- Provisioning Profile：`Sumly Widget App Store Distribution`（ASC ID `9AHN7SFWFG`，类型 `IOS_APP_STORE`，状态 `ACTIVE`，UUID `38590810-6b9e-40b7-ba69-05a08480a98c`，到期时间 `2027-09-30T05:54:57Z`），已安装至本机描述文件目录并在 `sumly_ios/scripts/ExportOptions-upload.plist` 中完成双目标映射。

## 构建与 TestFlight 内测通道

- 通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，本地 `Release` 归档 + 本地手动签名导出 + App Store Connect JWT API 上传及处理轮询）完成单一签名 IPA 上传。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b47/Sumly.ipa`，SHA-256：`f87fda5d938b164d1f55c854344dd5ac8a999455ef56a7fdb30ab1574b5f26d7`。
- IPA 结构核验：同时包含 `Payload/Sumly.app`（含 `Info.plist` 与 `embedded.mobileprovision`）及 `Payload/Sumly.app/PlugIns/SumlyWidget.appex`（含 `Info.plist` 与 `embedded.mobileprovision`），主 App 与小组件版本/构建号均为 `1.0.4 (47)`。
- Apple Build ID / Upload Reservation ID：`21af4582-71fc-4de9-9166-f8ad541a2b38`（上传时间 `2026-11-20T21:53:10-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `buildAudienceType`：`APP_STORE_ELIGIBLE`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（外部测试组按需更新，本次未主动触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认包含构建 `47`（当前 2 名内部测试员）。

## App Store 线上版提审通道

- 复用同一有效构建 `21af4582-71fc-4de9-9166-f8ad541a2b38`（`1.0.4 (47)`），未重复打包或上传。
- 新建线上 App Store 版本 `1.0.4`（版本 ID：`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`，`releaseType=AFTER_APPROVAL`），已关联构建 `47`。
- 同步更新简体中文（`zh-Hans`，本地化 ID：`9f287f2c-0577-4457-8011-ba5d3e767d40`）的 `whatsNew`、`keywords`（59 字符，≤100 字符上限）与 `description`；沿用既有已就绪的 iPhone 6.7"（4 张）与 iPad Pro 12.9"（4 张）商店截图。
- 同步更新审核说明 `appStoreReviewDetail`（ID：`4881f1c6-0438-4696-bb34-d103d1c9c0a4`），移除旧版表述，清晰说明新增桌面/锁屏小组件、3 秒极简入库、攒金盒与纪念卡、金豆形态及黄金温度计纯客观参考展示（无交易、无投顾）。
- 北京时间 `2026-11-21 13:56:33`（`2026-11-21T05:56:33.421Z`）完成提审，审核单 ID：`cb222ecb-de9a-470d-b619-a38f15f9634f`。
- App Store Connect 最终核实：版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）与审核单（`cb222ecb-de9a-470d-b619-a38f15f9634f`）状态均为 **`WAITING_FOR_REVIEW`**，绑定构建 `47`，发布方式 `AFTER_APPROVAL`。

## 验证记录

- iOS 全量构建与单元测试：`cd sumly_ios && make generate && make build && make test`，**291 项单测（8 个测试套件）全部通过**，零错误、零新增 Swift 编译警告。
- 上传脚本离线单测：`python3 -m unittest discover -s scripts -p 'test_upload_signed_ipa.py'`，12/12 全部通过。
