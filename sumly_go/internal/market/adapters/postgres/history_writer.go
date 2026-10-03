package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func dateOnly(t time.Time) pgtype.Date {
	y, m, d := t.Date()
	return pgtype.Date{Time: time.Date(y, m, d, 0, 0, 0, 0, time.UTC), Valid: true}
}
func (r *Writer) SeedAnnual(ctx context.Context, points []domain.GoldHistoryPoint) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	q := r.queries.WithTx(tx)
	if _, err = q.ClaimHistorySeed(ctx, "usgs-ds140-1900-2015-v1"); errors.Is(err, pgx.ErrNoRows) {
		return nil
	} else if err != nil {
		return err
	}
	if len(points) != 116 {
		return fmt.Errorf("annual seed must contain 116 years")
	}
	params := marketsqlc.SeedAnnualHistoryParams{}
	for _, p := range points {
		params.Dates = append(params.Dates, dateOnly(p.Date))
		params.Prices = append(params.Prices, p.Price)
	}
	if err = q.SeedAnnualHistory(ctx, params); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func (r *Writer) TryDailySync(ctx context.Context, now time.Time) (bool, error) {
	_, err := r.queries.TryDailySync(ctx, marketsqlc.TryDailySyncParams{Symbol: r.symbol, NowAt: timestamp(now), Day: dateOnly(now.UTC().Add(-8 * time.Hour))})
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}
func (r *Writer) FinishDailySync(ctx context.Context, now time.Time, success bool) error {
	return r.queries.FinishDailySync(ctx, marketsqlc.FinishDailySyncParams{Symbol: r.symbol, Day: dateOnly(now.UTC().Add(-8 * time.Hour)), Success: success})
}
