package fred

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestFREDSkipsUnconfiguredAndParsesObservations(t *testing.T) {
	unconfigured := New(nil, "")
	if unconfigured.Configured() {
		t.Fatalf("expected Configured()=false when api key is empty")
	}
	if _, err := unconfigured.FetchSeries(context.Background(), "DFII10"); !errors.Is(err, ErrNotConfigured) {
		t.Fatalf("expected ErrNotConfigured, got %v", err)
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("series_id") != "DFII10" || r.URL.Query().Get("api_key") != "demo-key" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`{
			"observations":[
				{"date":"2026-01-02","value":"2.15"},
				{"date":"2026-01-03","value":"."},
				{"date":"2026-01-05","value":"2.08"}
			]
		}`))
	}))
	defer srv.Close()

	client := New(srv.Client(), "demo-key")
	client.Endpoint = srv.URL
	client.MinInterval = time.Millisecond

	obs, err := client.FetchSeries(context.Background(), "DFII10")
	if err != nil {
		t.Fatalf("FetchSeries failed: %v", err)
	}
	if len(obs) != 2 || obs[0].Value != 2.15 || obs[1].Value != 2.08 {
		t.Fatalf("unexpected FRED observations: %+v", obs)
	}
}
