# TestFlight 1.0.5（59）与 App Store 1.0.5 草稿准备记录

- 日期：2026-11-22（北京时间）。
- 源码分支：`main`，构建原始源码提交 SHA：`1d476c72a2a5c1cd531cb1ac5df6b02c931b8c42`（已于归档与上传前推送至 `origin/main`）。
  - 本次发布周期合并至 `main` 的相关提交：
    - `79cccd6e1f55432698bb706b405dc7a706e672d2`（`sumly_ios`，cherry-pick 自 `c596248f891be92a00bd5e7c3bb0c265b3f72eb2`）：实现 StoreKit 2 记金会员订阅系统与缠论功能权限控制（新增 `Sumly.storekit`、`MembershipModels`、`MembershipPaywallSheet`、`MembershipStore`、`MembershipStoreTests`，并接入 `SumlyApp`、`AccountView`、`AccountProfilePresentation`、`HomeView`）。
    - `3268973d0e8b72d72c95efba19e455a963bb2be2`（`sumly_ios`，cherry-pick 自 `539e2d20793c81e6e2999beed407d6d093085b54`）：优化记金会员订阅文案为不含「禅观」的中性表述并补充对应单测与 ASC 审核截图导出。
    - `1d476c72a2a5c1cd531cb1ac5df6b02c931b8c42`（`sumly_ios`）：将 `Sumly` 与 `SumlyWidget` 两个 target 的版本与构建号同步更新为 `1.0.5 (59)`（同步 `sumly_ios/project.yml`、`sumly_ios/Sumly/Support/Info.plist`、`sumly_ios/SumlyWidget/Support/Info.plist`）。
- Bundle ID：`com.oryjk.sumly`（含内嵌小组件扩展 `com.oryjk.sumly.widget` / `SumlyWidget.appex`），版本：`1.0.5`，构建号：`59`，最低 iOS `17.0`。
- 本次发布**已分发至 TestFlight 内部测试组，并完成 App Store `1.0.5` 草稿及订阅商品准备，未提交 `1.0.5` 审核**（保持 `PREPARE_FOR_SUBMISSION` 待用户确认），未触发外部测试组分发，亦未触碰线上已上架版本 `1.0.4 (54)`。

## 构建与 TestFlight 内测核实

- 打包与上传方式：通过标准入口 `PATH="/usr/bin:$PATH" make upload`（`scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`，使用含 `cryptography` 的 `/usr/bin/python3`）一次性完成本地 `Release` 归档（含 `SumlyWidget.appex`）、本地签名导出、分片上传（2/2）与 Apple 处理等待。
- 本地签名 IPA 路径：`sumly_ios/build/ipa-b59/Sumly.ipa`，SHA-256：`f5d2b40bf55db90b9abb5c3b9af3e6da4585c9fb3944b9e2245a17d83abbe300`（主 App `com.oryjk.sumly` 与扩展 `com.oryjk.sumly.widget` 均为 `1.0.5 (59)`）。
- Apple Build ID / Upload Reservation ID：`e41f47fb-cb9a-41ad-91b6-a042927fb714`（上传时间 `2026-11-22T01:16:59-08:00`）。
- Apple 端最终核实结果：
  - `processingState`：`VALID`
  - `usesNonExemptEncryption`：`false`
  - `internalBuildState`：`IN_BETA_TESTING`
  - `externalBuildState`：`READY_FOR_BETA_SUBMISSION`（未触发外部分发）
  - 内部测试组「测试」（`f079109b-a665-463e-add4-5359f91dbe47`）：`isInternalGroup=true`、`hasAccessToAllBuilds=true`（自动分发），已确认自动包含构建 `59`（当前 2 名内部测试员）。

## App Store Connect 订阅商品更新与审核截图核实

- **记金年度会员**（`com.oryjk.sumly.membership.yearly`，商品 ID `6837923490`）：
  - `zh-Hans` 本地化（`98e2e0fe-a82c-4f30-8064-d55ffa803535`）描述更新为：`按年订阅记金会员，解锁高阶多周期走势与复盘工具。`
  - 审核截图 ID：`16a1cf41-3f85-41d5-ac95-468fa9984db7`（`asc_sub_review_paywall.png`，1290×2796），`assetDeliveryState`：`COMPLETE`。
  - 商品最终状态：**`READY_TO_SUBMIT`**。
- **记金月度会员**（`com.oryjk.sumly.membership.monthly`，商品 ID `6837923614`）：
  - `zh-Hans` 本地化（`1b387571-24f1-4298-b3b1-48497457fe28`）描述更新为：`按月订阅记金会员，解锁高阶多周期走势与复盘工具。`
  - 审核截图 ID：`70e07d12-573c-4670-8c9f-05adeeba7e34`（`asc_sub_review_paywall.png`，1290×2796），`assetDeliveryState`：`COMPLETE`。
  - 商品最终状态：**`READY_TO_SUBMIT`**。

## App Store 1.0.5 草稿与 12 张新版商店截图核实

- App ID：`6813884595`
- App Store `1.0.5` 草稿版本 ID：`848679c8-144b-43dd-a2fc-ea039e681dc1`
  - 平台：`IOS`，发布方式：`AFTER_APPROVAL`
  - 版本状态：`PREPARE_FOR_SUBMISSION`（**未提交审核**，待用户确认）
  - 关联构建：`1.0.5 (59)`（`e41f47fb-cb9a-41ad-91b6-a042927fb714`）
  - `zh-Hans` 本地化 ID：`b2472854-10b5-4a26-ac90-43a2db8a30f5`
- 商店截图替换与核验（仅操作 `1.0.5` 草稿，已清空继承旧图并按 `01.png` ~ `06.png` 严格顺序上传，全部 **12/12 `COMPLETE`**）：
  - `APP_IPHONE_67`（截图集 `89ed9ee3-b9dd-45bc-8df1-0044f255f126`，1290×2796，共 6 张）：
    1. `01.png`：`24400019-623a-80b3-8035-81ff5b0176ae`（`COMPLETE`）
    2. `02.png`：`2d400019-623a-80b3-8002-d77f7ee39958`（`COMPLETE`）
    3. `03.png`：`0a000019-623a-80b3-802e-5a085febd44d`（`COMPLETE`）
    4. `04.png`：`b6000019-623a-80b3-801d-a77de5c86e76`（`COMPLETE`）
    5. `05.png`：`f3000019-623a-80b3-8000-3362d02a5daf`（`COMPLETE`）
    6. `06.png`：`ee400019-623a-80b3-8011-7303ab9b0de3`（`COMPLETE`）
  - `APP_IPAD_PRO_3GEN_129`（截图集 `222f7350-efd9-48ee-9716-41423a678f03`，2048×2732，共 6 张）：
    1. `01.png`：`d9800019-623a-80b3-803b-3fe62c021e70`（`COMPLETE`）
    2. `02.png`：`b6000019-623a-80b3-802a-2244fb2e2130`（`COMPLETE`）
    3. `03.png`：`7fc00019-623a-80b3-8039-8c07bcbc18e2`（`COMPLETE`）
    4. `04.png`：`7f800019-623a-80b3-8026-f563178f118a`（`COMPLETE`）
    5. `05.png`：`39c00019-623a-80b3-8003-aa0124e33f7d`（`COMPLETE`）
    6. `06.png`：`8e800019-623a-80b3-8027-5a1dcac3eb02`（`COMPLETE`）
- App Store 线上版本只读核对（未改动）：
  - 版本 `1.0.4`（`ea14d1ca-7f3d-4aff-807b-7d9e3093b183`）：状态为 `READY_FOR_SALE`（`READY_FOR_DISTRIBUTION`），仍绑定构建 `54`（`6922a244-934c-4107-902d-8dd837f843f5`）。

## 验证记录

- iOS 全量生成与构建：`cd sumly_ios && make generate && make build` 通过，零编译错误、零新增 Swift 6 编译警告。
- iOS 全量单元测试：`xcodebuild -project Sumly.xcodeproj -scheme Sumly -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test` 执行 12 个测试套件共 **381 项单测全部通过**（耗时 60.761 秒）。
