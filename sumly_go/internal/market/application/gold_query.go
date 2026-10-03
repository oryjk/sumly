package application

import (
	"context"
	"errors"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

var errQuoteUnavailable = errors.New("no stored quote")
var errIntradayUnavailable = errors.New("no stored intraday data")

// GoldQuery has no upstream, writer, collector or shared process cache.
type GoldQuery struct {
	store  ports.GoldReadStore
	native bool
	now    func() time.Time
}

func NewGoldQuery(store ports.GoldReadStore) *GoldQuery {
	return &GoldQuery{store: store, now: time.Now}
}
func NewNativeGoldQuery(store ports.GoldReadStore) *GoldQuery {
	q := NewGoldQuery(store)
	q.native = true
	return q
}
func (q *GoldQuery) GetGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	quote, found, err := q.store.LoadQuote(ctx)
	if err != nil {
		return domain.GoldQuote{}, err
	}
	if !found {
		return domain.GoldQuote{}, errs.Wrap(errs.KindInternal, "行情暂时不可用", errQuoteUnavailable)
	}
	return quote, nil
}
func (q *GoldQuery) GetGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	return q.store.LoadDaily(ctx)
}
func (q *GoldQuery) GetGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	points, err := q.store.LoadIntraday(ctx)
	if err != nil {
		return nil, err
	}
	if len(points) == 0 {
		return nil, errs.Wrap(errs.KindInternal, "分时行情暂时不可用", errIntradayUnavailable)
	}
	return append([]domain.IntradayPoint(nil), points...), nil
}
