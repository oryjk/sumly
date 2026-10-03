package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

// GoldReadStore exposes only durable queries. HTTP reads never ingest data.
type GoldReadStore interface {
	LoadQuote(context.Context) (domain.GoldQuote, bool, error)
	LoadIntraday(context.Context) ([]domain.IntradayPoint, error)
	LoadRealtime(context.Context) ([]domain.RealtimePoint, error)
	LoadDaily(context.Context) ([]domain.DailyBar, error)
}

// GoldWriteStore exposes only ingestion. Upserts handle idempotency atomically.
type GoldWriteStore interface {
	SaveQuote(context.Context, domain.GoldQuote) error
	SaveIntraday(context.Context, []domain.IntradayPoint) error
	SaveRealtime(context.Context, domain.RealtimePoint) error
	PruneRealtime(context.Context) error
	SaveDaily(context.Context, []domain.DailyBar) error
}
