package postgres

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Writer owns only ingestion; no combined repository is exposed.
type Writer struct {
	pool    *pgxpool.Pool
	queries *marketsqlc.Queries
	symbol  string
	native  bool
}

var _ ports.GoldWriteStore = (*Writer)(nil)

func NewWriter(pool *pgxpool.Pool) *Writer {
	return &Writer{pool: pool, queries: marketsqlc.New(pool), symbol: "XAUUSD"}
}
func NewNativeWriter(pool *pgxpool.Pool, symbol string) *Writer {
	return &Writer{pool: pool, queries: marketsqlc.New(pool), symbol: symbol, native: true}
}

func (r *Writer) SaveRealtime(ctx context.Context, p domain.RealtimePoint) error {
	if r.native {
		return r.queries.SaveNativeSample(ctx, marketsqlc.SaveNativeSampleParams{Instrument: r.symbol, Bucket: timestamp(p.Time.Truncate(5 * time.Second)), SampledAt: timestamp(p.Time), SourceAt: timestamp(p.SourceTime), Price: p.Price})
	}
	return r.queries.SaveRealtime(ctx, marketsqlc.SaveRealtimeParams{
		Bucket: timestamp(p.Time.Truncate(5 * time.Second)), SampledAt: timestamp(p.Time), SourceAt: timestamp(p.SourceTime), PriceCny: p.Price,
	})
}

func (r *Writer) PruneRealtime(ctx context.Context) error {
	if r.native {
		return r.queries.PruneNativeSamples(ctx, r.symbol)
	}
	return r.queries.PruneRealtime(ctx)
}

func (r *Writer) SaveDaily(ctx context.Context, bars []domain.DailyBar) error {
	if len(bars) == 0 {
		return nil
	}
	params := marketsqlc.SaveDailyParams{Symbol: r.symbol}
	// DATE 使用交易日的年月日，不能把北京时间零点先转换成 UTC 的前一天。
	for _, bar := range bars {
		year, month, day := bar.Date.Date()
		params.Dates = append(params.Dates, pgtype.Date{Time: time.Date(year, month, day, 0, 0, 0, 0, time.UTC), Valid: true})
		params.Opens = append(params.Opens, bar.Open)
		params.Highs = append(params.Highs, bar.High)
		params.Lows = append(params.Lows, bar.Low)
		params.Closes = append(params.Closes, bar.Close)
	}
	return r.queries.SaveDaily(ctx, params)
}

func timestamp(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: true} }

func (r *Writer) SaveQuote(ctx context.Context, q domain.GoldQuote) error {
	return r.queries.SaveQuote(ctx, marketsqlc.SaveQuoteParams{Symbol: r.symbol, Currency: q.Currency, Price: q.Price, Open: q.Open, High: q.High, Low: q.Low, PrevClose: q.PrevClose, UsdCny: q.USDCNY, AsOf: timestamp(q.AsOf), SourceDelaySeconds: int32(q.SourceDelaySeconds)})
}
func (r *Writer) SaveIntraday(ctx context.Context, points []domain.IntradayPoint) error {
	if len(points) == 0 {
		return fmt.Errorf("cannot replace intraday snapshot with empty data")
	}
	rows := make([]intradayRow, 0, len(points))
	var end time.Time
	for _, p := range points {
		rows = append(rows, intradayRow{Time: p.Time, Price: p.Price})
		if p.Time.After(end) {
			end = p.Time
		}
	}
	data, err := json.Marshal(rows)
	if err != nil {
		return err
	}
	return r.queries.SaveIntraday(ctx, marketsqlc.SaveIntradayParams{Symbol: r.symbol, EventAt: timestamp(end), Points: data})
}
