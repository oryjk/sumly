# TestFlight 1.0.5（60）与 App Store 1.0.5 草稿构建更新记录

- 日期：2026-11-22（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`6425dbc9b907951c73d37b76686d8fcdd0f77eae`（已于归档与上传前推送至 `origin/main`）。
  - 本次构建纳入的主要提交：
    - `948db79a4d48f45d9cb8a5d5225334d5c8e9dcdd`（`sumly_ios`）：集成 iOS 远程配置动态热切开关与 StoreKit 2 诊断补强（新增 `RemoteAppConfig.swift`、`RemoteAppConfigTests.swift`，更新 `MembershipStore.swift`、`MembershipModels.swift`、`MembershipPaywallSheet.swift`、`SumlyApp.swift`、`HomeView.swift`、`AccountView.swift` 及 `MembershipStoreTests.swift`）。
    - `6425dbc9b907951c73d37b76686d8fcdd0f77eae`（`sumly_ios`）：将 `Sumly` 与 `SumlyWidget` 两个 target 的版本与构建号同步更新为 `1.0.5 (60)`（同步 `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`）。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.5`，构建号：`60`，最低 iOS `17.0`。
- 本次发布**已分发至 TestFlight 内部测试组，并同步将 App Store `1.0.5` 草稿关联构建更新为 Build `60`，未提交 `1.0.5` 审核**（保持 `PREPARE_FOR_SUBMISSION` 待用户确认），未触发外部测试组分发，亦未触碰线上已上架版本 `1.0.4 (54)`。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）一次性完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出、分片上传（2/2）与 Apple 处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b60/Sumly.ipa`，SHA-256：`83234bf74f169af6cfdd3d083c707249d9b0861eb2c43afc88b134fcf23944cf`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.5 (60)`）。
- Apple Build ID / Upload Reservation ID：`03688129-261b-4295-9de8-e9eb3c29d2a0`（上传时间 `2026-11-22T02:56:55-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认自动包含构建 `60`（当前 2 名内部测试员）。

## App Store 1.0.5 草稿、商店截图与订阅商品核实

- App ID：`6813884595`
- App Store `1.0.5` 草稿版本 ID：`848679c8-144b-43dd-a2fc-ea039e681dc1`
  - 平台：`IOS`，发布方式：`AFTER_APPROVAL`
  - 版本状态：`PREPARE_FOR_SUBMISSION`（**未提交审核**，待用户确认）
  - 关联构建：已从 Build `59`（`e41f47fb-cb9a-41ad-91b6-a042927fb714`）更新为 `1.0.5 (60)`（`03688129-261b-4295-9de8-e9eb3c29d2a0`，`processingState=VALID`）
  - `zh-Hans` 本地化 ID：`b2472854-10b5-4a26-ac90-43a2db8a30f5`
- 商店截图只读核验（12/12 `COMPLETE` 完好）：
  - `APP_IPHONE_67`（截图集 `89ed9ee3-b9dd-45bc-8df1-0044f255f126`，共 6 张，`01.png` ~ `06.png` 全部 `COMPLETE`）：
    1. `01.png`：`24400019-623a-80b3-8035-81ff5b0176ae`
    2. `02.png`：`2d400019-623a-80b3-8002-d77f7ee39958`
    3. `03.png`：`0a000019-623a-80b3-802e-5a085febd44d`
    4. `04.png`：`b6000019-623a-80b3-801d-a77de5c86e76`
    5. `05.png`：`f3000019-623a-80b3-8000-3362d02a5daf`
    6. `06.png`：`ee400019-623a-80b3-8011-7303ab9b0de3`
  - `APP_IPAD_PRO_3GEN_129`（截图集 `222f7350-efd9-48ee-9716-41423a678f03`，共 6 张，`01.png` ~ `06.png` 全部 `COMPLETE`）：
    1. `01.png`：`d9800019-623a-80b3-803b-3fe62c021e70`
    2. `02.png`：`b6000019-623a-80b3-802a-2244fb2e2130`
    3. `03.png`：`7fc00019-623a-80b3-8039-8c07bcbc18e2`
    4. `04.png`：`7f800019-623a-80b3-8026-f563178f118a`
    5. `05.png`：`39c00019-623a-80b3-8003-aa0124e33f7d`
    6. `06.png`：`8e800019-623a-80b3-8027-5a1dcac3eb02`
- 订阅商品只读核验（全部 `READY_TO_SUBMIT` 完好）：
  - **记金年度会员**（`com.oryjk.sumly.membership.yearly`，商品 ID `6837923490`）：`READY_TO_SUBMIT`
  - **记金月度会员**（`com.oryjk.sumly.membership.monthly`，商品 ID `6837923614`）：`READY_TO_SUBMIT`
- App Store 线上版本只读核对（未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），仍绑定构建 `54`（`6922a244-934c-4107-902d-8dd837f843f5`）。

## 验证记录

- iOS 全量生成与构建：`cd sumly_ios && make generate && make build` 通过，零编译错误、零新增 Swift 6 编译警告。
- iOS 全量单元测试：`xcodebuild -project Sumly.xcodeproj -scheme Sumly -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test` 执行 **12 个测试套件共 387 项单测全部通过**（耗时 60.078 秒）。
