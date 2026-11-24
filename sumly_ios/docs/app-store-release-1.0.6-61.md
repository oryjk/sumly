# App Store & TestFlight 1.0.6（61）发布准备与提审状态记录

- 日期：2026-11-24（北京时间）。
- 源码分支：`main`
  - 构建归档源码提交 SHA：`ddf21f1eb8aa430bac8dea000160e748b96730d0`（已于归档上传前推送至 `origin/main`）
  - 商店元数据同步提交 SHA：`1bba705`（已推送至 `origin/main`，`zh-Hans` 主名称保持 `记金` 以对齐工信部备案，副标题升级为 `攒金记账本·金条金豆金饰真实保本与回收估算`）
- Bundle ID：`com.oryjk.sumly`（主 App）+ `com.oryjk.sumly.widget`（WidgetKit 扩展），版本：`1.0.6`，构建号：`61`，最低 iOS `17.0`。
- 本版核心变更：
  1. 全站 6 语言国际化（`zh-Hans` / `en` / `es` / `fr` / `pt` / `ja` + 跟随系统自动适配，1,812 条词条 × 6 语种全部校验通过，支持设置页即时热切）；
  2. 新增应用内「意见与反馈」全栈闭环（分类提交、截图上传与开发者回复查询）；
  3. 黄金温度计页面进入卡顿深度排查与修复（`LazyVStack`、极值保留降采样、派生缓存、按 Tab 按需加载 + 280ms 导航动画礼让）；
  4. 全新升级高转化暗黑金 App Store 商店截图套件（6 张 iPhone 6.7" `1290×2796` + 6 张 iPad Pro 12.9" `2048×2732`）与全 6 语种商店元数据。

## 构建与 TestFlight 内测通道核实（已就绪）

- 本地签名 IPA 路径：`sumly_ios/build/ipa-b61/Sumly.ipa`
- IPA SHA-256：`9c4d5b2970a6f84ae6c2d49bc2c6dff435f552abe026f74a3b26f1a7e27bd20f`
- Apple Build ID：`33274f00-4cab-4f63-8fed-0ea2419bd661`（上传任务 ID 同上）
- Apple 端核实结果：
  - `processingState`：`VALID`
  - `buildAudienceType`：`APP_STORE_ELIGIBLE`
  - `usesNonExemptEncryption`：`false`
  - `expired`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`（内部测试组 `测试` `f079109b-a665-463e-add4-5359f91dbe47`，`hasAccessToAllBuilds=true`，已自动分发）

## App Store 1.0.6（61）草稿、6 语种元数据与 12 张新版截图核实

- App ID：`6813884595`
- App Store 版本 `1.0.6`（版本 ID：`8a52f4ba-749a-4d27-a469-23507217cf3c`）：
  - 状态：`PREPARE_FOR_SUBMISSION`
  - 发布方式：`AFTER_APPROVAL`
  - 已绑定构建：`61`（`33274f00-4cab-4f63-8fed-0ea2419bd661`）
  - 审核说明 `appStoreReviewDetail`：`e5f7ef0e-8f78-4895-a57a-23069a371dbf`（已更新 `1.0.6` 英文审核路径，`demoAccountRequired=false`）
- 可编辑 `appInfo`（`8bb0e192-b1ab-48bb-bbdf-ab632e91d1de`）6 语种名称与副标题已全部保存：
  - `zh-Hans`（`47b38064-9ec1-43f9-8f2d-205256d3ae1a`）：`记金` | `攒金记账本·金条金豆金饰真实保本与回收估算`
  - `en-US`（`baf5ef44-122c-4e6d-9c5e-ef74051617a2`）：`Sumly - Gold Portfolio & Value` | `Track Bars, Fees & Break-Even`
  - `es-ES`（`766f447d-3a39-4780-9e5c-918fd7a6a1b8`）：`Sumly - Control y Valor de Oro` | `Lingotes, joyas y coste real`
  - `fr-FR`（`4c46c562-248e-4fc1-bafe-4991c7d4798f`）：`Sumly - Suivi & Valeur de l'Or` | `Lingots, bijoux et seuil réel`
  - `pt-BR`（`90f4d4e1-8f54-4519-97b3-58f23d323931`）：`Sumly - Ouro: Carteira e Valor` | `Barras, joias e custo real`
  - `ja`（`99bdd04f-f821-4cc2-81ee-5b03ffed53ac`）：`Sumly - 金の資産管理・売却試算` | `金地金・純金積立の記録と損益分岐点`
- `appStoreVersionLocalizations` 6 语种描述、宣传文本、关键词、更新日志已全部保存：
  - `zh-Hans`：`a9990f69-ec3a-4914-a95a-75cf75139895`
  - `en-US`：`30551e2b-5517-46da-bba6-e1f43f537481`
  - `es-ES`：`ddf4847d-e91d-4f38-9f43-0884f8a47229`
  - `fr-FR`：`4ff3006a-e7e2-44f2-bb16-b17b11b5498f`
  - `pt-BR`：`b290dd86-237d-432c-a240-0231c9f0d6b7`
  - `ja`：`727a30fa-e6e7-4d2d-99b2-6d14e1ed5f07`
- 新版商店截图（`zh-Hans` 主语言，12/12 `COMPLETE`，严格按 `01~06` 排序）：
  - `APP_IPHONE_67`（`v106-iphone-01.png` ~ `06.png`）：
    - `57c00019-623a-80b3-801b-df20fbad128a`
    - `f8c00019-623a-80b3-801a-28504211fc74`
    - `65800019-623a-80b3-8030-e26ad611f1c8`
    - `37400019-623a-80b3-8001-cc3d24957e82`
    - `09000019-623a-80b3-801c-4394b2a2dd98`
    - `ab800019-623a-80b3-800a-8df85374b6a8`
  - `APP_IPAD_PRO_3GEN_129`（`v106-ipad-01.png` ~ `06.png`）：
    - `be800019-623a-80b3-8033-8d3990d80b5a`
    - `3ac00019-623a-80b3-803a-aeb56468d641`
    - `0d400019-623a-80b3-8007-6cff85910895`
    - `37c00019-623a-80b3-802d-e45a43db0a63`
    - `a8c00019-623a-80b3-801f-eab7cc2bc6dc`
    - `b7c00019-623a-80b3-8033-79705f06acd6`

## 最终提审阻断说明（待在 App Store Connect 网页端确认 ICP 备案提示）

- 调用 `POST /v1/reviewSubmissionItems` 绑定 `1.0.6` 时，Apple 返回 `HTTP 409`：
  - 错误码：`STATE_ERROR.ICP_NUMBER_MIIT_PROVIDER_NAME_MISMATCH`
  - 关联路径：`/v1/appIcpNumberDetails/6813884595`
  - 原文：`Your developer name does not match MIIT's records.`
- 原因分析：本次首次通过 API 修改了 `appInfo`（及 `zh-Hans` 名称/新增 5 个海外语种本地化），触发了 Apple 针对中国大陆工信部 ICP 备案号（`蜀ICP备2020035100号-3A`）的重新核验；Apple 公开 REST API 不暴露 `/v1/appIcpNumberDetails` 确认接口，需开发者登录 App Store Connect 网页端在「App 信息 → 中国大陆 ICP 备案」查看并确认/重新保存备案核验状态后，再点击「添加以供审核」（或通知再次运行 `prepare_asc_106.py --submit` 完成提审）。
- 线上在售版本 `1.0.5 (60)`（`848679c8-144b-43dd-a2fc-ea039e681dc1`）保持 `READY_FOR_SALE`，完全不受影响。

## 2026-11-24 全区暂时下架记录（因域名过期需重新备案）

- 时间：2026-11-24 21:31（北京时间）。
- 原因：主域名 `oryjk.cn` 过期需要重新备案，按用户要求通过 App Store Connect `v1/territoryAvailabilities` 将 App（ID `6813884595`）在全部 175 个国家/地区暂时下架。
- 核实结果：
  - `availableInNewTerritories`：`false`
  - 全部 175 个国家/地区均已置为 `available: false`（当前在售地区数：`0 / 175`，0 报错）
  - 中国大陆（`CHN`，`eyJzIjoiNjgxMzg4NDU5NSIsInQiOiJDSE4ifQ`）：`available=false`，`contentStatuses=["CANNOT_SELL"]`
  - `1.0.6 (61)` 草稿（`8a52f4ba-749a-4d27-a469-23507217cf3c`）及全部 6 语种元数据、12 张新版截图、TestFlight 内部测试构建 `61` 均完整保留，待新域名与重新备案完成后可随时重新上架并提审。
