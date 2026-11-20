package postgres

import (
	"context"
	"time"

	macrosqlc "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Writer owns only write/ingestion mutations for macro indicators; no read queries are exposed.
type Writer struct {
	pool    *pgxpool.Pool
	queries *macrosqlc.Queries
}

var _ ports.MacroWriteStore = (*Writer)(nil)

func NewWriter(pool *pgxpool.Pool) *Writer {
	return &Writer{pool: pool, queries: macrosqlc.New(pool)}
}

func (w *Writer) SeedSeries(ctx context.Context, catalog []domain.SeriesMeta) error {
	if len(catalog) == 0 {
		return nil
	}
	tx, err := w.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	q := w.queries.WithTx(tx)
	for _, s := range catalog {
		if err := q.UpsertMacroSeries(ctx, macrosqlc.UpsertMacroSeriesParams{
			SeriesID:     s.SeriesID,
			NameZh:       s.NameZh,
			Section:      s.Section,
			Unit:         s.Unit,
			Frequency:    s.Frequency,
			Source:       s.Source,
			GoldRelation: s.GoldRelation,
			PlainNote:    s.PlainNote,
			DisplayOrder: int32(s.DisplayOrder),
		}); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (w *Writer) UpsertObservations(ctx context.Context, seriesID string, observations []domain.Observation) error {
	clean := domain.SanitizeObservations(observations)
	if len(clean) == 0 {
		return nil
	}
	const chunkSize = 2000
	for start := 0; start < len(clean); start += chunkSize {
		end := start + chunkSize
		if end > len(clean) {
			end = len(clean)
		}
		chunk := clean[start:end]
		params := macrosqlc.UpsertMacroObservationsParams{
			SeriesID:  seriesID,
			ObsDates:  make([]pgtype.Date, 0, len(chunk)),
			ObsValues: make([]float64, 0, len(chunk)),
		}
		for _, o := range chunk {
			params.ObsDates = append(params.ObsDates, timeToPGDate(o.Date))
			params.ObsValues = append(params.ObsValues, o.Value)
		}
		if err := w.queries.UpsertMacroObservations(ctx, params); err != nil {
			return err
		}
	}
	return nil
}

func (w *Writer) UpsertCotObservations(ctx context.Context, seriesID string, observations []domain.CotObservation) error {
	clean := domain.SanitizeCotObservations(observations)
	if len(clean) == 0 {
		return nil
	}
	const chunkSize = 1000
	for start := 0; start < len(clean); start += chunkSize {
		end := start + chunkSize
		if end > len(clean) {
			end = len(clean)
		}
		chunk := clean[start:end]
		params := macrosqlc.UpsertMacroCotObservationsParams{
			SeriesID:      seriesID,
			ObsDates:      make([]pgtype.Date, 0, len(chunk)),
			MmLongs:       make([]float64, 0, len(chunk)),
			MmShorts:      make([]float64, 0, len(chunk)),
			MmNets:        make([]float64, 0, len(chunk)),
			SwapLongs:     make([]float64, 0, len(chunk)),
			SwapShorts:    make([]float64, 0, len(chunk)),
			SwapNets:      make([]float64, 0, len(chunk)),
			OpenInterests: make([]float64, 0, len(chunk)),
		}
		for _, o := range chunk {
			params.ObsDates = append(params.ObsDates, timeToPGDate(o.Date))
			params.MmLongs = append(params.MmLongs, o.MMLong)
			params.MmShorts = append(params.MmShorts, o.MMShort)
			params.MmNets = append(params.MmNets, o.MMNet)
			params.SwapLongs = append(params.SwapLongs, o.SwapLong)
			params.SwapShorts = append(params.SwapShorts, o.SwapShort)
			params.SwapNets = append(params.SwapNets, o.SwapNet)
			params.OpenInterests = append(params.OpenInterests, o.OpenInterest)
		}
		if err := w.queries.UpsertMacroCotObservations(ctx, params); err != nil {
			return err
		}
	}
	return nil
}

func (w *Writer) UpsertTemperatureDaily(ctx context.Context, modelVersion string, points []domain.TemperatureDailyPoint) error {
	if len(points) == 0 {
		return nil
	}
	tx, err := w.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	q := w.queries.WithTx(tx)
	for _, pt := range points {
		payload, err := marshalSnapshotPayload(pt.Snapshot)
		if err != nil {
			return err
		}
		missing := pt.MissingFactors
		if missing == nil {
			missing = []string{}
		}
		var goldPrice pgtype.Float8
		if pt.GoldPriceUSD != nil && domain.IsFinite(*pt.GoldPriceUSD) {
			goldPrice = pgtype.Float8{Float64: *pt.GoldPriceUSD, Valid: true}
		}
		if err := q.UpsertMacroTemperatureDaily(ctx, macrosqlc.UpsertMacroTemperatureDailyParams{
			ModelVersion:   modelVersion,
			ObsDate:        timeToPGDate(pt.Date),
			Score:          pt.Score,
			Level:          pt.Level,
			Degraded:       pt.Degraded,
			MissingFactors: missing,
			GoldPriceUsd:   goldPrice,
			PayloadJson:    payload,
		}); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (w *Writer) UpsertSyncState(ctx context.Context, state domain.SyncState) error {
	params := macrosqlc.UpsertMacroSyncStateParams{
		SeriesID:  state.SeriesID,
		Source:    state.Source,
		Status:    state.Status,
		LastError: state.LastError,
		RowCount:  int32(state.RowCount),
	}
	if state.LastSyncedAt != nil {
		params.LastSyncedAt = pgtype.Timestamptz{Time: state.LastSyncedAt.UTC(), Valid: true}
	}
	if state.LastSuccessAt != nil {
		params.LastSuccessAt = pgtype.Timestamptz{Time: state.LastSuccessAt.UTC(), Valid: true}
	}
	if state.LatestObsDate != nil {
		params.LatestObsDate = timeToPGDate(*state.LatestObsDate)
	}
	return w.queries.UpsertMacroSyncState(ctx, params)
}

func timeToPGDate(t time.Time) pgtype.Date {
	y, m, d := t.UTC().Date()
	return pgtype.Date{Time: time.Date(y, m, d, 0, 0, 0, 0, time.UTC), Valid: true}
}
