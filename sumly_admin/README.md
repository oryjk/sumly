# Sumly Admin (`sumly_admin`)

记金（Sumly）远程配置管理后台前端，基于 **React 19 + TypeScript + Vite + Tailwind CSS v4** 构建，提供暗黑金控制台界面，用于实时切换「禅观」收费门禁、控制「我的」页记金会员入口展示、配置限时免费公告，以及查看全量配置与变更审计日志。

## 功能特性

- **管理员令牌门禁（Token Gate）**：通过 `GET /admin/auth/verify` 校验 `ADMIN_API_TOKEN`，会话仅存储于 `sessionStorage`（关闭标签页自动清理），支持可选自定义 API Base 地址。
- **「禅观付费门禁」核心工作台**：
  - 实时生效状态横幅（收费中 / 免费开放中）
  - 一键切换 `chanlun_requires_membership`、`membership_entry_visible` 与 `free_access_notice`（最多 120 字）
  - 切换收费状态前弹出变更摘要确认弹层，防止误操作
  - 右侧「App 行为实时预览」同步模拟未订阅用户点击禅观与「我的」页入口行为
- **变更审计日志（Audit Trail）**：展示最近 30 条配置变更记录（北京时间格式化、操作人、变更备注、开关前后对比标签与 JSON 快照）。
- **扩展配置管理（All Configs）**：查看、JSON 校验编辑及新增其他动态配置项（校验合法 JSON 对象与 16 KB 体积上限）。

## 本地开发

确保后端 `sumly_go` 已启动（默认监听 `http://127.0.0.1:8080` 且已配置 `ADMIN_API_TOKEN`）：

```bash
cd sumly_admin
npm install
npm run dev
```

开发服务器默认运行在 `http://localhost:5173/sumly/admin/`，并将 `/sumly/api/*` 自动代理至 `VITE_API_TARGET`（默认 `http://127.0.0.1:8080`，代理时自动去除 `/sumly` 前缀）。如需指定其他后端地址：

```bash
VITE_API_TARGET=http://127.0.0.1:8081 npm run dev
```

## 类型检查与生产构建

```bash
cd sumly_admin
npx tsc --noEmit
npm run build
```

构建产物输出至 `sumly_admin/dist/`，已配置 `base: '/sumly/admin/'`，可直接由后端 `ADMIN_STATIC_DIR` 托管至 `https://oryjk.cn/sumly/admin/`，默认同源调用 `/sumly/api/v1`。
