package application

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

// Deliberately has no write methods and no upstream gateway.
type readOnlyMarket struct {
	quote   domain.GoldQuote
	found   bool
	minutes []domain.IntradayPoint
	points  []domain.RealtimePoint
	bars    []domain.DailyBar
	err     error
}

func (r *readOnlyMarket) LoadQuote(context.Context) (domain.GoldQuote, bool, error) {
	return r.quote, r.found, r.err
}
func (r *readOnlyMarket) LoadIntraday(context.Context) ([]domain.IntradayPoint, error) {
	return r.minutes, r.err
}
func (r *readOnlyMarket) LoadRealtime(context.Context) ([]domain.RealtimePoint, error) {
	return r.points, r.err
}
func (r *readOnlyMarket) LoadDaily(context.Context) ([]domain.DailyBar, error) { return r.bars, r.err }

func TestQueriesUseOnlyDurableReadPort(t *testing.T) {
	now := time.Now()
	store := &readOnlyMarket{found: true, quote: domain.GoldQuote{Symbol: "XAUUSD", Price: 4300, USDCNY: 7, AsOf: now}, minutes: []domain.IntradayPoint{{Time: now, Price: 4300}}, bars: []domain.DailyBar{{Close: 4300}}, points: []domain.RealtimePoint{{Time: now.Add(-5 * time.Second), SourceTime: now.Add(-5 * time.Second), Price: 950}, {Time: now, SourceTime: now, Price: 951}}}
	before := *store
	q := NewGoldQuery(store)
	for range 3 {
		if got, e := q.GetGoldQuote(context.Background()); e != nil || got.Price != 4300 {
			t.Fatal(got, e)
		}
		if got, e := q.GetGoldDailyKLines(context.Background()); e != nil || len(got) != 1 {
			t.Fatal(got, e)
		}
		if got, e := q.GetGoldIntraday(context.Background()); e != nil || len(got) != 1 {
			t.Fatal(got, e)
		}
		if got, interval, e := q.GetGoldRealtime(context.Background()); e != nil || interval != 5 || len(got) != 2 {
			t.Fatal(got, interval, e)
		}
	}
	if !reflect.DeepEqual(before, *store) {
		t.Fatal("query mutated durable data")
	}
}
func TestColdQueryDoesNotRequireSourceOrWriter(t *testing.T) {
	q := NewGoldQuery(&readOnlyMarket{})
	if _, e := q.GetGoldQuote(context.Background()); e == nil {
		t.Fatal("missing quote silently succeeded")
	}
	if got, e := q.GetGoldDailyKLines(context.Background()); e != nil || len(got) != 0 {
		t.Fatal(got, e)
	}
	if _, e := q.GetGoldIntraday(context.Background()); e == nil {
		t.Fatal("missing minute data silently succeeded")
	}
}
func TestQueriesPropagateDatabaseFailures(t *testing.T) {
	failure := errors.New("database offline")
	q := NewGoldQuery(&readOnlyMarket{err: failure})
	if _, e := q.GetGoldQuote(context.Background()); !errors.Is(e, failure) {
		t.Fatal(e)
	}
	if _, _, e := q.GetGoldRealtime(context.Background()); !errors.Is(e, failure) {
		t.Fatal(e)
	}
	if _, e := q.GetGoldDailyKLines(context.Background()); !errors.Is(e, failure) {
		t.Fatal(e)
	}
	if _, e := q.GetGoldIntraday(context.Background()); !errors.Is(e, failure) {
		t.Fatal(e)
	}
}

// Deliberately has no Load/Get methods. Daily idempotency belongs to persistence.
type writeOnlyMarket struct {
	quote   domain.GoldQuote
	quotes  int
	minutes []domain.IntradayPoint
	points  []domain.RealtimePoint
	bars    []domain.DailyBar
	err     error
}

func (w *writeOnlyMarket) SaveQuote(_ context.Context, q domain.GoldQuote) error {
	if w.err != nil {
		return w.err
	}
	w.quote = q
	w.quotes++
	return nil
}
func (w *writeOnlyMarket) SaveIntraday(_ context.Context, p []domain.IntradayPoint) error {
	w.minutes = p
	return w.err
}
func (w *writeOnlyMarket) SaveRealtime(_ context.Context, p domain.RealtimePoint) error {
	w.points = append(w.points, p)
	return w.err
}
func (w *writeOnlyMarket) PruneRealtime(context.Context) error { return w.err }
func (w *writeOnlyMarket) SaveDaily(_ context.Context, p []domain.DailyBar) error {
	w.bars = p
	return w.err
}
func TestCollectorWritesWithoutReadPort(t *testing.T) {
	now := time.Now()
	source := &fakeSource{quotes: []domain.GoldQuote{{Price: 4300, USDCNY: 7, AsOf: now}}}
	writer := &writeOnlyMarket{}
	c := NewGoldCollector(source, writer)
	c.now = func() time.Time { return now }
	if e := c.Sample(context.Background()); e != nil {
		t.Fatal(e)
	}
	if writer.quotes != 1 || len(writer.points) != 1 || writer.points[0].Price != source.quotes[0].CNYPerGram() {
		t.Fatal(writer)
	}
	source.err = errors.New("offline")
	if e := c.Sample(context.Background()); e == nil {
		t.Fatal("fetch failure hidden")
	}
	if writer.quotes != 1 || len(writer.points) != 1 {
		t.Fatal("failed source created fake sample")
	}
}
func TestCollectorDoesNotSampleFailedQuoteWrite(t *testing.T) {
	now := time.Now()
	failure := errors.New("write failed")
	writer := &writeOnlyMarket{err: failure}
	c := NewGoldCollector(&fakeSource{quotes: []domain.GoldQuote{{Price: 4300, USDCNY: 7, AsOf: now}}}, writer)
	if e := c.Sample(context.Background()); !errors.Is(e, failure) {
		t.Fatal(e)
	}
	if len(writer.points) != 0 {
		t.Fatal("sample persisted despite quote write failure")
	}
}
