package application

import (
	"context"
	"log/slog"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

type SyncSources struct {
	Treasury ports.TreasurySource
	FRED     ports.FREDSource
	Yahoo    ports.YahooSource
	SPDR     ports.SPDRSource
	CFTC     ports.CFTCSource
	Bitcoin  ports.BitcoinSource
	IMF      ports.IMFSource
	SeedCSV  ports.SeedCSVSource
}

// MacroSyncer orchestrates background data ingestion, derived calculation, and temperature computation.
// It must never be invoked from HTTP GET handlers.
type MacroSyncer struct {
	reader  ports.MacroReadStore
	writer  ports.MacroWriteStore
	sources SyncSources
	now     func() time.Time
}

func NewMacroSyncer(reader ports.MacroReadStore, writer ports.MacroWriteStore, sources SyncSources) *MacroSyncer {
	return &MacroSyncer{
		reader:  reader,
		writer:  writer,
		sources: sources,
		now:     time.Now,
	}
}

// Seed persists the indicator catalog and embedded static CSV seed data idempotently.
func (s *MacroSyncer) Seed(ctx context.Context) error {
	if err := s.writer.SeedSeries(ctx, domain.Catalog()); err != nil {
		return err
	}
	if s.sources.SeedCSV != nil {
		for _, id := range []string{domain.SeriesCBGoldNet, domain.SeriesUSDReserveShare} {
			obs, err := s.sources.SeedCSV.LoadSeries(id)
			if err != nil {
				slog.Warn("macro seed csv load failed", "series_id", id, "err", err)
				continue
			}
			if len(obs) > 0 {
				if err := s.writer.UpsertObservations(ctx, id, obs); err != nil {
					slog.Warn("macro seed csv upsert failed", "series_id", id, "err", err)
					continue
				}
				source := domain.SourceSeedCSV
				if id == domain.SeriesUSDReserveShare {
					source = domain.SourceIMF
				}
				s.recordSuccess(ctx, id, source, obs)
			}
		}
	}
	return nil
}

// SyncAll fetches all external sources independently, recalculates derived indicators, and updates daily temperature.
func (s *MacroSyncer) SyncAll(ctx context.Context) {
	if err := s.writer.SeedSeries(ctx, domain.Catalog()); err != nil {
		slog.Warn("macro seed catalog failed during sync", "err", err)
		return
	}

	// 1. Treasury Fiscal Data (US_DEBT_DAILY)
	if s.sources.Treasury != nil {
		obs, err := s.sources.Treasury.FetchUSDebtDaily(ctx)
		s.saveSeriesOutcome(ctx, domain.SeriesUSDebtDaily, domain.SourceTreasury, obs, err)
	}

	// 2. FRED (20 series; skipped with clear warning if FRED_API_KEY is unset)
	if s.sources.FRED != nil {
		if !s.sources.FRED.Configured() {
			slog.Warn("macro FRED sync skipped because FRED_API_KEY is not configured; other sources continue normally")
			now := s.now().UTC()
			for _, spec := range domain.FREDSeriesSpecs() {
				_ = s.writer.UpsertSyncState(ctx, domain.SyncState{
					SeriesID:     spec.SeriesID,
					Source:       domain.SourceFRED,
					Status:       "skipped",
					LastSyncedAt: &now,
					LastError:    "FRED_API_KEY not configured",
				})
			}
		} else {
			for _, spec := range domain.FREDSeriesSpecs() {
				if ctx.Err() != nil {
					return
				}
				obs, err := s.sources.FRED.FetchSeries(ctx, spec.SeriesID)
				if err == nil && (spec.ScaleDiv > 0 || spec.Decimals >= 0) {
					obs = scaleObservations(obs, spec.ScaleDiv, spec.Decimals)
				}
				s.saveSeriesOutcome(ctx, spec.SeriesID, domain.SourceFRED, obs, err)
			}
		}
	}

	// 3. Yahoo Finance (11 series + 518880.SS proxy for Shanghai premium)
	var etfSGEProxy []domain.Observation
	if s.sources.Yahoo != nil {
		for _, spec := range domain.YahooSeriesSpecs() {
			if ctx.Err() != nil {
				return
			}
			obs, err := s.sources.Yahoo.FetchTicker(ctx, spec.Ticker)
			s.saveSeriesOutcome(ctx, spec.SeriesID, domain.SourceYahoo, obs, err)
		}
		if ctx.Err() == nil {
			if rawETF, err := s.sources.Yahoo.FetchTicker(ctx, "518880.SS"); err == nil {
				etfSGEProxy = make([]domain.Observation, 0, len(rawETF))
				for _, o := range rawETF {
					if o.Value > 0 {
						etfSGEProxy = append(etfSGEProxy, domain.Observation{
							Date:  o.Date,
							Value: domain.RoundTo(o.Value*100.0, 2),
						})
					}
				}
			} else {
				slog.Warn("macro yahoo 518880.SS proxy fetch failed", "err", err)
			}
		}
	}

	// 4. SPDR Gold Shares real tonnes (GLD). Never mix price into tonnes on error.
	if s.sources.SPDR != nil && ctx.Err() == nil {
		obs, err := s.sources.SPDR.FetchGLDTonnes(ctx)
		s.saveSeriesOutcome(ctx, domain.SeriesGLD, domain.SourceSPDR, obs, err)
	}

	// 5. CFTC Gold COT (persisted to macro_cot_observations + mm_net mirrored to macro_observations)
	if s.sources.CFTC != nil && ctx.Err() == nil {
		cotObs, err := s.sources.CFTC.FetchGoldCot(ctx)
		if err != nil {
			s.recordError(ctx, domain.SeriesGoldCOT, domain.SourceCFTC, err)
		} else if len(cotObs) > 0 {
			if err := s.writer.UpsertCotObservations(ctx, domain.SeriesGoldCOT, cotObs); err != nil {
				s.recordError(ctx, domain.SeriesGoldCOT, domain.SourceCFTC, err)
			} else {
				mirrored := make([]domain.Observation, 0, len(cotObs))
				for _, c := range cotObs {
					mirrored = append(mirrored, domain.Observation{Date: c.Date, Value: c.MMNet})
				}
				if err := s.writer.UpsertObservations(ctx, domain.SeriesGoldCOT, mirrored); err != nil {
					s.recordError(ctx, domain.SeriesGoldCOT, domain.SourceCFTC, err)
				} else {
					s.recordSuccess(ctx, domain.SeriesGoldCOT, domain.SourceCFTC, mirrored)
				}
			}
		}
	}

	// 6. Bitcoin (Blockchain.com)
	if s.sources.Bitcoin != nil && ctx.Err() == nil {
		price, err := s.sources.Bitcoin.FetchBTCPrice(ctx)
		s.saveSeriesOutcome(ctx, domain.SeriesBTCUSD, domain.SourceBitcoin, price, err)
		if ctx.Err() == nil {
			mcap, err := s.sources.Bitcoin.FetchBTCMarketCap(ctx)
			s.saveSeriesOutcome(ctx, domain.SeriesBTCMCap, domain.SourceBitcoin, mcap, err)
		}
	}

	// 7. IMF COFER + Seed CSV
	if s.sources.IMF != nil && ctx.Err() == nil {
		obs, err := s.sources.IMF.FetchUSDReserveShare(ctx)
		s.saveSeriesOutcome(ctx, domain.SeriesUSDReserveShare, domain.SourceIMF, obs, err)
	}
	if s.sources.SeedCSV != nil && ctx.Err() == nil {
		obs, err := s.sources.SeedCSV.LoadSeries(domain.SeriesCBGoldNet)
		s.saveSeriesOutcome(ctx, domain.SeriesCBGoldNet, domain.SourceSeedCSV, obs, err)
	}

	if ctx.Err() != nil {
		return
	}

	// 8. Recompute all derived indicators & daily temperature history
	s.recomputeDerivedAndTemperature(ctx, etfSGEProxy)
}

func (s *MacroSyncer) recomputeDerivedAndTemperature(ctx context.Context, etfSGEProxy []domain.Observation) {
	baseIDs := []string{
		domain.SeriesPCEPILFE,
		domain.SeriesFYOINT,
		domain.SeriesFYFR,
		domain.SeriesFYFSGDA188S,
		domain.SeriesGFDEGDQ188S,
		domain.SeriesGoldUSD,
		domain.SeriesSilver,
		domain.SeriesOil,
		domain.SeriesDEXCHUS,
		domain.SeriesDGS10,
		domain.SeriesDGS2,
		domain.SeriesGLD,
		domain.SeriesGLDPrice,
		domain.SeriesDFII10,
		domain.SeriesDTWEXBGS,
		domain.SeriesGVZCLS,
		domain.SeriesCBGoldNet,
		domain.SeriesUSDReserveShare,
	}
	obsMap, err := s.reader.LoadObservationsBySeries(ctx, baseIDs)
	if err != nil {
		slog.Warn("macro load base observations failed", "err", err)
		return
	}

	pceYoY := domain.CalcPCEYoY(obsMap[domain.SeriesPCEPILFE])
	s.saveDerived(ctx, domain.SeriesPCEYoY, pceYoY)

	interestRatio := domain.CalcInterestRatio(obsMap[domain.SeriesFYOINT], obsMap[domain.SeriesFYFR])
	s.saveDerived(ctx, domain.SeriesInterestRatio, interestRatio)

	fiscalStress := domain.CalcFiscalStress(interestRatio, obsMap[domain.SeriesFYFSGDA188S], obsMap[domain.SeriesGFDEGDQ188S])
	s.saveDerived(ctx, domain.SeriesFiscalStress, fiscalStress)

	goldMA := domain.CalcGoldMA(obsMap[domain.SeriesGoldUSD])
	s.saveDerived(ctx, domain.SeriesGoldMA, goldMA)

	goldCNY := domain.CalcGoldCNY(obsMap[domain.SeriesGoldUSD], obsMap[domain.SeriesDEXCHUS])
	s.saveDerived(ctx, domain.SeriesGoldCNY, goldCNY)

	// Prefer existing sumly_go SGE AU9999 daily bars when available, falling back to 518880.SS * 100.
	sgeSeries := mergeSGESeries(etfSGEProxy, s.loadSGEAU9999Safe(ctx))
	shanghaiPremium := domain.CalcShanghaiPremium(sgeSeries, obsMap[domain.SeriesGoldUSD], obsMap[domain.SeriesDEXCHUS])
	s.saveDerived(ctx, domain.SeriesShanghaiPremium, shanghaiPremium)

	spread10Y2Y := domain.CalcTreasurySpread(obsMap[domain.SeriesDGS10], obsMap[domain.SeriesDGS2])
	s.saveDerived(ctx, domain.SeriesTreasury10Y2YSpread, spread10Y2Y)

	goldSilverRatio := domain.CalcRatio(obsMap[domain.SeriesGoldUSD], obsMap[domain.SeriesSilver])
	s.saveDerived(ctx, domain.SeriesGoldSilverRatio, goldSilverRatio)

	goldOilRatio := domain.CalcRatio(obsMap[domain.SeriesGoldUSD], obsMap[domain.SeriesOil])
	s.saveDerived(ctx, domain.SeriesGoldOilRatio, goldOilRatio)

	cotObs, err := s.reader.LoadCotObservations(ctx, domain.SeriesGoldCOT)
	if err != nil {
		slog.Warn("macro load cot observations failed", "err", err)
	}

	_, history := domain.ComputeTemperature(domain.TemperatureInputs{
		Gold:            obsMap[domain.SeriesGoldUSD],
		Silver:          obsMap[domain.SeriesSilver],
		GoldSilverRatio: goldSilverRatio,
		Cot:             cotObs,
		ShanghaiPremium: shanghaiPremium,
		GLDTonnes:       obsMap[domain.SeriesGLD],
		GLDPrice:        obsMap[domain.SeriesGLDPrice],
		DFII10:          obsMap[domain.SeriesDFII10],
		DTWEXBGS:        obsMap[domain.SeriesDTWEXBGS],
		GVZCLS:          obsMap[domain.SeriesGVZCLS],
		DebtToGDP:       obsMap[domain.SeriesGFDEGDQ188S],
		FiscalStress:    fiscalStress,
		CBGoldNet:       obsMap[domain.SeriesCBGoldNet],
		USDReserveShare: obsMap[domain.SeriesUSDReserveShare],
	})
	if len(history) > 0 {
		if err := s.writer.UpsertTemperatureDaily(ctx, domain.ModelVersionV1, history); err != nil {
			slog.Warn("macro upsert temperature daily failed", "err", err)
		}
	}
}

func (s *MacroSyncer) RunScheduler(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = 6 * time.Hour
	}
	if err := s.Seed(ctx); err != nil {
		slog.Warn("macro initial seed failed", "err", err)
	}
	s.SyncAll(ctx)

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.SyncAll(ctx)
		}
	}
}

func (s *MacroSyncer) loadSGEAU9999Safe(ctx context.Context) []domain.Observation {
	obs, err := s.reader.LoadSGEAU9999Daily(ctx)
	if err != nil {
		slog.Warn("macro load SGE AU9999 daily bars failed; falling back to ETF proxy", "err", err)
		return nil
	}
	return obs
}

func mergeSGESeries(etfProxy, sgeDirect []domain.Observation) []domain.Observation {
	if len(etfProxy) == 0 {
		return domain.SanitizeObservations(sgeDirect)
	}
	if len(sgeDirect) == 0 {
		return domain.SanitizeObservations(etfProxy)
	}
	merged := make([]domain.Observation, 0, len(etfProxy)+len(sgeDirect))
	merged = append(merged, etfProxy...)
	// SanitizeObservations keeps the last entry for duplicate dates, so direct SGE overrides ETF proxy.
	merged = append(merged, sgeDirect...)
	return domain.SanitizeObservations(merged)
}

func scaleObservations(obs []domain.Observation, scaleDiv float64, decimals int) []domain.Observation {
	out := make([]domain.Observation, 0, len(obs))
	for _, o := range obs {
		v := o.Value
		if scaleDiv > 0 {
			v = v / scaleDiv
		}
		if decimals >= 0 {
			v = domain.RoundTo(v, decimals)
		}
		out = append(out, domain.Observation{Date: o.Date, Value: v})
	}
	return out
}

func (s *MacroSyncer) saveSeriesOutcome(ctx context.Context, seriesID, source string, obs []domain.Observation, fetchErr error) {
	if fetchErr != nil {
		s.recordError(ctx, seriesID, source, fetchErr)
		return
	}
	if len(obs) == 0 {
		return
	}
	if err := s.writer.UpsertObservations(ctx, seriesID, obs); err != nil {
		s.recordError(ctx, seriesID, source, err)
		return
	}
	s.recordSuccess(ctx, seriesID, source, obs)
}

func (s *MacroSyncer) saveDerived(ctx context.Context, seriesID string, obs []domain.Observation) {
	if len(obs) == 0 {
		return
	}
	if err := s.writer.UpsertObservations(ctx, seriesID, obs); err != nil {
		s.recordError(ctx, seriesID, domain.SourceDerived, err)
		return
	}
	s.recordSuccess(ctx, seriesID, domain.SourceDerived, obs)
}

func (s *MacroSyncer) recordSuccess(ctx context.Context, seriesID, source string, obs []domain.Observation) {
	now := s.now().UTC()
	var latest *time.Time
	if len(obs) > 0 {
		d := obs[len(obs)-1].Date
		latest = &d
	}
	_ = s.writer.UpsertSyncState(ctx, domain.SyncState{
		SeriesID:      seriesID,
		Source:        source,
		Status:        "ok",
		LastSyncedAt:  &now,
		LastSuccessAt: &now,
		LastError:     "",
		RowCount:      len(obs),
		LatestObsDate: latest,
	})
}

func (s *MacroSyncer) recordError(ctx context.Context, seriesID, source string, err error) {
	slog.Warn("macro series sync failed", "series_id", seriesID, "source", source, "err", err)
	now := s.now().UTC()
	_ = s.writer.UpsertSyncState(ctx, domain.SyncState{
		SeriesID:     seriesID,
		Source:       source,
		Status:       "error",
		LastSyncedAt: &now,
		LastError:    err.Error(),
	})
}
