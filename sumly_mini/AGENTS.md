# sumly_mini - AGENTS

## 项目定位

sumly 微信小程序 / H5 端，技术栈 `uni-app + Vue 3 + TypeScript + Vite + @wot-ui/ui`，
对接 `../sumly_go` 后端（响应 envelope 为 `{ code, message, data }`）。

## 常用命令

```bash
cd sumly_mini
bun install
bun run dev:mp-weixin
bun run build:mp-weixin
bun run dev:h5
bun run build:h5
bun run type-check
```

## 关键目录

```text
src/
  api/           # 按业务域封装接口
  components/    # 通用组件（暂空，按需创建）
  config/        # 环境配置（API 根路径）
  mock/          # VITE_USE_MOCK 开发数据（全有或全无）
  pages/         # 小程序页面
  static/        # 静态资源
  stores/        # 模块级 reactive 会话与全局状态
  types/         # 类型定义
  utils/         # 请求、登录态存储、工具方法
```

## 协作约定

- 页面逻辑、接口封装、通用工具保持分层，不要把所有请求直接散落在页面里。
- 新增接口优先放入 `src/api/<domain>.ts`，并补充对应类型（`src/types/`）。
- 登录态只通过 `src/stores/appSession.ts`（经 `src/utils/sessionBridge.ts` 取得单例）
  与 `src/utils/authStorage.ts` 读写，页面不要直接操作 token 存储。
  两者互相 import 会成环，故单例放在 sessionBridge。
- **登录是显式操作**：无 token 时保持游客态，启动时不自动登录。
  手动退出标记阻止静默重登。
- **代际（generation）是异步安全的核心**：登录、退出、换号都自增代际，
  过期或换号后返回的响应不得复活会话、清掉新凭据或改写其它账户缓存。
  新增任何异步回调都要先比对代际。
- **云端 revision 是 int64**，超过 2^53 的值无法用 JS number 精确表示。
  `src/utils/holdingWire.ts` 用结构扫描从原始文本取词法值，PUT 也手工拼 JSON，
  **不要改回 `JSON.parse` + `Number()`**。
- **盈亏拆解必须精确对账**：分项之和要精确等于总盈亏分。因此分值以十进制
  整数字符串保存、运算走 BigInt，并对**累计值**取整而非逐项独立舍入
  （见 `src/domain/holdings/breakdown.ts`）。元→分换算不要用 `value * 100`。
- 视觉规范：全站「深色 + 金」主题，视觉基准为 iOS 端
  `../sumly_ios/Sumly/Sources/DesignSystem/GoldTheme.swift`。颜色/描边/圆角/控件高度/间距
  只允许引用 `src/uni.css` 里的 `--gold-*` 令牌，禁止硬编码；桌面端适配通过在
  `@media (min-width: 768px)` 中收敛为手机宽度列实现。通用控件做成 `src/components/`
  下的组件（如 `GoldInput`），样式随组件走并吃令牌。
- 涨跌配色遵守国内习惯：红涨（`--gold-up`）绿跌（`--gold-down`）。
- 底部导航与中央添加入口统一走 `src/stores/navigation.ts` 的注册路径，
  页面不硬编码跳转地址。
- H5 开发测试登录：「我的」页在 `#ifdef H5` 下提供"标识 + 开发登录"入口
  （`loginWithDevIdentifier`），走后端 `/auth/dev/login`（需 `DEV_LOGIN_ENABLED=true`）；
  mock 模式下不渲染该入口。
- **`.vue` 模板里不能写 TS 类型断言**（`$event as {...}` 会报语法错误），
  把取值逻辑写成 `<script setup>` 里的函数再在模板调用。模板里也不能直接用
  `uni.*`，同样提到脚本里。
- 微信订阅消息：H5 无该能力，`requestSubscribeMessage` 只在 MP-WEIXIN 编译；
  `success` 回调只代表弹窗结束，必须逐模板检查 accept/reject/ban；
  授权只能由用户点击触发，不允许在轮询里自动弹。服务端未配置模板时
  `capabilities.available=false`，此时不请求授权——如实呈现不可用。
- 修改核心流程时，确认字段与后端真实 JSON 一致；后端契约见 `../sumly_go/docs/openapi.yaml`。
- 小程序环境差异较多，避免随意引入仅适用于 Web 的 API（如 `URL`、`URLSearchParams`）。
- 页面 SFC 默认只承担页面编排：生命周期、加载状态、页面级表单状态、导航和组件事件 wiring。
- 页面专属组件放在 `src/pages/<domain>/components/`；只有稳定跨页面复用的组件才放进 `src/components/`。
- mock 模式必须“全有或全无”：新接口要么补 mock handler，要么明确关闭 `VITE_USE_MOCK`。
  mock 不得谎报成功：订阅消息能力固定报不可用，发送结果不声称已送达。
- `manifest.json` 的 `mp-weixin.appid` 需替换为真实小程序 appid（当前为占位 `touristappid`），
  且必须与后端 `WECHAT_APP_ID` 一致。

## 跨端约束（H5 与小程序兼容）

日常开发以 H5 为主，但必须保证 mp-weixin 可编译可运行；H5 显示正常不代表小程序正常。

- 统一使用 `uni.*` API（`uni.request`、`uni.getStorageSync`、`uni.navigateTo`…），
  不要直接调用 `wx.*`。
- 禁止浏览器 DOM API：不写 `document.*`、`window.*`、`localStorage`、`querySelector` 等，
  存储统一用 `uni.getStorageSync` / `uni.setStorageSync`。
- 微信专属能力（`uni.login` 换 code、`open-type` 按钮等）必须用条件编译
  `#ifdef MP-WEIXIN` / `#ifndef MP-WEIXIN` 隔离，并提供 H5 降级路径
  （如 H5 开发登录入口）。
- 运行时 Vue 组件必须直接从 `.vue` 文件导入（如 `@/components/NeoInput/NeoInput.vue`），
  不要经 barrel 文件二次导出：mp-weixin 编译器不追踪二次导出，会漏掉
  `usingComponents`，构建成功但组件不渲染；类型与纯 TS 函数不受此限。
- 新增页面或功能后，定期执行 `bun run build:mp-weixin` 确认小程序可编译。
