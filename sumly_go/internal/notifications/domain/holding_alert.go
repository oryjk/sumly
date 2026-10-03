package domain

import (
	"errors"
	"regexp"
	"time"
)

var (
	ErrInvalidDeviceID = errors.New("invalid device id")
	ErrCredentials     = errors.New("invalid credentials")
	ErrInvalidRequest  = errors.New("invalid request id")
	ErrGrantNotFound   = errors.New("grant not found or expired")
	ErrUnavailable     = errors.New("notification provider unavailable")
	ErrPayloadTooLarge = errors.New("payload too large")
)

// 最多允许的游客提醒条数与 body 上限，与计划一致。
const MaxGuestAlerts = 1000
const MaxBytes = 4 * 1024 * 1024

var (
	uuidPattern = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
)

// UUID 规范化；非法返回 false。
func NormalizeDeviceID(value string) (string, bool) {
	v := trim(value)
	if !uuidPattern.MatchString(v) {
		return "", false
	}
	return lower(v), true
}

// request_id 允许更宽松的标识，但长度受限。
func NormalizeRequestID(value string) (string, bool) {
	v := trim(value)
	if v == "" || len(v) > 160 {
		return "", false
	}
	for _, c := range v {
		if c < 0x21 || c > 0x7e {
			return "", false
		}
	}
	return v, true
}

// Capability 报告服务端是否具备真实发送能力。
// 没有配置模板时 available 为 false，前端据此不请求订阅授权。
type Capability struct {
	Available  bool   `json:"available"`
	TemplateID string `json:"template_id"`
}

// EventStatus 是单次发送的结果。unknown 表示结果未知，
// 必须按ID 查询恢复，不能自动重发。
type EventStatus string

const (
	EventDelivered EventStatus = "delivered"
	EventFailed    EventStatus = "failed"
	EventUnknown   EventStatus = "unknown"
	EventSkipped   EventStatus = "skipped"
)

// Event 是一次送达尝试。
type Event struct {
	ID        string      `json:"id"`
	Status    EventStatus `json:"status"`
	CreatedAt time.Time   `json:"-"`
	ExpiresAt time.Time   `json:"-"`
}

// AlertKind 与持仓提醒目标一一对应。
type AlertKind string

const (
	AlertBreakEven    AlertKind = "breakEven"
	AlertProfitAmount AlertKind = "profitAmount"
	AlertPrice        AlertKind = "price"
	AlertReturnPct    AlertKind = "returnPercent"
)

// Alert 是参与评估的提醒配置。
type Alert struct {
	ID        string    `json:"id"`
	Kind      AlertKind `json:"kind"`
	Threshold float64   `json:"threshold"`
}

// GoldInput 是评估所需的收益输入，与持仓 domain 字段一致。
type GoldInput struct {
	Grams             float64  `json:"grams"`
	Purity            float64  `json:"purity"`
	UnitPrice         float64  `json:"unit_price"`
	LaborFee          float64  `json:"labor_fee"`
	OtherCost         float64  `json:"other_cost"`
	TotalCostOverride *float64 `json:"total_cost_override"`
	PerGramDeduction  float64  `json:"per_gram_deduction"`
	DiscountRate      float64  `json:"discount_rate"`
	FixedFee          float64  `json:"fixed_fee"`
}

// Valid 校验输入；非法数值不得参与计算。
func (g GoldInput) Valid() bool {
	purity := g.Purity
	if purity == 0 {
		purity = 1
	}
	grams := g.Grams
	return finite(grams) && grams > 0 &&
		finite(purity) && purity > 0 && purity <= 1 &&
		finite(g.UnitPrice) && g.UnitPrice >= 0 &&
		finite(g.LaborFee) && g.LaborFee >= 0 &&
		finite(g.OtherCost) && g.OtherCost >= 0 &&
		finite(g.PerGramDeduction) && g.PerGramDeduction >= 0 &&
		finite(g.DiscountRate) && g.DiscountRate >= 0 && g.DiscountRate < 1 &&
		finite(g.FixedFee) && g.FixedFee >= 0
}

// ValidatedRecord 是游客提交的一条待评估配置。
// 只接受 UUID、数值与固定枚举——不接受任意标题、正文或品牌，
// 避免把订阅消息变成任意文本发送通道。
type ValidatedRecord struct {
	RecordID string    `json:"record_id"`
	Input    GoldInput `json:"input"`
	Alerts   []Alert   `json:"alerts"`
}

// Validated 校验整条配置。
func (v ValidatedRecord) Valid() bool {
	if !uuidPattern.MatchString(trim(v.RecordID)) {
		return false
	}
	if !v.Input.Valid() {
		return false
	}
	if len(v.Alerts) == 0 || len(v.Alerts) > 4 {
		return false
	}
	seen := map[string]bool{}
	for _, a := range v.Alerts {
		if !uuidPattern.MatchString(trim(a.ID)) || seen[lower(trim(a.ID))] {
			return false
		}
		seen[lower(trim(a.ID))] = true
		switch a.Kind {
		case AlertBreakEven, AlertProfitAmount, AlertPrice, AlertReturnPct:
		default:
			return false
		}
		if !finite(a.Threshold) || a.Threshold < 0 {
			return false
		}
		if a.Kind == AlertPrice && a.Threshold <= 0 {
			return false
		}
	}
	return true
}

// GuestConfiguration 是游客提交的限额配置集合。
type GuestConfiguration []ValidatedRecord

// Validate 校验整批配置。
func (g GuestConfiguration) Validate() error {
	if len(g) > MaxGuestAlerts {
		return ErrPayloadTooLarge
	}
	seen := map[string]bool{}
	for _, record := range g {
		if !record.Valid() {
			return ErrInvalid
		}
		key := lower(trim(record.RecordID))
		if seen[key] {
			return ErrInvalid
		}
		seen[key] = true
	}
	return nil
}

var ErrInvalid = errors.New("invalid configuration")
