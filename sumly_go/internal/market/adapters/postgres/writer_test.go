package postgres

import (
	"math"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

func TestMergeIntradayRowsPreservesDaySessionDeduplicatesAndPrunes48Hours(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	latest := time.Date(2026, 11, 27, 23, 22, 0, 0, tz)
	expired := latest.Add(-48*time.Hour - time.Minute)  // 超过 48h，应裁剪
	boundary := latest.Add(-48 * time.Hour)             // 恰在 48h 边界，保留
	dayOpen := time.Date(2026, 11, 27, 9, 0, 0, 0, tz)  // 当日日盘
	dayMid := time.Date(2026, 11, 27, 12, 30, 0, 0, tz) // 日盘 11:31~13:29 连续交易
	dayClose := time.Date(2026, 11, 27, 15, 30, 0, 0, tz)
	nightOpen := time.Date(2026, 11, 27, 20, 0, 0, 0, tz)

	existing := []intradayRow{
		{Time: expired, Price: 740.0},
		{Time: boundary, Price: 750.0},
		{Time: dayOpen, Price: 765.0},
		{Time: dayMid, Price: 780.0},
		{Time: dayClose, Price: 784.0},
		{Time: nightOpen, Price: 785.0},
	}
	// 夜盘新抓取仅返回夜盘窗口（不含白天日盘），且修正了 20:00 价格
	incoming := []domain.IntradayPoint{
		{Time: latest, Price: 779.2},
		{Time: nightOpen, Price: 785.5},
	}

	merged, gotLatest, err := mergeIntradayRows(existing, incoming)
	if err != nil {
		t.Fatalf("mergeIntradayRows: %v", err)
	}
	if !gotLatest.Equal(latest) {
		t.Fatalf("latest = %v, want %v", gotLatest, latest)
	}
	if len(merged) != 6 {
		t.Fatalf("len(merged) = %d, want 6: %+v", len(merged), merged)
	}
	want := []struct {
		ts    time.Time
		price float64
	}{
		{boundary, 750.0},
		{dayOpen, 765.0},
		{dayMid, 780.0},
		{dayClose, 784.0},
		{nightOpen, 785.5}, // incoming 覆盖同时间戳旧值
		{latest, 779.2},
	}
	for i, w := range want {
		if !merged[i].Time.Equal(w.ts) || merged[i].Price != w.price {
			t.Fatalf("merged[%d] = (%v, %v), want (%v, %v)", i, merged[i].Time, merged[i].Price, w.ts, w.price)
		}
	}
}

func TestMergeIntradayRowsRejectsEmptyOrInvalidIncoming(t *testing.T) {
	now := time.Now().UTC()
	if _, _, err := mergeIntradayRows(nil, nil); err == nil {
		t.Fatal("expected error for empty incoming")
	}
	for _, bad := range []domain.IntradayPoint{
		{Time: time.Time{}, Price: 780},
		{Time: now, Price: 0},
		{Time: now, Price: -1},
		{Time: now, Price: math.NaN()},
		{Time: now, Price: math.Inf(1)},
	} {
		if _, _, err := mergeIntradayRows(nil, []domain.IntradayPoint{bad}); err == nil {
			t.Fatalf("expected error for invalid incoming point %+v", bad)
		}
	}
}
