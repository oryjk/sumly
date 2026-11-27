package application

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

func TestDomesticAU9999SessionWindowNightCrossingMidnight(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	// 前一日日盘（应被排除）+ 当日周五夜盘 20:00 ~ 次日 02:28（真实稀疏/密集分钟点）+ 02:30 收盘锚点
	minutes := make([]domain.IntradayPoint, 0, 320)
	// 11-20 日盘：09:00 ~ 11:30, 13:30 ~ 15:30
	for m := 0; m <= 150; m += 5 {
		minutes = append(minutes, domain.IntradayPoint{
			Time:  time.Date(2026, 11, 20, 9, 0, 0, 0, tz).Add(time.Duration(m) * time.Minute),
			Price: 778.00,
		})
	}
	for m := 0; m <= 120; m += 5 {
		minutes = append(minutes, domain.IntradayPoint{
			Time:  time.Date(2026, 11, 20, 13, 30, 0, 0, tz).Add(time.Duration(m) * time.Minute),
			Price: 775.00,
		})
	}
	// 11-20 夜盘：20:00 ~ 11-21 02:28（构造 256 个真实成交点，覆盖 773.48 → 755.01）
	nightStart := time.Date(2026, 11, 20, 20, 0, 0, 0, tz)
	nightLastBar := time.Date(2026, 11, 21, 2, 28, 0, 0, tz)
	const nightBars = 256
	for i := range nightBars {
		offsetMinutes := i * 388 / (nightBars - 1) // 0 .. 388 (20:00 .. 02:28)
		ts := nightStart.Add(time.Duration(offsetMinutes) * time.Minute)
		price := 773.48 - float64(i)*(773.48-755.01)/float64(nightBars-1)
		minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: math.Round(price*100) / 100})
	}
	// 确保首尾与预期精准对齐
	minutes[len(minutes)-nightBars] = domain.IntradayPoint{Time: nightStart, Price: 773.48}
	minutes[len(minutes)-1] = domain.IntradayPoint{Time: nightLastBar, Price: 755.01}

	closeAt := time.Date(2026, 11, 21, 2, 30, 0, 0, tz)
	store := &readOnlyMarket{
		found: true,
		quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: closeAt},
		points: []domain.RealtimePoint{
			{Time: closeAt.Add(-5 * time.Second), SourceTime: closeAt, Price: 755.01},
			{Time: closeAt.Add(30 * time.Second), SourceTime: closeAt, Price: 755.01}, // 收盘后墙上时钟滞后样本
		},
		minutes: minutes,
	}

	q := NewNativeGoldQuery(store)
	q.now = func() time.Time { return closeAt.Add(20 * time.Hour) } // 周六晚间休市查看

	window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if window.IntervalSeconds != 60 {
		t.Fatalf("interval_seconds = %d, want 60", window.IntervalSeconds)
	}
	if window.WindowSeconds != 23400 {
		t.Fatalf("window_seconds = %d, want 23400 (6.5h)", window.WindowSeconds)
	}
	if !window.Start.Equal(nightStart) || !window.End.Equal(closeAt) {
		t.Fatalf("window range = [%v, %v], want [%v, %v]", window.Start, window.End, nightStart, closeAt)
	}
	if len(window.Points) != nightBars+1 { // 256 真实分钟点 + 02:30 收盘锚点
		t.Fatalf("points len = %d, want %d", len(window.Points), nightBars+1)
	}
	if !window.Points[0].Time.Equal(nightStart) || window.Points[0].Price != 773.48 {
		t.Fatalf("first point = %+v, want 20:00 @ 773.48", window.Points[0])
	}
	last := window.Points[len(window.Points)-1]
	if !last.Time.Equal(closeAt) || last.Price != 755.01 {
		t.Fatalf("last point = %+v, want 02:30 @ 755.01", last)
	}
	for _, p := range window.Points {
		if p.Time.Before(nightStart) {
			t.Fatalf("leaked pre-session point: %+v", p)
		}
	}
}

func TestDomesticAU9999SessionWindowNightPreMidnightMergesLiveTail(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	nightStart := time.Date(2026, 11, 20, 20, 0, 0, 0, tz)
	lastBar := time.Date(2026, 11, 20, 23, 14, 0, 0, tz)
	liveQuoteAt := time.Date(2026, 11, 20, 23, 15, 30, 0, tz)

	minutes := []domain.IntradayPoint{
		{Time: time.Date(2026, 11, 20, 15, 30, 0, 0, tz), Price: 775.00}, // 旧日盘
		{Time: nightStart, Price: 773.48},
		{Time: time.Date(2026, 11, 20, 21, 30, 0, 0, tz), Price: 770.20},
		{Time: lastBar, Price: 768.10},
	}
	realtime := []domain.RealtimePoint{
		{Time: lastBar.Add(20 * time.Second), SourceTime: lastBar.Add(20 * time.Second), Price: 768.15},
		{Time: time.Date(2026, 11, 20, 23, 15, 10, 0, tz), SourceTime: time.Date(2026, 11, 20, 23, 15, 10, 0, tz), Price: 768.40},
		{Time: time.Date(2026, 11, 20, 23, 15, 25, 0, tz), SourceTime: time.Date(2026, 11, 20, 23, 15, 25, 0, tz), Price: 768.60},
	}

	store := &readOnlyMarket{
		found:   true,
		quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 768.80, AsOf: liveQuoteAt},
		points:  realtime,
		minutes: minutes,
	}
	q := NewNativeGoldQuery(store)
	q.now = func() time.Time { return liveQuoteAt.Add(5 * time.Second) }

	window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	wantSeconds := int(liveQuoteAt.Sub(nightStart).Seconds()) // 3h15m30s = 11730
	if window.IntervalSeconds != 60 || window.WindowSeconds != wantSeconds {
		t.Fatalf("interval=%d window_seconds=%d, want 60/%d", window.IntervalSeconds, window.WindowSeconds, wantSeconds)
	}
	// 3 根夜盘分钟线 + 23:15 尾点（由 liveQuoteAt 覆盖同分钟 5s 采样）= 4 点
	if len(window.Points) != 4 {
		t.Fatalf("expected 4 points, got %d: %+v", len(window.Points), window.Points)
	}
	if !window.Points[0].Time.Equal(nightStart) {
		t.Fatalf("first point = %+v, want %v", window.Points[0], nightStart)
	}
	if last := window.Points[len(window.Points)-1]; !last.Time.Equal(liveQuoteAt) || last.Price != 768.80 {
		t.Fatalf("last point = %+v, want %v @ 768.80", last, liveQuoteAt)
	}
}

func TestDomesticAU9999SessionWindowDaySessionKeepsRealPointsWithoutLunchFill(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	dayStart := time.Date(2026, 11, 20, 9, 0, 0, 0, tz)
	morningClose := time.Date(2026, 11, 20, 11, 30, 0, 0, tz)
	afternoonOpen := time.Date(2026, 11, 20, 13, 30, 0, 0, tz)
	dayClose := time.Date(2026, 11, 20, 15, 30, 0, 0, tz)

	minutes := make([]domain.IntradayPoint, 0, 300)
	// 前一夜盘（应被排除）
	minutes = append(minutes,
		domain.IntradayPoint{Time: time.Date(2026, 11, 19, 20, 0, 0, 0, tz), Price: 780.00},
		domain.IntradayPoint{Time: time.Date(2026, 11, 20, 2, 30, 0, 0, tz), Price: 779.00},
	)
	// 上午盘 09:00 ~ 11:30（151 分钟）
	for m := 0; m <= 150; m++ {
		minutes = append(minutes, domain.IntradayPoint{
			Time:  dayStart.Add(time.Duration(m) * time.Minute),
			Price: 776.00 + float64(m)*0.01,
		})
	}
	// 下午盘 13:30 ~ 15:29（120 分钟，故意缺 15:30 让收盘报价补齐尾点）
	for m := 0; m < 120; m++ {
		minutes = append(minutes, domain.IntradayPoint{
			Time:  afternoonOpen.Add(time.Duration(m) * time.Minute),
			Price: 774.50 - float64(m)*0.01,
		})
	}

	store := &readOnlyMarket{
		found:   true,
		quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 773.30, AsOf: dayClose},
		minutes: minutes,
	}
	q := NewNativeGoldQuery(store)
	q.now = func() time.Time { return time.Date(2026, 11, 20, 18, 0, 0, 0, tz) }

	window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if window.IntervalSeconds != 60 || window.WindowSeconds != 23400 {
		t.Fatalf("interval=%d window_seconds=%d, want 60/23400", window.IntervalSeconds, window.WindowSeconds)
	}
	if !window.Start.Equal(dayStart) || !window.End.Equal(dayClose) {
		t.Fatalf("window range = [%v, %v], want [%v, %v]", window.Start, window.End, dayStart, dayClose)
	}
	wantCount := 151 + 120 + 1
	if len(window.Points) != wantCount {
		t.Fatalf("points len = %d, want %d", len(window.Points), wantCount)
	}
	// 确认不含前一夜盘，且午休 11:31 ~ 13:29 无假点填充
	for _, p := range window.Points {
		if p.Time.Before(dayStart) {
			t.Fatalf("leaked previous night point: %+v", p)
		}
		if p.Time.After(morningClose) && p.Time.Before(afternoonOpen) {
			t.Fatalf("unexpected synthetic lunch break point: %+v", p)
		}
	}
	if last := window.Points[len(window.Points)-1]; !last.Time.Equal(dayClose) || last.Price != 773.30 {
		t.Fatalf("last point = %+v, want 15:30 @ 773.30", last)
	}
}

func TestDomesticAU9999SessionWindowGuardsStalePostCloseAndNewSessionBreak(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)

	t.Run("does not extend night session to bogus post-close quote hours after 02:30", func(t *testing.T) {
		nightStart := time.Date(2026, 11, 20, 20, 0, 0, 0, tz)
		lastBar := time.Date(2026, 11, 21, 2, 28, 0, 0, tz)
		bogusPostClose := time.Date(2026, 11, 21, 6, 30, 0, 0, tz)

		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: bogusPostClose},
			minutes: []domain.IntradayPoint{
				{Time: nightStart, Price: 773.48},
				{Time: lastBar, Price: 755.01},
			},
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return time.Date(2026, 11, 21, 14, 0, 0, 0, tz) }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !window.End.Equal(lastBar) || len(window.Points) != 2 {
			t.Fatalf("expected end anchored at last real bar %v, got end=%v len=%d", lastBar, window.End, len(window.Points))
		}
	})

	t.Run("newly opened night session without night minute bars degrades to new session 5s samples without bridging day session", func(t *testing.T) {
		nightOpen := time.Date(2026, 11, 20, 20, 0, 0, 0, tz)
		now := time.Date(2026, 11, 20, 20, 3, 0, 0, tz)
		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 773.10, AsOf: now},
			points: []domain.RealtimePoint{
				{Time: time.Date(2026, 11, 20, 15, 29, 55, 0, tz), SourceTime: time.Date(2026, 11, 20, 15, 29, 55, 0, tz), Price: 775.00},
				{Time: nightOpen.Add(5 * time.Second), SourceTime: nightOpen.Add(5 * time.Second), Price: 773.48},
				{Time: now, SourceTime: now, Price: 773.10},
			},
			minutes: []domain.IntradayPoint{
				{Time: time.Date(2026, 11, 20, 15, 28, 0, 0, tz), Price: 775.10},
				{Time: time.Date(2026, 11, 20, 15, 30, 0, 0, tz), Price: 775.00},
			},
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return now }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if window.IntervalSeconds != 5 || window.WindowSeconds != 1200 {
			t.Fatalf("expected 5s/1200s fallback, got interval=%d window=%d", window.IntervalSeconds, window.WindowSeconds)
		}
		if len(window.Points) != 2 {
			t.Fatalf("expected only 2 new-session points, got %+v", window.Points)
		}
		for _, p := range window.Points {
			if p.Time.Before(nightOpen) {
				t.Fatalf("leaked previous day session point: %+v", p)
			}
		}
	})

	t.Run("empty minute snapshot gracefully degrades to 5s samples", func(t *testing.T) {
		end := time.Date(2026, 11, 21, 2, 30, 0, 0, tz)
		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
			points: []domain.RealtimePoint{
				{Time: end.Add(-10 * time.Second), SourceTime: end.Add(-10 * time.Second), Price: 755.20},
				{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 755.10},
				{Time: end, SourceTime: end, Price: 755.01},
			},
		}
		q := NewNativeGoldQuery(store)
		q.now = func() time.Time { return end.Add(12 * time.Hour) }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if window.IntervalSeconds != 5 || window.WindowSeconds != 1200 || len(window.Points) != 3 {
			t.Fatalf("unexpected 5s fallback: interval=%d window=%d len=%d", window.IntervalSeconds, window.WindowSeconds, len(window.Points))
		}
	})
}

func TestInternationalXAUUSDSessionWindowSixHoursAndGapTruncation(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)

	t.Run("returns 6h (21600s) minute curve in CNY/g and merges newer live tail", func(t *testing.T) {
		endBar := time.Date(2026, 11, 21, 4, 58, 0, 0, tz)
		quoteAt := time.Date(2026, 11, 21, 5, 0, 0, 0, tz)
		start12h := quoteAt.Add(-12 * time.Hour)
		minutes := make([]domain.IntradayPoint, 0, 720)
		for ts := start12h; !ts.After(endBar); ts = ts.Add(time.Minute) {
			minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: 4370.0})
		}
		quote := domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4380.0, USDCNY: 7.0, AsOf: quoteAt}
		store := &readOnlyMarket{
			found: true,
			quote: quote,
			points: []domain.RealtimePoint{
				{Time: time.Date(2026, 11, 21, 4, 59, 10, 0, tz), SourceTime: time.Date(2026, 11, 21, 4, 59, 10, 0, tz), Price: 984.5},
				{Time: time.Date(2026, 11, 21, 4, 59, 50, 0, tz), SourceTime: time.Date(2026, 11, 21, 4, 59, 50, 0, tz), Price: 985.0},
			},
			minutes: minutes,
		}
		q := NewGoldQuery(store)
		q.now = func() time.Time { return quoteAt.Add(10 * time.Hour) }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		wantStart := quoteAt.Add(-6 * time.Hour)
		if window.IntervalSeconds != 60 || window.WindowSeconds != 21600 {
			t.Fatalf("interval=%d window_seconds=%d, want 60/21600", window.IntervalSeconds, window.WindowSeconds)
		}
		if !window.Start.Equal(wantStart) || !window.End.Equal(quoteAt) {
			t.Fatalf("window range = [%v, %v], want [%v, %v]", window.Start, window.End, wantStart, quoteAt)
		}
		// 23:00..04:58 共 359 根分钟线 + 04:59:50 合并尾点 + 05:00:00 报价尾点 = 361 点
		if len(window.Points) != 361 {
			t.Fatalf("points len = %d, want 361", len(window.Points))
		}
		wantFirstPrice := 4370.0 / domain.GramsPerTroyOunce * 7.0
		if math.Abs(window.Points[0].Price-wantFirstPrice) > 1e-9 {
			t.Fatalf("first price = %v, want %v", window.Points[0].Price, wantFirstPrice)
		}
		last := window.Points[len(window.Points)-1]
		if !last.Time.Equal(quoteAt) || math.Abs(last.Price-quote.CNYPerGram()) > 1e-9 {
			t.Fatalf("last point = %+v, want %v @ %v", last, quoteAt, quote.CNYPerGram())
		}
	})

	t.Run("truncates across >2h halt/weekend gap to start of new session", func(t *testing.T) {
		preBreakEnd := time.Date(2026, 11, 21, 4, 30, 0, 0, tz)
		postBreakStart := time.Date(2026, 11, 21, 7, 0, 0, 0, tz) // 2.5h gap (>2h)
		end := time.Date(2026, 11, 21, 9, 0, 0, 0, tz)

		var minutes []domain.IntradayPoint
		for ts := preBreakEnd.Add(-2 * time.Hour); !ts.After(preBreakEnd); ts = ts.Add(time.Minute) {
			minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: 4350.0})
		}
		for ts := postBreakStart; !ts.After(end); ts = ts.Add(time.Minute) {
			minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: 4390.0})
		}

		store := &readOnlyMarket{
			found:   true,
			quote:   domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4390.0, USDCNY: 7.0, AsOf: end},
			minutes: minutes,
		}
		q := NewGoldQuery(store)
		q.now = func() time.Time { return end.Add(30 * time.Second) }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if window.IntervalSeconds != 60 || window.WindowSeconds != 7200 {
			t.Fatalf("interval=%d window_seconds=%d, want 60/7200", window.IntervalSeconds, window.WindowSeconds)
		}
		if !window.Start.Equal(postBreakStart) || !window.End.Equal(end) || len(window.Points) != 121 {
			t.Fatalf("unexpected post-gap window: start=%v end=%v len=%d", window.Start, window.End, len(window.Points))
		}
	})

	t.Run("keeps continuous 6h curve across 1h daily rollover gap (<=2h)", func(t *testing.T) {
		rolloverStart := time.Date(2026, 11, 20, 5, 0, 0, 0, tz)
		rolloverEnd := time.Date(2026, 11, 20, 6, 0, 0, 0, tz) // 1h gap (<=2h)
		end := time.Date(2026, 11, 20, 9, 0, 0, 0, tz)
		start6h := end.Add(-6 * time.Hour) // 03:00

		var minutes []domain.IntradayPoint
		for ts := start6h; !ts.After(rolloverStart); ts = ts.Add(time.Minute) {
			minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: 4360.0})
		}
		for ts := rolloverEnd; !ts.After(end); ts = ts.Add(time.Minute) {
			minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: 4365.0})
		}

		store := &readOnlyMarket{
			found:   true,
			quote:   domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4365.0, USDCNY: 7.0, AsOf: end},
			minutes: minutes,
		}
		q := NewGoldQuery(store)
		q.now = func() time.Time { return end.Add(10 * time.Second) }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if window.IntervalSeconds != 60 || window.WindowSeconds != 21600 || !window.Start.Equal(start6h) {
			t.Fatalf("expected full 6h across 1h rollover, got interval=%d window=%d start=%v", window.IntervalSeconds, window.WindowSeconds, window.Start)
		}
	})

	t.Run("empty minute snapshot gracefully degrades to 5s samples", func(t *testing.T) {
		end := time.Date(2026, 11, 21, 5, 0, 0, 0, tz)
		store := &readOnlyMarket{
			found: true,
			quote: domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4380.0, USDCNY: 7.0, AsOf: end},
			points: []domain.RealtimePoint{
				{Time: end.Add(-10 * time.Second), SourceTime: end.Add(-10 * time.Second), Price: 985.0},
				{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 985.2},
				{Time: end, SourceTime: end, Price: 985.5},
			},
		}
		q := NewGoldQuery(store)
		q.now = func() time.Time { return end.Add(10 * time.Hour) }

		window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if window.IntervalSeconds != 5 || window.WindowSeconds != 1200 || len(window.Points) != 3 {
			t.Fatalf("unexpected 5s fallback: interval=%d window=%d len=%d", window.IntervalSeconds, window.WindowSeconds, len(window.Points))
		}
	})
}

func TestRealtimeWindowMode20mPreservesBackwardCompatibilityAndErrorPropagation(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	end := time.Date(2026, 11, 21, 2, 30, 0, 0, tz)
	minutes := make([]domain.IntradayPoint, 0, 390)
	for m := 0; m <= 389; m++ {
		minutes = append(minutes, domain.IntradayPoint{
			Time:  time.Date(2026, 11, 20, 20, 0, 0, 0, tz).Add(time.Duration(m) * time.Minute),
			Price: 760.0,
		})
	}
	store := &readOnlyMarket{
		found:   true,
		quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
		minutes: minutes,
	}
	q := NewNativeGoldQuery(store)
	q.now = func() time.Time { return end.Add(12 * time.Hour) }

	for _, mode := range []domain.RealtimeWindowMode{"", domain.RealtimeWindowMode20m} {
		window, err := q.GetGoldRealtimeWindow(context.Background(), mode)
		if err != nil {
			t.Fatalf("mode=%q unexpected error: %v", mode, err)
		}
		if window.WindowSeconds != 1200 || window.IntervalSeconds != 60 || len(window.Points) != 21 {
			t.Fatalf("mode=%q unexpected 20m contract: window=%d interval=%d len=%d", mode, window.WindowSeconds, window.IntervalSeconds, len(window.Points))
		}
	}

	// 数据库错误必须透传
	failure := errors.New("db down")
	errQuery := NewGoldQuery(&readOnlyMarket{err: failure})
	if _, err := errQuery.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession); !errors.Is(err, failure) {
		t.Fatalf("expected db error propagated, got %v", err)
	}
}

func TestInstrumentsRealtimeWindowRoutesDomesticAndInternationalSessions(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	nightStart := time.Date(2025, 11, 20, 20, 0, 0, 0, tz)
	nightEnd := time.Date(2025, 11, 21, 2, 30, 0, 0, tz)
	auStore := &readOnlyMarket{
		// 即使最新报价暂时缺失，au9999 仍依据 Instrument 元数据识别为国内上金所交易时段
		found: false,
		minutes: []domain.IntradayPoint{
			{Time: time.Date(2025, 11, 20, 15, 0, 0, 0, tz), Price: 775.0},
			{Time: nightStart, Price: 773.48},
			{Time: nightEnd, Price: 755.01},
		},
	}
	auQuery := NewNativeGoldQuery(auStore)
	auQuery.now = func() time.Time { return nightEnd.Add(10 * time.Hour) }

	intlEnd := time.Date(2025, 11, 21, 5, 0, 0, 0, tz)
	intlStart := intlEnd.Add(-6 * time.Hour)
	intlStore := &readOnlyMarket{
		found: true,
		quote: domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4380.0, USDCNY: 7.0, AsOf: intlEnd},
		minutes: []domain.IntradayPoint{
			{Time: intlEnd.Add(-8 * time.Hour), Price: 4350.0},
			{Time: intlStart, Price: 4360.0},
			{Time: intlEnd.Add(-4 * time.Hour), Price: 4365.0},
			{Time: intlEnd.Add(-2 * time.Hour), Price: 4370.0},
			{Time: intlEnd, Price: 4380.0},
		},
	}
	intlQuery := NewNativeGoldQuery(intlStore)
	intlQuery.now = func() time.Time { return intlEnd.Add(10 * time.Hour) }

	svc := NewInstruments([]InstrumentMarket{
		{Instrument: domain.Instrument{ID: "au9999", Symbol: "AU9999", Currency: "CNY", Unit: "CNY/g", Exchange: "SGE"}, Service: auQuery},
		{Instrument: domain.Instrument{ID: "xauusd", Symbol: "XAUUSD", Currency: "USD", Unit: "USD/troy_oz"}, Service: intlQuery},
	})

	_, auWin, err := svc.RealtimeWindow(context.Background(), "au9999", domain.RealtimeWindowModeSession)
	if err != nil {
		t.Fatalf("au9999 session error: %v", err)
	}
	if auWin.IntervalSeconds != 60 || auWin.WindowSeconds != 23400 || len(auWin.Points) != 2 {
		t.Fatalf("unexpected au9999 session without quote: interval=%d window=%d points=%+v", auWin.IntervalSeconds, auWin.WindowSeconds, auWin.Points)
	}

	_, intlWin, err := svc.RealtimeWindow(context.Background(), "xauusd", domain.RealtimeWindowModeSession)
	if err != nil {
		t.Fatalf("xauusd session error: %v", err)
	}
	if intlWin.IntervalSeconds != 60 || intlWin.WindowSeconds != 21600 || len(intlWin.Points) != 4 || intlWin.Points[0].Price != 4360.0 {
		t.Fatalf("unexpected xauusd native session: interval=%d window=%d points=%+v", intlWin.IntervalSeconds, intlWin.WindowSeconds, intlWin.Points)
	}
}

func TestDomesticAU9999DayWindowBridgesDayAndNightContinuously(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	dayStart := time.Date(2026, 11, 27, 9, 0, 0, 0, tz)
	nightOpen := time.Date(2026, 11, 27, 20, 0, 0, 0, tz)
	nightNow := time.Date(2026, 11, 27, 22, 34, 0, 0, tz)

	minutes := []domain.IntradayPoint{
		// 前一日夜盘（应被排除）
		{Time: time.Date(2026, 11, 27, 2, 20, 0, 0, tz), Price: 762.0},
		// 当天日盘 09:00 ~ 15:30（大涨）
		{Time: dayStart, Price: 765.0},
		{Time: time.Date(2026, 11, 27, 11, 30, 0, 0, tz), Price: 776.5},
		{Time: time.Date(2026, 11, 27, 13, 30, 0, 0, tz), Price: 781.2},
		{Time: time.Date(2026, 11, 27, 15, 30, 0, 0, tz), Price: 784.0},
		// 当晚夜盘 20:00 ~ 22:33
		{Time: nightOpen, Price: 785.0},
		{Time: time.Date(2026, 11, 27, 22, 33, 0, 0, tz), Price: 779.2},
	}

	store := &readOnlyMarket{
		found: true,
		quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 779.0, AsOf: nightNow},
		points: []domain.RealtimePoint{
			{Time: nightNow, SourceTime: nightNow, Price: 779.0},
		},
		minutes: minutes,
	}
	q := NewNativeGoldQuery(store)
	q.now = func() time.Time { return nightNow.Add(5 * time.Second) }

	window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeDay)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if window.IntervalSeconds != 60 {
		t.Fatalf("interval = %d, want 60", window.IntervalSeconds)
	}
	if !window.Start.Equal(dayStart) || !window.End.Equal(nightNow) {
		t.Fatalf("window = [%v, %v], want [%v, %v]", window.Start, window.End, dayStart, nightNow)
	}
	// 排除凌晨 02:20 前一夜盘，保留当天 09:00 日盘 + 20:00 夜盘 + 22:34 尾点 = 7 点
	if len(window.Points) != 7 {
		t.Fatalf("points len = %d, want 7: %+v", len(window.Points), window.Points)
	}
	if !window.Points[0].Time.Equal(dayStart) || window.Points[0].Price != 765.0 {
		t.Fatalf("first point = %+v, want 09:00 @ 765.0", window.Points[0])
	}
	if last := window.Points[len(window.Points)-1]; !last.Time.Equal(nightNow) || last.Price != 779.0 {
		t.Fatalf("last point = %+v, want 22:34 @ 779.0", last)
	}

	// 夜盘刚开盘 2 分钟（夜盘分钟线尚未落地）时，仍保留当天白天日盘并拼接夜盘最新 5s/报价尾点
	justOpened := time.Date(2026, 11, 27, 20, 2, 0, 0, tz)
	storeOpening := &readOnlyMarket{
		found: true,
		quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 785.5, AsOf: justOpened},
		points: []domain.RealtimePoint{
			{Time: nightOpen.Add(30 * time.Second), SourceTime: nightOpen.Add(30 * time.Second), Price: 785.0},
			{Time: justOpened, SourceTime: justOpened, Price: 785.5},
		},
		minutes: minutes[:5], // 仅有凌晨 02:20 + 当天日盘 09:00..15:30
	}
	qOpening := NewNativeGoldQuery(storeOpening)
	qOpening.now = func() time.Time { return justOpened.Add(5 * time.Second) }
	openWin, err := qOpening.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeDay)
	if err != nil {
		t.Fatalf("opening error: %v", err)
	}
	if !openWin.Start.Equal(dayStart) || !openWin.End.Equal(justOpened) {
		t.Fatalf("opening window = [%v, %v], want [%v, %v]", openWin.Start, openWin.End, dayStart, justOpened)
	}
	if len(openWin.Points) < 5 || !openWin.Points[0].Time.Equal(dayStart) {
		t.Fatalf("opening should preserve day session points, got %+v", openWin.Points)
	}
}

func TestInternationalXAUUSDDayWindowCoversFullTradingDayUpTo23Hours(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	// 冬令时：北京时间 07:00 开盘（美东前日 18:00），至当晚 22:35（共 15h35m）
	prevDayTail := time.Date(2026, 11, 27, 5, 55, 0, 0, tz)
	openAt := time.Date(2026, 11, 27, 7, 0, 0, 0, tz)
	lastBar := time.Date(2026, 11, 27, 22, 34, 0, 0, tz)
	quoteAt := time.Date(2026, 11, 27, 22, 35, 0, 0, tz)

	minutes := []domain.IntradayPoint{
		{Time: prevDayTail, Price: 3566.0}, // 上一交易日尾点，应被切掉
	}
	for ts := openAt; !ts.After(lastBar); ts = ts.Add(time.Minute) {
		minutes = append(minutes, domain.IntradayPoint{Time: ts, Price: 3565.0 + float64(ts.Sub(openAt)/time.Minute)*0.08})
	}

	store := &readOnlyMarket{
		found:   true,
		quote:   domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 3638.0, USDCNY: 6.6547, AsOf: quoteAt},
		minutes: minutes,
	}
	q := NewGoldQuery(store)
	q.now = func() time.Time { return quoteAt.Add(5 * time.Second) }

	window, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeDay)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if window.IntervalSeconds != 60 {
		t.Fatalf("interval = %d, want 60", window.IntervalSeconds)
	}
	if !window.Start.Equal(openAt) || !window.End.Equal(quoteAt) {
		t.Fatalf("window = [%v, %v], want [%v, %v]", window.Start, window.End, openAt, quoteAt)
	}
	// 07:00..22:34 共 935 根分钟线 + 22:35 实时尾点 = 936 点
	if len(window.Points) != 936 {
		t.Fatalf("points len = %d, want 936", len(window.Points))
	}
	if window.Points[0].Time.Before(openAt) {
		t.Fatalf("leaked prior trading day point: %+v", window.Points[0])
	}
}

func TestDomesticAU9999DayWindowAfter2000UsesPriorNaturalDayPrevCloseAndKeepsContinuousDay(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	dayStart := time.Date(2026, 11, 27, 9, 0, 0, 0, tz)
	midday := time.Date(2026, 11, 27, 12, 15, 0, 0, tz) // 11:31~13:29 连续日盘真实成交
	dayClose := time.Date(2026, 11, 27, 15, 30, 0, 0, tz)
	nightOpen := time.Date(2026, 11, 27, 20, 0, 0, 0, tz)
	lateNight := time.Date(2026, 11, 28, 1, 30, 0, 0, tz)

	bars := []domain.DailyBar{
		{Date: time.Date(2026, 11, 26, 0, 0, 0, 0, tz), Close: 765.0},
		{Date: time.Date(2026, 11, 27, 0, 0, 0, 0, tz), Close: 784.0}, // 今日日盘收盘价，不能误当作自然日昨收
	}
	minutes := []domain.IntradayPoint{
		{Time: time.Date(2026, 11, 27, 2, 20, 0, 0, tz), Price: 762.0}, // 前一日夜盘尾点，应排除
		{Time: dayStart, Price: 766.0},
		{Time: midday, Price: 780.5},
		{Time: dayClose, Price: 784.0},
		{Time: nightOpen, Price: 785.0},
		{Time: lateNight.Add(-time.Minute), Price: 779.5},
	}

	// 新浪在 20:00 后已把 quote.PrevClose 切为今日 15:30 收盘价 784.0
	store := &readOnlyMarket{
		found:   true,
		quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 779.0, PrevClose: 784.0, AsOf: lateNight},
		minutes: minutes,
		bars:    bars,
	}
	q := NewNativeGoldQuery(store)
	q.now = func() time.Time { return lateNight.Add(5 * time.Second) }

	// window=day（自然日全天 09:00→次日02:30）：window_start=11-27 09:00、保留 12:15 连续日盘点、prev_close 必须为 11-26 收盘价 765.0
	dayWin, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeDay)
	if err != nil {
		t.Fatalf("day window error: %v", err)
	}
	if !dayWin.Start.Equal(dayStart) || !dayWin.End.Equal(lateNight) {
		t.Fatalf("day window = [%v, %v], want [%v, %v]", dayWin.Start, dayWin.End, dayStart, lateNight)
	}
	if dayWin.PrevClose != 765.0 {
		t.Fatalf("day window prev_close = %v, want 765.0 (prior natural day close)", dayWin.PrevClose)
	}
	hasMidday := false
	for _, p := range dayWin.Points {
		if p.Time.Equal(midday) && p.Price == 780.5 {
			hasMidday = true
		}
	}
	if !hasMidday {
		t.Fatalf("expected continuous midday point 12:15 to be preserved, got %+v", dayWin.Points)
	}

	// window=session（单盘口夜盘 20:00→02:30）：与交易所官方切换一致，prev_close 沿用 784.0
	sessWin, err := q.GetGoldRealtimeWindow(context.Background(), domain.RealtimeWindowModeSession)
	if err != nil {
		t.Fatalf("session window error: %v", err)
	}
	if sessWin.PrevClose != 784.0 {
		t.Fatalf("session window prev_close = %v, want 784.0", sessWin.PrevClose)
	}
}
