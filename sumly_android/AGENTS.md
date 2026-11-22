# 记金 Android 开发约定

- 原生 Kotlin、Jetpack Compose、Material 3 和 AndroidX Lifecycle。网络使用 Retrofit、Gson 和 OkHttp。最低版本为 Android 8.0（API 26）。正式包名为 `com.oryjk.sumly`。
- 使用单 Gradle 应用模块。由 `bootstrap` 组装依赖，各功能用 ViewModel 和只读 `StateFlow` 驱动界面。业务计算用纯 Kotlin，网络和设备存储封装在服务或存储接口之后。
- 产品行为以 `../sumly_ios/Sumly/Sources` 当前实现为基准，接口和字段以 `../sumly_go/docs/openapi.yaml` 及 Go handler 为准。行情和持仓估值使用相同口径，缺报价保留空状态，涨跌遵循红涨绿跌。
- 游客账本与账户数据隔离。游客数据只允许显式导入。账户同步启用前，需完整实现隔离缓存、版本 CAS、持久化三方合并基线、显式冲突处理及会话代次校验。登录凭据使用 Android Keystore 加密后存储。
- 开发验证执行 `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`。发布遵守仓库根目录规则。签名配置、密钥和构建产物留在 Git 外。
