# TestFlight 1.0.2 (34)

- 日期 2026-11-19（北京时间）。
- 记金源码 `ce59be65294ba31005dee701db4197ae11e4018a`，分支 `codex/app-store-1-0`。禅观后端源码 `2cafc966a255de04c170807e1ba6c6f4e24b68ae`，分支 `codex/sumly-chanlun-sso`。
- Bundle ID `com.oryjk.sumly`，版本 1.0.2，构建 34，归档配置 `InternalTest`，导出选项 `testFlightInternalTestingOnly=true`。
- 用独立测试账号进入「我的 → 打开禅观」。HTTPS 页面及兑换接口通过 `ai.oryjk.cn:82/sumly-chanlun-dev/`，签发留在服务器内部。测试环境使用独立的钥匙串、偏好、持仓与行情缓存。
- iPhone 17 Pro 模拟器验证公网免登及导航范围。两级 Nginx 配置语法通过，原 Android 反代规则与备份一致，登录和更新接口均返回 200。
- 本次数验只覆盖身份和免登，会员购买核验及功能授权尚未接入。
