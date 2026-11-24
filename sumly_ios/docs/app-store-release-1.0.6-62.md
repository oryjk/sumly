# 记金 1.0.6（62）公网入口修复与提审

2026-11-24，北京时间。

- 源码分支 `main`。编译归档的提交为 `89aafd3a9546ef106f75c4b491a6b2df89c92ec9`。
- 客户端生产 API 改为 `https://oryjk.cn:82/sumly/api/v1`。iOS 主 App 和小组件共用配置，Android 也已更新默认 API。应用内隐私链接改用 `:82`。
- 公网验证覆盖健康检查、行情、应用配置和隐私页。iOS 406 项测试通过。Android 单测、Lint 和 Debug 构建通过。
- 商店支持及隐私网址改为 GitHub 上可直接访问的 [记金支持与隐私](https://github.com/oryjk/sumly/blob/main/docs/app-store-support.md)，提交为 `bd33a33c31872e7a1a818ebca8161b38d63098d2`。App Store Connect 已接受六种语言的两类链接。Apple 拒绝了此前带 `:82` 的支持网址。

## 构建与分发

- 版本 `1.0.6`，构建 `62`，包标识 `com.oryjk.sumly`，小组件包标识 `com.oryjk.sumly.widget`。
- IPA SHA-256 为 `d1d6627f670804739c6ec3f03744da1762f5176e0fd84efee3fb494f16619fef`。
- App Store Connect 构建 ID `25da0af5-6782-4b95-be01-57c070c5ed11`。处理状态 `VALID`，可用于 App Store。
- TestFlight 内部「测试」组已包含该构建，保持自动分发，状态为 `IN_BETA_TESTING`。
- App Store 版本 `8a52f4ba-749a-4d27-a469-23507217cf3c` 已绑定构建 62。审核单 `abff3a58-ac24-492e-a3bf-4adc4667f011` 提交成功，版本和审核单均为 `WAITING_FOR_REVIEW`。
- 销售范围仍为 `0 / 175`。审核通过后再恢复销售区域，避免旧版在公网 `443` 不通期间重新向用户开放下载。
