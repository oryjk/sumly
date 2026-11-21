package markethttp

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/gin-gonic/gin"
)

type domesticFixture struct{}

func (domesticFixture) LoadQuote(context.Context) (domain.GoldQuote, bool, error) {
	return domain.GoldQuote{Currency: "CNY", Symbol: "AU9999", Price: 946, PrevClose: 947.09, Open: 944.5, High: 946, Low: 938.5, AsOf: time.Now()}, true, nil
}
func (domesticFixture) LoadDaily(context.Context) ([]domain.DailyBar, error) {
	return []domain.DailyBar{}, nil
}
func TestInstrumentRoutesUseNativeUnitAndRejectUnknown(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	s := application.NewInstruments([]application.InstrumentMarket{{Instrument: domain.Instrument{ID: "au9999", Symbol: "AU9999", Kind: "spot", Currency: "CNY", Unit: "CNY/g", QuoteSource: "sina"}, Service: application.NewNativeGoldQuery(domesticFixture{})}})
	NewInstrumentsHandler(s).RegisterPublicRoutes(r.Group("/api/v1/app"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/instruments/au9999/quote", nil))
	var body struct {
		Data struct {
			Price      float64       `json:"price"`
			CNY        float64       `json:"cny_per_gram"`
			Instrument InstrumentDTO `json:"instrument"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || body.Data.Price != 946 || body.Data.CNY != 946 || body.Data.Instrument.Unit != "CNY/g" {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/instruments/unknown/quote", nil))
	if w.Code != 404 {
		t.Fatalf("unknown=%d", w.Code)
	}
}

func (domesticFixture) LoadRealtime(context.Context) ([]domain.RealtimePoint, error) { return nil, nil }
func (domesticFixture) LoadIntraday(context.Context) ([]domain.IntradayPoint, error) { return nil, nil }

type closedMarketFixture struct {
	quote   domain.GoldQuote
	points  []domain.RealtimePoint
	minutes []domain.IntradayPoint
}

func (f closedMarketFixture) LoadQuote(context.Context) (domain.GoldQuote, bool, error) {
	return f.quote, true, nil
}
func (f closedMarketFixture) LoadDaily(context.Context) ([]domain.DailyBar, error) { return nil, nil }
func (f closedMarketFixture) LoadRealtime(context.Context) ([]domain.RealtimePoint, error) {
	return f.points, nil
}
func (f closedMarketFixture) LoadIntraday(context.Context) ([]domain.IntradayPoint, error) {
	return f.minutes, nil
}

func TestRealtimeRoutesFallbackContractForDomesticAndInternational(t *testing.T) {
	gin.SetMode(gin.TestMode)
	end := time.Now().Add(-12 * time.Hour).Truncate(time.Minute)

	auMinutes := make([]domain.IntradayPoint, 0, 20)
	intlMinutes := make([]domain.IntradayPoint, 0, 20)
	for i := 20; i >= 1; i-- {
		ts := end.Add(-time.Duration(i) * time.Minute)
		auMinutes = append(auMinutes, domain.IntradayPoint{Time: ts, Price: 760.0})
		intlMinutes = append(intlMinutes, domain.IntradayPoint{Time: ts, Price: 4370.0})
	}

	auStore := closedMarketFixture{
		quote: domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: end},
		points: []domain.RealtimePoint{
			{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 755.01},
			{Time: end, SourceTime: end, Price: 755.01},
		},
		minutes: auMinutes,
	}
	intlStore := closedMarketFixture{
		quote: domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4378.29, USDCNY: 7.0, AsOf: end},
		points: []domain.RealtimePoint{
			{Time: end.Add(-5 * time.Second), SourceTime: end.Add(-5 * time.Second), Price: 985.0},
			{Time: end, SourceTime: end, Price: 985.0},
		},
		minutes: intlMinutes,
	}

	router := gin.New()
	group := router.Group("/api/v1/app")
	NewHandler(application.NewGoldQuery(intlStore)).RegisterPublicRoutes(group)
	NewInstrumentsHandler(application.NewInstruments([]application.InstrumentMarket{
		{
			Instrument: domain.Instrument{ID: "au9999", Symbol: "AU9999", Kind: "spot", Currency: "CNY", Unit: "CNY/g", QuoteSource: "sina", DailySource: "sge"},
			Service:    application.NewNativeGoldQuery(auStore),
		},
	})).RegisterPublicRoutes(group)

	for _, path := range []string{"/api/v1/app/market/gold/instruments/au9999/realtime", "/api/v1/app/market/gold/realtime"} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 {
			t.Fatalf("%s status=%d body=%s", path, w.Code, w.Body.String())
		}
		var resp struct {
			Code int `json:"code"`
			Data struct {
				Unit            string `json:"unit"`
				IntervalSeconds int    `json:"interval_seconds"`
				WindowSeconds   int    `json:"window_seconds"`
				Points          []any  `json:"points"`
			} `json:"data"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("%s decode: %v", path, err)
		}
		if resp.Code != 0 || resp.Data.Unit != "CNY/g" || resp.Data.IntervalSeconds != 60 || resp.Data.WindowSeconds != 1200 || len(resp.Data.Points) != 21 {
			t.Fatalf("%s unexpected contract: %s", path, w.Body.String())
		}
	}
}

func TestRealtimeRoutesWindowQueryParamContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tz := time.FixedZone("CST", 8*3600)

	// 国内 AU9999：前日日盘 + 夜盘 20:00 ~ 次日 02:28 + 02:30 收盘报价（固定过去日期，避免依赖宿主机时钟）
	auNightStart := time.Date(2025, 11, 20, 20, 0, 0, 0, tz)
	auCloseAt := time.Date(2025, 11, 21, 2, 30, 0, 0, tz)
	auMinutes := []domain.IntradayPoint{
		{Time: time.Date(2025, 11, 20, 15, 30, 0, 0, tz), Price: 775.00},
	}
	for m := 0; m <= 388; m += 2 { // 195 个夜盘真实分钟点，20:00..02:28
		auMinutes = append(auMinutes, domain.IntradayPoint{
			Time:  auNightStart.Add(time.Duration(m) * time.Minute),
			Price: 773.48 - float64(m)*0.04,
		})
	}
	auStore := closedMarketFixture{
		quote:   domain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 755.01, AsOf: auCloseAt},
		minutes: auMinutes,
	}

	// 国际 XAUUSD：12 小时分钟线，截止 05:00
	intlCloseAt := time.Date(2025, 11, 21, 5, 0, 0, 0, tz)
	intlMinutes := make([]domain.IntradayPoint, 0, 720)
	for m := 720; m >= 1; m-- {
		intlMinutes = append(intlMinutes, domain.IntradayPoint{
			Time:  intlCloseAt.Add(-time.Duration(m) * time.Minute),
			Price: 4370.0,
		})
	}
	intlStore := closedMarketFixture{
		quote:   domain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 4380.0, USDCNY: 7.0, AsOf: intlCloseAt},
		minutes: intlMinutes,
	}

	router := gin.New()
	group := router.Group("/api/v1/app")
	NewHandler(application.NewGoldQuery(intlStore)).RegisterPublicRoutes(group)
	NewInstrumentsHandler(application.NewInstruments([]application.InstrumentMarket{
		{
			Instrument: domain.Instrument{ID: "au9999", Symbol: "AU9999", Kind: "spot", Currency: "CNY", Unit: "CNY/g", QuoteSource: "sina", DailySource: "sge", Exchange: "SGE"},
			Service:    application.NewNativeGoldQuery(auStore),
		},
	})).RegisterPublicRoutes(group)

	type realtimeResp struct {
		Code int `json:"code"`
		Data struct {
			Unit            string `json:"unit"`
			IntervalSeconds int    `json:"interval_seconds"`
			WindowSeconds   int    `json:"window_seconds"`
			WindowStart     string `json:"window_start"`
			WindowEnd       string `json:"window_end"`
			Points          []struct {
				Time  string  `json:"time"`
				Price float64 `json:"price"`
			} `json:"points"`
		} `json:"data"`
	}

	// 1. 不带参数及 ?window=20m：100% 保持 1200s 兼容
	for _, path := range []string{
		"/api/v1/app/market/gold/instruments/au9999/realtime",
		"/api/v1/app/market/gold/instruments/au9999/realtime?window=20m",
		"/api/v1/app/market/gold/realtime",
		"/api/v1/app/market/gold/realtime?window=20m",
	} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 {
			t.Fatalf("%s status=%d body=%s", path, w.Code, w.Body.String())
		}
		var resp realtimeResp
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("%s decode: %v", path, err)
		}
		if resp.Code != 0 || resp.Data.Unit != "CNY/g" || resp.Data.IntervalSeconds != 60 || resp.Data.WindowSeconds != 1200 || len(resp.Data.Points) != 21 {
			t.Fatalf("%s unexpected 20m response: %s", path, w.Body.String())
		}
	}

	// 2. 国内 AU9999 ?window=session：完整夜盘 20:00 ~ 02:30 (23400s)
	{
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/instruments/au9999/realtime?window=session", nil))
		if w.Code != 200 {
			t.Fatalf("au9999 session status=%d body=%s", w.Code, w.Body.String())
		}
		var resp realtimeResp
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatal(err)
		}
		if resp.Code != 0 || resp.Data.Unit != "CNY/g" || resp.Data.IntervalSeconds != 60 || resp.Data.WindowSeconds != 23400 {
			t.Fatalf("au9999 session contract mismatch: %s", w.Body.String())
		}
		if resp.Data.WindowStart != "2025-11-20T20:00:00+08:00" || resp.Data.WindowEnd != "2025-11-21T02:30:00+08:00" {
			t.Fatalf("au9999 session bounds mismatch: start=%s end=%s", resp.Data.WindowStart, resp.Data.WindowEnd)
		}
		if len(resp.Data.Points) != 196 {
			t.Fatalf("au9999 session points len=%d, want 196", len(resp.Data.Points))
		}
		if resp.Data.Points[0].Time != "2025-11-20T20:00:00+08:00" || resp.Data.Points[len(resp.Data.Points)-1].Time != "2025-11-21T02:30:00+08:00" {
			t.Fatalf("au9999 session endpoints mismatch: first=%+v last=%+v", resp.Data.Points[0], resp.Data.Points[len(resp.Data.Points)-1])
		}
	}

	// 3. 国际 XAUUSD ?window=session：完整 6 小时 23:00 ~ 05:00 (21600s)
	{
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/realtime?window=session", nil))
		if w.Code != 200 {
			t.Fatalf("xauusd session status=%d body=%s", w.Code, w.Body.String())
		}
		var resp realtimeResp
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatal(err)
		}
		if resp.Code != 0 || resp.Data.Unit != "CNY/g" || resp.Data.IntervalSeconds != 60 || resp.Data.WindowSeconds != 21600 {
			t.Fatalf("xauusd session contract mismatch: %s", w.Body.String())
		}
		if len(resp.Data.Points) != 361 {
			t.Fatalf("xauusd session points len=%d, want 361", len(resp.Data.Points))
		}
		if resp.Data.Points[0].Time != "2025-11-20T23:00:00+08:00" || resp.Data.Points[len(resp.Data.Points)-1].Time != "2025-11-21T05:00:00+08:00" {
			t.Fatalf("xauusd session endpoints mismatch: first=%+v last=%+v", resp.Data.Points[0], resp.Data.Points[len(resp.Data.Points)-1])
		}
	}

	// 4. 非法 window 参数返回 422 (KindValidation)
	for _, path := range []string{
		"/api/v1/app/market/gold/instruments/au9999/realtime?window=invalid",
		"/api/v1/app/market/gold/realtime?window=invalid",
	} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 422 {
			t.Fatalf("%s expected 422, got %d body=%s", path, w.Code, w.Body.String())
		}
	}
}
