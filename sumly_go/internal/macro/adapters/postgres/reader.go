package postgres

import (
	"context"
	"errors"
	"time"

	macrosqlc "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Reader owns only read queries for macro indicators; no mutation methods are exposed.
type Reader struct {
	queries *macrosqlc.Queries
}

var _ ports.MacroReadStore = (*Reader)(nil)

func NewReader(pool *pgxpool.Pool) *Reader {
	return &Reader{queries: macrosqlc.New(pool)}
}

func (r *Reader) ListSeries(ctx context.Context, section string) ([]domain.SeriesMeta, error) {
	if section != "" {
		rows, err := r.queries.ListMacroSeriesBySection(ctx, section)
		if err != nil {
			return nil, err
		}
		out := make([]domain.SeriesMeta, 0, len(rows))
		for _, row := range rows {
			out = append(out, domain.SeriesMeta{
				SeriesID:     row.SeriesID,
				NameZh:       row.NameZh,
				Section:      row.Section,
				Unit:         row.Unit,
				Frequency:    row.Frequency,
				Source:       row.Source,
				GoldRelation: row.GoldRelation,
				PlainNote:    row.PlainNote,
				DisplayOrder: int(row.DisplayOrder),
			})
		}
		return out, nil
	}
	rows, err := r.queries.ListMacroSeries(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]domain.SeriesMeta, 0, len(rows))
	for _, row := range rows {
		out = append(out, domain.SeriesMeta{
			SeriesID:     row.SeriesID,
			NameZh:       row.NameZh,
			Section:      row.Section,
			Unit:         row.Unit,
			Frequency:    row.Frequency,
			Source:       row.Source,
			GoldRelation: row.GoldRelation,
			PlainNote:    row.PlainNote,
			DisplayOrder: int(row.DisplayOrder),
		})
	}
	return out, nil
}

func (r *Reader) GetSeries(ctx context.Context, seriesID string) (domain.SeriesMeta, bool, error) {
	row, err := r.queries.GetMacroSeries(ctx, seriesID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.SeriesMeta{}, false, nil
	}
	if err != nil {
		return domain.SeriesMeta{}, false, err
	}
	return domain.SeriesMeta{
		SeriesID:     row.SeriesID,
		NameZh:       row.NameZh,
		Section:      row.Section,
		Unit:         row.Unit,
		Frequency:    row.Frequency,
		Source:       row.Source,
		GoldRelation: row.GoldRelation,
		PlainNote:    row.PlainNote,
		DisplayOrder: int(row.DisplayOrder),
	}, true, nil
}

func (r *Reader) LoadObservations(ctx context.Context, seriesID string) ([]domain.Observation, error) {
	rows, err := r.queries.LoadMacroObservations(ctx, seriesID)
	if err != nil {
		return nil, err
	}
	out := make([]domain.Observation, 0, len(rows))
	for _, row := range rows {
		if !row.ObsDate.Valid {
			continue
		}
		out = append(out, domain.Observation{
			Date:  pgDateToTime(row.ObsDate),
			Value: row.Value,
		})
	}
	return out, nil
}

func (r *Reader) LoadObservationsBySeries(ctx context.Context, seriesIDs []string) (map[string][]domain.Observation, error) {
	result := make(map[string][]domain.Observation, len(seriesIDs))
	if len(seriesIDs) == 0 {
		return result, nil
	}
	rows, err := r.queries.LoadMacroObservationsBySeriesIDs(ctx, seriesIDs)
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		if !row.ObsDate.Valid {
			continue
		}
		result[row.SeriesID] = append(result[row.SeriesID], domain.Observation{
			Date:  pgDateToTime(row.ObsDate),
			Value: row.Value,
		})
	}
	return result, nil
}

func (r *Reader) LoadCotObservations(ctx context.Context, seriesID string) ([]domain.CotObservation, error) {
	rows, err := r.queries.LoadMacroCotObservations(ctx, seriesID)
	if err != nil {
		return nil, err
	}
	out := make([]domain.CotObservation, 0, len(rows))
	for _, row := range rows {
		if !row.ObsDate.Valid {
			continue
		}
		out = append(out, domain.CotObservation{
			Date:         pgDateToTime(row.ObsDate),
			MMLong:       row.MmLong,
			MMShort:      row.MmShort,
			MMNet:        row.MmNet,
			SwapLong:     row.SwapLong,
			SwapShort:    row.SwapShort,
			SwapNet:      row.SwapNet,
			OpenInterest: row.OpenInterest,
		})
	}
	return out, nil
}

func (r *Reader) LoadTemperatureHistory(ctx context.Context, modelVersion string) ([]domain.TemperatureDailyPoint, error) {
	rows, err := r.queries.LoadMacroTemperatureHistory(ctx, modelVersion)
	if err != nil {
		return nil, err
	}
	out := make([]domain.TemperatureDailyPoint, 0, len(rows))
	for _, row := range rows {
		if !row.ObsDate.Valid {
			continue
		}
		var goldPrice *float64
		if row.GoldPriceUsd.Valid {
			v := row.GoldPriceUsd.Float64
			goldPrice = &v
		}
		missing := row.MissingFactors
		if missing == nil {
			missing = []string{}
		}
		out = append(out, domain.TemperatureDailyPoint{
			Date:           pgDateToTime(row.ObsDate),
			Score:          row.Score,
			Level:          row.Level,
			Degraded:       row.Degraded,
			MissingFactors: missing,
			GoldPriceUSD:   goldPrice,
			Snapshot:       unmarshalSnapshotPayload(row.PayloadJson),
		})
	}
	return out, nil
}

func (r *Reader) GetLatestTemperature(ctx context.Context, modelVersion string) (domain.TemperatureDailyPoint, bool, error) {
	row, err := r.queries.GetLatestMacroTemperature(ctx, modelVersion)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.TemperatureDailyPoint{}, false, nil
	}
	if err != nil {
		return domain.TemperatureDailyPoint{}, false, err
	}
	var goldPrice *float64
	if row.GoldPriceUsd.Valid {
		v := row.GoldPriceUsd.Float64
		goldPrice = &v
	}
	missing := row.MissingFactors
	if missing == nil {
		missing = []string{}
	}
	return domain.TemperatureDailyPoint{
		Date:           pgDateToTime(row.ObsDate),
		Score:          row.Score,
		Level:          row.Level,
		Degraded:       row.Degraded,
		MissingFactors: missing,
		GoldPriceUSD:   goldPrice,
		Snapshot:       unmarshalSnapshotPayload(row.PayloadJson),
	}, true, nil
}

func (r *Reader) ListSyncStates(ctx context.Context) ([]domain.SyncState, error) {
	rows, err := r.queries.ListMacroSyncStates(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]domain.SyncState, 0, len(rows))
	for _, row := range rows {
		out = append(out, toDomainSyncState(row.SeriesID, row.Source, row.Status, row.LastSyncedAt, row.LastSuccessAt, row.LastError, int(row.RowCount), row.LatestObsDate))
	}
	return out, nil
}

func (r *Reader) GetSyncState(ctx context.Context, seriesID string) (domain.SyncState, bool, error) {
	row, err := r.queries.GetMacroSyncState(ctx, seriesID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.SyncState{}, false, nil
	}
	if err != nil {
		return domain.SyncState{}, false, err
	}
	return toDomainSyncState(row.SeriesID, row.Source, row.Status, row.LastSyncedAt, row.LastSuccessAt, row.LastError, int(row.RowCount), row.LatestObsDate), true, nil
}

func (r *Reader) LoadSGEAU9999Daily(ctx context.Context) ([]domain.Observation, error) {
	rows, err := r.queries.LoadSGEAU9999DailyCloses(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]domain.Observation, 0, len(rows))
	for _, row := range rows {
		if !row.TradingDate.Valid || !domain.IsFinite(row.Close) || row.Close <= 0 {
			continue
		}
		out = append(out, domain.Observation{
			Date:  pgDateToTime(row.TradingDate),
			Value: row.Close,
		})
	}
	return out, nil
}

func pgDateToTime(d pgtype.Date) time.Time {
	y, m, day := d.Time.Date()
	return time.Date(y, m, day, 0, 0, 0, 0, time.UTC)
}

func toDomainSyncState(
	seriesID, source, status string,
	lastSynced, lastSuccess pgtype.Timestamptz,
	lastErr string,
	rowCount int,
	latestObs pgtype.Date,
) domain.SyncState {
	st := domain.SyncState{
		SeriesID:  seriesID,
		Source:    source,
		Status:    status,
		LastError: lastErr,
		RowCount:  rowCount,
	}
	if lastSynced.Valid {
		t := lastSynced.Time.UTC()
		st.LastSyncedAt = &t
	}
	if lastSuccess.Valid {
		t := lastSuccess.Time.UTC()
		st.LastSuccessAt = &t
	}
	if latestObs.Valid {
		d := pgDateToTime(latestObs)
		st.LatestObsDate = &d
	}
	return st
}
