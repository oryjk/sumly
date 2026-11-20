package postgres

import (
	"context"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

func TestMacroPostgresRoundtrip(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	writer := NewWriter(pool)
	reader := NewReader(pool)

	if err := writer.SeedSeries(ctx, domain.Catalog()); err != nil {
		t.Fatalf("SeedSeries failed: %v", err)
	}
	series, err := reader.ListSeries(ctx, "")
	if err != nil {
		t.Fatalf("ListSeries failed: %v", err)
	}
	if len(series) != len(domain.Catalog()) {
		t.Fatalf("expected %d series, got %d", len(domain.Catalog()), len(series))
	}

	d1 := time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)
	d2 := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	if err := writer.UpsertObservations(ctx, domain.SeriesUSDebtDaily, []domain.Observation{
		{Date: d1, Value: 36.2146},
		{Date: d2, Value: 36.2250},
	}); err != nil {
		t.Fatalf("UpsertObservations failed: %v", err)
	}
	obs, err := reader.LoadObservations(ctx, domain.SeriesUSDebtDaily)
	if err != nil || len(obs) != 2 || obs[0].Value != 36.2146 {
		t.Fatalf("LoadObservations unexpected: obs=%+v err=%v", obs, err)
	}

	if err := writer.UpsertCotObservations(ctx, domain.SeriesGoldCOT, []domain.CotObservation{
		{Date: d1, MMLong: 200000, MMShort: 50000, MMNet: 150000, SwapLong: 40000, SwapShort: 190000, SwapNet: -150000, OpenInterest: 500000},
	}); err != nil {
		t.Fatalf("UpsertCotObservations failed: %v", err)
	}
	cot, err := reader.LoadCotObservations(ctx, domain.SeriesGoldCOT)
	if err != nil || len(cot) != 1 || cot[0].MMNet != 150000 {
		t.Fatalf("LoadCotObservations unexpected: cot=%+v err=%v", cot, err)
	}

	snap := domain.EmptyTemperatureSnapshot()
	snap.AsOf = "2026-01-03"
	snap.Score = 62.5
	snap.Level = domain.LevelWarm
	price := 2700.5
	if err := writer.UpsertTemperatureDaily(ctx, domain.ModelVersionV1, []domain.TemperatureDailyPoint{
		{Date: d2, Score: 62.5, Level: domain.LevelWarm, Degraded: true, MissingFactors: []string{domain.DimPositioning}, GoldPriceUSD: &price, Snapshot: &snap},
	}); err != nil {
		t.Fatalf("UpsertTemperatureDaily failed: %v", err)
	}
	latest, ok, err := reader.GetLatestTemperature(ctx, domain.ModelVersionV1)
	if err != nil || !ok || latest.Snapshot == nil || latest.Score != 62.5 {
		t.Fatalf("GetLatestTemperature unexpected: latest=%+v ok=%v err=%v", latest, ok, err)
	}

	now := time.Now().UTC()
	if err := writer.UpsertSyncState(ctx, domain.SyncState{
		SeriesID:      domain.SeriesUSDebtDaily,
		Source:        domain.SourceTreasury,
		Status:        "ok",
		LastSyncedAt:  &now,
		LastSuccessAt: &now,
		RowCount:      2,
		LatestObsDate: &d2,
	}); err != nil {
		t.Fatalf("UpsertSyncState failed: %v", err)
	}
	state, ok, err := reader.GetSyncState(ctx, domain.SeriesUSDebtDaily)
	if err != nil || !ok || state.Status != "ok" || state.RowCount != 2 {
		t.Fatalf("GetSyncState unexpected: state=%+v ok=%v err=%v", state, ok, err)
	}
}
