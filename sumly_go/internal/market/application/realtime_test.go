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

func TestCollectorClampsModerateFutureSkewAndRejectsExtremeFuture(t *testing.T) {
	now := time.Date(2026, 11, 21, 1, 30, 0, 0, time.FixedZone("CST", 8*3600))

	for _, skew := range []time.Duration{15 * time.Second, 60 * time.Second, 90 * time.Second} {
		// 国内原生 AU9999（native=true）
		nativeWriter := &writeOnlyMarket{}
		nativeQuote := domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 760.12, AsOf: now.Add(skew)}
		nativeCollector := NewNativeGoldCollector(&fakeSource{quotes: []domain.GoldQuote{nativeQuote}}, nativeWriter)
		nativeCollector.now = func() time.Time { return now }
		if err := nativeCollector.Sample(context.Background()); err != nil {
			t.Fatalf("native skew %v unexpected error: %v", skew, err)
		}
		if nativeWriter.quotes != 1 || !nativeWriter.quote.AsOf.Equal(now) {
			t.Fatalf("native skew %v quote not clamped to now: %+v", skew, nativeWriter.quote)
		}
		if len(nativeWriter.points) != 1 || !nativeWriter.points[0].Time.Equal(now) || !nativeWriter.points[0].SourceTime.Equal(now) || nativeWriter.points[0].Price != 760.12 {
			t.Fatalf("native skew %v realtime point not clamped to now: %+v", skew, nativeWriter.points)
		}

		// 国际 XAUUSD（native=false）
		intlWriter := &writeOnlyMarket{}
		intlQuote := domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4378.29, USDCNY: 7.0, AsOf: now.Add(skew)}
		intlCollector := NewGoldCollector(&fakeSource{quotes: []domain.GoldQuote{intlQuote}}, intlWriter)
		intlCollector.now = func() time.Time { return now }
		if err := intlCollector.Sample(context.Background()); err != nil {
			t.Fatalf("intl skew %v unexpected error: %v", skew, err)
		}
		if intlWriter.quotes != 1 || !intlWriter.quote.AsOf.Equal(now) {
			t.Fatalf("intl skew %v quote not clamped to now: %+v", skew, intlWriter.quote)
		}
		if len(intlWriter.points) != 1 || !intlWriter.points[0].Time.Equal(now) || !intlWriter.points[0].SourceTime.Equal(now) {
			t.Fatalf("intl skew %v realtime point not clamped to now: %+v", skew, intlWriter.points)
		}
	}

	// 超前 120 秒仍拒绝，不落库报价也不写实时点
	rejectedWriter := &writeOnlyMarket{}
	rejectedQuote := domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 760.12, AsOf: now.Add(120 * time.Second)}
	rejectedCollector := NewNativeGoldCollector(&fakeSource{quotes: []domain.GoldQuote{rejectedQuote}}, rejectedWriter)
	rejectedCollector.now = func() time.Time { return now }
	if err := rejectedCollector.Sample(context.Background()); err == nil {
		t.Fatal("expected +120s quote to be rejected")
	}
	if rejectedWriter.quotes != 0 || len(rejectedWriter.points) != 0 {
		t.Fatalf("rejected future quote persisted: quotes=%d points=%d", rejectedWriter.quotes, len(rejectedWriter.points))
	}
}

func TestRealtimeClosedMarketIncompleteSecondsFallsBackToMinutes(t *testing.T) {
	end := time.Date(2026, 11, 21, 2, 30, 0, 0, time.FixedZone("CST", 8*3600))
	minutes := make([]domain.IntradayPoint, 0, 20)
	for i := 20; i >= 1; i-- {
		minutes = append(minutes, domain.IntradayPoint{
			Time:  end.Add(-time.Duration(i) * time.Minute),
			Price: 760.0 - float64(20-i)*0.1,
		})
	}

	t.Run("domestic AU9999 two-point straight line falls back to 60s minutes", func(t *testing.T) {
		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
			points: []domain.RealtimePoint{
				{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 755.01},
				{Time: end, SourceTime: end, Price: 755.01},
			},
			minutes: minutes,
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return end.Add(12 * time.Hour) }

		got, interval, err := q.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if interval != 60 || len(got) != 21 {
			t.Fatalf("expected 60s fallback with 21 points, got interval=%d len=%d", interval, len(got))
		}
		if !got[0].Time.Equal(end.Add(-RealtimeWindow)) || !got[20].Time.Equal(end) || got[20].Price != 755.01 {
			t.Fatalf("unexpected endpoints: first=%+v last=%+v", got[0], got[20])
		}
	})

	t.Run("international XAUUSD short 5m second-span falls back to 60s minutes", func(t *testing.T) {
		intlQuote := domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4378.29, USDCNY: 7.0, AsOf: end}
		shortPoints := make([]domain.RealtimePoint, 0, 61)
		for i := 60; i >= 0; i-- {
			at := end.Add(-time.Duration(i) * 5 * time.Second)
			shortPoints = append(shortPoints, domain.RealtimePoint{Time: at, SourceTime: at, Price: 980})
		}
		intlMinutes := make([]domain.IntradayPoint, 0, 20)
		for i := 20; i >= 1; i-- {
			intlMinutes = append(intlMinutes, domain.IntradayPoint{Time: end.Add(-time.Duration(i) * time.Minute), Price: 4370})
		}
		store := &readOnlyMarket{
			found:   true,
			quote:   intlQuote,
			points:  shortPoints,
			minutes: intlMinutes,
		}
		q := NewGoldQuery(store)
		q.now = func() time.Time { return end.Add(12 * time.Hour) }

		got, interval, err := q.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if interval != 60 || len(got) != 21 || got[20].Price != intlQuote.CNYPerGram() {
			t.Fatalf("expected 60s fallback with 21 converted points, got interval=%d len=%d last=%+v", interval, len(got), got[len(got)-1])
		}
	})

	t.Run("complete 5s samples still preferred over minutes", func(t *testing.T) {
		fullPoints := make([]domain.RealtimePoint, 0, 181)
		for i := 180; i >= 0; i-- {
			at := end.Add(-time.Duration(i) * 5 * time.Second)
			fullPoints = append(fullPoints, domain.RealtimePoint{Time: at, SourceTime: at, Price: 758.5})
		}
		store := &readOnlyMarket{
			found:   true,
			quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
			points:  fullPoints,
			minutes: minutes,
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return end.Add(12 * time.Hour) }

		got, interval, err := q.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if interval != 5 || len(got) != 181 {
			t.Fatalf("expected complete 5s samples to win, got interval=%d len=%d", interval, len(got))
		}
	})

	t.Run("gracefully falls back to frozen 5s when no intraday minutes exist", func(t *testing.T) {
		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
			points: []domain.RealtimePoint{
				{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 755.01},
				{Time: end, SourceTime: end, Price: 755.01},
			},
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return end.Add(12 * time.Hour) }

		got, interval, err := q.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if interval != 5 || len(got) != 2 {
			t.Fatalf("expected graceful fallback to frozen 5s, got interval=%d len=%d", interval, len(got))
		}
	})

	t.Run("keeps frozen 5s when partial 5s span exceeds available minute span", func(t *testing.T) {
		partialPoints := make([]domain.RealtimePoint, 0, 61)
		for i := 60; i >= 0; i-- {
			at := end.Add(-time.Duration(i) * 5 * time.Second) // 5 minutes span (<10m)
			partialPoints = append(partialPoints, domain.RealtimePoint{Time: at, SourceTime: at, Price: 758.5})
		}
		shortMinutes := []domain.IntradayPoint{
			{Time: end.Add(-3 * time.Minute), Price: 757.0},
			{Time: end.Add(-2 * time.Minute), Price: 756.5},
			{Time: end.Add(-1 * time.Minute), Price: 756.0},
		}
		store := &readOnlyMarket{
			found:   true,
			quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
			points:  partialPoints,
			minutes: shortMinutes,
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return end.Add(12 * time.Hour) }

		got, interval, err := q.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if interval != 5 || len(got) != 61 {
			t.Fatalf("expected partial 5s with longer span to win, got interval=%d len=%d", interval, len(got))
		}
	})

	t.Run("sparse SGE AU9999 night minutes carry forward same-session price without bridging market breaks", func(t *testing.T) {
		tz := time.FixedZone("CST", 8*3600)
		closeAt := time.Date(2026, 11, 21, 2, 30, 0, 0, tz)
		bar0204 := time.Date(2026, 11, 21, 2, 4, 0, 0, tz)
		bar0228 := time.Date(2026, 11, 21, 2, 28, 0, 0, tz)

		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: closeAt},
			points: []domain.RealtimePoint{
				{Time: closeAt.Add(-5 * time.Second), SourceTime: closeAt, Price: 755.01},
				{Time: closeAt, SourceTime: closeAt, Price: 755.01},
			},
			minutes: []domain.IntradayPoint{
				{Time: bar0204, Price: 760.00},
				{Time: bar0228, Price: 755.01},
			},
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return closeAt.Add(18 * time.Hour) }

		got, interval, err := q.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if interval != 60 || len(got) != 21 {
			t.Fatalf("expected 60s carried minute window with 21 points, got interval=%d len=%d", interval, len(got))
		}
		if !got[0].Time.Equal(closeAt.Add(-RealtimeWindow)) || !got[0].SourceTime.Equal(bar0204) || got[0].Price != 760.00 {
			t.Fatalf("unexpected first point: %+v", got[0])
		}
		if !got[18].Time.Equal(bar0228) || !got[18].SourceTime.Equal(bar0228) || got[18].Price != 755.01 {
			t.Fatalf("unexpected 02:28 point: %+v", got[18])
		}
		if !got[20].Time.Equal(closeAt) || got[20].Price != 755.01 {
			t.Fatalf("unexpected close point: %+v", got[20])
		}

		// 若上一笔成交在休市前（超过 60 分钟），不跨休市顺延。
		staleStore := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: closeAt},
			points: []domain.RealtimePoint{
				{Time: closeAt.Add(-5 * time.Second), SourceTime: closeAt, Price: 755.01},
				{Time: closeAt, SourceTime: closeAt, Price: 755.01},
			},
			minutes: []domain.IntradayPoint{
				{Time: closeAt.Add(-4 * time.Hour), Price: 770.00},
			},
		}
		staleQuery := NewNativeGoldQuery(staleStore)
		staleQuery.now = func() time.Time { return closeAt.Add(18 * time.Hour) }
		staleGot, staleInterval, err := staleQuery.GetGoldRealtime(context.Background())
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if staleInterval != 5 || len(staleGot) != 2 {
			t.Fatalf("expected stale pre-break bar not to be carried across break, got interval=%d len=%d", staleInterval, len(staleGot))
		}
	})
}
