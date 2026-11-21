package application

import (
	"context"
	"fmt"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

// MacroQuery is strictly read-only and depends solely on ports.MacroReadStore.
type MacroQuery struct {
	reader ports.MacroReadStore
}

func NewMacroQuery(reader ports.MacroReadStore) *MacroQuery {
	return &MacroQuery{reader: reader}
}

func (q *MacroQuery) GetTemperature(ctx context.Context) (domain.TemperatureSnapshot, error) {
	point, ok, err := q.reader.GetLatestTemperature(ctx, domain.ModelVersionV1)
	if err != nil {
		return domain.TemperatureSnapshot{}, err
	}
	if !ok {
		return domain.EmptyTemperatureSnapshot(), nil
	}
	if point.Snapshot != nil {
		return domain.SanitizePublicTemperatureSnapshot(*point.Snapshot), nil
	}
	fallback := domain.EmptyTemperatureSnapshot()
	fallback.AsOf = domain.FormatDate(point.Date)
	fallback.Score = point.Score
	fallback.Level = point.Level
	_, fallback.LevelLabel = domain.LevelForScore(point.Score)
	fallback.Degraded = point.Degraded
	if point.MissingFactors != nil {
		fallback.MissingFactors = point.MissingFactors
	}
	return domain.SanitizePublicTemperatureSnapshot(fallback), nil
}

// GetStrategyBrief builds the protected internal personal-framework & IP content brief
// strictly from read-only persisted macro snapshots and series.
func (q *MacroQuery) GetStrategyBrief(ctx context.Context, officialAccountName string) (domain.StrategyBrief, error) {
	snap, err := q.GetTemperature(ctx)
	if err != nil {
		return domain.StrategyBrief{}, err
	}

	treasurySummary, err := q.loadTreasurySummary(ctx)
	if err != nil {
		return domain.StrategyBrief{}, err
	}

	cotObs, err := q.reader.LoadCotObservations(ctx, domain.SeriesGoldCOT)
	if err != nil {
		return domain.StrategyBrief{}, err
	}
	cleanCot := domain.SanitizeCotObservations(cotObs)
	var latestCot *domain.CotObservation
	if len(cleanCot) > 0 {
		last := cleanCot[len(cleanCot)-1]
		latestCot = &last
	}

	return domain.BuildStrategyBrief(domain.StrategyBriefInput{
		Snapshot:            snap,
		Treasury:            &treasurySummary,
		LatestCot:           latestCot,
		OfficialAccountName: officialAccountName,
	}), nil
}

func (q *MacroQuery) loadTreasurySummary(ctx context.Context) (domain.TreasurySummary, error) {
	seriesIDs := []string{
		domain.SeriesUSDebtDaily,
		domain.SeriesGFDEBTN,
		domain.SeriesGFDEGDQ188S,
		domain.SeriesInterestRatio,
		domain.SeriesFiscalStress,
		domain.SeriesDGS10,
		domain.SeriesDGS2,
		domain.SeriesTreasury10Y2YSpread,
		domain.SeriesDFII10,
		domain.SeriesT10YIE,
		domain.SeriesTLT,
	}
	obsMap, err := q.reader.LoadObservationsBySeries(ctx, seriesIDs)
	if err != nil {
		return domain.TreasurySummary{}, err
	}
	debtRaw := domain.SanitizeObservations(obsMap[domain.SeriesUSDebtDaily])
	if len(debtRaw) == 0 {
		debtRaw = domain.SanitizeObservations(obsMap[domain.SeriesGFDEBTN])
	}
	summary := domain.TreasurySummary{
		TotalDebtTrillionUSD:  latestValuePtr(debtRaw, 4),
		DebtChangeYoYTrillion: domain.CalculateChanges(debtRaw).ChangeYoY,
		DebtToGDPPct:          latestValuePtr(obsMap[domain.SeriesGFDEGDQ188S], 2),
		InterestToRevenuePct:  latestValuePtr(obsMap[domain.SeriesInterestRatio], 2),
		FiscalStressScore:     latestValuePtr(obsMap[domain.SeriesFiscalStress], 1),
		Yield10YNominalPct:    latestValuePtr(obsMap[domain.SeriesDGS10], 2),
		Yield2YNominalPct:     latestValuePtr(obsMap[domain.SeriesDGS2], 2),
		Spread10Y2YPct:        latestValuePtr(obsMap[domain.SeriesTreasury10Y2YSpread], 2),
		Yield10YRealPct:       latestValuePtr(obsMap[domain.SeriesDFII10], 2),
		Breakeven10YPct:       latestValuePtr(obsMap[domain.SeriesT10YIE], 2),
		TLTPrice:              latestValuePtr(obsMap[domain.SeriesTLT], 2),
	}
	summary.GoldImpactNote = buildTreasuryGoldImpactNote(summary)
	return summary, nil
}

func (q *MacroQuery) GetTemperatureHistory(ctx context.Context, rawRange string) (domain.Range, []domain.TemperatureDailyPoint, error) {
	rng, ok := domain.ParseRange(rawRange, domain.Range3Y, false)
	if !ok {
		return "", nil, sharederror.New(sharederror.KindValidation, "invalid range; allowed: 1y, 3y, 5y, all")
	}
	points, err := q.reader.LoadTemperatureHistory(ctx, domain.ModelVersionV1)
	if err != nil {
		return "", nil, err
	}
	if len(points) == 0 || rng == domain.RangeAll {
		if points == nil {
			points = []domain.TemperatureDailyPoint{}
		}
		return rng, points, nil
	}
	start := domain.RangeStartDate(points[len(points)-1].Date, rng)
	if start == nil {
		return rng, points, nil
	}
	filtered := make([]domain.TemperatureDailyPoint, 0, len(points))
	for _, pt := range points {
		if !pt.Date.Before(*start) {
			filtered = append(filtered, pt)
		}
	}
	return rng, filtered, nil
}

func (q *MacroQuery) GetTreasuryDashboard(ctx context.Context, rawRange string) (domain.TreasuryDashboard, error) {
	rng, ok := domain.ParseRange(rawRange, domain.Range5Y, true)
	if !ok {
		return domain.TreasuryDashboard{}, sharederror.New(sharederror.KindValidation, "invalid range; allowed: 1y, 3y, 5y, 10y, all")
	}

	cardSeriesIDs := []string{
		domain.SeriesUSDebtDaily,
		domain.SeriesGFDEGDQ188S,
		domain.SeriesFYFSGDA188S,
		domain.SeriesInterestRatio,
		domain.SeriesFiscalStress,
		domain.SeriesDGS10,
		domain.SeriesDGS2,
		domain.SeriesTreasury10Y2YSpread,
		domain.SeriesDFII10,
		domain.SeriesT10YIE,
		domain.SeriesTLT,
		domain.SeriesIEF,
		domain.SeriesSHV,
	}
	loadIDs := append(append([]string{}, cardSeriesIDs...), domain.SeriesGFDEBTN)

	obsMap, err := q.reader.LoadObservationsBySeries(ctx, loadIDs)
	if err != nil {
		return domain.TreasuryDashboard{}, err
	}

	metaByID := make(map[string]domain.SeriesMeta, len(loadIDs))
	for _, s := range domain.Catalog() {
		metaByID[s.SeriesID] = s
	}
	if stored, err := q.reader.ListSeries(ctx, ""); err == nil {
		for _, s := range stored {
			metaByID[s.SeriesID] = s
		}
	}

	debtRaw := domain.SanitizeObservations(obsMap[domain.SeriesUSDebtDaily])
	if len(debtRaw) == 0 {
		debtRaw = domain.SanitizeObservations(obsMap[domain.SeriesGFDEBTN])
	}
	realYieldRaw := domain.SanitizeObservations(obsMap[domain.SeriesDFII10])
	nominalYieldRaw := domain.SanitizeObservations(obsMap[domain.SeriesDGS10])

	summary := domain.TreasurySummary{
		TotalDebtTrillionUSD:  latestValuePtr(debtRaw, 4),
		DebtChangeYoYTrillion: domain.CalculateChanges(debtRaw).ChangeYoY,
		DebtToGDPPct:          latestValuePtr(obsMap[domain.SeriesGFDEGDQ188S], 2),
		InterestToRevenuePct:  latestValuePtr(obsMap[domain.SeriesInterestRatio], 2),
		FiscalStressScore:     latestValuePtr(obsMap[domain.SeriesFiscalStress], 1),
		Yield10YNominalPct:    latestValuePtr(nominalYieldRaw, 2),
		Yield2YNominalPct:     latestValuePtr(obsMap[domain.SeriesDGS2], 2),
		Spread10Y2YPct:        latestValuePtr(obsMap[domain.SeriesTreasury10Y2YSpread], 2),
		Yield10YRealPct:       latestValuePtr(realYieldRaw, 2),
		Breakeven10YPct:       latestValuePtr(obsMap[domain.SeriesT10YIE], 2),
		TLTPrice:              latestValuePtr(obsMap[domain.SeriesTLT], 2),
	}
	summary.GoldImpactNote = buildTreasuryGoldImpactNote(summary)

	cards := make([]domain.IndicatorSummary, 0, len(cardSeriesIDs))
	var latestAsOf time.Time
	for _, id := range cardSeriesIDs {
		meta, exists := metaByID[id]
		if !exists {
			continue
		}
		card := domain.BuildIndicatorSummary(meta, obsMap[id])
		if card.LatestDate != nil && card.LatestDate.After(latestAsOf) {
			latestAsOf = *card.LatestDate
		}
		cards = append(cards, card)
	}

	return domain.TreasuryDashboard{
		AsOf:               domain.FormatDate(latestAsOf),
		Summary:            summary,
		Cards:              cards,
		DebtSeries:         domain.FilterObservationsByRange(debtRaw, rng),
		RealYieldSeries:    domain.FilterObservationsByRange(realYieldRaw, rng),
		NominalYieldSeries: domain.FilterObservationsByRange(nominalYieldRaw, rng),
	}, nil
}

func (q *MacroQuery) ListIndicators(ctx context.Context, section string) ([]domain.SectionWithIndicators, error) {
	section = strings.TrimSpace(section)
	if section != "" && !domain.IsValidSection(section) {
		return nil, sharederror.New(sharederror.KindValidation, "invalid section id")
	}

	seriesList, err := q.reader.ListSeries(ctx, section)
	if err != nil {
		return nil, err
	}
	if len(seriesList) == 0 {
		// Cold-start graceful metadata fallback before background seeding completes.
		for _, meta := range domain.Catalog() {
			if section == "" || meta.Section == section {
				seriesList = append(seriesList, meta)
			}
		}
	}

	ids := make([]string, 0, len(seriesList))
	for _, s := range seriesList {
		ids = append(ids, s.SeriesID)
	}
	obsMap, err := q.reader.LoadObservationsBySeries(ctx, ids)
	if err != nil {
		return nil, err
	}

	bySection := make(map[string][]domain.IndicatorSummary)
	for _, meta := range seriesList {
		bySection[meta.Section] = append(bySection[meta.Section], domain.BuildIndicatorSummary(meta, obsMap[meta.SeriesID]))
	}

	sections := domain.Sections()
	out := make([]domain.SectionWithIndicators, 0, len(sections))
	for _, sec := range sections {
		if section != "" && sec.ID != section {
			continue
		}
		indicators := bySection[sec.ID]
		if indicators == nil {
			indicators = []domain.IndicatorSummary{}
		}
		out = append(out, domain.SectionWithIndicators{
			Section:    sec,
			Indicators: indicators,
		})
	}
	return out, nil
}

func (q *MacroQuery) GetIndicatorDetail(ctx context.Context, seriesID, rawRange string) (domain.IndicatorDetail, error) {
	seriesID = strings.TrimSpace(seriesID)
	if seriesID == "" {
		return domain.IndicatorDetail{}, sharederror.New(sharederror.KindValidation, "series_id is required")
	}
	rng, ok := domain.ParseRange(rawRange, domain.Range5Y, true)
	if !ok {
		return domain.IndicatorDetail{}, sharederror.New(sharederror.KindValidation, "invalid range; allowed: 1y, 3y, 5y, 10y, all")
	}

	meta, found, err := q.reader.GetSeries(ctx, seriesID)
	if err != nil {
		return domain.IndicatorDetail{}, err
	}
	if !found {
		meta, found = domain.FindSeries(seriesID)
		if !found {
			return domain.IndicatorDetail{}, sharederror.New(sharederror.KindNotFound, fmt.Sprintf("indicator %s not found", seriesID))
		}
	}

	obs, err := q.reader.LoadObservations(ctx, seriesID)
	if err != nil {
		return domain.IndicatorDetail{}, err
	}
	clean := domain.SanitizeObservations(obs)
	summary := domain.BuildIndicatorSummary(meta, clean)
	percentiles := domain.CalculatePercentiles(clean)
	filtered := domain.FilterObservationsByRange(clean, rng)

	syncStatus := "pending"
	var lastSyncedAt *time.Time
	if state, ok, err := q.reader.GetSyncState(ctx, seriesID); err == nil && ok {
		syncStatus = state.Status
		lastSyncedAt = state.LastSyncedAt
	}

	return domain.IndicatorDetail{
		Summary:      summary,
		Range:        rng,
		Percentiles:  percentiles,
		LastSyncedAt: lastSyncedAt,
		SyncStatus:   syncStatus,
		Observations: filtered,
	}, nil
}

func (q *MacroQuery) GetGoldCot(ctx context.Context, rawRange string) (domain.CotDashboard, error) {
	rng, ok := domain.ParseRange(rawRange, domain.Range3Y, false)
	if !ok {
		return domain.CotDashboard{}, sharederror.New(sharederror.KindValidation, "invalid range; allowed: 1y, 3y, 5y, all")
	}
	obs, err := q.reader.LoadCotObservations(ctx, domain.SeriesGoldCOT)
	if err != nil {
		return domain.CotDashboard{}, err
	}
	clean := domain.SanitizeCotObservations(obs)
	var latest *domain.CotObservation
	if len(clean) > 0 {
		l := clean[len(clean)-1]
		latest = &l
	}
	points := domain.FilterCotByRange(clean, rng)
	return domain.CotDashboard{
		SeriesID: domain.SeriesGoldCOT,
		Range:    rng,
		Latest:   latest,
		Points:   points,
	}, nil
}

func (q *MacroQuery) GetSyncStatus(ctx context.Context) (domain.SyncStatusOverview, error) {
	states, err := q.reader.ListSyncStates(ctx)
	if err != nil {
		return domain.SyncStatusOverview{}, err
	}
	byID := make(map[string]domain.SyncState, len(states))
	for _, st := range states {
		byID[st.SeriesID] = st
	}

	catalog := domain.Catalog()
	overview := domain.SyncStatusOverview{
		TotalSeries: len(catalog),
		States:      make([]domain.SyncState, 0, len(catalog)),
	}
	for _, meta := range catalog {
		st, ok := byID[meta.SeriesID]
		if !ok {
			st = domain.SyncState{
				SeriesID: meta.SeriesID,
				Source:   meta.Source,
				Status:   "pending",
			}
		}
		switch st.Status {
		case "ok":
			overview.OKCount++
		case "error":
			overview.ErrorCount++
		case "skipped":
			overview.SkippedCount++
		default:
			overview.PendingCount++
		}
		if st.LastSyncedAt != nil {
			if overview.LastSyncedAt == nil || st.LastSyncedAt.After(*overview.LastSyncedAt) {
				t := *st.LastSyncedAt
				overview.LastSyncedAt = &t
			}
		}
		overview.States = append(overview.States, st)
	}
	return overview, nil
}

func latestValuePtr(obs []domain.Observation, decimals int) *float64 {
	clean := domain.SanitizeObservations(obs)
	if len(clean) == 0 {
		return nil
	}
	v := domain.RoundTo(clean[len(clean)-1].Value, decimals)
	return &v
}

func buildTreasuryGoldImpactNote(s domain.TreasurySummary) string {
	parts := make([]string, 0, 3)
	if s.TotalDebtTrillionUSD != nil {
		if s.DebtChangeYoYTrillion != nil {
			parts = append(parts, fmt.Sprintf("美债总规模达 %.2f 万亿美元（同比 %+.2f 万亿），持续扩张长期支撑黄金信用替代逻辑", *s.TotalDebtTrillionUSD, *s.DebtChangeYoYTrillion))
		} else {
			parts = append(parts, fmt.Sprintf("美债总规模达 %.2f 万亿美元，债务规模高位构成黄金中长期支撑", *s.TotalDebtTrillionUSD))
		}
	}
	if s.Yield10YRealPct != nil {
		if *s.Yield10YRealPct >= 1.8 {
			parts = append(parts, fmt.Sprintf("10Y 实际利率 %.2f%% 处于偏高水平，短期对金价构成机会成本约束", *s.Yield10YRealPct))
		} else if *s.Yield10YRealPct <= 0.8 {
			parts = append(parts, fmt.Sprintf("10Y 实际利率 %.2f%% 偏低，显著利好无息黄金配置", *s.Yield10YRealPct))
		} else {
			parts = append(parts, fmt.Sprintf("10Y 实际利率 %.2f%% 处于温和区间", *s.Yield10YRealPct))
		}
	}
	if s.FiscalStressScore != nil {
		if *s.FiscalStressScore >= 65 {
			parts = append(parts, fmt.Sprintf("财政压力指数 %.1f 偏高，强化长期顺风", *s.FiscalStressScore))
		} else {
			parts = append(parts, fmt.Sprintf("财政压力指数 %.1f", *s.FiscalStressScore))
		}
	}
	if len(parts) == 0 {
		return "美债与利率数据正在同步中，同步完成后将自动生成黄金影响解读。"
	}
	return strings.Join(parts, "；") + "。"
}
