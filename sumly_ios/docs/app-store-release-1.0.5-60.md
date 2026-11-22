# App Store & TestFlight 1.0.5（60）正式提审记录（全员免费版）

- 日期：2026-11-22（北京时间）。
- 源码分支：`main`，Build `60` 原始源码提交 SHA：`6425dbc9b907951c73d37b76686d8fcdd0f77eae`（已于归档与上传前推送至 `origin/main`）。
- Bundle ID：`com.oryjk.sumly`（主 App）+ `com.oryjk.sumly.widget`（WidgetKit 扩展），版本：`1.0.5`，构建号：`60`，最低 iOS `17.0`。
- 版本策略：**全员免费正式上线版本**，不关联未激活付费协议的订阅商品，线上远程配置已同步切换为全员免费开放模式。

## 线上远程配置（全员免费模式）核实

- 变更接口：`PUT https://oryjk.cn/sumly/api/v1/admin/configs/membership_paywall`（使用 `ADMIN_API_TOKEN` 兜底通道，未影响 `admin` 账号首次改密状态）。
  - 变更操作人：`release-bot`
  - 变更备注：`1.0.5 正式上线版本全员免费开放`
  - 变更时间：`2026-11-22T11:09:00Z`（北京时间 `2026-11-22 19:09:00`）
  - 响应状态：HTTP `200`（`code: 0`）
- 公网接口实测：`GET https://oryjk.cn/sumly/api/v1/app/config`
  - 响应状态：HTTP `200`
  - `membership_paywall.chanlun_requires_membership`：`false`
  - `membership_paywall.membership_entry_visible`：`false`
  - `membership_paywall.free_access_notice`：`""`
  - `updated_at`：`2026-11-22T11:09:00Z`

## 构建与 TestFlight 内测通道（复用已验证签名包）

- 本次 App Store 正式提审**直接复用已上传并通过 TestFlight 校验的 `1.0.5 (60)` 有效构建**，未重新打包或重复上传（详见 [testflight-1.0.5-60.md](testflight-1.0.5-60.md)）。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b60/Sumly.ipa`，SHA-256：`83234bf74f169af6cfdd3d083c707249d9b0861eb2c43afc88b134fcf23944cf`。
- Apple Build ID：`03688129-261b-4295-9de8-e9eb3c29d2a0`（上传时间 `2026-11-22T02:56:55-08:00`）。
- Apple 端核实结果：
  - `processingState`：`VALID`
  - `buildAudienceType`：`APP_STORE_ELIGIBLE`
  - `usesNonExemptEncryption`：`false`
  - `expired`：`false`

## App Store 1.0.5（60）正式提审与商店截图核实

- App ID：`6813884595`
- App Store 版本 `1.0.5`（版本 ID：`848679c8-144b-43dd-a2fc-ea039e681dc1`）：
  - 平台：`IOS`
  - 发布方式：`AFTER_APPROVAL`（审核通过后自动发布）
  - 绑定构建：`60`（`03688129-261b-4295-9de8-e9eb3c29d2a0`）
  - 关联审核项：仅包含 `appStoreVersion` `1.0.5`（Item ID：`MzJkYjcyMjUtYWY0OS00MDJiLTliZmQtMDgwMzc3MDljZDUzfDZ8ODk1ODUxOTQz`），**未关联任何订阅商品**。
- 元数据更新（同步至 [app-store-metadata-zh-Hans.json](app-store-metadata-zh-Hans.json)）：
  - `zh-Hans` 本地化 ID：`b2472854-10b5-4a26-ac90-43a2db8a30f5`（已更新 `whatsNew`）
  - `appStoreReviewDetail` ID：`26b796d6-7176-42ef-baca-9a023dd5981f`（已更新 `notes`，`demoAccountRequired=false`）
  - `whatsNew` 摘要：
    1. 「我的」与「设置」页全面暗黑金视觉升级，新增个人攒金档案、一键隐私遮罩，以及用户名行纯图标 5 态云同步指示；
    2. 全新 3 页暗黑金新手引导与持仓页「3 步开启记金」任务卡，帮助首次使用快速上手；
    3. 首页行情状态文案升级为直白易懂的休市、休盘与收盘提示，休市及当日未收盘买入红点支持末端临时挂靠与视口外提示；
    4. 优化表单数字键盘弹出时的底部按钮排布与收起交互，并全面更新商店展示界面。
- 新版商店截图核验（12/12 `COMPLETE`）：
  - `APP_IPHONE_67`（截图集 `89ed9ee3-b9dd-45bc-8df1-0044f255f126`，6 张 `01.png`～`06.png` 全部 `COMPLETE`）：
    - `24400019-623a-80b3-8035-81ff5b0176ae`（`01.png`）
    - `2d400019-623a-80b3-8002-d77f7ee39958`（`02.png`）
    - `0a000019-623a-80b3-802e-5a085febd44d`（`03.png`）
    - `b6000019-623a-80b3-801d-a77de5c86e76`（`04.png`）
    - `f3000019-623a-80b3-8000-3362d02a5daf`（`05.png`）
    - `ee400019-623a-80b3-8011-7303ab9b0de3`（`06.png`）
  - `APP_IPAD_PRO_3GEN_129`（截图集 `222f7350-efd9-48ee-9716-41423a678f03`，6 张 `01.png`～`06.png` 全部 `COMPLETE`）：
    - `d9800019-623a-80b3-803b-3fe62c021e70`（`01.png`）
    - `b6000019-623a-80b3-802a-2244fb2e2130`（`02.png`）
    - `7fc00019-623a-80b3-8039-8c07bcbc18e2`（`03.png`）
    - `7f800019-623a-80b3-8026-f563178f118a`（`04.png`）
    - `39c00019-623a-80b3-8003-aa0124e33f7d`（`05.png`）
    - `8e800019-623a-80b3-8027-5a1dcac3eb02`（`06.png`）
- 提审提交与最终状态核实：
  - 提交时间：`2026-11-22T11:10:50.338Z`（北京时间 `2026-11-22 19:10:50`）
  - 新审核单 ID：`32db7225-af49-402b-9bfd-08037709cd53`
  - 审核单状态：**`WAITING_FOR_REVIEW`**
  - 版本 `1.0.5`（`848679c8-144b-43dd-a2fc-ea039e681dc1`）状态：`appStoreState=WAITING_FOR_REVIEW`、`appVersionState=WAITING_FOR_REVIEW`、`releaseType=AFTER_APPROVAL`，绑定构建 `60`（`03688129-261b-4295-9de8-e9eb3c29d2a0`）。
- 线上在售版本只读核对（未受影响）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）仍为 **`READY_FOR_SALE`**（`READY_FOR_DISTRIBUTION`），绑定构建 `54`（`6922a244-934c-4107-902d-8dd837f843f5`）。

## 验证记录

- 原始构建提交 `6425dbc9b907951c73d37b76686d8fcdd0f77eae` 已于 TestFlight `1.0.5 (60)` 发布阶段完成全量构建与 12 个测试套件共 387 项单测验证（全部通过，详见 [testflight-1.0.5-60.md](testflight-1.0.5-60.md)）。
- 本次提审未改动任何源码或重新打包上传 IPA，仅切换线上远程配置为全员免费模式并完成 App Store `1.0.5 (60)` 元数据更新与正式提审。
