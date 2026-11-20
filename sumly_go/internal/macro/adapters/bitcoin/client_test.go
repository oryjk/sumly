package bitcoin

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestBitcoinPriceAndMarketCap(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/market-price" {
			_, _ = w.Write([]byte(`{"values":[{"x":1735776000,"y":95000.5}]}`))
			return
		}
		_, _ = w.Write([]byte(`{"values":[{"x":1735776000,"y":1880000000000}]}`))
	}))
	defer srv.Close()

	c := New(srv.Client())
	c.BaseURL = srv.URL
	price, err := c.FetchBTCPrice(context.Background())
	if err != nil || len(price) != 1 || price[0].Value != 95000.5 {
		t.Fatalf("unexpected price: %+v, err=%v", price, err)
	}
	mcap, err := c.FetchBTCMarketCap(context.Background())
	if err != nil || len(mcap) != 1 || mcap[0].Value != 1880.0 {
		t.Fatalf("unexpected mcap: %+v, err=%v", mcap, err)
	}
}
