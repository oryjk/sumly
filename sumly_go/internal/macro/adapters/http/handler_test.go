package macrohttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestTemperaturePublicComplianceAndGuideHelp(t *testing.T) {
	gin.SetMode(gin.TestMode)
	d2 := time.Date(2026, 2, 10, 0, 0, 0, 0, time.UTC)
	price := 2880.5
	dev := -17.2
	prem := -0.42
	// Intentionally store legacy advisory copy in the backing store to verify HTTP read path sanitizes it.
	legacySnap := domain.TemperatureSnapshot{
		AsOf:            "2026-02-10",
		ModelVersion:    domain.ModelVersionV1,
		Degraded:        false,
		MissingFactors:  []string{},
		Score:           31.5,
		Level:           domain.LevelCool,
		LevelLabel:      "偏冷蓄势",
		VolatilityAlert: true,
		VolatilityNote:  "黄金隐含波动率（GVZ=28.7）处于近 3 年 91% 极端高位，建议控制单笔仓位、拉长分批节奏。",
		MacroRegime: domain.MacroRegime{
			Score:   72.0,
			Regime:  domain.RegimeTailwind,
			Label:   "长期宏观顺风",
			Summary: "建议分批建仓",
		},
		ActionGuide: domain.ActionGuide{
			Signal:              "accumulate",
			Title:               "偏冷蓄势 · 逢低加配",
			Summary:             "适合稳步定投或逢回调加仓",
			DCAMultiplier:       1.2,
			DCALabel:            "偏冷加配 1.2x",
			MA200DeviationPct:   &dev,
			MA200Note:           "低于年线，安全垫较厚",
			DomesticPremiumPct:  &prem,
			DomesticPremiumNote: "当前国内买金性价比偏高",
			Disclaimer:          "旧免责声明",
		},
		Dimensions: domain.EmptyTemperatureSnapshot().Dimensions,
	}

	store := stubReadStore{
		temp: []domain.TemperatureDailyPoint{
			{Date: d2, Score: 31.5, Level: domain.LevelCool, GoldPriceUSD: &price, Snapshot: &legacySnap},
		},
	}

	cases := []struct {
		name        string
		opts        HandlerOptions
		wantAccName string
		wantAccNote string
	}{
		{
			name:        "without official account config",
			opts:        HandlerOptions{},
			wantAccName: "",
			wantAccNote: "",
		},
		{
			name:        "with official account name only",
			opts:        HandlerOptions{OfficialAccountName: "数里黄金笔记"},
			wantAccName: "数里黄金笔记",
			wantAccNote: domain.DefaultOfficialAccountNote,
		},
		{
			name:        "with official account name and custom note",
			opts:        HandlerOptions{OfficialAccountName: "数里黄金笔记", OfficialAccountNote: "每周宏观方法论拆解"},
			wantAccName: "数里黄金笔记",
			wantAccNote: "每周宏观方法论拆解",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			handler := NewHandlerWithOptions(application.NewMacroQuery(store), tc.opts)
			router := gin.New()
			handler.RegisterPublicRoutes(router.Group("/api/v1/app"))

			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/app/macro/temperature", nil))
			if rec.Code != http.StatusOK {
				t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
			}

			var env struct {
				Code    int                 `json:"code"`
				Message string              `json:"message"`
				Data    TemperatureResponse `json:"data"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if env.Code != 0 || env.Message != "ok" {
				t.Fatalf("unexpected envelope: %+v", env)
			}
			// Backward-compatible fields preserved
			if env.Data.ActionGuide.Signal != "accumulate" || env.Data.ActionGuide.DCAMultiplier != 1.2 {
				t.Fatalf("expected backward-compatible signal/multiplier, got %+v", env.Data.ActionGuide)
			}
			if env.Data.ActionGuide.MA200DeviationPct == nil || *env.Data.ActionGuide.MA200DeviationPct != -17.2 {
				t.Fatalf("expected ma200_deviation_pct=-17.2, got %v", env.Data.ActionGuide.MA200DeviationPct)
			}
			if env.Data.ActionGuide.DomesticPremiumPct == nil || *env.Data.ActionGuide.DomesticPremiumPct != -0.42 {
				t.Fatalf("expected domestic_premium_pct=-0.42, got %v", env.Data.ActionGuide.DomesticPremiumPct)
			}
			// Advisory words must not leak in public payload
			for _, bad := range []string{"逢低加配", "建仓", "加仓", "定投", "适合", "仓位", "分批", "性价比"} {
				if strings.Contains(rec.Body.String(), bad) {
					t.Fatalf("public temperature payload leaked forbidden term %q: %s", bad, rec.Body.String())
				}
			}
			// GuideHelp checks
			if env.Data.GuideHelp == nil {
				t.Fatalf("expected guide_help present in response")
			}
			if env.Data.GuideHelp.Title != "黄金温度计说明" || len(env.Data.GuideHelp.Levels) != 5 {
				t.Fatalf("unexpected guide_help: %+v", env.Data.GuideHelp)
			}
			if env.Data.GuideHelp.OfficialAccountName != tc.wantAccName || env.Data.GuideHelp.OfficialAccountNote != tc.wantAccNote {
				t.Fatalf("guide_help account mismatch: got (%q, %q), want (%q, %q)",
					env.Data.GuideHelp.OfficialAccountName, env.Data.GuideHelp.OfficialAccountNote,
					tc.wantAccName, tc.wantAccNote)
			}
		})
	}
}

func TestInternalStrategyBriefAuthAndPayload(t *testing.T) {
	gin.SetMode(gin.TestMode)
	d1 := time.Date(2025, 2, 10, 0, 0, 0, 0, time.UTC)
	d2 := time.Date(2026, 2, 10, 0, 0, 0, 0, time.UTC)
	price := 2910.0
	snap := domain.EmptyTemperatureSnapshot()
	snap.AsOf = "2026-02-10"
	snap.Degraded = false
	snap.Score = 29.4
	snap.Level = domain.LevelCool
	snap.LevelLabel = domain.LabelForLevel(domain.LevelCool)
	snap.MacroRegime = domain.DescribeMacroRegime(domain.RegimeTailwind, 71.5)
	snap.ActionGuide = domain.BuildActionGuide(snap.MacroRegime, domain.LevelCool, 29.4, nil, nil, false)

	store := stubReadStore{
		obs: map[string][]domain.Observation{
			domain.SeriesUSDebtDaily: {{Date: d1, Value: 34.2}, {Date: d2, Value: 36.4}},
			domain.SeriesDFII10:      {{Date: d2, Value: 2.05}},
			domain.SeriesDGS10:       {{Date: d2, Value: 4.45}},
		},
		cot: []domain.CotObservation{
			{Date: d2, MMLong: 210000, MMShort: 40000, MMNet: 170000, OpenInterest: 500000},
		},
		temp: []domain.TemperatureDailyPoint{
			{Date: d2, Score: 29.4, Level: domain.LevelCool, GoldPriceUSD: &price, Snapshot: &snap},
		},
	}

	t.Run("unconfigured token returns 404 and never exposes endpoint", func(t *testing.T) {
		h := NewHandlerWithOptions(application.NewMacroQuery(store), HandlerOptions{InternalToken: ""})
		r := gin.New()
		h.RegisterInternalRoutes(r.Group("/api/v1/internal"))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil)
		req.Header.Set("X-Macro-Internal-Token", "any-token")
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("expected 404 when unconfigured, got %d body=%s", rec.Code, rec.Body.String())
		}
	})

	t.Run("configured token enforces constant-time auth via header or bearer", func(t *testing.T) {
		const secret = "super-secret-internal-token"
		h := NewHandlerWithOptions(application.NewMacroQuery(store), HandlerOptions{
			OfficialAccountName: "测试复盘号",
			InternalToken:       secret,
		})
		r := gin.New()
		h.RegisterInternalRoutes(r.Group("/api/v1/internal"))

		// Missing token -> 401
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil))
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("missing token: expected 401, got %d", rec.Code)
		}
		if strings.Contains(rec.Body.String(), secret) {
			t.Fatalf("error response must never echo token")
		}

		// Wrong token -> 401
		wrongReq := httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil)
		wrongReq.Header.Set("X-Macro-Internal-Token", "wrong-token")
		wrongRec := httptest.NewRecorder()
		r.ServeHTTP(wrongRec, wrongReq)
		if wrongRec.Code != http.StatusUnauthorized {
			t.Fatalf("wrong token: expected 401, got %d", wrongRec.Code)
		}

		// Valid X-Macro-Internal-Token -> 200
		okReq := httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil)
		okReq.Header.Set("X-Macro-Internal-Token", secret)
		okRec := httptest.NewRecorder()
		r.ServeHTTP(okRec, okReq)
		if okRec.Code != http.StatusOK {
			t.Fatalf("valid header token: expected 200, got %d body=%s", okRec.Code, okRec.Body.String())
		}

		var env struct {
			Code    int                   `json:"code"`
			Message string                `json:"message"`
			Data    StrategyBriefResponse `json:"data"`
		}
		if err := json.Unmarshal(okRec.Body.Bytes(), &env); err != nil {
			t.Fatalf("unmarshal strategy brief: %v", err)
		}
		if env.Code != 0 || env.Data.Framework.Signal != "accumulate" || env.Data.Framework.ReferencePaceMultiplier != 1.2 {
			t.Fatalf("unexpected strategy brief framework: %+v", env.Data.Framework)
		}
		if !strings.Contains(env.Data.OfficialAccountReply, "测试复盘号") || !strings.Contains(env.Data.CommunityBrief, "CFTC 黄金 COT") {
			t.Fatalf("unexpected generated templates: reply=%q brief=%q", env.Data.OfficialAccountReply, env.Data.CommunityBrief)
		}

		// Valid Authorization: Bearer <token> -> 200
		bearerReq := httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil)
		bearerReq.Header.Set("Authorization", "Bearer "+secret)
		bearerRec := httptest.NewRecorder()
		r.ServeHTTP(bearerRec, bearerReq)
		if bearerRec.Code != http.StatusOK {
			t.Fatalf("valid bearer token: expected 200, got %d body=%s", bearerRec.Code, bearerRec.Body.String())
		}
	})
}
