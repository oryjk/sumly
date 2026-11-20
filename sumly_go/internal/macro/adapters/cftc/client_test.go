package cftc

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

func TestCFTCFetchGoldCot(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[
			{
				"report_date_as_yyyy_mm_dd":"2026-01-06T00:00:00.000",
				"m_money_positions_long_all":"220000",
				"m_money_positions_short_all":"40000",
				"swap_positions_long_all":"50000",
				"swap__positions_short_all":"230000",
				"open_interest_all":"500000"
			}
		]`))
	}))
	defer srv.Close()

	c := New(srv.Client())
	c.Endpoint = srv.URL
	obs, err := c.FetchGoldCot(context.Background())
	if err != nil {
		t.Fatalf("FetchGoldCot failed: %v", err)
	}
	if len(obs) != 1 {
		t.Fatalf("expected 1 cot obs, got %d", len(obs))
	}
	got := obs[0]
	if domain.FormatDate(got.Date) != "2026-01-06" || got.MMNet != 180000 || got.SwapNet != -180000 || got.OpenInterest != 500000 {
		t.Fatalf("unexpected cot obs: %+v", got)
	}
	ratio := got.MMNetRatioPct()
	if ratio == nil || *ratio != 36.0 {
		t.Fatalf("unexpected ratio: %v", ratio)
	}
}
