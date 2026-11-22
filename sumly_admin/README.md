# Sumly Admin (`sumly_admin`)

记金（Sumly）远程配置管理后台前端，基于 **React 19 + TypeScript + Vite + Tailwind CSS v4** 构建，提供暗黑金控制台界面，用于实时切换「禅观」收费门禁、控制「我的」页记金会员入口展示、配置限时免费公告，以及查看全量配置与变更审计日志。

## 功能特性

- **管理员账号密码登录与会话恢复**：
  - 通过 `POST /admin/auth/login` 使用管理员账号（默认预填 `admin`）与密码登录，支持密码显隐切换与可折叠的高级 API 地址配置（默认同源 `/sumly/api/v1`）。
  - 会话令牌与用户名仅存储在当前标签页的 `sessionStorage` 中；刷新页面时自动调用 `GET /admin/auth/verify` 校验会话有效性并同步 `must_change_password` 状态。
- **首次登录强制改密**：
  - 使用服务端初始引导密码首次登录（`must_change_password === true`）时，自动拦截并引导进入「首次登录请设置永久密码」页面。
  - 实时校验新密码长度（≥ 8 位且 ≤ 72 字节）、强度等级、不可与当前密码相同以及二次确认一致性；提交至 `POST /admin/auth/change-password` 后由后端加密持久化保存至数据库，并立即解锁进入控制台。
  - 若在未改密状态下触发配置写入（`PUT /admin/configs/:key` 返回 `403 / 40301`），前端自动切回强制改密页防止状态卡死。
- **随时修改密码与安全退出**：
  - 顶部导航栏展示当前登录账号，支持随时点击「修改密码」通过弹窗更新永久密码（同时注销其他终端会话，当前会话保持有效）。
  - 点击「退出登录」先调用 `POST /admin/auth/logout` 吊销服务端会话，再清理本地 `sessionStorage`。
- **「禅观付费门禁」核心工作台**：
  - 实时生效状态横幅（收费中 / 免费开放中）
  - 一键切换 `chanlun_requires_membership`、`membership_entry_visible` 与 `free_access_notice`（最多 120 字）
  - 切换收费状态前弹出变更摘要确认弹层，防止误操作
  - 右侧「App 行为实时预览」同步模拟未订阅用户点击禅观与「我的」页入口行为
- **变更审计日志（Audit Trail）**：展示最近 30 条配置变更记录（北京时间格式化、操作人、变更备注、开关前后对比标签与 JSON 快照）。
- **扩展配置管理（All Configs）**：查看、JSON 校验编辑及新增其他动态配置项（校验合法 JSON 对象与 16 KB 体积上限）。

## 本地开发与联调

### 1. 联调本地 Go 服务（默认）

确保后端 `sumly_go` 已启动（默认监听 `http://127.0.0.1:8080`，且已配置初始管理员引导密码 `ADMIN_BOOTSTRAP_PASSWORD`）：

```bash
cd sumly_admin
npm install
npm run dev
```

开发服务器默认运行在 `http://localhost:5173/sumly/admin/`，会将 `/sumly/api/*` 自动代理到 `http://127.0.0.1:8080/api/*`。

### 2. 联调生产或自定义后端地址

`vite.config.ts` 支持自动识别目标 URL 的部署前缀，无论联调本地端口还是带 `/sumly` 前缀的线上环境均可直接使用：

```bash
# 联调线上环境（自动代理 /sumly/api/* -> https://oryjk.cn/sumly/api/*）
VITE_API_TARGET=https://oryjk.cn/sumly npm run dev

# 联调其他本地端口（自动代理 /sumly/api/* -> http://127.0.0.1:8081/api/*）
VITE_API_TARGET=http://127.0.0.1:8081 npm run dev
```

### 3. 首次登录与改密流程

1. 打开 `http://localhost:5173/sumly/admin/`，输入账号（默认 `admin`）与服务端初始引导密码，点击「登录控制台」。
2. 首次登录成功后将自动进入「首次登录请设置永久密码」界面；输入当前初始密码与不少于 8 位的新密码并确认提交。
3. 新密码加密持久化入库后自动进入配置工作台；后续可随时在顶部导航栏点击「修改密码」更新密码，或点击「退出登录」注销当前会话。

## 类型检查与生产构建

```bash
cd sumly_admin
npx tsc --noEmit
npm run build
```

构建产物输出至 `sumly_admin/dist/`，已配置 `base: '/sumly/admin/'`，可直接由后端 `ADMIN_STATIC_DIR` 托管至 `https://oryjk.cn/sumly/admin/`，默认同源调用 `/sumly/api/v1`。
