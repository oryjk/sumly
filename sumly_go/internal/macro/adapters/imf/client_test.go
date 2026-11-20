package imf

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/seedcsv"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

func TestIMFParsesSDMXAndFallsBackToSeedCSV(t *testing.T) {
	t.Run("SDMX JSON success", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_, _ = w.Write([]byte(`{
				"CompactData":{
					"DataSet":{
						"Series":{
							"Obs":[
								{"@TIME_PERIOD":"2025-Q3","@OBS_VALUE":"56.9"},
								{"@TIME_PERIOD":"2025-Q4","@OBS_VALUE":"56.8"}
							]
						}
					}
				}
			}`))
		}))
		defer srv.Close()

		c := New(srv.Client(), seedcsv.New())
		c.BaseURL = srv.URL
		obs, err := c.FetchUSDReserveShare(context.Background())
		if err != nil {
			t.Fatalf("FetchUSDReserveShare failed: %v", err)
		}
		if len(obs) != 2 || domain.FormatDate(obs[0].Date) != "2025-07-01" || obs[1].Value != 56.8 {
			t.Fatalf("unexpected IMF observations: %+v", obs)
		}
	})

	t.Run("API failure falls back to embedded CSV", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusForbidden)
		}))
		defer srv.Close()

		c := New(srv.Client(), seedcsv.New())
		c.BaseURL = srv.URL
		obs, err := c.FetchUSDReserveShare(context.Background())
		if err != nil {
			t.Fatalf("expected CSV fallback success, got %v", err)
		}
		if len(obs) < 25 {
			t.Fatalf("expected full USD reserve CSV history, got %d rows", len(obs))
		}
	})

	t.Run("embedded CB_GOLD_NET CSV loads cleanly", func(t *testing.T) {
		loader := seedcsv.New()
		obs, err := loader.LoadSeries(domain.SeriesCBGoldNet)
		if err != nil {
			t.Fatalf("LoadSeries CB_GOLD_NET failed: %v", err)
		}
		if len(obs) != 16 || obs[len(obs)-1].Value != 863 {
			t.Fatalf("unexpected CB_GOLD_NET CSV rows: len=%d last=%+v", len(obs), obs[len(obs)-1])
		}
	})
}
