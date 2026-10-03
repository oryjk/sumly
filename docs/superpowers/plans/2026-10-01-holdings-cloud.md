# 账户持仓云存储与离线同步

用户已要求执行云存储，并要求部署和上传供界面测试。现有 local-only 约束被此请求更新；保留旧游客数据，账户间隔离。

## 方案与接口（任务共同约束）
- PostgreSQL 每用户保存一个版本化 JSON 文档，GET/PUT `/api/v1/app/holdings`，既有 JWT 实时会话/active user 校验。
- 响应 envelope data: `{revision: Int64, document: {schemaVersion: 1, books: [String], records: [Record]}}`。首次 GET 返回 revision 0、默认账本和空 records（无需写入）。
- PUT body: `{expectedRevision: Int64, document: Document}`；成功 revision +1、原样 document。版本冲突 HTTP409，绝不覆盖已有数据。用户 ID 只来自认证上下文。上限4MiB请求/响应、1000 records、100 books、每记录4 alerts。
- Record 使用 camelCase 字段与 Swift HoldingRecord 一致：id(UUID), grams, unitPriceCNY, timestamp, note, createdAt, brand, bookName, disposition(holding/sold/gift), disposedAt?, disposalAmount, purchaseID?, extraFee, purchaseChannel, counterparty, assetType, purity, laborFee, purchaseTotalOverride?, recoveryDeduction, recoveryDiscount, recoveryFixedFee, alerts。
- Date 为 Unix 毫秒数字。Alert: id(UUID), kind(breakEven/returnPercent/profitAmount/price), threshold(Double>=0), enabled(Bool), basis(domestic/international)。运行基线、armed、冷却是设备状态，不进入云文档。
- 文档字段严格校验有限数字、正克数、非负金额、纯度0<值<=1、折扣0<=值<1、正常日期、字符串长度、重复UUID和账本名。旧持仓任意 assetType 保留，不强制新表单 enum；price=0在有实际总额时有效。书名最大100字符、note2000字符、其余文本200字符。
- PUT 在事务中串行检查账户状态、版本更新；账户注销必须同步删除该用户云文档（当前实现为硬删除，使用 FK CASCADE；冻结保留数据）。不修改旧行情及登录契约。
- iOS每账户独立 SwiftData 缓存与 UserDefaults；游客继续用旧存储。显式导入游客记录（UUID幂等，不删除原游客记录）。云同步基于已持久化 base document 做三方合并：不同记录自动合并，同一购入及其部分处置组成的记录族互改/删改时，冲突提示选择本机或云端，避免同时保留两端处置导致重量重复；不得整库盲覆盖。保存本机修改后再推进base，失败保留待同步状态。离线可编辑、前台自动重试、手动同步。
- 同步请求绑定userID+sessionGeneration；登出/替换时取消，不让旧响应写进新账户。服务请求拒绝重定向，401刷新一次，账户注销清空其设备缓存和服务端文档。

### Task 1: Backend holdings aggregate
Own only sumly_go changes. Implement domain/ports/application/PostgreSQL(sqlc)/HTTP/bootstrap migration00007 and auth deletion integration. TDD for validation, CAS/user isolation, auth routes, deletion. Explicit TEST_DATABASE_URL only for PostgreSQL integration. Update OpenAPI and backend docs/AGENTS. Run generate/gofmt/go test/vet/build. Do not commit, deploy, push or access real account messages. Report exact outcomes and unrun integration.

### Task 2: iOS synchronization
Own only sumly_ios changes. Implement Codable snapshot, three-way merge, authenticated bounded transport, account cache and sync coordinator, root scoped containers/defaults, sync status/import/conflict UI/account deletion, offline restoration. Add meaningful merge, network/account-race/persistence tests. Update local-only docs. Generate/build/test. Do not commit/push.

### Task 3: Review and release
Independently review new synchronization paths, fix substantive issues. Verify end-to-end isolated test backend with real database if available. Discover existing deployment configuration without exposing secrets; deploy migration/backend on known host if authorized and credentials available. Increment to next ASC build, archive/upload, confirm TestFlight readiness. No real SMS/email or account creation without authorization.

## 部署恢复与验证（2026-10-01）

首次迁移因 macOS AppleDouble `._00001_initial.sql` 被 goose 当作迁移文件而失败；回滚后确认线上旧镜像仍运行，数据库保持版本6，尚无 holdings_snapshots 表。
清理发布目录15个 `._*` 文件，并重建部署包和源码包，过滤 AppleDouble 条目及扩展属性；API/迁移二进制哈希与原已校验包一致。以后打包使用 `COPYFILE_DISABLE=1 tar --no-xattrs --exclude='._*' ...`，部署前额外断言迁移目录无侧文件。
重试成功应用00007，数据库当前版本7且 holdings_snapshots 存在，运行镜像 `sumly-backend:20261001-holdings-b22`。公网 holdings 未登录401、国内行情200、含新接口的 OpenAPI200、2026-10-01隐私页200；没有进行真实账户写入、短信或邮件测试。
iOS既有签名归档0.1.1(22)复用，未重新实现功能。TestFlight上传与Apple处理状态记录待补。

App Store Connect 上传命令已成功（`/tmp/sumly-cloud-upload-b22.log`: `Upload succeeded`、`EXPORT SUCCEEDED`）。Apple处理状态与内部测试组可用性继续检查，尚未宣称TestFlight可更新。

最终发布完成：App Store Connect构建22（ID 1f3350aa-e70d-4fb4-93de-d1d570913ba9）Apple处理VALID、内部IN_BETA_TESTING，已确认属于内部「测试」组；可在TestFlight更新。后端migration7、新镜像、公网接口及隐私页均验证通过。
