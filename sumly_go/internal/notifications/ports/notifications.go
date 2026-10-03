package ports

import (
	"context"
	"time"

	holdingsdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
)

// QuoteReader 读取真实行情。实现方必须使用真实读端口，
// 不得回源采集或写库。
type QuoteReader interface {
	Read(ctx context.Context, basis string) (price float64, asOf time.Time, err error)
}

// HoldingReader 读取账户已保存的持仓文档。
// 账户评估必须从这里重读配置，而不是信任客户端提交的内容。
type HoldingReader interface {
	Read(ctx context.Context, userID int64) (holdingsdomain.Document, error)
}

// WechatSender 发送到微信订阅消息。收件人由服务端掌握，
// 客户端不能指定。ExchangeCode 用服务端验证过的 code 换取 openid。
type WechatSender interface {
	Send(ctx context.Context, recipient, template string, fields map[string]string) error
	ExchangeCode(ctx context.Context, code string) (string, error)
}

// Cryptography 提供随机与摘要，用于生成高熵令牌并只存其 hash。
type Cryptography interface {
	Random() string
	Digest(string, string) string
}

// Store 持久化授权、事件与设备基线。
type Store interface {
	PutGrant(ctx context.Context, grant Grant) error
	Grant(ctx context.Context, hash string, now time.Time) (Grant, error)
	Event(ctx context.Context, deviceID, workspace, requestID, alertID string) (domain.Event, bool, error)
	EventByID(ctx context.Context, deviceID, workspace, eventID string) (domain.Event, bool, error)
	PutEvent(ctx context.Context, event domain.Event, deviceID, workspace, requestID, alertID string) error
	Baselines(ctx context.Context, deviceID, workspace string) (map[string]Baseline, error)
	PutBaseline(ctx context.Context, deviceID, workspace, configHash string, baseline Baseline) error
	Purge(ctx context.Context, now time.Time) error
}

// Grant 是服务端签发的短期高熵令牌，只在数据库存 hash。
type Grant struct {
	Hash      string
	DeviceID  string
	Workspace string
	// UserID 为 0 表示游客授权（只关联设备，不建立账户）。
	UserID     int64
	TemplateID string
	OpenID     string
	ExpiresAt  time.Time
}

// Baseline 是设备侧的运行态，不随账户配置同步。
type Baseline struct {
	PreviousPrice   float64
	PreviousAsOf    time.Time
	Armed           bool
	LastTriggeredAt *time.Time
}
