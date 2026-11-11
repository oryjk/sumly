# sumly_ios - AGENTS

## 项目定位

sumly 的 iOS 原生端，`SwiftUI + Swift 6 + Swift Charts + XcodeGen`，iOS 17 起。
当前功能：后端黄金行情、账户持仓云存储与 SwiftData 离线缓存、原生账户中心。
Apple、+86 手机验证码、邮箱注册/密码登录接 `../sumly_go`；登录账户使用独立缓存及按用户隔离的云文档。
游客继续使用原 SwiftData 存储，只可显式导入账户；切换/退出不得重新归属记录。账户注销删除云端及该账户缓存，保留独立游客数据。
同步必须使用版本 CAS 与持久化 base 做三方合并，冲突需用户明确选择；请求绑定账户及 sessionGeneration，过期响应不得写入缓存。

## 常用命令

```bash
cd sumly_ios
make generate   # 改完 project.yml 后重新生成 .xcodeproj（不要手改工程文件）
make build      # 模拟器编译
make test       # 模拟器跑单测（Swift Testing）
make open       # 生成并用 Xcode 打开
make upload     # 本地归档/签名导出，再通过 JWT API 上传
```

## iOS 发布与 TestFlight（必须遵守）

发布前先读 [上传操作文档](docs/app-store-connect-api-upload.md)。用户已确认采用「本地签名 IPA + App Store Connect JWT API」流程；后续发布必须沿用。

- 标准入口是 `make upload` → `scripts/upload_app_store.sh` → `scripts/upload_signed_ipa.py`。
  Xcode / `xcodebuild` 仅用于编译、归档和本地导出（`destination=export`）。
  除非用户明确要求换方式，禁止使用 Xcode Organizer 上传、`destination=upload`、`altool` 或 Transporter 上传；API 网络异常也不得自行切回这些方式。
- 已有该版本的签名 IPA 时，使用 `bash scripts/upload_app_store.sh --ipa <IPA路径>`，复用对应的 `.asc-upload-state.json`。
  不重复归档、不删除恢复状态、不因网络失败递增 build number。版本、包身份和校验和必须匹配；未知创建结果先对账，不能重复创建任务；Apple 处理中只查询状态，不再次传文件。
- 上传默认沿用环境代理。代理异常时可用 `SUMLY_UPLOAD_DIRECT=1` 仅让该上传进程直连，保持 TLS 验证，不修改系统代理。
  连接阻塞或超时要及时报告实际阶段和原因，不反复静默重试；详见操作文档中的超时说明。
- TestFlight 分发必须覆盖所有现有测试组，包括内部「测试」组与公开链接的「外部测试」组。每次发布均从 Apple 查询实际最新的有效构建及版本，不用本地版本配置推断线上最新构建。
  内部组保持自动分发；外部组每次必须添加最新构建、核对测试信息、提交所需的 Beta App Review，并启用审核通过后自动通知测试者。只加入内部组不算完成。
- 发布完成条件：目标构建 `processingState=VALID`、`internalBuildState=IN_BETA_TESTING`，所有目标组均包含该构建；有外部组时，还须确认 `externalBuildState=IN_BETA_TESTING`。
  若 Apple 外部审核仍在等待或进行中，明确报告「已加入测试组、已提交审核，外部暂不能下载」，不得宣称发布已全部完成；不得为等待审核反复上传 IPA。
  完成一次最终核实后，立即报告版本/build 和 TestFlight 可测试状态，并结束发布任务。
  **成功后不得为了验证恢复脚本再次启动上传命令、重复联网核实或继续修上传工具。** 后续工具改进另行安排；必要的脚本验证在上传前使用离线测试完成。
- 故障重试不重复已经通过且代码未变的完整测试。凭据、私钥、JWT 和临时签名 URL 不得写入日志或提交。

2026-10-01 已验证该流程：0.1.1（23）通过签名 IPA / JWT API 上传，Apple 状态 VALID / IN_BETA_TESTING，已进入内部「测试」组。

## 关键目录

```text
project.yml                # 工程声明（改 target/依赖/Info.plist 在这里）
Sumly/Sources/
  App/                     # 应用入口
  DesignSystem/            # GoldTheme 令牌 + 通用卡片/胶囊样式
  Features/Home/           # 首页（视图、ViewModel、PriceRange 切片）
  Features/Account/        # 账户 UI；Core 内为服务、Keychain、会话、表单和 Apple 状态
  GoldMarket/              # 金价模型 + GoldPriceServicing 协议与实现
Sumly/Resources/           # Assets.xcassets
Tests/                     # 单测（解析/切片/ViewModel）
scripts/make_appicon.py    # AppIcon 生成脚本（Pillow，可选）
```

## 协作约定

- 工程由 XcodeGen 生成，`.xcodeproj` 不入库：新增/删除文件后必须 `make generate`，
  工程结构改动只改 `project.yml`。
- 视觉只允许引用 `DesignSystem/GoldTheme.swift` 的令牌（深色 + 金行情风），
  页面禁止硬编码颜色/形状；涨跌配色遵守国内习惯：红涨（`up`）绿跌（`down`）。
- 行情默认走后端 `BackendGoldPriceService`（`/api/v1/app/market/gold/*`），
  实时报价由各页 ViewModel 每 3 秒轮询（行情页写入尾根 K 线，持仓页用于元/克估值）；
  `SinaGoldPriceService` 为直连新浪的备用实现。数据源改动只动协议实现与注入处，
  不要在视图里直接发请求。
- 持仓记录用 SwiftData（`Features/Holdings/HoldingRecord`），`timestamp` 是用户指定的
  精确持有时点（可补录历史），改字段需考虑本地迁移；汇总/收益计算集中在
  `HoldingsStats` 纯函数，别在视图里散落算式。
- 新功能目录 `Sumly/Sources/Features/<Name>/`：View + ViewModel（`@MainActor @Observable`）
  + 纯逻辑类型分离，纯逻辑（解析、切片等）必须有对应单测。
- 认证 API 契约以 `../sumly_go/docs/openapi.yaml` 为准。Apple challenge 的 nonce 原样传递，
  不重复哈希；服务端配置不可用时不能使用假登录/验证码兜底。
- 登录尝试代际与已建立会话代际必须分开：关闭表单或失败重登不能丢弃已提交的刷新结果；
  真正退出、账号替换则必须阻止旧请求复活。注销重验绑定原用户 ID/provider，不能改删其他账号。
- 凭据只存专属 Keychain；退出标记用于防止删除失败后恢复旧凭据，禁止存储密码/验证码。
- Swift 6 严格并发：服务层 `Sendable`，可变共享状态用 actor，不用 `NSLock`。
- 日期一律存「当地时区当天正午」的 `Date`（见 `SinaGoldPriceService.parseDay`），
  避免时区/夏令时导致的日期漂移。
- 单测用 Swift Testing（`import Testing`），mock 服务实现协议放测试文件内。
- 模拟器验证：`xcrun simctl install/launch` + `io screenshot` 截图目视检查新 UI。
