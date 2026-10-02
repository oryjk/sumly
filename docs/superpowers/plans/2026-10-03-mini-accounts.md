# 小程序账户与云同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 微信替代 Apple 登录，完整支持 App 的手机/邮箱认证、会话生命周期与账户持仓同步。

**Architecture:** 微信 code 兑换接入现有有状态认证体系；前端统一会话与代际，持仓按账户隔离，以持久化 base 和版本 CAS 三方合并。保留既有旧微信登录响应契约。

**Tech Stack:** uni-app/Vue/TypeScript/Bun，Go 1.26.5 六边形架构，PostgreSQL/sqlc。

**Spec:** `docs/superpowers/specs/2026-10-03-mini-app-parity-design.md`。

## Global Constraints

继承总计划所有约束；依赖 B1/B2 的完整文档与工作区接口。旧 openid 用户必须在同 appid 的确认范围内复用 ID；不得隐式绑定手机/邮箱/Apple 账户。

## Review Focus

旧微信用户迁移/并发注册（C1）、旧请求清掉新凭据/登录竞态/注销错号（C2）、购入族冲突/持久化失败/巨大revision/大小写UUID（C3）。

---

### C1：微信统一会话后端

**Files:** Create `sumly_go/db/migrations/00009_wechat_sessions.sql`、`internal/auth/application/wechat_sessions.go`、`internal/auth/application/wechat_sessions_test.go`、`internal/auth/adapters/http/wechat_sessions_test.go`、`internal/auth/adapters/postgres/wechat_sessions_test.go`；Modify `internal/auth/{domain/native.go,ports/native.go,adapters/postgres/native.go,adapters/http/native.go,adapters/wechat/client.go}`、`db/queries/auth.sql`、`internal/bootstrap/{native.go,dependencies.go,config.go}`、`docs/openapi.yaml`、`.env.example` 和对应配置/契约测试；sqlc 输出由 `make generate` 更新。

**Interfaces:** 新 `WechatSessions.Login(ctx context.Context, code string) (domain.LoginResult,error)`；注入现有 `ports.WechatGateway`、NativeStore、Sessions、配置 appid 与已确认 legacy appid。domain.Capabilities 新增 `Wechat bool`。NativeStore 新增 `LoginWechat(ctx context.Context, appID, legacyAppID, openID string, session domain.Session) (domain.User,error)`，在一事务中关联身份/旧用户并插入会话。HTTP `POST /auth/wechat/session` body `{js_code:string}`，返回既有 NativeLoginResult envelope；`/auth/me` provider 支持 wechat。不返回 raw openid/session_key。

- [ ] 写 Go 用例：有效 code => provider wechat/expires_in900；空code/配置关闭/上游拒绝无会话；同配置appid的legacy用户ID与快照不变；并发首次注册只一用户；不同appid同openid不碰已有身份；微信用户能刷新/服务端退出/最近5分钟重验注销，冻结/注销旧会话不能使用，旧 `/wechat/login` 响应字段与既有测试不变。
- [ ] 运行 `cd sumly_go && make test`，确认新增用例失败；数据库用例只有 TEST_DATABASE_URL 已配置才运行，缺少时记录跳过。
- [ ] 扩展 provider CHECK（只新增迁移），身份subject采用 appid+openid 的明确编码。设置显式 `WECHAT_LEGACY_APP_ID`，只有该值等于当前appid才允许旧 raw-openid 迁移；不确认归属时不猜测。新用户存储 scoped内部openid，旧接口使用相同身份解析但仍签旧JWT，避免两条登录链创建两账户。关联前锁身份及用户，旧账号已关联另一appid时拒绝复用；迁移不改持仓。接入capabilities、refresh/logout/delete现有会话，完善OpenAPI/配置说明，保留iOS协议兼容。
- [ ] `make generate` 后执行 `make test`、`make vet`、`make build`；覆盖旧Apple/phone/email和legacy JWT regression；无数据库环境不声称真实迁移验证通过，不运行共享业务库迁移。
- [ ] 只提交本任务变更：`feat(auth): add compatible WeChat account sessions`。

### C2：前端认证与我的页面

**Files:** Modify `sumly_mini/src/{api/auth.ts,types/app.ts,stores/appSession.ts,utils/authStorage.ts,utils/request.ts,App.vue,pages/user/index.vue,mock/handlers.ts}`；Create `src/types/auth.ts`、`src/domain/auth/forms.ts`、`src/pages/user/components/{AuthenticationForm,AccountActions}.vue`、`tests/{auth-session,auth-forms,authenticated-request}.test.ts`。

**Interfaces:** `AuthProvider='wechat'|'phone'|'email'`、`AuthUser` 精确适配 NativeUser，`AuthCredentials={accessToken:string;refreshToken:string;expiresAt:number;user:AuthUser}`。API方法按现有OpenAPI新增 `getCapabilities()`、`loginWechatSession(code)`、`sendPhoneCode(phone)`、`loginPhone(phone,code)`、`sendEmailCode(email,purpose)`、`registerEmail(email,code,password)`、`loginEmail(email,password)`、`resetPassword(email,code,password)`、`refreshSession(token)`、`logoutSession(token)`、`deleteAccount()`。

store保留 `useAppSession/ensureSessionReady/applyCurrentUser/clearSession` 公共兼容；新增 `sessionGeneration`、`captureSession():{userID:number;generation:number}|null`、`isCurrentSession(capture):boolean`、`refreshAccess():Promise<void>`、`login(provider,form):Promise<void>`、`logout():Promise<void>`、`beginAccountDeletion():DeletionIntent`、`deleteAccount(intent):Promise<void>`。`DeletionIntent={userID:number;provider:AuthProvider;generation:number}`。

所有登录/refresh API返回 `Promise<NativeLoginResult>`（原始token/refresh_token/expires_in/user）；`getCapabilities():Promise<{wechat:boolean;phone:boolean;email:boolean}>`（忽略兼容保留的apple字段）；发码返回 `Promise<{retry_after:60;expires_in:300}>`，重置/退出/注销返回 `Promise<void>`。发送参数是对应OpenAPI字段，email purpose仅 `'register'|'reset_password'`。原生 user.id 不安全整数则拒绝建立会话，避免舍入到其他用户；注销API固定confirmation `'DELETE'`，由store绑定intent执行。

- [ ] 写测试：token恢复、并发401只刷新一次、最多重试一次；关闭/失败登录表单不抹掉已建立会话；退出/换号使旧bootstrap/login/refresh/profile失效且不清新凭据；微信session升级只保持同一用户缓存；强制重验成其他用户不能注销；手机+86格式/邮件normalize、密码12–128Unicode字符与512字节上限、验证码60秒冷却/300秒有效、服务不可用不假成功。
- [ ] 运行 `bun test tests/auth-session.test.ts tests/auth-forms.test.ts tests/authenticated-request.test.ts` 确认失败。
- [ ] 实现显式登录（无token默认游客，替换App启动自动微信登录），微信 `uni.login` 仅 MP-WEIXIN 编译；保留H5开发入口与手机/邮箱。凭据作为一个专属存储单元保存，manual logout防恢复；每条受保护请求在刷新后检查代际再重试，旧响应丢弃。我的页面复现身份、同步入口、资料编辑、清行情缓存、重验/退出/注销；注销绑定原intent和二次确认，成功后仅清对应账户缓存。mock 覆盖完整认证状态，能力关闭/错误/退出真实可测试。
- [ ] 运行目标测试、类型检查/双构建；mock与真实开发账户验证所有表单，H5无微信不挂起；在隔离测试账户验证注销，勿操作真实用户账户。
- [ ] 只提交本任务变更：`feat(mini): add native-parity account flows`。

### C3：精确版本与账户持仓同步

**Files:** Create `src/api/holdings.ts`、`src/utils/holdingWire.ts`、`src/domain/holdings/merge.ts`、`src/stores/holdingsSync.ts`、`src/pages/user/components/SyncStatus.vue`、`tests/{holding-wire,holding-merge,holding-sync}.test.ts`；Modify B2 `src/stores/holdings.ts`、`src/utils/holdingStorage.ts`、`src/pages/user/index.vue`、`src/App.vue`、`src/mock/handlers.ts`。

**Interfaces:** `HoldingSnapshot={revision:string;document:HoldingDocument}`；revision 是非负十进制字符串，范围 `[0,9223372036854775807)`。`decodeHoldingSnapshot(rawJson:string):HoldingSnapshot`、`encodeHoldingPut(expectedRevision:string,document):string`；GET响应读取原始文本，JSON tokenizer保留revision词法值，不将int64转换为JS number/BigInt运行依赖，PUT仍输出JSON整数而非字符串。产生 `getHoldings():Promise<HoldingSnapshot>`、`putHoldings(expectedRevision,document):Promise<HoldingSnapshot>`、`mergeDocuments(base,local,remote,choice?:'local'|'remote'):{document:HoldingDocument;conflicts:string[]}`、`useHoldingsSync()` 的 `status/conflicts/sync(choice?):Promise<void>/importGuest():Promise<void>/eraseAccountCache(userID):void`。

decode读取并校验完整 `{code,message,data:{revision,document}}` envelope；tokenizer按JSON结构定位 `data.revision`，不是文本正则替换，字符串中出现revision不得改变解码。GET和PUT成功响应都读取原始文本。C3修改 `src/utils/request.ts` 新增受同一认证刷新/代际保护的文本响应模式，不能绕过C2重新实现受保护请求。

- [ ] 写测试：`decodeHoldingSnapshot`保持9007199254740993，PUT整数原样、fractional date原样；无diff/新增/编辑/删除/编辑对删除三方合并；UUID大小写去重，购入族跨版本链接形成一合并单元；409后重取/无冲突重试/真冲突停；游客重复导入不重复且原记录保留；晚响应换号/退出不写，存储写失败base/revision不变，本地未同步退出重登仍在。
- [ ] 运行 `bun test tests/holding-wire.test.ts tests/holding-merge.test.ts tests/holding-sync.test.ts` 确认失败。
- [ ] 按 Swift `HoldingCloudMerge` 合并（并查集覆盖base/local/remote所有关联，不只单记录）；base/revision/document同槽落盘，成功落盘后才发布synced。put期间本地新编辑保留dirty并接续同步；429/网络/冻结/413/422错误可见且保留本地。冲突选择绑定该版本，云再变更则重新合并。显式导入/退出/注销按完整规格实现。完整mock快照、revision、CAS与多账户隔离。
- [ ] 运行目标测试和全小程序检查；用两个隔离测试客户端制造真实409、离线编辑/重登/冲突，验证App兼容同账户全字段，并填同步证据。
- [ ] 只提交本任务变更：`feat(mini): add isolated durable holdings cloud sync`。
