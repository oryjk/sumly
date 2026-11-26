# 记金 1.0.7（67）内测发布

2026-11-27，北京时间。

- 源码分支为 `main`，功能与版本提交为 `1714dc83bc2266721f059fff2a5ba31d7b37faac`。
- 本次变更：新增持仓「在谁手上（家庭持有人）」功能，支持母亲、父亲、老公、老婆、孩子、爷爷、奶奶 7 位家庭成员及默认「自己持有」；iOS 端内置 7 位家人暗黑金定制矢量头像，支持记一笔 / 编辑持仓 4×2 宫格直选、列表标题旁独立圆形头像展示、持仓详情徽章展示、按称呼搜索及部分赠卖继承，并补齐 6 语本地化；Go 后端同步扩展持仓云快照可选字段 `holder`（未设置时省略以兼容历史记录与旧客户端）。
- 签名 IPA 的主 App 与小组件均为 `1.0.7 (67)`。IPA SHA-256 为 `df500fa41f256b05930bf363f3633e192c6bb492ecf4abdffab529edd25b6612`。
- App Store Connect 构建 ID 为 `9f46f185-f71b-43d1-9c67-8f2c6d6d0dd0`。构建为 `VALID / IN_BETA_TESTING`，内部「测试」组含构建 67，自动分发已开启（`hasAccessToAllBuilds=true`）。
- 验证：Go 后端全量 `go test ./...`、`go vet ./...`、`go build` 通过；iOS 端新增 `HoldingHolderTests` 及 `LocalizationCoreTests`、`GoldKeyboardDismissTests`、`HoldingsCloudTests`、`HoldingsPageTests`、`HoldingAssetFormProfileTests`、`HoldingsTests` 定向模拟器单测全部通过，并完成暗黑金视觉渲染图目视检查（全量并行模拟器运行中的既往 SwiftData 通知竞争与偶发键盘焦点抢占行为已在前序版本记录，隔离重跑均通过）。
