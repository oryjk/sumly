# App Store & TestFlight 1.0.4（54）

- 日期：2026-11-22（北京时间；构建上传于 2026-11-21）。
- 源码分支：`main`，构建原始源码提交 SHA：`2393edb4a631b5b0fd063a110f8be589f3de0caa`（已于归档与上传前推送至 `origin/main`）。
  - 本版本完整叠加 `1.0.4 (47)`～`(51)` 全部功能（悬浮胶囊底栏与「持有」页重构、3 秒极简入库与黄金形态联动补充细节、「金豆」品类与金属质感图标、「我的攒金盒」里程碑卡片与入库纪念卡、「怎么算的？」计算拆解页可视化重构、攒金陪伴日历重构、首页走势图买入点红点虚线连接/角标/滑查浮窗/多笔明细抽屉、黄金温度计「短期热度 × 长期宏观」分栏客观解读及宏观线性/对数坐标切换、WidgetKit 桌面与锁屏小组件），并在 `52`～`54` 迭代中新增以下核心能力：
    - `1.0.4 (52)`（`27d2bbdcb5df0e4659f80ed8a8c8b1151c7034a1`）：宏观指标档案的数据来源（9 种）与计量单位（11 种）全面中文化（`MacroPresentation.sourceLabel` / `unitLabel`，大小写与空白归一化、空串与未知值回退）。
    - `1.0.4 (53)`（`b88b95f263418b736f85a9657dbea1785987903d` / `7036ba4bf08eb3bbed4040746e1bfdffd1d1e66e`）：新增美债财政压力表（210° 半圆弧压力表盘）与宏观全景温度计（支持 6 大板块交互联动）。
    - `1.0.4 (54)`（`e13aea931d95399a25e7ff051557a7394f28d2a1` / `a06499af968d02536fa6048d0ff3c0112efc4f91` / `2393edb4a631b5b0fd063a110f8be589f3de0caa`）：首页「实时」升级为完整最近交易时段分时图（`?window=session`，展示国内 Au99.99 夜盘/日盘完整走势与国际伦敦金收盘前 6 小时分时）及休市降频逻辑，主 App `Sumly` 与小组件扩展 `SumlyWidget` 版本/构建号同步至 `1.0.4 (54)`。
- Bundle ID：`com.oryjk.sumly`（主 App）+ `com.oryjk.sumly.widget`（WidgetKit 扩展），版本：`1.0.4`，构建号：`54`，最低 iOS `17.0`。

## 构建与 TestFlight 内测通道（复用已验证签名包）

- 本次 App Store 提审**直接复用已上传并通过 TestFlight 校验的 `1.0.4 (54)` 有效构建**，未重新打包或重复上传（详见 [testflight-1.0.4-54.md](testflight-1.0.4-54.md)）。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b54/Sumly.ipa`，SHA-256：`ee57e847fe558d2bff9347b7d582ec1edcb07cfb6d9fcd65c559fe0a3ebfd8bd`。
- IPA 结构核验：同时包含 `Payload/Sumly.app`（`com.oryjk.sumly`）及 `Payload/Sumly.app/PlugIns/SumlyWidget.appex`（`com.oryjk.sumly.widget`），主 App 与小组件版本/构建号均为 `1.0.4 (54)`。
- Apple Build ID：`6922a244-934c-4107-902d-8dd837f843f5`（上传时间 `2026-11-21T07:50:12-08:00`）。
- Apple 端核实结果：
  - `processingState`：`VALID`
  - `buildAudienceType`：`APP_STORE_ELIGIBLE`
  - `usesNonExemptEncryption`：`false`
  - `expired`：`false`

## App Store 线上版提审通道

- 复用同一有效构建 `6922a244-934c-4107-902d-8dd837f843f5`（`1.0.4 (54)`），未重复打包或上传。
- 已撤回原 `1.0.4 (51)` 待审核单 `40e560a9-415a-406d-8e93-83c5fec5182f`，等待版本 `1.0.4`（版本 ID：`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`，`releaseType=AFTER_APPROVAL`）进入可编辑状态后，将关联构建切换为 `54`。
- 同步更新简体中文 `zh-Hans` 本地化（本地化 ID：`9f287f2c-0577-4457-8011-ba5d3e767d40`）的 `whatsNew` 更新说明，以及审核说明 `appStoreReviewDetail`（ID：`4881f1c6-0438-4696-bb34-d103d1c9c0a4`），并已同步至 [app-store-metadata-zh-Hans.json](app-store-metadata-zh-Hans.json)；沿用既有已就绪的 iPhone 6.7"（4 张）与 iPad Pro 12.9"（4 张）商店截图。
- `whatsNew` 摘要（100% 客观功能与数据描述，无任何投资/交易建议词、无付费社群字样，且 `whatsNew` 与 `reviewNotes` 均不含无关字样）：
  - 悬浮胶囊底栏与「持有」页、3 秒极简入库与按黄金形态动态联动的记账补充细节；
  - 新增「金豆」品类、金属质感图标、「我的攒金盒」里程碑卡片与入库纪念卡分享；
  - 「怎么算的？」计算拆解页可视化升级（堆叠对比柱状图、每克保本价构成尺、折叠公式与隐私脱敏）；
  - 攒金陪伴日历重构（日收益热力图、年度总览、日账本卡片、支持隐私脱敏的月度/年度海报分享）；
  - 首页走势图升级：新增「实时」完整最近交易时段分时图（国内夜盘/日盘完整走势与国际收盘前 6 小时分时），买入记录支持红点垂直虚线连接、单/多笔角标、滑查浮窗、多笔明细抽屉及买入单价与参考金价差额对比；
  - 宏观总览与黄金温度计升级：新增美债财政压力表（210° 半圆弧压力表盘）与宏观全景温度计（支持 6 大板块交互联动），宏观指标档案的数据来源与计量单位全面中文化，黄金温度计升级为「短期热度 × 长期宏观」分栏客观解读，宏观历史走势支持线性/对数坐标切换；
  - 桌面与锁屏金价小组件。
- 北京时间 `2026-11-22 00:36:56`（`2026-11-21T16:36:56.036Z`）完成提审，新审核单 ID：`db19d699-8c88-4543-bb22-069b1c9a0fe4`。
- App Store Connect 最终核实：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）与新审核单（`db19d699-8c88-4543-bb22-069b1c9a0fe4`）状态均为 **`WAITING_FOR_REVIEW`**，绑定构建 `54`（`6922a244-934c-4107-902d-8dd837f843f5`），发布方式 `AFTER_APPROVAL`（审核通过后自动发布）。
  - 在售版本 `1.0.3`（`338b2329-6ca2-4e75-90e4-b5bdfeabd86c`）只读核对仍为 **`READY_FOR_SALE`**，绑定构建 `41`（`8055796d-1440-41e7-afe6-de719dd3586a`），未受影响。

## 验证记录

- 原始构建 `2393edb4a631b5b0fd063a110f8be589f3de0caa` 已于 TestFlight 1.0.4（54）发布阶段完成验证：
  - Go 后端全量测试与静态检查（`go test -count=1 -race ./... && go vet ./...`）全部通过，且 `sumly_go` 生产服务已部署至 `peiqian`（`/data/sumly/releases/20261121-2393edb`），4 条公网实时接口链路实测全部 HTTP `200`。
  - iOS 全量构建与单元测试（`make generate && make build && make test`）**335 项单测（11 个测试套件）全部通过**，零编译错误、零新增 Swift 6 编译警告。
