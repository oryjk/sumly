package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"time"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

const intradayRetentionWindow = 48 * time.Hour

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

// SaveIntraday 在事务内锁定当前品种快照并与既有分钟点按时间戳合并（去重、升序、保留最近 48 小时），
// 防止上游窗口滚动或夜盘快照整行覆盖抹掉白天日盘数据；早于既有 event_at 的陈旧快照保持单调拒绝。
func (r *Writer) SaveIntraday(ctx context.Context, points []domain.IntradayPoint) error {
	incomingRows, incomingEnd, err := validateIncomingIntraday(points)
	if err != nil {
		return err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var (
		existingEventAt pgtype.Timestamptz
		existingData    []byte
		existingRows    []intradayRow
	)
	err = tx.QueryRow(ctx,
		`SELECT event_at, points FROM market_intraday_snapshots WHERE symbol = $1 FOR UPDATE`,
		r.symbol,
	).Scan(&existingEventAt, &existingData)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if err == nil {
		if existingEventAt.Valid && incomingEnd.Before(existingEventAt.Time) {
			return nil
		}
		if len(existingData) > 0 {
			if unmarshalErr := json.Unmarshal(existingData, &existingRows); unmarshalErr != nil {
				return fmt.Errorf("decode existing intraday snapshot: %w", unmarshalErr)
			}
		}
	}

	merged, latest := mergeValidatedIntradayRows(existingRows, incomingRows)
	data, err := json.Marshal(merged)
	if err != nil {
		return err
	}
	if err := r.queries.WithTx(tx).SaveIntraday(ctx, marketsqlc.SaveIntradayParams{
		Symbol:  r.symbol,
		EventAt: timestamp(latest),
		Points:  data,
	}); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func validateIncomingIntraday(points []domain.IntradayPoint) ([]intradayRow, time.Time, error) {
	if len(points) == 0 {
		return nil, time.Time{}, fmt.Errorf("cannot replace intraday snapshot with empty data")
	}
	rows := make([]intradayRow, 0, len(points))
	var latest time.Time
	for _, p := range points {
		if p.Time.IsZero() || p.Price <= 0 || math.IsNaN(p.Price) || math.IsInf(p.Price, 0) {
			return nil, time.Time{}, fmt.Errorf("invalid intraday point")
		}
		rows = append(rows, intradayRow{Time: p.Time, Price: p.Price})
		if p.Time.After(latest) {
			latest = p.Time
		}
	}
	return rows, latest, nil
}

func mergeIntradayRows(existing []intradayRow, incoming []domain.IntradayPoint) ([]intradayRow, time.Time, error) {
	incomingRows, _, err := validateIncomingIntraday(incoming)
	if err != nil {
		return nil, time.Time{}, err
	}
	merged, latest := mergeValidatedIntradayRows(existing, incomingRows)
	return merged, latest, nil
}

func mergeValidatedIntradayRows(existing, incoming []intradayRow) ([]intradayRow, time.Time) {
	byTime := make(map[int64]intradayRow, len(existing)+len(incoming))
	for _, row := range existing {
		if row.Time.IsZero() || row.Price <= 0 || math.IsNaN(row.Price) || math.IsInf(row.Price, 0) {
			continue
		}
		byTime[row.Time.UTC().UnixMicro()] = row
	}
	for _, row := range incoming {
		byTime[row.Time.UTC().UnixMicro()] = row
	}
	merged := make([]intradayRow, 0, len(byTime))
	for _, row := range byTime {
		merged = append(merged, row)
	}
	sort.Slice(merged, func(i, j int) bool {
		return merged[i].Time.Before(merged[j].Time)
	})
	latest := merged[len(merged)-1].Time
	cutoff := latest.Add(-intradayRetentionWindow)
	kept := merged[:0]
	for _, row := range merged {
		if !row.Time.Before(cutoff) {
			kept = append(kept, row)
		}
	}
	return kept, latest
}
