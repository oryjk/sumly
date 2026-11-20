# TestFlight 1.0.2 (36)

- 日期 2026-11-19（北京时间）。记金源码 `6df5e4980f034aa572337b4a0765948255908c21`，分支 `codex/app-store-1-0`。禅观网页沿用 `codex/sumly-chanlun-sso` 上的 `2cafc966a255de04c170807e1ba6c6f4e24b68ae`。
- Bundle ID `com.oryjk.sumly`，版本 1.0.2，构建 36。归档配置为 `InternalTest`，分发目标为内部「测试」组。
- 「金伴 → 禅观」使用全屏页面，左上角按钮返回金伴。WebView 延伸到屏幕底部，网页底栏处理 Home 指示条安全区。
- 198 项 iOS 测试通过。iPhone 17 Pro Max 模拟器通过联调账号打开公网禅观，验证 WebView 底边对齐、行情和跟踪按钮可点击、左上角返回金伴，并目视检查全屏截图。
- App Store Connect 构建 ID `b473499c-8088-4fda-aa04-b3827c95d90e`。处理状态 `VALID`，分发范围 `INTERNAL_ONLY`，内部「测试」组状态 `IN_BETA_TESTING`。简体中文测试说明已保存。
- 严格签名校验通过，最低系统版本为 iOS 17.0。IPA SHA-256 为 `fd3875c60fda6691f580101f79fb29d92d3f86e7da6ebea988f3706d52af186b`。
