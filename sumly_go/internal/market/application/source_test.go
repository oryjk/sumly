package application

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

type fakeSource struct {
	quotes []domain.GoldQuote
	daily  []domain.DailyBar
	err    error

	quoteCalls int
	dailyCalls int
}

func (f *fakeSource) FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	f.quoteCalls++
	if f.err != nil {
		return domain.GoldQuote{}, f.err
	}
	if f.quoteCalls <= len(f.quotes) {
		return f.quotes[f.quoteCalls-1], nil
	}
	return f.quotes[len(f.quotes)-1], nil
}

func (f *fakeSource) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	f.dailyCalls++
	if f.err != nil {
		return nil, f.err
	}
	return f.daily, nil
}
