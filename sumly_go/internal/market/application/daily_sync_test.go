package application

import (
	"context"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

func TestSyncDailyExcludesLiveAndInvalidBarsWithoutReadingOldData(t *testing.T) {
	now := time.Date(2026, 9, 29, 9, 0, 0, 0, time.UTC)
	old := domain.DailyBar{Date: now.AddDate(0, 0, -2), Open: 1000, High: 1100, Low: 900, Close: 1050}
	latest := old
	latest.Date = now.AddDate(0, 0, -1)
	today := old
	today.Date = now
	invalid := old
	invalid.Date = now.AddDate(0, 0, -3)
	invalid.Close = 0
	source := &fakeSource{daily: []domain.DailyBar{old, latest, today, invalid}}
	store := &writeOnlyMarket{}
	s := NewGoldCollector(source, store)
	s.now = func() time.Time { return now }
	if err := s.SyncDaily(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(store.bars) != 2 || store.bars[1].Close != 1050 {
		t.Fatal("bad incremental write", store.bars)
	}
	if err := s.SyncDaily(context.Background()); err != nil {
		t.Fatal(err)
	}
	if source.dailyCalls != 2 {
		t.Fatal("collector did not fetch independently", source.dailyCalls)
	}
}

func TestSyncDailyPreservesSourceCloseDespiteInconsistentHistoricalBounds(t *testing.T) {
	bar := domain.DailyBar{Date: time.Date(2012, 12, 25, 0, 0, 0, 0, time.UTC), Open: 1660.69, High: 1657.01, Low: 1656.51, Close: 1658.79}
	store := &writeOnlyMarket{}
	s := NewGoldCollector(&fakeSource{daily: []domain.DailyBar{bar}}, store)
	if err := s.SyncDaily(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(store.bars) != 1 || store.bars[0].Close != bar.Close {
		t.Fatal("discarded usable close because source OHLC disagreed")
	}
}
