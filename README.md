# sumly

小程序 / H5 / iOS 多端 + 后端 monorepo（`git@github.com:oryjk/-sumly.git`），应用中文名「记金」——
记录黄金等个人资产，按最新行情计算市值与每日涨跌。
三个子项目共用同一套工程模式：按子项目分目录、每目录自带 `AGENTS.md` 架构与协作约定、
后端六边形架构 + `{ code, message, data }` 响应 envelope、前端视觉只允许引用设计令牌。

| 子项目 | 说明 |
| --- | --- |
| [`sumly_go/`](sumly_go/) | Go 后端：Gin + PostgreSQL(pgx/goose/sqlc) + JWT，六边形架构 |
| [`sumly_mini/`](sumly_mini/) | 用户端：uni-app + Vue 3 + TypeScript + Vite + @wot-ui/ui |
| [`sumly_ios/`](sumly_ios/) | iOS 原生端：SwiftUI + Swift 6 + Swift Charts + XcodeGen（iOS 17+） |

## 当前完成

- 微信注册登录闭环：`uni.login` → `POST /api/v1/app/auth/wechat/session`
  （js_code 换 openid，签发可刷新的 access/refresh 会话，用户不存在自动注册）。
  身份以 `appid + openid` 编码，禁止跨 appid 误绑定；旧 `/auth/wechat/login`
  契约保持不变。
- 统一原生认证：+86 手机验证码、邮箱注册/密码登录/密码重置、
  `capabilities` 能力检测、服务端退出与账户注销。
- 会话管理：代际隔离异步响应、并发 401 只刷新一次、手动退出阻止静默重登、
  退出/换号/注销后的旧响应不写入任何缓存。
- 行情：国内 Au99.99 与国际伦敦金双口径、报价/实时/日线/增量同步、
  十种时间范围、交互式图表（拖动缩放、查价、缩略导航、区间统计）、
  短 TTL 缓存与故障回退、历史游标持久化。
- 持仓：多账本、搜索筛选排序、批量迁移删除、部分卖出与赠送（成本守恒）、
  日期参考价（历史日只用当日收盘价，手动输入不被异步覆盖）、盈亏拆解
  （分项精确对账到分）、记金日历、买前计算器与情景测算。
- 持仓云同步：按账户隔离的版本 CAS 与持久化 base 三方合并，购入族作为
  同一合并单元，冲突需用户显式选择，int64 revision 保留完整精度。
- 持仓目标提醒：保本/收益率/盈利金额/金价四类目标，穿越触发、24 小时冷却、
  异常跳变过滤；微信订阅消息送达需服务端配置真实模板，未配置时
  `capabilities.available=false` 并如实呈现不可用。
- 工程配套：goose 迁移、sqlc 生成、内嵌 OpenAPI 文档（`/api/docs`）、
  Makefile、Dockerfile、单元测试 + 可跳过的 PostgreSQL 集成测试、
  mock 模式（`VITE_USE_MOCK=true`，全有或全无）。

小程序与 iOS App 的逐项验收记录见
[`docs/mini-app-parity-verification.md`](docs/mini-app-parity-verification.md)。
其中 UI 与真机项、以及微信订阅消息的真实送达**尚未验证**，需人工执行。

## 数据库

sumly 的表放在独立 schema `sumly`（`DATABASE_URL` 带 `search_path=sumly`），不占用
public schema，因此可与其他项目安全共用同一个 PostgreSQL 实例，数据与迁移历史完全隔离。
首次接入一个实例需先执行一次 `CREATE SCHEMA IF NOT EXISTS sumly;`。
集成测试通过 `TEST_DATABASE_URL` 指向任意可丢弃的测试库，每个用例创建随机 schema
并在结束时自动回收（`sumly_go/internal/testsupport`）。

## 本地联调

```bash
# 后端（需本地 PostgreSQL，详见 sumly_go/README.md）
cd sumly_go
cp .env.example .env   # 已有占位 .env，可直接试用
make migrate-up
make run               # 默认 :18090

# 小程序
cd sumly_mini
bun install
bun run dev:h5            # H5 调试
bun run dev:mp-weixin     # 产物 dist/dev/mp-weixin，用微信开发者工具打开

# iOS（模拟器，详见 sumly_ios/README.md）
cd sumly_ios
make open                 # Xcode 打开后直接 Cmd+R
```

真实微信登录需要把 `sumly_go/.env` 的 `WECHAT_APP_ID/WECHAT_APP_SECRET` 与
`sumly_mini/src/manifest.json` 的 appid 换成同一个真实小程序的值。

各子项目的架构约束与协作约定见各自目录下的 `AGENTS.md`。
