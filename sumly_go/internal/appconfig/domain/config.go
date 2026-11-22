package domain

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"
	"unicode/utf8"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const (
	KeyMembershipPaywall = "membership_paywall"

	MaxFreeAccessNoticeRunes = 120
	MaxConfigValueBytes      = 16 * 1024
	MaxConfigKeyLength       = 64
	MaxDescriptionRunes      = 256
	MaxOperatorRunes         = 64
	MaxNoteRunes             = 256
)

// MembershipPaywallConfig 控制禅观会员门禁、会员入口显隐与限时免费公告。
type MembershipPaywallConfig struct {
	ChanlunRequiresMembership bool   `json:"chanlun_requires_membership"`
	MembershipEntryVisible    bool   `json:"membership_entry_visible"`
	FreeAccessNotice          string `json:"free_access_notice"`
}

// DefaultMembershipPaywallConfig 返回安全默认配置：即使库中缺行也默认收费，避免空行绕过付费。
func DefaultMembershipPaywallConfig() MembershipPaywallConfig {
	return MembershipPaywallConfig{
		ChanlunRequiresMembership: true,
		MembershipEntryVisible:    true,
		FreeAccessNotice:          "",
	}
}

// PublicAppConfig 是面向客户端的公开只读远程配置视图。
type PublicAppConfig struct {
	MembershipPaywall MembershipPaywallConfig
	UpdatedAt         time.Time
}

// ConfigEntry 对应 app_configs 表中的一条远程配置记录。
type ConfigEntry struct {
	Key         string
	ValueJSON   json.RawMessage
	Description string
	UpdatedBy   string
	UpdatedAt   time.Time
}

// AuditLog 对应 app_config_audit_logs 表中的一条变更审计日志。
type AuditLog struct {
	ID           int64
	ConfigKey    string
	OldValueJSON json.RawMessage
	NewValueJSON json.RawMessage
	Operator     string
	Note         string
	CreatedAt    time.Time
}

// ValidateKey 校验配置 key：仅允许小写字母/数字开头，包含小写字母、数字、点、下划线与连字符。
func ValidateKey(raw string) (string, error) {
	key := strings.TrimSpace(raw)
	if key == "" {
		return "", sharederror.New(sharederror.KindValidation, "config key is required")
	}
	if len(key) > MaxConfigKeyLength {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("config key must not exceed %d characters", MaxConfigKeyLength))
	}
	if key == "audit-logs" {
		return "", sharederror.New(sharederror.KindValidation, "config key 'audit-logs' is reserved")
	}
	for i := 0; i < len(key); i++ {
		ch := key[i]
		isLower := ch >= 'a' && ch <= 'z'
		isDigit := ch >= '0' && ch <= '9'
		if i == 0 {
			if !isLower && !isDigit {
				return "", sharederror.New(sharederror.KindValidation, "config key must start with a lowercase letter or digit")
			}
			continue
		}
		if !isLower && !isDigit && ch != '_' && ch != '-' && ch != '.' {
			return "", sharederror.New(sharederror.KindValidation, "config key contains invalid characters")
		}
	}
	return key, nil
}

type rawMembershipPaywallPayload struct {
	ChanlunRequiresMembership *bool   `json:"chanlun_requires_membership"`
	MembershipEntryVisible    *bool   `json:"membership_entry_visible"`
	FreeAccessNotice          *string `json:"free_access_notice"`
}

// ValidateMembershipPaywall 对 membership_paywall 执行强类型严格校验并返回规范化 JSON。
func ValidateMembershipPaywall(raw json.RawMessage) (MembershipPaywallConfig, json.RawMessage, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 {
		return MembershipPaywallConfig{}, nil, sharederror.New(sharederror.KindValidation, "membership_paywall value is required")
	}
	if len(trimmed) > MaxConfigValueBytes {
		return MembershipPaywallConfig{}, nil, sharederror.New(sharederror.KindValidation, "config value exceeds 16KB limit")
	}
	if trimmed[0] != '{' {
		return MembershipPaywallConfig{}, nil, sharederror.New(sharederror.KindValidation, "membership_paywall value must be a JSON object")
	}

	decoder := json.NewDecoder(bytes.NewReader(trimmed))
	decoder.DisallowUnknownFields()

	var payload rawMembershipPaywallPayload
	if err := decoder.Decode(&payload); err != nil {
		return MembershipPaywallConfig{}, nil, sharederror.Wrap(sharederror.KindValidation, "invalid membership_paywall payload: "+err.Error(), err)
	}
	if err := ensureNoTrailingJSON(decoder); err != nil {
		return MembershipPaywallConfig{}, nil, err
	}
	if payload.ChanlunRequiresMembership == nil {
		return MembershipPaywallConfig{}, nil, sharederror.New(sharederror.KindValidation, "chanlun_requires_membership is required and must be a boolean")
	}
	if payload.MembershipEntryVisible == nil {
		return MembershipPaywallConfig{}, nil, sharederror.New(sharederror.KindValidation, "membership_entry_visible is required and must be a boolean")
	}

	notice := ""
	if payload.FreeAccessNotice != nil {
		notice = strings.TrimSpace(*payload.FreeAccessNotice)
		if utf8.RuneCountInString(notice) > MaxFreeAccessNoticeRunes {
			return MembershipPaywallConfig{}, nil, sharederror.New(sharederror.KindValidation, fmt.Sprintf("free_access_notice must not exceed %d characters", MaxFreeAccessNoticeRunes))
		}
	}

	cfg := MembershipPaywallConfig{
		ChanlunRequiresMembership: *payload.ChanlunRequiresMembership,
		MembershipEntryVisible:    *payload.MembershipEntryVisible,
		FreeAccessNotice:          notice,
	}
	normalized, err := json.Marshal(cfg)
	if err != nil {
		return MembershipPaywallConfig{}, nil, sharederror.Wrap(sharederror.KindInternal, "marshal membership_paywall", err)
	}
	return cfg, json.RawMessage(normalized), nil
}

// DecodeMembershipPaywallOrDefault 安全解析存储的 membership_paywall JSON；
// 缺失字段或损坏时回退安全默认值，绝不意外关闭付费门禁。
func DecodeMembershipPaywallOrDefault(raw json.RawMessage) MembershipPaywallConfig {
	cfg := DefaultMembershipPaywallConfig()
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 {
		return cfg
	}
	if err := json.Unmarshal(trimmed, &cfg); err != nil {
		return DefaultMembershipPaywallConfig()
	}
	cfg.FreeAccessNotice = strings.TrimSpace(cfg.FreeAccessNotice)
	return cfg
}

// ValidateConfigValue 根据 key 对配置值执行校验：
// - membership_paywall：强类型严格校验
// - 其他扩展 key：允许合法 JSON 对象且不超过 16KB
func ValidateConfigValue(key string, raw json.RawMessage) (json.RawMessage, error) {
	if key == KeyMembershipPaywall {
		_, normalized, err := ValidateMembershipPaywall(raw)
		return normalized, err
	}

	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 {
		return nil, sharederror.New(sharederror.KindValidation, "config value is required")
	}
	if len(trimmed) > MaxConfigValueBytes {
		return nil, sharederror.New(sharederror.KindValidation, "config value exceeds 16KB limit")
	}
	if trimmed[0] != '{' {
		return nil, sharederror.New(sharederror.KindValidation, "config value must be a JSON object")
	}

	decoder := json.NewDecoder(bytes.NewReader(trimmed))
	var obj map[string]any
	if err := decoder.Decode(&obj); err != nil {
		return nil, sharederror.Wrap(sharederror.KindValidation, "invalid JSON object: "+err.Error(), err)
	}
	if obj == nil {
		return nil, sharederror.New(sharederror.KindValidation, "config value must be a JSON object")
	}
	if err := ensureNoTrailingJSON(decoder); err != nil {
		return nil, err
	}

	var compacted bytes.Buffer
	if err := json.Compact(&compacted, trimmed); err != nil {
		return nil, sharederror.Wrap(sharederror.KindValidation, "invalid JSON object", err)
	}
	if compacted.Len() > MaxConfigValueBytes {
		return nil, sharederror.New(sharederror.KindValidation, "config value exceeds 16KB limit")
	}
	return json.RawMessage(compacted.Bytes()), nil
}

// ValidateMetadata 清洗并校验配置更新的描述、操作人与备注。
func ValidateMetadata(description *string, operator, note string) (*string, string, string, error) {
	var normalizedDesc *string
	if description != nil {
		trimmed := strings.TrimSpace(*description)
		if utf8.RuneCountInString(trimmed) > MaxDescriptionRunes {
			return nil, "", "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("description must not exceed %d characters", MaxDescriptionRunes))
		}
		normalizedDesc = &trimmed
	}
	trimmedOperator := strings.TrimSpace(operator)
	if utf8.RuneCountInString(trimmedOperator) > MaxOperatorRunes {
		return nil, "", "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("operator must not exceed %d characters", MaxOperatorRunes))
	}
	trimmedNote := strings.TrimSpace(note)
	if utf8.RuneCountInString(trimmedNote) > MaxNoteRunes {
		return nil, "", "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("note must not exceed %d characters", MaxNoteRunes))
	}
	return normalizedDesc, trimmedOperator, trimmedNote, nil
}

func ensureNoTrailingJSON(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return sharederror.New(sharederror.KindValidation, "config value contains trailing data")
	}
	return nil
}
