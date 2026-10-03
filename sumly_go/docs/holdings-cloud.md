# 持仓账户快照

迁移 `00007_holdings.sql` 后，所有现有用户认证方式均可调用 `GET/PUT /api/v1/app/holdings`。
路由复用 JWT / 实时原生会话及 active 用户中间件；repository 在事务内再次检查账户状态。
用户 ID 只来自 Actor，payload 不允许 owner/userID。游客数据仍留在设备。

GET 返回 `{code:0,message:"ok",data:{revision:0,document:{schemaVersion:1,books:["默认账本"],records:[]}}}`，
尚无快照时不会 INSERT。PUT body 为 `{expectedRevision:0,document:{...}}`，成功返回同一 envelope，
revision 加 1。409 不改变云文档；客户端重新 GET，并以已保存的 base document 做三方合并。

所有非可选字段必填，未知字段、必填 null、JSON 尾随值拒绝（422）。可选 `disposedAt`、`purchaseID`、
`purchaseTotalOverride` 支持省略或 null。精确字段定义和上限见 [OpenAPI](openapi.yaml)。
日期为 Unix 毫秒 Double，保留小数，范围公历 0001–9999 年。UUID 接受大小写，记录 UUID 大小写无关去重。
处置枚举为 `holding/sold/gift`，与现有 iOS 数据一致（不是 gifted）。提醒仅保存配置，不保存 armed、基线、冷却。
书名、note、其余文本上限分别为 100、2000、200 个 Unicode 字符；文本禁止 NUL。
任意历史 `assetType` 都保留；零单价需要正数 `purchaseTotalOverride`。

请求与成功响应上限 4 MiB；过大请求返回 413。每快照最多 1000 records、100 books，每 record 最多 4 alerts。
全部数值必须有限，金额与阈值非负、克数为正、纯度 `(0,1]`、折扣 `[0,1)`。记录 bookName 必须列在 books。
books 非空且名称唯一，alerts UUID 在每条记录内唯一。处置记录须有 disposedAt，且不早于 timestamp。
GET/PUT 返回 `Cache-Control: no-store`，不会在日志中记录快照内容。

数据库 `holdings_snapshots` 每用户一行，JSONB 文档与 BIGINT revision 一起更新。
事务先 `SELECT status FROM users ... FOR UPDATE`，因此首次插入也能串行 CAS，账户删除不能与旧请求交错重建快照。
原生账户注销和 Apple account-deleted 事件目前均使用硬 `DELETE FROM users`，通过 `ON DELETE CASCADE`
原子删除持仓。当前没有软注销路径；将来若新增软注销，必须在同一事务内显式删除持仓。
冻结用户拒绝访问与写入，但保留快照，不将冻结当作注销。

## 验证

单元/HTTP 测试覆盖数值/结构校验、Actor 权限、401/409/413/422、必填 null、未知字段、小数毫秒。
PostgreSQL 集成覆盖并发首次 CAS 仅一个成功、账户隔离、旧版本不覆盖、冻结保留、硬删除级联以及原生注销。
只使用显式 `TEST_DATABASE_URL`，每测试创建随机 schema 并迁移，结束 DROP；不使用 `DATABASE_URL`，不启动 Docker。

## 线上部署（2026-10-01）

已在既有 jd 主机部署 `sumly-backend:20261001-holdings-b22`，数据库 schema `sumly` 当前 migration version7，已确认 holdings_snapshots 存在。公网新接口未登录返回401，国内行情及 OpenAPI正常200；没有使用真实用户数据做写入测试。

macOS打包须排除AppleDouble：使用 `COPYFILE_DISABLE=1 tar --no-xattrs --exclude='._*' ...`。首次部署因 `._00001_initial.sql` 无法解析版本号而失败，自动回滚旧服务，未应用00007。恢复时仅移除发布目录中的15个侧文件，清理部署/源码归档的元数据，并确认API/迁移程序哈希未变；随后迁移与服务健康检查通过。发布目录部署脚本在停止服务前断言迁移目录无 `._*` 文件。此修复没有改动业务实现。
