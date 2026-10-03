package ports

import (
	"context"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

type HistorySyncReader interface {
	SyncHistory(context.Context, domain.HistorySeries, string) (domain.HistorySync, error)
}
type AnnualHistoryStore interface {
	LoadAnnual(context.Context) ([]domain.GoldHistoryPoint, error)
}
type DailySyncSchedule interface {
	TryDailySync(context.Context, time.Time) (bool, error)
	FinishDailySync(context.Context, time.Time, bool) error
}
