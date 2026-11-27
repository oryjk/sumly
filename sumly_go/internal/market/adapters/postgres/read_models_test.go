package postgres_test

import (
	"context"
	"math"
	"reflect"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestQuoteAndIntradayPersistAcrossReadersAndRejectOlderSnapshots(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	end := time.Now().Add(-48 * time.Hour).Truncate(time.Microsecond)
	for i, symbol := range []string{"AU9999", "XAUUSD", "GCZ26.CMX"} {
		writer := postgres.NewNativeWriter(pool, symbol)
		quote := domain.GoldQuote{Symbol: symbol, Currency: "USD", Price: float64(4300 + i), Open: 4200, High: 4400, Low: 4100, PrevClose: 4250, USDCNY: 7, AsOf: end, SourceDelaySeconds: 1800}
		if err := writer.SaveQuote(ctx, quote); err != nil {
			t.Fatal(err)
		}
		minutes := []domain.IntradayPoint{{Time: end.Add(-time.Minute), Price: quote.Price - 1}, {Time: end, Price: quote.Price}}
		if err := writer.SaveIntraday(ctx, minutes); err != nil {
			t.Fatal(err)
		}
		older := quote
		older.AsOf = end.Add(-time.Minute)
		older.Price = 1
		if err := writer.SaveQuote(ctx, older); err != nil {
			t.Fatal(err)
		}
		if err := writer.SaveIntraday(ctx, minutes[:1]); err != nil {
			t.Fatal(err)
		}
		if err := writer.SaveIntraday(ctx, nil); err == nil {
			t.Fatal("empty update erased snapshot")
		}
		if err := writer.SaveIntraday(ctx, []domain.IntradayPoint{{Time: end, Price: math.NaN()}}); err == nil {
			t.Fatal("invalid update accepted")
		}
		got, found, err := postgres.NewNativeReader(pool, symbol).LoadQuote(ctx)
		if err != nil || !found || !reflect.DeepEqual(got, quote) {
			t.Fatal(got, found, err)
		}
		points, err := postgres.NewNativeReader(pool, symbol).LoadIntraday(ctx)
		if err != nil || len(points) != 2 || points[1].Price != quote.Price || !points[1].Time.Equal(end) {
			t.Fatal(points, err)
		}
	}
}
func TestAllQueriesWorkWithReadOnlyDatabaseSessions(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	writer := postgres.NewWriter(pool)
	now := time.Now().Truncate(time.Microsecond)
	if err := writer.SaveQuote(ctx, domain.GoldQuote{Symbol: "XAUUSD", Price: 4300, USDCNY: 7, AsOf: now}); err != nil {
		t.Fatal(err)
	}
	if err := writer.SaveIntraday(ctx, []domain.IntradayPoint{{Time: now, Price: 4300}}); err != nil {
		t.Fatal(err)
	}
	if err := writer.SaveDaily(ctx, []domain.DailyBar{{Date: now.AddDate(0, 0, -1), Open: 4200, High: 4400, Low: 4100, Close: 4300}}); err != nil {
		t.Fatal(err)
	}
	// Every connection in this test's pool is now read-only. Ingestion is finished.
	readonly := pool.Config()
	readonly.ConnConfig.RuntimeParams["default_transaction_read_only"] = "on"
	readPool, err := pgxpool.NewWithConfig(ctx, readonly)
	if err != nil {
		t.Fatal(err)
	}
	defer readPool.Close()
	reader := postgres.NewReader(readPool)
	query := application.NewGoldQuery(reader)
	if _, err := query.GetGoldQuote(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := query.GetGoldDailyKLines(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := query.GetGoldIntraday(ctx); err != nil {
		t.Fatal(err)
	}
	if _, _, err := query.GetGoldRealtime(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := application.NewStoredGoldHistory(query, reader).GetGoldHistory(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := application.NewHistorySync(reader, nil).Sync(ctx, "xauusd", ""); err != nil {
		t.Fatal(err)
	}
}
func TestDelayedSamplesDoNotManufactureRepeatedTicks(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	writer := postgres.NewNativeWriter(pool, "GCZ26.CMX")
	end := time.Now().Add(-30 * time.Minute).Truncate(time.Microsecond)
	point := domain.RealtimePoint{Time: end, SourceTime: end, Price: 4300}
	for range 3 {
		if err := writer.SaveRealtime(ctx, point); err != nil {
			t.Fatal(err)
		}
	}
	points, err := postgres.NewNativeReader(pool, "GCZ26.CMX").LoadRealtime(ctx)
	if err != nil || len(points) != 1 || !points[0].Time.Equal(end) {
		t.Fatal(points, err)
	}
}

func TestSaveIntradayMergesDayAndNightAndPrunesBeyond48Hours(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	writer := postgres.NewNativeWriter(pool, "AU9999")
	reader := postgres.NewNativeReader(pool, "AU9999")

	tz := time.FixedZone("CST", 8*3600)
	latest := time.Date(2026, 11, 27, 23, 22, 0, 0, tz)
	expired := latest.Add(-48*time.Hour - time.Minute)
	dayOpen := time.Date(2026, 11, 27, 9, 0, 0, 0, tz)
	dayClose := time.Date(2026, 11, 27, 15, 30, 0, 0, tz)
	nightOpen := time.Date(2026, 11, 27, 20, 0, 0, 0, tz)

	if err := writer.SaveIntraday(ctx, []domain.IntradayPoint{
		{Time: expired, Price: 740.0},
		{Time: dayOpen, Price: 765.0},
		{Time: dayClose, Price: 784.0},
	}); err != nil {
		t.Fatal(err)
	}
	if err := writer.SaveIntraday(ctx, []domain.IntradayPoint{
		{Time: nightOpen, Price: 785.0},
		{Time: latest, Price: 779.2},
	}); err != nil {
		t.Fatal(err)
	}

	points, err := reader.LoadIntraday(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(points) != 4 || !points[0].Time.Equal(dayOpen) || !points[3].Time.Equal(latest) {
		t.Fatalf("expected merged day+night with expired pruned, got %+v", points)
	}
}
