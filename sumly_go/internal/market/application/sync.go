package application

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

type HistorySync struct {
	reader ports.HistorySyncReader
	series map[string]domain.HistorySeries
}

func NewHistorySync(reader ports.HistorySyncReader, catalog []domain.Instrument) *HistorySync {
	series := map[string]domain.HistorySeries{"xauusd": {ID: "xauusd", Symbol: "XAUUSD", Unit: "USD/troy_oz"}}
	for _, i := range catalog {
		series[i.ID] = domain.HistorySeries{ID: i.ID, Symbol: i.Symbol, Unit: i.Unit}
	}
	return &HistorySync{reader: reader, series: series}
}
func (q *HistorySync) Sync(ctx context.Context, id, cursor string) (domain.HistorySync, error) {
	series, ok := q.series[id]
	if !ok || len(cursor) > 160 {
		return domain.HistorySync{}, domain.ErrInvalidSyncQuery
	}
	return q.reader.SyncHistory(ctx, series, cursor)
}
