package application

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/ports"
)

// 配置模板字段映射。真实模板 ID 与字段名必须由部署方提供，
// 缺失时能力检测返回不可用，而不是用假模板糊弄过去。
type TemplateConfig struct {
	TemplateID string
	// Fields 把内部字段映射到模板的 thing 字段名。
	Fields map[string]string
}

// HoldingAlerts 是持仓提醒的应用层：校验、重算与发送编排。
type HoldingAlerts struct {
	Store    ports.Store
	Quotes   ports.QuoteReader
	Holdings ports.HoldingReader
	Wechat   ports.WechatSender
	Crypto   ports.Cryptography
	Template TemplateConfig
	Now      func() time.Time
	// GrantTTL 为授权有效期，固定 15 分钟。
	GrantTTL time.Duration
}

// Capability 报告是否具备真实发送能力。
func (h HoldingAlerts) Capability() domain.Capability {
	if h.Template.TemplateID == "" || h.Wechat == nil || len(h.Template.Fields) == 0 {
		return domain.Capability{Available: false}
	}
	return domain.Capability{Available: true, TemplateID: h.Template.TemplateID}
}

func (h HoldingAlerts) now() time.Time {
	if h.Now != nil {
		return h.Now()
	}
	return time.Now()
}

func (h HoldingAlerts) grantTTL() time.Duration {
	if h.GrantTTL > 0 {
		return h.GrantTTL
	}
	return 15 * time.Minute
}

// GrantResult 是签发授权的结果。
type GrantResult struct {
	Grant     string `json:"grant"`
	ExpiresIn int    `json:"expires_in"`
}

// Grants 用服务端验证过的 code 换取 openid，签发短期高熵令牌。
// 令牌只关联设备（游客）或绑定会话账户，不会自动改变登录状态。
func (h HoldingAlerts) Grants(ctx context.Context, code, deviceID, templateID string, userID int64, workspace string) (GrantResult, error) {
	if h.Capability().Available == false {
		return GrantResult{}, domain.ErrUnavailable
	}
	normalized, ok := domain.NormalizeDeviceID(deviceID)
	if !ok {
		return GrantResult{}, domain.ErrInvalidDeviceID
	}
	if strings.TrimSpace(code) == "" {
		return GrantResult{}, domain.ErrInvalid
	}
	// 只允许已配置的模板；不接受客户端任意指定模板。
	if strings.TrimSpace(templateID) != h.Template.TemplateID {
		return GrantResult{}, domain.ErrInvalid
	}

	openID, err := h.Wechat.ExchangeCode(ctx, code)
	if err != nil {
		return GrantResult{}, err
	}
	if strings.TrimSpace(openID) == "" {
		return GrantResult{}, domain.ErrCredentials
	}

	token := h.Crypto.Random()
	expires := h.now().Add(h.grantTTL())
	err = h.Store.PutGrant(ctx, ports.Grant{
		Hash:       digest(token),
		DeviceID:   normalized,
		Workspace:  workspace,
		UserID:     userID,
		TemplateID: h.Template.TemplateID,
		OpenID:     openID,
		ExpiresAt:  expires,
	})
	if err != nil {
		return GrantResult{}, err
	}
	return GrantResult{Grant: token, ExpiresIn: int(h.grantTTL().Seconds())}, nil
}

// EvaluateInput 是一次评估请求。
type EvaluateInput struct {
	DeviceID  string
	RequestID string
	Grant     string
	Workspace string
	Guest     domain.GuestConfiguration
}

// EvaluateResult 是评估结果。
type EvaluateResult struct {
	Events []domain.Event `json:"events"`
}

// Evaluate 重算已保存的配置并在穿越时发送。
//
// 关键约束：
// - 每次都重新读取配置与真实报价，不用客户端提交的阈值直接判断；
// - 相同 requestID 只发送一次（幂等）；
// - 成功前不消耗基线与冷却，失败保留可重试状态；
// - unknown 状态不得自动重发，按 ID 查询恢复。
func (h HoldingAlerts) Evaluate(ctx context.Context, in EvaluateInput) (EvaluateResult, error) {
	if h.Capability().Available == false {
		return EvaluateResult{}, domain.ErrUnavailable
	}
	deviceID, ok := domain.NormalizeDeviceID(in.DeviceID)
	if !ok {
		return EvaluateResult{}, domain.ErrInvalidDeviceID
	}
	requestID, ok := domain.NormalizeRequestID(in.RequestID)
	if !ok {
		return EvaluateResult{}, domain.ErrInvalidRequest
	}
	grant, err := h.Store.Grant(ctx, digest(in.Grant), h.now())
	if err != nil {
		return EvaluateResult{}, err
	}
	// 授权必须属于同一设备与工作区
	if grant.DeviceID != deviceID || grant.Workspace != in.Workspace {
		return EvaluateResult{}, domain.ErrGrantNotFound
	}

	// 游客用本次提交的受限配置；账户一律从云文档重读，不接受客户端内容
	configs := in.Guest
	if grant.UserID != 0 {
		configs, err = h.configurations(ctx, grant)
		if err != nil {
			return EvaluateResult{}, err
		}
	}
	if len(configs) == 0 {
		return EvaluateResult{Events: []domain.Event{}}, nil
	}

	price, asOf, err := h.Quotes.Read(ctx, grant.TemplateID)
	if err != nil {
		return EvaluateResult{}, err
	}
	// 报价必须新鲜，与 App 的 300 秒窗口一致
	if h.now().Sub(asOf) > 300*time.Second || h.now().Sub(asOf) < -60*time.Second {
		return EvaluateResult{}, domain.ErrUnavailable
	}

	baselines, err := h.Store.Baselines(ctx, deviceID, in.Workspace)
	if err != nil {
		return EvaluateResult{}, err
	}

	events := make([]domain.Event, 0, len(configs))
	for _, config := range configs {
		input := config.Input
		hash := configHash(config)
		baseline := baselines[hash]

		for _, alert := range config.Alerts {
			// 幂等：同一 requestID + alert 只处理一次
			if existing, found, _ := h.Store.Event(ctx, deviceID, in.Workspace, requestID, alert.ID); found {
				events = append(events, existing)
				continue
			}
			triggered, next := EvaluateOne(alert, input, baseline, price, asOf, h.now())
			if !triggered {
				// 未穿越也要更新基线，供下次判断
				baselines[hash] = next
				continue
			}
			status := h.deliver(ctx, grant, config, alert, price)
			// 只有成功才消耗基线与冷却；失败保留可重试状态
			if status == domain.EventDelivered {
				baselines[hash] = next
			}
			event := domain.Event{
				ID:        newEventID(h.Crypto.Random()),
				Status:    status,
				CreatedAt: h.now(),
				ExpiresAt: h.now().Add(7 * 24 * time.Hour),
			}
			if err := h.Store.PutEvent(ctx, event, deviceID, in.Workspace, requestID, alert.ID); err != nil {
				return EvaluateResult{}, err
			}
			events = append(events, event)
		}
	}

	for hash, baseline := range baselines {
		if err := h.Store.PutBaseline(ctx, deviceID, in.Workspace, hash, baseline); err != nil {
			return EvaluateResult{}, err
		}
	}
	return EvaluateResult{Events: events}, nil
}

// deliver 尝试发送；结果未知时记 unknown，不盲目重发。
func (h HoldingAlerts) deliver(ctx context.Context, grant ports.Grant, config domain.ValidatedRecord, alert domain.Alert, price float64) domain.EventStatus {
	fields := map[string]string{
		"kind":      string(alert.Kind),
		"threshold": formatFloat(alert.Threshold),
		"price":     formatFloat(price),
		"record":    config.RecordID,
	}
	for key, name := range h.Template.Fields {
		fields[key] = name
	}
	if err := h.Wechat.Send(ctx, grant.OpenID, grant.TemplateID, fields); err != nil {
		if err == context.DeadlineExceeded || err == context.Canceled {
			return domain.EventUnknown
		}
		return domain.EventFailed
	}
	return domain.EventDelivered
}

// Event 按 ID 查询单次事件。未知结果不得当成失败自动重发。
// Event 按 ID 查询单次事件。未知结果不得当成失败自动重发。
func (h HoldingAlerts) Event(ctx context.Context, grantToken, deviceID, workspace, eventID string) (domain.Event, error) {
	normalized, ok := domain.NormalizeDeviceID(deviceID)
	if !ok {
		return domain.Event{}, domain.ErrInvalidDeviceID
	}
	g, err := h.Store.Grant(ctx, digest(grantToken), h.now())
	if err != nil {
		return domain.Event{}, err
	}
	// 授权必须属于同一设备与工作区
	if g.DeviceID != normalized || g.Workspace != workspace {
		return domain.Event{}, domain.ErrGrantNotFound
	}
	event, found, err := h.Store.EventByID(ctx, normalized, workspace, eventID)
	if err != nil {
		return domain.Event{}, err
	}
	if !found {
		return domain.Event{}, domain.ErrGrantNotFound
	}
	return event, nil
}

// configurations 返回要评估的配置：账户从云文档重读，游客用受限提交。
func (h HoldingAlerts) configurations(ctx context.Context, grant ports.Grant) (domain.GuestConfiguration, error) {
	if grant.UserID == 0 {
		return nil, nil
	}
	doc, err := h.Holdings.Read(ctx, grant.UserID)
	if err != nil {
		return nil, err
	}
	return fromHoldingsDocument(doc), nil
}

func digest(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func newEventID(seed string) string {
	raw := strings.ReplaceAll(seed, "-", "")
	if len(raw) < 32 {
		raw += strings.Repeat("0", 32-len(raw))
	}
	raw = raw[:32]
	return strings.Join([]string{raw[0:8], raw[8:12], raw[12:16], raw[16:20], raw[20:32]}, "-")
}

func configHash(config domain.ValidatedRecord) string {
	var b strings.Builder
	b.WriteString(config.RecordID)
	b.WriteByte('|')
	for _, a := range config.Alerts {
		b.WriteString(a.ID)
		b.WriteByte(':')
		b.WriteString(string(a.Kind))
		b.WriteByte(':')
		b.WriteString(formatFloat(a.Threshold))
		b.WriteByte(';')
	}
	return digest(b.String())
}
