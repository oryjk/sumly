package eastmoney

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestParseIntradayFiltersInvalidDeduplicatesAndSortsInShanghai(t *testing.T) {
	body := []byte(`{
		"rc": 0,
		"data": {
			"code": "AU9999",
			"market": 118,
			"klines": [
				"2026-11-21 02:29,759.80,755.01,760.00,755.01,120",
				"2026-11-21 02:27,760.00,760.00,760.10,759.90,45",
				"2026-11-21 02:28,760.00,759.50,760.00,759.50,30",
				"2026-11-21 02:28,760.00,759.85,760.00,759.50,35",
				"bad-time,760.00,760.00,760.00,760.00,10",
				"2026-11-21 02:25,760.00,0,760.00,760.00,10",
				"2026-11-21 02:24,760.00,-12.5,760.00,760.00,10",
				"2026-11-21 02:23,760.00,NaN,760.00,760.00,10",
				"2026-11-21 02:22,760.00,Inf,760.00,760.00,10",
				"2026-11-21 02:21,760.00",
				"2026-11-20 20:01,758.00,758.60,759.00,757.80,88"
			]
		}
	}`)

	points, err := parseIntraday(body)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(points) != 4 {
		t.Fatalf("expected 4 valid deduplicated points, got %d: %+v", len(points), points)
	}

	want := []struct {
		ts    string
		price float64
	}{
		{"2026-11-20T20:01:00+08:00", 758.60},
		{"2026-11-21T02:27:00+08:00", 760.00},
		{"2026-11-21T02:28:00+08:00", 759.85},
		{"2026-11-21T02:29:00+08:00", 755.01},
	}
	for i, w := range want {
		if gotTS := points[i].Time.Format(time.RFC3339); gotTS != w.ts {
			t.Fatalf("point[%d] time = %s, want %s", i, gotTS, w.ts)
		}
		if points[i].Price != w.price {
			t.Fatalf("point[%d] price = %v, want %v", i, points[i].Price, w.price)
		}
	}
}

func TestParseIntradayRejectsEmptyOrMalformedPayload(t *testing.T) {
	cases := []string{
		`not-json`,
		`{"data":null}`,
		`{"data":{"klines":[]}}`,
		`{"data":{"klines":["bad,1,2","2026-11-21 02:29,759,0,760,755,1"]}}`,
	}
	for _, body := range cases {
		if _, err := parseIntraday([]byte(body)); err == nil {
			t.Fatalf("expected error for payload %s", body)
		}
	}
}

func TestFetchGoldIntradayBuildsExpectedRequestAndChecksStatus(t *testing.T) {
	wantURL := "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=118.AU9999&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56&klt=1&fqt=1&lmt=480&end=20500101"
	client := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method != http.MethodGet {
			t.Fatalf("method = %s", r.Method)
		}
		if r.URL.String() != wantURL {
			t.Fatalf("url = %s, want %s", r.URL.String(), wantURL)
		}
		if r.Header.Get("User-Agent") == "" {
			t.Fatal("missing User-Agent header")
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader(`{"data":{"klines":["2026-11-21 02:29,759.80,755.01,760.00,755.01,120"]}}`)),
			Header:     make(http.Header),
		}, nil
	})}, "118.AU9999")

	points, err := client.FetchGoldIntraday(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(points) != 1 || points[0].Price != 755.01 || points[0].Time.Format(time.RFC3339) != "2026-11-21T02:29:00+08:00" {
		t.Fatalf("unexpected points: %+v", points)
	}

	failClient := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusBadGateway,
			Body:       io.NopCloser(strings.NewReader("bad gateway")),
			Header:     make(http.Header),
		}, nil
	})}, "118.AU9999")
	if _, err := failClient.FetchGoldIntraday(context.Background()); err == nil {
		t.Fatal("expected HTTP 502 error")
	}
}
