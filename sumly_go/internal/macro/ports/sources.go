package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

type TreasurySource interface {
	FetchUSDebtDaily(ctx context.Context) ([]domain.Observation, error)
}

type FREDSource interface {
	Configured() bool
	FetchSeries(ctx context.Context, seriesID string) ([]domain.Observation, error)
}

type YahooSource interface {
	FetchTicker(ctx context.Context, ticker string) ([]domain.Observation, error)
}

type SPDRSource interface {
	FetchGLDTonnes(ctx context.Context) ([]domain.Observation, error)
}

type CFTCSource interface {
	FetchGoldCot(ctx context.Context) ([]domain.CotObservation, error)
}

type BitcoinSource interface {
	FetchBTCPrice(ctx context.Context) ([]domain.Observation, error)
	FetchBTCMarketCap(ctx context.Context) ([]domain.Observation, error)
}

type IMFSource interface {
	FetchUSDReserveShare(ctx context.Context) ([]domain.Observation, error)
}

type SeedCSVSource interface {
	LoadSeries(seriesID string) ([]domain.Observation, error)
}
