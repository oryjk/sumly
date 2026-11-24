# 记金 1.0.6（63）公网端口迁移

2026-11-24，北京时间。

- 源码分支 `main`，归档提交 `bd1f2604cf12ca3f054807008f7942cb5cfdeaf7`。
- iOS 主 App、小组件及 Android 默认 API 改为 `https://oryjk.cn:18443/sumly/api/v1`，应用内隐私页使用同一公网端口。
- 外网访问健康检查、黄金报价和隐私页均返回 HTTP 200，且 HTTPS 证书验证通过。iOS 串行执行 406 项测试通过，Android 单测、Lint 和 Debug 构建通过。
- iOS 版本 `1.0.6`，构建 `63`。签名 IPA 的主 App 与小组件均已验证内嵌 `:18443`。IPA SHA-256 为 `08608435fce3792e2c56fa90598dacadaf7c474e557b578b57b37c1139e2b8ad`。
- App Store Connect 构建 ID 为 `5a8b1e8b-6a4e-452c-9bf7-6bffeb7f81b2`，处理状态 `VALID`。
- TestFlight 内部「测试」组已包含构建 63，自动分发开启，构建状态为 `IN_BETA_TESTING`。

## App Store 正式版

- 北京时间 2026-11-24 23:32 撤回构建 62 的审核，将正式版 `1.0.6` 绑定到构建 63，重新提交并核实状态为 `WAITING_FOR_REVIEW`。
- 正式版 ID 为 `8a52f4ba-749a-4d27-a469-23507217cf3c`，新审核单 ID 为 `5e4e1a41-ee42-4951-a782-f32165bcb1ae`。版本发布方式为审核通过后自动发布。
- 提审时可销售地区为 `0 / 175`。等构建 63 过审后恢复销售地区，避免审核期间旧版本重新开放下载。
