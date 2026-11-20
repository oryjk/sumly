package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

// MacroWriteStore exposes only write/ingestion mutations; it must never expose read queries.
type MacroWriteStore interface {
	SeedSeries(ctx context.Context, catalog []domain.SeriesMeta) error
	UpsertObservations(ctx context.Context, seriesID string, observations []domain.Observation) error
	UpsertCotObservations(ctx context.Context, seriesID string, observations []domain.CotObservation) error
	UpsertTemperatureDaily(ctx context.Context, modelVersion string, points []domain.TemperatureDailyPoint) error
	UpsertSyncState(ctx context.Context, state domain.SyncState) error
}
