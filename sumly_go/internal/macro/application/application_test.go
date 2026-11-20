package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

type memMacroStore struct {
	series map[string]domain.SeriesMeta
	obs    map[string][]domain.Observation
	cot    map[string][]domain.CotObservation
	temp   []domain.TemperatureDailyPoint
	states map[string]domain.SyncState
	sge    []domain.Observation
}

func newMemMacroStore() *memMacroStore {
	return &memMacroStore{
		series: map[string]domain.SeriesMeta{},
		obs:    map[string][]domain.Observation{},
		cot:    map[string][]domain.CotObservation{},
		states: map[string]domain.SyncState{},
	}
}

var _ ports.MacroReadStore = (*memMacroStore)(nil)
var _ ports.MacroWriteStore = (*memMacroStore)(nil)

func (m *memMacroStore) SeedSeries(_ context.Context, catalog []domain.SeriesMeta) error {
	for _, s := range catalog {
		m.series[s.SeriesID] = s
	}
	return nil
}

func (m *memMacroStore) UpsertObservations(_ context.Context, seriesID string, observations []domain.Observation) error {
	m.obs[seriesID] = domain.SanitizeObservations(append(m.obs[seriesID], observations...))
	return nil
}

func (m *memMacroStore) UpsertCotObservations(_ context.Context, seriesID string, observations []domain.CotObservation) error {
	m.cot[seriesID] = domain.SanitizeCotObservations(append(m.cot[seriesID], observations...))
	return nil
}

func (m *memMacroStore) UpsertTemperatureDaily(_ context.Context, _ string, points []domain.TemperatureDailyPoint) error {
	m.temp = append([]domain.TemperatureDailyPoint(nil), points...)
	return nil
}

func (m *memMacroStore) UpsertSyncState(_ context.Context, state domain.SyncState) error {
	m.states[state.SeriesID] = state
	return nil
}

func (m *memMacroStore) ListSeries(_ context.Context, section string) ([]domain.SeriesMeta, error) {
	out := make([]domain.SeriesMeta, 0, len(m.series))
	for _, s := range domain.Catalog() {
		if stored, ok := m.series[s.SeriesID]; ok {
			if section == "" || stored.Section == section {
				out = append(out, stored)
			}
		}
	}
	return out, nil
}

func (m *memMacroStore) GetSeries(_ context.Context, seriesID string) (domain.SeriesMeta, bool, error) {
	s, ok := m.series[seriesID]
	return s, ok, nil
}

func (m *memMacroStore) LoadObservations(_ context.Context, seriesID string) ([]domain.Observation, error) {
	return m.obs[seriesID], nil
}

func (m *memMacroStore) LoadObservationsBySeries(_ context.Context, seriesIDs []string) (map[string][]domain.Observation, error) {
	out := make(map[string][]domain.Observation, len(seriesIDs))
	for _, id := range seriesIDs {
		out[id] = m.obs[id]
	}
	return out, nil
}

func (m *memMacroStore) LoadCotObservations(_ context.Context, seriesID string) ([]domain.CotObservation, error) {
	return m.cot[seriesID], nil
}

func (m *memMacroStore) LoadTemperatureHistory(_ context.Context, _ string) ([]domain.TemperatureDailyPoint, error) {
	return m.temp, nil
}

func (m *memMacroStore) GetLatestTemperature(_ context.Context, _ string) (domain.TemperatureDailyPoint, bool, error) {
	if len(m.temp) == 0 {
		return domain.TemperatureDailyPoint{}, false, nil
	}
	return m.temp[len(m.temp)-1], true, nil
}

func (m *memMacroStore) ListSyncStates(_ context.Context) ([]domain.SyncState, error) {
	out := make([]domain.SyncState, 0, len(m.states))
	for _, st := range m.states {
		out = append(out, st)
	}
	return out, nil
}

func (m *memMacroStore) GetSyncState(_ context.Context, seriesID string) (domain.SyncState, bool, error) {
	st, ok := m.states[seriesID]
	return st, ok, nil
}

func (m *memMacroStore) LoadSGEAU9999Daily(_ context.Context) ([]domain.Observation, error) {
	return m.sge, nil
}

type stubTreasury struct {
	obs []domain.Observation
}

func (s stubTreasury) FetchUSDebtDaily(context.Context) ([]domain.Observation, error) {
	return s.obs, nil
}

type stubFRED struct {
	configured bool
	data       map[string][]domain.Observation
}

func (s stubFRED) Configured() bool { return s.configured }
func (s stubFRED) FetchSeries(_ context.Context, id string) ([]domain.Observation, error) {
	return s.data[id], nil
}

type stubYahoo struct {
	data map[string][]domain.Observation
}

func (s stubYahoo) FetchTicker(_ context.Context, ticker string) ([]domain.Observation, error) {
	return s.data[ticker], nil
}

type stubSPDR struct {
	err error
}

func (s stubSPDR) FetchGLDTonnes(context.Context) ([]domain.Observation, error) {
	return nil, s.err
}

type stubCFTC struct {
	obs []domain.CotObservation
}

func (s stubCFTC) FetchGoldCot(context.Context) ([]domain.CotObservation, error) {
	return s.obs, nil
}

func TestSyncAllSkipsUnconfiguredFREDAndPreservesGLDOnSPDRError(t *testing.T) {
	store := newMemMacroStore()
	ctx := context.Background()

	// Pre-populate existing GLD tonnes in DB so we verify SPDR failure preserves them and does NOT overwrite with price.
	d0 := time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC)
	_ = store.UpsertObservations(ctx, domain.SeriesGLD, []domain.Observation{{Date: d0, Value: 900.5}})

	gold := make([]domain.Observation, 0, 40)
	silver := make([]domain.Observation, 0, 40)
	gldPrice := make([]domain.Observation, 0, 40)
	for i := 0; i < 40; i++ {
		dt := d0.AddDate(0, 0, i)
		gold = append(gold, domain.Observation{Date: dt, Value: 2600 + float64(i)*5})
		silver = append(silver, domain.Observation{Date: dt, Value: 30 + float64(i)*0.1})
		gldPrice = append(gldPrice, domain.Observation{Date: dt, Value: 240 + float64(i)*0.5})
	}

	syncer := NewMacroSyncer(store, store, SyncSources{
		Treasury: stubTreasury{obs: []domain.Observation{{Date: d0, Value: 36.2}}},
		FRED:     stubFRED{configured: false},
		Yahoo: stubYahoo{data: map[string][]domain.Observation{
			"GC=F": gold,
			"SI=F": silver,
			"GLD":  gldPrice,
		}},
		SPDR: stubSPDR{err: errors.New("spdr 503")},
		CFTC: stubCFTC{obs: []domain.CotObservation{
			{Date: d0, MMLong: 200000, MMShort: 50000, MMNet: 150000, OpenInterest: 500000},
		}},
	})
	syncer.SyncAll(ctx)

	// FRED should be skipped, not error
	if st := store.states[domain.SeriesDFII10]; st.Status != "skipped" {
		t.Fatalf("expected DFII10 status=skipped, got %+v", st)
	}
	// SPDR failed: status=error and GLD tonnes still 900.5 (never polluted with GLD price ~240)
	if st := store.states[domain.SeriesGLD]; st.Status != "error" {
		t.Fatalf("expected GLD status=error, got %+v", st)
	}
	if len(store.obs[domain.SeriesGLD]) != 1 || store.obs[domain.SeriesGLD][0].Value != 900.5 {
		t.Fatalf("GLD tonnes should remain untouched on SPDR error, got %+v", store.obs[domain.SeriesGLD])
	}
	// CFTC mm_net mirrored to macro_observations
	if len(store.obs[domain.SeriesGoldCOT]) != 1 || store.obs[domain.SeriesGoldCOT][0].Value != 150000 {
		t.Fatalf("expected GOLD_COT mm_net mirrored, got %+v", store.obs[domain.SeriesGoldCOT])
	}
	// Derived GOLD_SILVER_RATIO computed
	if len(store.obs[domain.SeriesGoldSilverRatio]) != 40 {
		t.Fatalf("expected 40 GOLD_SILVER_RATIO points, got %d", len(store.obs[domain.SeriesGoldSilverRatio]))
	}
	// Temperature computed & stored
	query := NewMacroQuery(store)
	snap, err := query.GetTemperature(ctx)
	if err != nil {
		t.Fatalf("GetTemperature failed: %v", err)
	}
	if snap.AsOf == "" || !snap.Degraded {
		t.Fatalf("expected computed degraded snapshot, got %+v", snap)
	}
}

func TestMacroQueryColdStartAndValidation(t *testing.T) {
	store := newMemMacroStore()
	query := NewMacroQuery(store)
	ctx := context.Background()

	snap, err := query.GetTemperature(ctx)
	if err != nil || !snap.Degraded || snap.AsOf != "" {
		t.Fatalf("unexpected cold start temperature: snap=%+v err=%v", snap, err)
	}
	sections, err := query.ListIndicators(ctx, "")
	if err != nil || len(sections) != 6 {
		t.Fatalf("expected 6 sections on cold start, got len=%d err=%v", len(sections), err)
	}
	if _, err := query.ListIndicators(ctx, "invalid_section"); err == nil {
		t.Fatalf("expected validation error for invalid section")
	}
	if _, err := query.GetIndicatorDetail(ctx, "UNKNOWN_SERIES", "5y"); err == nil {
		t.Fatalf("expected not found error for unknown series")
	}
}
