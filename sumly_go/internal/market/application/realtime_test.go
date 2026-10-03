package application

import (
	"context"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

func TestRealtimeClosedMarketEndsAtSourceQuoteAndRecoversActualMinutes(t *testing.T) {
	end := time.Date(2026, 9, 19, 4, 54, 0, 0, time.FixedZone("CST", 8*3600))
	quote := domain.GoldQuote{Price: 4378.29, USDCNY: 6.6977, AsOf: end}
	store := &readOnlyMarket{found: true, quote: quote}
	for i := 21; i > 0; i-- {
		store.minutes = append(store.minutes, domain.IntradayPoint{Time: end.Add(-time.Duration(i) * time.Minute), Price: 4370})
	}
	q := NewGoldQuery(store)
	q.now = func() time.Time { return end.Add(48 * time.Hour) }
	points, interval, e := q.GetGoldRealtime(context.Background())
	if e != nil || interval != 60 || len(points) != 21 || !points[0].Time.Equal(end.Add(-RealtimeWindow)) || !points[20].Time.Equal(end) || points[20].Price != quote.CNYPerGram() {
		t.Fatal(points, interval, e)
	}
	if len(store.points) != 0 {
		t.Fatal("minute recovery wrote five-second samples")
	}
}
func TestRealtimeClosedMarketKeepsSecondsAndUsesLastSourceTimestamp(t *testing.T) {
	end := time.Now().Add(-48 * time.Hour).Truncate(time.Minute)
	quote := domain.GoldQuote{Price: 4378.29, USDCNY: 6.6977, AsOf: end}
	store := &readOnlyMarket{found: true, quote: quote}
	for i := -250; i <= 12; i++ {
		at := end.Add(time.Duration(i) * 5 * time.Second)
		source := at
		if at.After(end) {
			source = end
		}
		store.points = append(store.points, domain.RealtimePoint{Time: at, SourceTime: source, Price: 940})
	}
	points, interval, e := NewGoldQuery(store).GetGoldRealtime(context.Background())
	if e != nil || interval != 5 || len(points) != 241 || !points[0].Time.Equal(end.Add(-RealtimeWindow)) || !points[240].Time.Equal(end) || points[240].Price != quote.CNYPerGram() {
		t.Fatal(len(points), interval, e)
	}
}
func TestRealtimeStoredSamplesSurviveMissingQuote(t *testing.T) {
	end := time.Now().Add(-48 * time.Hour)
	store := &readOnlyMarket{points: []domain.RealtimePoint{{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 900}, {Time: end, SourceTime: end, Price: 901}}}
	points, interval, e := NewGoldQuery(store).GetGoldRealtime(context.Background())
	if e != nil || interval != 5 || len(points) != 2 || points[1].Price != 901 {
		t.Fatal(points, interval, e)
	}
}
func TestRealtimeCollectorRejectsStaleOrInvalidSamples(t *testing.T) {
	now := time.Now()
	for _, quote := range []domain.GoldQuote{{Price: 3100, USDCNY: 7, AsOf: now.Add(-time.Hour)}, {Price: 3100, AsOf: now}} {
		writer := &writeOnlyMarket{}
		c := NewGoldCollector(&fakeSource{quotes: []domain.GoldQuote{quote}}, writer)
		c.now = func() time.Time { return now }
		if e := c.Sample(context.Background()); e != nil {
			t.Fatal(e)
		}
		if len(writer.points) != 0 {
			t.Fatal("stale/unconvertible sample accepted")
		}
	}
}
func TestNativeRealtimeKeepsOriginalUnitWithoutFX(t *testing.T) {
	for _, currency := range []string{"CNY", "USD"} {
		now := time.Now()
		writer := &writeOnlyMarket{}
		c := NewNativeGoldCollector(&fakeSource{quotes: []domain.GoldQuote{{Price: 946, Currency: currency, AsOf: now}}}, writer)
		if e := c.Sample(context.Background()); e != nil {
			t.Fatal(e)
		}
		if len(writer.points) != 1 || writer.points[0].Price != 946 {
			t.Fatal(writer.points)
		}
	}
}
func TestDelayedFeedPreservesEventTime(t *testing.T) {
	now := time.Now()
	quote := domain.GoldQuote{Price: 4424.9, Currency: "USD", AsOf: now.Add(-30 * time.Minute), SourceDelaySeconds: 1800}
	writer := &writeOnlyMarket{}
	c := NewNativeGoldCollector(&fakeSource{quotes: []domain.GoldQuote{quote}}, writer)
	c.now = func() time.Time { return now }
	if e := c.Sample(context.Background()); e != nil {
		t.Fatal(e)
	}
	if len(writer.points) != 1 || !writer.points[0].Time.Equal(quote.AsOf) {
		t.Fatal(writer.points)
	}
	now = now.Add(48 * time.Hour)
	if e := c.Sample(context.Background()); e != nil {
		t.Fatal(e)
	}
	if len(writer.points) != 1 {
		t.Fatal("stopped delayed feed created ticks")
	}
}
