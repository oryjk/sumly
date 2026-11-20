package yahoo

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestYahooFetchTickerParsesAdjCloseAndClose(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{
			"chart":{
				"result":[{
					"timestamp":[1735776000,1735862400,1735948800],
					"indicators":{
						"quote":[{"close":[2650.0,null,2675.5]}],
						"adjclose":[{"adjclose":[2651.25,null,2676.75]}]
					}
				}]
			}
		}`))
	}))
	defer srv.Close()

	c := New(srv.Client())
	c.BaseURL = srv.URL
	obs, err := c.FetchTicker(context.Background(), "GC=F")
	if err != nil {
		t.Fatalf("FetchTicker failed: %v", err)
	}
	if len(obs) != 2 || obs[0].Value != 2651.25 || obs[1].Value != 2676.75 {
		t.Fatalf("unexpected Yahoo observations: %+v", obs)
	}
}
