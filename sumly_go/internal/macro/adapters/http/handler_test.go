package macrohttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"github.com/gin-gonic/gin"
)

type stubReadStore struct {
	series map[string]domain.SeriesMeta
	obs    map[string][]domain.Observation
	cot    []domain.CotObservation
	temp   []domain.TemperatureDailyPoint
	states map[string]domain.SyncState
}

func (s stubReadStore) ListSeries(_ context.Context, section string) ([]domain.SeriesMeta, error) {
	out := make([]domain.SeriesMeta, 0)
	for _, meta := range domain.Catalog() {
		if section == "" || meta.Section == section {
			out = append(out, meta)
		}
	}
	return out, nil
}
func (s stubReadStore) GetSeries(_ context.Context, id string) (domain.SeriesMeta, bool, error) {
	m, ok := domain.FindSeries(id)
	return m, ok, nil
}
func (s stubReadStore) LoadObservations(_ context.Context, id string) ([]domain.Observation, error) {
	return s.obs[id], nil
}
func (s stubReadStore) LoadObservationsBySeries(_ context.Context, ids []string) (map[string][]domain.Observation, error) {
	out := make(map[string][]domain.Observation, len(ids))
	for _, id := range ids {
		out[id] = s.obs[id]
	}
	return out, nil
}
func (s stubReadStore) LoadCotObservations(_ context.Context, _ string) ([]domain.CotObservation, error) {
	return s.cot, nil
}
func (s stubReadStore) LoadTemperatureHistory(_ context.Context, _ string) ([]domain.TemperatureDailyPoint, error) {
	return s.temp, nil
}
func (s stubReadStore) GetLatestTemperature(_ context.Context, _ string) (domain.TemperatureDailyPoint, bool, error) {
	if len(s.temp) == 0 {
		return domain.TemperatureDailyPoint{}, false, nil
	}
	return s.temp[len(s.temp)-1], true, nil
}
func (s stubReadStore) ListSyncStates(_ context.Context) ([]domain.SyncState, error) {
	out := make([]domain.SyncState, 0, len(s.states))
	for _, st := range s.states {
		out = append(out, st)
	}
	return out, nil
}
func (s stubReadStore) GetSyncState(_ context.Context, id string) (domain.SyncState, bool, error) {
	st, ok := s.states[id]
	return st, ok, nil
}
func (s stubReadStore) LoadSGEAU9999Daily(_ context.Context) ([]domain.Observation, error) {
	return nil, nil
}

func TestMacroHTTPHandlersContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	now := time.Date(2026, 2, 10, 8, 0, 0, 0, time.UTC)
	d1 := time.Date(2025, 2, 10, 0, 0, 0, 0, time.UTC)
	d2 := time.Date(2026, 2, 10, 0, 0, 0, 0, time.UTC)
	price := 2880.5
	snap := domain.EmptyTemperatureSnapshot()
	snap.AsOf = "2026-02-10"
	snap.Score = 68.2
	snap.Level = domain.LevelWarm
	snap.LevelLabel = "偏热活跃"

	store := stubReadStore{
		obs: map[string][]domain.Observation{
			domain.SeriesUSDebtDaily: {{Date: d1, Value: 34.5}, {Date: d2, Value: 36.4}},
			domain.SeriesDFII10:      {{Date: d1, Value: 1.9}, {Date: d2, Value: 2.05}},
			domain.SeriesDGS10:       {{Date: d1, Value: 4.2}, {Date: d2, Value: 4.45}},
			domain.SeriesDGS2:        {{Date: d1, Value: 4.1}, {Date: d2, Value: 4.15}},
		},
		cot: []domain.CotObservation{
			{Date: d2, MMLong: 210000, MMShort: 40000, MMNet: 170000, SwapLong: 45000, SwapShort: 215000, SwapNet: -170000, OpenInterest: 500000},
		},
		temp: []domain.TemperatureDailyPoint{
			{Date: d2, Score: 68.2, Level: domain.LevelWarm, GoldPriceUSD: &price, Snapshot: &snap},
		},
		states: map[string]domain.SyncState{
			domain.SeriesUSDebtDaily: {SeriesID: domain.SeriesUSDebtDaily, Source: domain.SourceTreasury, Status: "ok", LastSyncedAt: &now, LastSuccessAt: &now, RowCount: 2, LatestObsDate: &d2},
		},
	}
	handler := NewHandler(application.NewMacroQuery(store))
	router := gin.New()
	handler.RegisterPublicRoutes(router.Group("/api/v1/app"))

	endpoints := []string{
		"/api/v1/app/macro/temperature",
		"/api/v1/app/macro/temperature/history?range=3y",
		"/api/v1/app/macro/treasury?range=5y",
		"/api/v1/app/macro/indicators",
		"/api/v1/app/macro/indicators?section=treasury_fiscal",
		"/api/v1/app/macro/indicators/US_DEBT_DAILY?range=5y",
		"/api/v1/app/macro/cot/gold?range=3y",
		"/api/v1/app/macro/sync/status",
	}
	for _, ep := range endpoints {
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, ep, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s status=%d body=%s", ep, rec.Code, rec.Body.String())
		}
		var env struct {
			Code    int             `json:"code"`
			Message string          `json:"message"`
			Data    json.RawMessage `json:"data"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
			t.Fatalf("GET %s invalid JSON envelope: %v", ep, err)
		}
		if env.Code != 0 || env.Message != "ok" {
			t.Fatalf("GET %s unexpected envelope: code=%d message=%q", ep, env.Code, env.Message)
		}
	}

	// Verify exact flat keys on indicator detail response
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/app/macro/indicators/US_DEBT_DAILY?range=5y", nil))
	var detailEnv struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &detailEnv); err != nil {
		t.Fatal(err)
	}
	expectedKeys := []string{
		"series_id", "name_zh", "section", "unit", "frequency", "source",
		"gold_relation", "plain_note", "latest_date", "latest_value",
		"change_5d", "change_20d", "change_3m", "change_yoy", "percentile_3y",
		"range", "percentiles", "last_synced_at", "sync_status", "observations",
	}
	for _, k := range expectedKeys {
		if _, exists := detailEnv.Data[k]; !exists {
			t.Errorf("indicator detail missing key %q", k)
		}
	}

	// Invalid section -> 422, unknown series -> 404, invalid range -> 422
	for _, tc := range []struct {
		url  string
		code int
	}{
		{"/api/v1/app/macro/indicators?section=nope", http.StatusUnprocessableEntity},
		{"/api/v1/app/macro/indicators/NOT_REAL", http.StatusNotFound},
		{"/api/v1/app/macro/temperature/history?range=10y", http.StatusUnprocessableEntity},
		{"/api/v1/app/macro/cot/gold?range=invalid", http.StatusUnprocessableEntity},
	} {
		out := httptest.NewRecorder()
		router.ServeHTTP(out, httptest.NewRequest(http.MethodGet, tc.url, nil))
		if out.Code != tc.code {
			t.Fatalf("GET %s expected %d, got %d body=%s", tc.url, tc.code, out.Code, out.Body.String())
		}
	}
}
