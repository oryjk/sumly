# 记金 1.0.7（66）内测发布

2026-11-25，北京时间。

- 源码分支为 `main`，客户端提交为 `757ab8d`，版本文件提交为 `00920f4a50dc771caf60eb240b87068f1b5d9b2a`。
- iOS 主 App、小组件和 Android 使用三条 API 入口。主线为 `https://oryjk.cn/sumly/api/v1`，第一备用为 `https://backup.oryjk.cn:19443/sumly/api/v1`，第二备用为 `https://home.oryjk.cn:18443/sumly/api/v1`。访问三个入口的黄金报价均返回 HTTP 200，证书校验通过。
- 签名 IPA 的主 App 与小组件均为 `1.0.7 (66)`，已检查三条地址均写入产物。IPA SHA-256 为 `70c3630f6f12a79ac0b7b100ace594e93dfb1c437c4d679cb35b8dfde1bc96ed`。
- App Store Connect 构建 ID 为 `08918b44-73e6-4954-8086-2bde5b901458`。构建为 `VALID / IN_BETA_TESTING`，内部「测试」组含构建 66，自动分发已开启。
- iOS Swift 测试 35 项通过，15 项定向模拟器测试通过。全量模拟器中的 SwiftData 崩溃已在原提交复现，另有键盘焦点断言失败。排除这两项后的模拟器测试 408 项通过、1 项跳过。Android 90 项单测、Lint 和 Debug 构建通过。
