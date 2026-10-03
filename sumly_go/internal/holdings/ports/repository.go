package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
)

// Repository serializes each write against account deletion/status changes and
// applies expectedRevision atomically. Missing active accounts return unauthorized.
type Repository interface {
	Get(context.Context, int64) (domain.Snapshot, error)
	Put(context.Context, int64, int64, domain.Document) (domain.Snapshot, error)
}
