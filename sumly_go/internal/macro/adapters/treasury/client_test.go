package treasury

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

func TestFetchUSDebtDailyConvertsToTrillionUSD4Decimals(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		page := r.URL.Query().Get("page[number]")
		if page == "1" {
			_, _ = w.Write([]byte(`{
				"data":[
					{"record_date":"2026-01-02","tot_pub_debt_out_amt":"36214567890123.45"},
					{"record_date":"bad","tot_pub_debt_out_amt":"100"}
				],
				"meta":{"total-pages":2}
			}`))
			return
		}
		_, _ = w.Write([]byte(`{
			"data":[
				{"record_date":"2026-01-03","tot_pub_debt_out_amt":"36225000000000.00"}
			],
			"meta":{"total-pages":2}
		}`))
	}))
	defer srv.Close()

	c := New(srv.Client())
	c.Endpoint = srv.URL
	obs, err := c.FetchUSDebtDaily(context.Background())
	if err != nil {
		t.Fatalf("FetchUSDebtDaily failed: %v", err)
	}
	if len(obs) != 2 {
		t.Fatalf("expected 2 observations across 2 pages, got %d", len(obs))
	}
	if domain.FormatDate(obs[0].Date) != "2026-01-02" || obs[0].Value != 36.2146 {
		t.Fatalf("unexpected obs[0]: %+v", obs[0])
	}
	if domain.FormatDate(obs[1].Date) != "2026-01-03" || obs[1].Value != 36.225 {
		t.Fatalf("unexpected obs[1]: %+v", obs[1])
	}
}
