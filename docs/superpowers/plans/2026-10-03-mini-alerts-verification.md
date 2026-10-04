# 小程序提醒与完整验收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留App全部持仓目标提醒，适配微信实际送达并提供完整功能对齐证据。

**Architecture:** 提醒计算与设备运行态分离，配置使用既有云文档；前台监测不变，微信送达由独立通知边界完成。只有真实发送成功才确认系统送达，未知结果不盲目重发。

**Tech Stack:** uni-app/Vue/Bun，Go六边形模块，微信订阅消息，PostgreSQL幂等送达状态。

**Spec:** `docs/superpowers/specs/2026-10-03-mini-app-parity-design.md`。

## Global Constraints

继承总计划所有约束；依赖A–C。提醒基线/armed/冷却不能写入账户云文档；前台每3秒检查，后台取消；失败保留重试状态。首页订阅仍保留App尚未开放提示。

平台依据：[uni.requestSubscribeMessage 官方文档](https://uniapp.dcloud.net.cn/api/other/requestSubscribeMessage.html)，2026-10-03已核对：H5不支持；须用户点击/支付后调起；一次最多3模板；success内还须检查模板返回accept/reject/ban。本功能复用一个真实持仓模板覆盖四目标，不一次申请四模板。微信服务端文档本次读取失败；D2实施前须重新核对[发送接口文档](https://developers.weixin.qq.com/miniprogram/dev/OpenApiDoc/mp-message-management/subscribe-message/sendMessage.html)，不得猜测模板字段或错误码。

## Review Focus

无穿越首次报价/旧报价/异常跳变（D1）；accept/reject/ban与发送未知、手机/邮箱/游客收件身份、并发请求/处置变化/切号（D2）；微信组件漏渲染与真实配置未齐（D3）。

---

### D1：提醒引擎、配置与生命周期

**Files:** Create `sumly_mini/src/domain/holdings/alerts.ts`、`src/stores/holdingAlerts.ts`、`src/pages/holdings/components/HoldingAlerts.vue`、`tests/{holding-alerts,holding-alert-lifecycle}.test.ts`；Modify `src/pages/holdings/detail.vue`、`src/App.vue`。

**Interfaces:** `AlertRuntime={previousPrice:number|null;previousAsOf:number|null;armed:boolean;lastTriggeredAt:number|null}`；`AlertEvaluation={next:AlertRuntime;triggered:boolean}`；产生 `evaluateAlert(alert:HoldingAlert,runtime:AlertRuntime,input:GoldReturnInput,price:number,asOf:number,now:number):AlertEvaluation`、`mergeAlertForm(edited,values,latest,basis):HoldingAlert[]|null`；`useHoldingAlerts()` 的 `start()/stop()/issue` 与 `acknowledge(eventID,outcome)`，运行态分workspace+recordID+alertID独立持久化。

- [x] 写测试：首次超过目标不触发；先低于 `target-max(0.01,target*0.001)` 再达到触发；24h冷却；300秒有效/未来60秒边界、重复asOf不触发、>20%跳变忽略、长断档重置基线；四目标反推共享B1；编辑失效值/禁用/换口径和成本变更按Swift重置；送达失败不消耗armed/冷却，后台/换号停止，处置记录不监测。
- [x] 运行 `bun test tests/holding-alerts.test.ts tests/holding-alert-lifecycle.test.ts` 确认失败。
- [x] 移植 `HoldingAlertEngine/Form`，实现详情四目标编辑/开关/提示；先计算候选next，送达确认后再发布触发运行态；非触发baseline可落盘。App根生命周期统一驱动，切Tab不重复创建定时器。前台反馈与系统送达分别标明，前台弹窗不伪装成微信消息成功。
- [x] 运行目标测试和类型检查/双构建；通过注入报价/时钟验证穿越与冷却，不等真实金价达到目标、不伪造生产报价。
- [x] 只提交本任务变更：`feat(mini): port holding alert rules and lifecycle`。

### D2：微信订阅与可信发送适配

**Files:** Create `sumly_go/internal/notifications/{domain/holding_alert.go,application/holding_alerts.go,ports/notifications.go,adapters/http/handler.go,adapters/wechat/client.go,adapters/postgres/repository.go}` 和各层 `_test.go`、`db/migrations/00010_holding_notifications.sql`、`db/queries/notifications.sql`；Modify `sqlc.yaml`、`internal/bootstrap/{config.go,dependencies.go,router.go}`、`.env.example`、`docs/openapi.yaml` 和测试；Create `sumly_mini/src/{api/notifications.ts,types/notifications.ts,utils/wechatSubscriptions.ts}`、`tests/wechat-subscriptions.test.ts`；Modify D1提醒store/组件与mock handlers。

**Interfaces:** Go通知端口：`QuoteReader.Read(ctx,basis) (price float64,asOf time.Time,err error)`、`HoldingReader.Read(ctx,userID int64) (document,error)`、`WechatSender.Send(ctx,recipient,template string,fields map[string]string) error`；application负责校验/重算、adapters处理真实provider字段。HTTP新增 `GET /notifications/holding/capabilities`、`POST /notifications/holding/grants`、`POST /notifications/holding/evaluate`、`GET /notifications/holding/events/{id}`，路径均在 `/api/v1/app` 下，统一envelope。capability `{available:boolean;template_id:string|null}`；grants body `{js_code:string;device_id:string;template_id:string}`，返回 `{grant:string;expires_in:number}`；evaluate body `{device_id:string;request_id:string;guest_configuration?:ValidatedGuestAlertInput[]}`，返回 `{events:{id:string;status:'delivered'|'failed'|'unknown'|'skipped'}[]}`。grant用专属请求header，不复用登录token；登录账户还须Bearer会话，后端绑定userID+deviceID与已验证微信地址，账户来自Actor。

端口具体Go签名为 `Read(ctx context.Context,basis string) (float64,time.Time,error)` 和 `Read(ctx context.Context,userID int64) (holdingsdomain.Document,error)`；`holdingsdomain` 引用已有持仓domain，不令application依赖HTTP/JSON DTO。`ValidatedGuestAlertInput={record_id:string;input:GoldReturnInput;alerts:HoldingAlert[]}`，仅含UUID/数值/固定枚举，不接受任意标题/正文/品牌；每次最多1000条、每条4提醒、body上限4MiB。device_id/request_id均规范UUID；guest grant关联设备而不建立用户，15分钟到期，只允许同appid已配置模板；账户grant另绑定会话userID，使用header `X-Holding-Notification-Grant`。status查询按相同grant/workspace校验，返回一条同结构event，未知状态不得当成失败自动重发。

前端 `requestHoldingSubscription(templateID:string):Promise<'accept'|'reject'|'ban'>`、`createNotificationGrant(code,deviceID,templateID)`、`evaluateHoldingNotifications(deviceID,requestID,guestConfiguration?)`、`getNotificationEvent(id)`；grant存专属workspace key，切号失效；不是注册/关联微信登录身份。

D2将D1监测器接入evaluate：前台每3秒提交当前设备的评估请求（含未穿越时的报价基线建立），而非仅在本地已触发时才调用，否则服务端无法确认穿越。前端候选引擎用于即时状态，系统消息以服务端事件为准；服务器按配置hash重置设备基线并使用真实行情读端口，与本地同组fixture验证。需要续订时显示明确操作按钮，仅用户点击时再次 `uni.requestSubscribeMessage/uni.login`，不得在轮询中自动弹授权。

- [x] 写测试：缺模板不可用且不请求订阅；success但reject/ban不当接受；code服务端验真，客户端不能指定openid或任意文案；不同workspace/device不能使用grant；手机/邮箱登录也可由用户明确订阅绑定消息收件地址而不改账户；游客提醒不用自动登录或导入云文档；处置/删除/改成本后重读配置不发旧目标；相同requestID只发送一次；超时unknown通过status查询恢复，不自动再次send；旧会话/冻结/注销不重建通知；失败不确认本地冷却。
- [ ] 运行 `cd sumly_go && make test` 和 `cd sumly_mini && bun test tests/wechat-subscriptions.test.ts tests/holding-alert-lifecycle.test.ts`，确认新增用例失败。
- [x] 实现独立notifications模块；模板ID及字段映射通过配置，实施前根据真实模板填映射并做结构校验，缺配置返回不可用。微信access_token获取/缓存只在adapter，错误分类按已核实官方契约，日志无grant/code/token/openid。grants是服务端验证code后生成的短期高熵令牌（只存hash），不自动改变登录状态。账户评估从已保存云文档重读；游客提交限额的临时数值配置，由独立校验和同一纯算法重算，只允许固定模板内容，不当作账户持仓持久化。设备基线/幂等事件单独存表、expire清理，与配置云文档分离；原子claim发送，unknown保留不盲重试。未同步账户变更须先同步；冲突未解决不按旧配置发送。按前台请求评估，不启动后台监控。
- [ ] 对照D1 fixture验证Go/TS引擎一致；执行Go测试/vet/build、小程序全部检查及provider HTTP fake-server测试；真实模板/授权齐备后由用户操作验证发送，拒绝/耗尽/失败显示真状态。需要的appid、模板和字段配置未提供则列为环境阻塞，不省略此项。
- [x] 只提交本任务变更：`feat(notifications): adapt holding alerts to WeChat subscriptions`。

### D3：逐项跨端验收与交付

**Files:** Create `docs/mini-app-parity-verification.md`；Modify `sumly_mini/README.md`、`sumly_mini/AGENTS.md`、根 `README.md`（仅本迁移相关说明）。修复验收发现的问题时修改对应任务文件/测试，不另建平行实现。

**Interfaces:** 验收文档每行 `{feature,AppBaseline,automatedEvidence,H5Evidence,WeChatEvidence,deviceEvidence,status,blocker}`；status仅为通过/失败/未运行，不能把“需配置”记为通过。

- [x] 将规格第3节20行模块展开为可操作用例；包括真实国内/国际行情、历史/实时全部手势、离线游客完整持仓、手机/邮箱/微信全生命周期、跨设备CAS冲突、cache清除不清持仓、目标提醒与未开放入口。使用统一fixture但真实接口验收关闭mock。
- [x] 执行 `cd sumly_mini && bun run test && bun run type-check && bun run build:h5 && bun run build:mp-weixin`，`cd sumly_go && make test && make vet && make build`；记录输出与数据库集成跳过项。仅在失败/新更改时重跑受影响检查，不重复未变全套。
- [ ] 使用H5、微信开发者工具和真机与App逐页操作/截图对照；覆盖canvas/usingComponents、暗色表单/键盘/日期、安全区与胶囊、前后台、弱网、登录与消息授权。没有开发者工具/真机通道则如实记录未运行，保留待验项。
- [ ] 运行 verification-before-completion 与 requesting-code-review 流程，检查每项证据及代码diff；修复可重现缺陷并验证，填写实际状态。更新文档；全量完成声明仅在全部验收满足时使用。
- [x] 只提交本任务变更：`docs(mini): record full App parity verification`；报告已实现内容、测试和未通过/环境阻塞，不部署或发布。
