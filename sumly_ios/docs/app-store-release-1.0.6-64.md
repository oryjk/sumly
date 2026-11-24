# 记金 1.0.6（64）内测发布

2026-11-25，北京时间。

- 源码分支为 `main`。客户端提交为 `25181381918071edb1f065bf3e76da40c486b8e3`，生成的构建号文件提交为 `329e92697b82e5d9a768644cc7c7b2a7f8bdf96b`。
- iOS 主 App、小组件和 Android 接入备用 API `https://backup.oryjk.cn:19443/sumly/api/v1`。查询遇到连接故障或网关故障时尝试备用入口，写操作只发送一次。
- iOS 串行模拟器测试通过 408 项、跳过 1 项，Swift 认证测试通过 33 项。Android 通过 88 项单测、Lint 和 Debug 构建。备用黄金报价及健康检查从外网返回 HTTP 200，HTTPS 校验通过。
- 签名 IPA 的主 App 和小组件均为 `1.0.6 (64)`，且已检查包含备用地址。IPA SHA-256 为 `8e7bc5e92f92ceeacba1d4ffec7f272aa352e398ff3665795aa915ca23c6421a`。
- App Store Connect 构建 ID 为 `2061f80e-5291-4bdf-bdc0-d46abbaf49cb`。处理状态为 `VALID`，内部测试状态为 `IN_BETA_TESTING`，已核实内部「测试」组包含构建 64 且自动分发开启。
