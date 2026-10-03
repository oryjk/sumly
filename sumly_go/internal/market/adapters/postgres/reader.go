package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Reader owns only queries; no combined repository is exposed.
type Reader struct {
	pool    *pgxpool.Pool
	queries *marketsqlc.Queries
	symbol  string
	native  bool
}

var _ ports.GoldReadStore = (*Reader)(nil)

func NewReader(pool *pgxpool.Pool) *Reader {
	return &Reader{pool: pool, queries: marketsqlc.New(pool), symbol: "XAUUSD"}
}
func NewNativeReader(pool *pgxpool.Pool, symbol string) *Reader {
	return &Reader{pool: pool, queries: marketsqlc.New(pool), symbol: symbol, native: true}
}

func (r *Reader) LoadRealtime(ctx context.Context) ([]domain.RealtimePoint, error) {
	if r.native {
		rows, err := r.queries.LoadNativeSamples(ctx, r.symbol)
		if err != nil {
			return nil, err
		}
		result := make([]domain.RealtimePoint, 0, len(rows))
		for _, row := range rows {
			result = append(result, domain.RealtimePoint{Time: row.SampledAt.Time, SourceTime: row.SourceAt.Time, Price: row.Price})
		}
		return result, nil
	}
	rows, err := r.queries.LoadRealtime(ctx)
	if err != nil {
		return nil, err
	}
	result := make([]domain.RealtimePoint, 0, len(rows))
	for _, row := range rows {
		result = append(result, domain.RealtimePoint{Time: row.SampledAt.Time, SourceTime: row.SourceAt.Time, Price: row.PriceCny})
	}
	return result, nil
}

func (r *Reader) LoadDaily(ctx context.Context) ([]domain.DailyBar, error) {
	rows, err := r.queries.LoadDaily(ctx, r.symbol)
	if err != nil {
		return nil, err
	}
	result := make([]domain.DailyBar, 0, len(rows))
	zone := time.FixedZone("CST", 8*3600)
	for _, row := range rows {
		year, month, day := row.TradingDate.Time.Date()
		result = append(result, domain.DailyBar{Date: time.Date(year, month, day, 0, 0, 0, 0, zone), Open: row.Open, High: row.High, Low: row.Low, Close: row.Close})
	}
	return result, nil
}

func (r *Reader) LoadQuote(ctx context.Context) (domain.GoldQuote, bool, error) {
	row, err := r.queries.LoadQuote(ctx, r.symbol)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.GoldQuote{}, false, nil
	}
	if err != nil {
		return domain.GoldQuote{}, false, err
	}
	return domain.GoldQuote{Symbol: row.Symbol, Currency: row.Currency, Price: row.Price, Open: row.Open, High: row.High, Low: row.Low, PrevClose: row.PrevClose, USDCNY: row.UsdCny, AsOf: row.AsOf.Time, SourceDelaySeconds: int(row.SourceDelaySeconds)}, true, nil
}
func (r *Reader) LoadIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	data, err := r.queries.LoadIntraday(ctx, r.symbol)
	if errors.Is(err, pgx.ErrNoRows) {
		return []domain.IntradayPoint{}, nil
	}
	if err != nil {
		return nil, err
	}
	var rows []intradayRow
	if err = json.Unmarshal(data, &rows); err != nil {
		return nil, err
	}
	points := make([]domain.IntradayPoint, 0, len(rows))
	for _, row := range rows {
		points = append(points, domain.IntradayPoint{Time: row.Time, Price: row.Price})
	}
	return points, nil
}
