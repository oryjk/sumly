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
