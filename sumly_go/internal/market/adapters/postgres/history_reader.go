package postgres

import (
	"context"
	"strconv"
	"strings"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/jackc/pgx/v5"
)

func (r *Reader) LoadAnnual(ctx context.Context) ([]domain.GoldHistoryPoint, error) {
	rows, err := r.queries.LoadAnnualHistory(ctx)
	if err != nil {
		return nil, err
	}
	points := make([]domain.GoldHistoryPoint, 0, len(rows))
	for _, row := range rows {
		points = append(points, domain.GoldHistoryPoint{Date: row.TradingDate.Time, Price: row.Close, Granularity: "annual", Source: row.Source})
	}
	return points, nil
}
func (r *Reader) SyncHistory(ctx context.Context, series domain.HistorySeries, cursor string) (domain.HistorySync, error) {
	result := domain.HistorySync{Series: series.ID, Unit: series.Unit, Points: []domain.HistoryChange{}}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return result, err
	}
	defer tx.Rollback(ctx)
	q := r.queries.WithTx(tx)
	clock, err := q.HistoryClock(ctx)
	if err != nil {
		return result, err
	}
	prefix := clock.Epoch + ":" + series.ID + ":"
	revision, parseErr := strconv.ParseInt(strings.TrimPrefix(cursor, prefix), 10, 64)
	result.Reset = !strings.HasPrefix(cursor, prefix) || parseErr != nil || revision < 0 || revision > clock.Revision
	if result.Reset {
		revision = 0
	}
	rows, err := q.HistoryDelta(ctx, marketsqlc.HistoryDeltaParams{Symbol: series.Symbol, Revision: revision})
	if err != nil {
		return result, err
	}
	for _, row := range rows {
		if result.Reset && row.Deleted {
			continue
		}
		result.Points = append(result.Points, domain.HistoryChange{Date: row.TradingDate.Time.Format("2006-01-02"), Granularity: row.Granularity, Open: row.Open, High: row.High, Low: row.Low, Close: row.Close, Source: row.Source, Deleted: row.Deleted})
	}
	result.Cursor = prefix + strconv.FormatInt(clock.Revision, 10)
	return result, tx.Commit(ctx)
}
