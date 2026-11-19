# App Store 1.0.2 (37)

- 记金源码 `ea1127862ec5d0c89bb02899d4c15948637e4f54`，分支 `codex/app-store-1-0`。生产禅观源码 `3fb7f23753cb448d9ec5d590aa25aee03f532ee4`，分支 `codex/sumly-chanlun-prod`。禅观基线 `245cf7c7549a35645bb7b52635662e036dbe32d1` 与部署前的 115 个后端、测试和依赖文件一致。
- Bundle ID `com.oryjk.sumly`，版本 1.0.2，构建 37，`Release` 配置。目标先供内部 TestFlight 使用，再提交正式审核，采用审核后自动发布。
- 入口为 `https://match.oryjk.cn/chanlun/?secid=600519.SH&timeframe=30m&view=market`。参数只用于网页，兑换地址保持不带参数。应用沿用正式账号和设备存储，先前联调账号的数据未迁移。
- 京东云正式记金的 `sumly-chanlun-bridge` 通过现有记金会话校验，再以 WireGuard 向 peiqian 签发票据。它没有业务数据库，正式记金后端容器及数据库无需迁移。生产侧只允许京东云 WireGuard 来源签发，公开签发路径返回 404。
- peiqian 服务复用已有配置、运行时和持久化数据。新源码位于 `/data/chanlun/releases/sumly-b37`，由 `zz-sumly-bridge.conf` 指定。原配置 `ios-b1.conf` 仍可作为回退。京东云 nginx 配置备份在 `/root/docker_data/sumly/releases/chanlun-b37/nginx.before.conf`。
- Go 测试、`go vet` 与 Linux 构建通过。禅观后端 190 项及 H5 49 项通过，H5 构建与线上资产一致。iOS 模拟器 200 项通过、1 项需要登录凭据的测试跳过，独立认证测试 26 项通过。
- 生产实测覆盖 WireGuard 签发、HTTPS 兑换、15 分钟安全 Cookie 及同一票据重放拒绝，正式记金拒绝无效登录态。正式行情页、普通禅观游客会话、Android 登录和更新接口均返回 200。真实 Apple 账号授权待 iPhone 内测。
