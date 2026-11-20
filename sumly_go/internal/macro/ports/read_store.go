package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

// MacroReadStore exposes only read queries; it must never mutate state or call external providers.
type MacroReadStore interface {
	ListSeries(ctx context.Context, section string) ([]domain.SeriesMeta, error)
	GetSeries(ctx context.Context, seriesID string) (domain.SeriesMeta, bool, error)
	LoadObservations(ctx context.Context, seriesID string) ([]domain.Observation, error)
	LoadObservationsBySeries(ctx context.Context, seriesIDs []string) (map[string][]domain.Observation, error)
	LoadCotObservations(ctx context.Context, seriesID string) ([]domain.CotObservation, error)
	LoadTemperatureHistory(ctx context.Context, modelVersion string) ([]domain.TemperatureDailyPoint, error)
	GetLatestTemperature(ctx context.Context, modelVersion string) (domain.TemperatureDailyPoint, bool, error)
	ListSyncStates(ctx context.Context) ([]domain.SyncState, error)
	GetSyncState(ctx context.Context, seriesID string) (domain.SyncState, bool, error)
	LoadSGEAU9999Daily(ctx context.Context) ([]domain.Observation, error)
}
