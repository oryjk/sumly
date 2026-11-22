package ports

import (
	"context"
	"encoding/json"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
)

// UpsertParams 封装单次配置写入与审计记录所需的持久化参数。
type UpsertParams struct {
	Key         string
	ValueJSON   json.RawMessage
	Description *string
	Operator    string
	Note        string
}

// Repository 定义远程配置及变更审计日志的存储端口。
type Repository interface {
	GetByKey(ctx context.Context, key string) (domain.ConfigEntry, bool, error)
	ListAll(ctx context.Context) ([]domain.ConfigEntry, error)
	UpsertWithAudit(ctx context.Context, params UpsertParams) (domain.ConfigEntry, error)
	ListAuditLogs(ctx context.Context, limit int) ([]domain.AuditLog, error)
}
