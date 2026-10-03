# sumly_mini

sumly 微信小程序端。uni-app + Vue 3 + TypeScript + Vite，UI 组件库 @wot-ui/ui，
架构与工程约定见 [AGENTS.md](AGENTS.md)。

## 当前能力

对齐 iOS App 的深色金主题，实现行情、持仓、账户与提醒四大模块。

**行情**：国内 Au99.99 与国际伦敦金双口径、十种时间范围、交互式图表
（拖动/缩放/查价/区间统计）、增量历史同步与本地缓存。

**持仓**：多账本、搜索筛选排序、批量迁移删除、部分卖出与赠送（成本守恒）、
添加编辑（自动带日期参考价）、盈亏拆解（精确到分）、记金日历、买前计算器与情景测算。

**账户**：微信 / +86 手机 / 邮箱三种登录、显式登录（启动不自动登录）、
会话代际隔离、跨设备持仓同步与三方合并冲突处理、游客数据显式导入、
退出与注销（含云端清理）。

**提醒**：保本 / 收益率 / 盈利金额 / 金价四类目标，穿越触发、24 小时冷却、
异常跳变过滤。微信订阅消息送达需服务端配置模板（见下）。

跨端验收记录见 [`../docs/mini-app-parity-verification.md`](../docs/mini-app-parity-verification.md)。

## 快速开始

```bash
bun install

# H5 开发（默认连本地 sumly_go，见 .env.development）
bun run dev:h5

# 微信小程序开发（产物在 dist/dev/mp-weixin，用微信开发者工具打开该目录）
bun run dev:mp-weixin
```

## 常用命令

```bash
bun run test         # Bun 内置 runner，416 个用例
bun run type-check   # vue-tsc
bun run build:h5
bun run build:mp-weixin
```

真机/开发者工具里使用微信登录前：

1. 把 `src/manifest.json` 的 `mp-weixin.appid` 换成真实 appid；
2. `../sumly_go/.env` 的 `WECHAT_APP_ID` / `WECHAT_APP_SECRET` 填同一小程序的密钥；
3. 开发者工具中开启「不校验合法域名」（本地 HTTP 调试）。

## 环境变量

| 变量 | 说明 |
| --- | --- |
| `VITE_API_BASE_URL` | Go App API 根路径，必须以 `/api/v1/app` 结尾 |
| `VITE_USE_MOCK` | `true` 时启用 mock 数据（全有或全无） |
| `VITE_PUBLIC_BASE` | H5 部署子路径（如 `/mini/`） |

## 微信订阅消息

持仓提醒的微信消息送达需要服务端配置真实模板：
`HOLDING_NOTIFICATION_TEMPLATE_ID` 与各 `HOLDING_NOTIFICATION_FIELD_*`。

**未配置时** `GET /notifications/holding/capabilities` 返回
`available: false`，小程序不会请求订阅授权，提醒只在前台以本地提示呈现。
这是预期行为，不是缺陷。

## mock 模式

`VITE_USE_MOCK=true` 时全部接口走 `src/mock/`，不请求真实后端。
mock 必须「全有或全无」：未覆盖的接口直接报错，不回落真实服务器。
注意 mock 的订阅消息能力**固定为不可用**，与生产未配置模板时行为一致。
