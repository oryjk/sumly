# 记金 Android

记金的原生 Android 客户端，最低支持 Android 8.0（API 26）。正式包名为 `com.oryjk.sumly`，本地调试包使用 `com.oryjk.sumly.debug`，可与正式版并存。

工程沿用 Local233「策略货架」Android `a0959ff` 的主要技术和版本。Gradle 8.10.2、AGP 8.7.3、Kotlin 2.0.21、JDK 17、SDK 35、Compose BOM 2024.12.01、Material 3、AndroidX Lifecycle 2.8.7、Retrofit 2.11、Gson 和 OkHttp 4.12。依赖按记金实际使用的能力引入。

## 开发

可在 Android Studio 打开本目录。命令行构建使用 Android SDK 35 和 JDK 17。

```bash
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

调试 APK 位于 `app/build/outputs/apk/debug/app-debug.apk`。正式签名待确定。

## 代码结构

- `bootstrap` 是唯一应用组装入口，通过 ViewModel Factory 显式注入行情服务、账户服务和游客存储。
- `ui/navigation` 组合行情、持有、日历、我的和独立的快速添加入口。配色取自 iOS `GoldTheme`。
- `features` 按功能组织 Compose、ViewModel、业务模型、接口适配。界面订阅不可变状态，计算规则集中在纯 Kotlin 类型。
- `core/network` 复用 Go API 信封、生产基址和授权语义；生产请求走 HTTPS，接口路径保留 `/sumly/api/v1` 前缀。

## iOS 对齐范围

视觉基准为本机 iPhone 17 模拟器的 iOS 1.0.4（54）。

- 行情默认国内 Au99.99、近三月。支持国内/国际切换、完整交易时段分时、历史区间、线性/对数、单指查价、双指缩放和区间导航。旧版实时接口回退到滚动窗口。保本线和可点开的买入明细来自当前账本，随金额隐藏设置关闭。
- 黄金温度、美国国债、宏观指标详情和 CFTC 黄金期货持仓使用 Go 实际数据，支持历史区间与触摸查值。
- 游客持有与日历使用独立 SQLite 库，支持多个账本、快速入库、编辑、金额隐藏和部分卖出或赠出。历史参考价精确匹配购入日收盘，国际价格按当前汇率折算。找不到参考价时可填写实际成交价。
- 持有页提供全部持仓收益、盈亏来源和单笔情景测算。入库后可生成纪念卡，经系统分享 PNG。金额隐藏时遮盖敏感值并收起分享入口。四类持仓提醒只在应用前台检查报价，阈值配置参与云同步，设备监测状态保存在本机。
- 桌面小组件显示与应用当前行情口径一致的公开报价、涨跌和报价时间，更新由 Android 系统调度。
- 账户通过服务端能力检测提供 Google 登录、邮箱注册与登录、密码重设和手机号验证码。设置支持双向绑定 Google 和邮箱、退出与注销、手动同步、显式导入游客记录和清理行情缓存。
- 邮箱和 Google 凭据绑定到同一用户后，Android 和 iOS 共用该账户的云端账本。Android 使用独立账户缓存、版本 CAS、持久化三方合并和冲突确认。离线时可继续记录，重新联网后自动同步。游客账本与账户账本分开保存。
- 禅观入口通过登录后的短时票据兑换网页会话。票据交换与导航规则有单元测试覆盖。

## 登录环境

Google 使用 Android Credential Manager。服务端通过 `GOOGLE_OAUTH_CLIENT_ID` 发布 Google Cloud 项目的 Web OAuth 客户端 ID。为 `com.oryjk.sumly.debug` 和 `com.oryjk.sumly` 各登记对应签名证书的 SHA-1，并在同一 Google Cloud 项目创建 Android OAuth 客户端。邮箱验证码由服务端配置的 SMTP 发送。服务端配置见 [Go 后端原生认证](../sumly_go/README.md)。

仅使用 Apple 登录的既有 iOS 账户仍需单独的跨端绑定入口。真实 Google 账号、线上邮箱和禅观生产账号联调依赖服务端配置及测试凭据。

## 验证

Android 16 模拟器与隔离 Go/PostgreSQL 服务联调使用同一邮箱账户。测试调用 iOS 现有网络与编解码源码，验证邮件验证码注册、Swift 写入持仓、Android 拉取并确认导入游客记录、Swift 读回、退出切回游客和换号隔离。81 项 Android 单测通过，Android Lint 无错误，调试 APK 最低版本为 API 26，Android 8.0 设备实测待进行。
