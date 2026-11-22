package application

import (
	"context"
	"encoding/json"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
)

const (
	DefaultAuditLogLimit = 30
	MaxAuditLogLimit     = 100
)

// UpdateConfigCommand 封装管理后台更新单个配置项的请求。
type UpdateConfigCommand struct {
	Key         string
	ValueJSON   json.RawMessage
	Description *string
	Operator    string
	Note        string
}

// Service 提供远程应用配置的公开只读查询与管理后台读写用例。
type Service struct {
	repo ports.Repository
	now  func() time.Time
}

func NewService(repo ports.Repository) *Service {
	return &Service{
		repo: repo,
		now:  time.Now,
	}
}

func (s *Service) GetPublicConfig(ctx context.Context) (domain.PublicAppConfig, error) {
	entry, found, err := s.repo.GetByKey(ctx, domain.KeyMembershipPaywall)
	if err != nil {
		return domain.PublicAppConfig{}, err
	}
	if !found {
		return domain.PublicAppConfig{
			MembershipPaywall: domain.DefaultMembershipPaywallConfig(),
			UpdatedAt:         s.now().UTC(),
		}, nil
	}
	updatedAt := entry.UpdatedAt.UTC()
	if updatedAt.IsZero() {
		updatedAt = s.now().UTC()
	}
	return domain.PublicAppConfig{
		MembershipPaywall: domain.DecodeMembershipPaywallOrDefault(entry.ValueJSON),
		UpdatedAt:         updatedAt,
	}, nil
}

func (s *Service) ListConfigs(ctx context.Context) ([]domain.ConfigEntry, error) {
	items, err := s.repo.ListAll(ctx)
	if err != nil {
		return nil, err
	}
	if items == nil {
		return []domain.ConfigEntry{}, nil
	}
	return items, nil
}

func (s *Service) UpdateConfig(ctx context.Context, cmd UpdateConfigCommand) (domain.ConfigEntry, error) {
	key, err := domain.ValidateKey(cmd.Key)
	if err != nil {
		return domain.ConfigEntry{}, err
	}
	normalizedValue, err := domain.ValidateConfigValue(key, cmd.ValueJSON)
	if err != nil {
		return domain.ConfigEntry{}, err
	}
	desc, operator, note, err := domain.ValidateMetadata(cmd.Description, cmd.Operator, cmd.Note)
	if err != nil {
		return domain.ConfigEntry{}, err
	}
	return s.repo.UpsertWithAudit(ctx, ports.UpsertParams{
		Key:         key,
		ValueJSON:   normalizedValue,
		Description: desc,
		Operator:    operator,
		Note:        note,
	})
}

func (s *Service) ListAuditLogs(ctx context.Context, limit int) ([]domain.AuditLog, error) {
	if limit <= 0 {
		limit = DefaultAuditLogLimit
	} else if limit > MaxAuditLogLimit {
		limit = MaxAuditLogLimit
	}
	logs, err := s.repo.ListAuditLogs(ctx, limit)
	if err != nil {
		return nil, err
	}
	if logs == nil {
		return []domain.AuditLog{}, nil
	}
	return logs, nil
}
