package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

type intradaySource struct {
	fakeSource
	calls  int
	points []domain.IntradayPoint
}

func (f *intradaySource) FetchGoldIntraday(context.Context) ([]domain.IntradayPoint, error) {
	f.calls++
	return f.points, f.err
}
func TestIntradayQueriesReturnCopiesAndKeepStoredTimestamp(t *testing.T) {
	now := time.Now()
	store := &readOnlyMarket{minutes: []domain.IntradayPoint{{Time: now, Price: 4300}}}
	q := NewGoldQuery(store)
	first, e := q.GetGoldIntraday(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	first[0].Price = 1
	second, e := q.GetGoldIntraday(context.Background())
	if e != nil || second[0].Price != 4300 || !second[0].Time.Equal(now) {
		t.Fatal(second, e)
	}
}
func TestIntradayCollectorKeepsLastSnapshotOnFailureOrEmptyData(t *testing.T) {
	now := time.Now()
	source := &intradaySource{points: []domain.IntradayPoint{{Time: now, Price: 4300}}}
	writer := &writeOnlyMarket{}
	c := NewGoldCollector(source, writer)
	if e := c.SyncIntraday(context.Background()); e != nil {
		t.Fatal(e)
	}
	source.err = errors.New("offline")
	if e := c.SyncIntraday(context.Background()); e == nil {
		t.Fatal("hidden failed fetch")
	}
	source.err = nil
	source.points = nil
	if e := c.SyncIntraday(context.Background()); e == nil {
		t.Fatal("empty snapshot accepted")
	}
	if len(writer.minutes) != 1 || writer.minutes[0].Price != 4300 || !writer.minutes[0].Time.Equal(now) {
		t.Fatal(writer.minutes)
	}
}
