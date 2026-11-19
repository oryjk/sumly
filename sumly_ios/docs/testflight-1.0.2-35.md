# TestFlight 1.0.2 (35)

- 日期 2026-11-19（北京时间）。记金源码 `d158f27c1759194206414105eaf5b3ae5e1b6c40`，分支 `codex/app-store-1-0`。禅观沿用 `codex/sumly-chanlun-sso` 上的 `2cafc966a255de04c170807e1ba6c6f4e24b68ae`。
- Bundle ID `com.oryjk.sumly`，版本 1.0.2，构建 35。归档配置 `InternalTest`，分发目标为 TestFlight 内部「测试」组。
- 「动态」走势图默认近三月。底栏第二项为「金伴」，「记金」打开原来的持仓和账本页，「禅观」复用当前登录打开网页。
- local233 隔离 API 启用了限时的 Apple 登录凭证，有效至北京时间 2026-12-19 23:12。京东云生产私钥原地签发凭证，联调端保留原独立数据库与会话密钥，并禁用 Apple 授权撤销。
- Go 测试、`go vet`、Linux 构建和 198 项 iOS 测试通过。iPhone 17 Pro Max 模拟器验证近三月、两个金伴入口、原持仓页和可用的 Apple 按钮。公网检查通过 Apple 登录挑战、邮箱会话兑换禅观一次性票据、Cookie 范围及重放拦截。真实 Apple 账号授权待 iPhone 验证。
- 正式后端 Apple 登录能力和 Android 禅观登录、更新接口复查正常。
