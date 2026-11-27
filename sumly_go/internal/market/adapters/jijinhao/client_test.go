package jijinhao

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
	tz := time.FixedZone("CST", 8*3600)
	t1 := time.Date(2026, 11, 20, 23, 55, 0, 0, tz).UnixMilli()
	t2 := time.Date(2026, 11, 21, 2, 4, 0, 0, tz).UnixMilli()
	t3 := time.Date(2026, 11, 21, 2, 28, 0, 0, tz).UnixMilli()

	body := []byte(`var quote_json = {
		"flag": true,
		"code": "JO_71",
		"style": 0,
		"data": [
			{"q1": 758.0, "q2": 755.01, "q3": 758.0, "q4": 755.01, "time": ` + itoa64(t3) + `},
			{"q1": 760.0, "q2": 760.0,  "q3": 760.0, "q4": 760.0,  "time": ` + itoa64(t2) + `},
			{"q1": 760.0, "q2": 760.5,  "q3": 760.5, "q4": 760.0,  "time": ` + itoa64(t2+15000) + `},
			{"q1": 765.0, "q2": 0,      "q3": 765.0, "q4": 765.0,  "time": ` + itoa64(t1) + `},
			{"q1": 765.0, "q2": -1.5,   "q3": 765.0, "q4": 765.0,  "time": ` + itoa64(t1) + `},
			{"q1": 765.0, "q2": 766.0,  "q3": 766.0, "q4": 765.0,  "time": 0},
			{"q1": 765.98,"q2": 766.0,  "q3": 766.0, "q4": 765.98, "time": ` + itoa64(t1) + `}
		]
	};`)

	points, err := parseIntraday(body)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(points) != 3 {
		t.Fatalf("expected 3 deduplicated points, got %d: %+v", len(points), points)
	}

	want := []struct {
		ts    string
		price float64
	}{
		{"2026-11-20T23:55:00+08:00", 766.0},
		{"2026-11-21T02:04:00+08:00", 760.5},
		{"2026-11-21T02:28:00+08:00", 755.01},
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

func TestParseIntradayRejectsInvalidPayload(t *testing.T) {
	cases := []string{
		`not-jsonp`,
		`var quote_json = {bad json};`,
		`var quote_json = {"flag":false,"data":[{"q2":755.01,"time":1795199280000}]};`,
		`var quote_json = {"flag":true,"data":[]};`,
		`var quote_json = {"flag":true,"data":[{"q2":0,"time":1795199280000}]};`,
	}
	for _, body := range cases {
		if _, err := parseIntraday([]byte(body)); err == nil {
			t.Fatalf("expected error for payload %s", body)
		}
	}
}

func TestFetchGoldIntradayBuildsExpectedRequestAndChecksStatus(t *testing.T) {
	wantURL := "https://api.jijinhao.com/quoteCenter/history.htm?code=JO_71&style=0&pageSize=800"
	ts := time.Date(2026, 11, 21, 2, 28, 0, 0, time.FixedZone("CST", 8*3600)).UnixMilli()
	client := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method != http.MethodGet {
			t.Fatalf("method = %s", r.Method)
		}
		if r.URL.String() != wantURL {
			t.Fatalf("url = %s, want %s", r.URL.String(), wantURL)
		}
		if r.Header.Get("User-Agent") == "" || r.Header.Get("Referer") == "" {
			t.Fatalf("missing required headers: ua=%q referer=%q", r.Header.Get("User-Agent"), r.Header.Get("Referer"))
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader(`var quote_json = {"flag":true,"data":[{"q2":755.01,"time":` + itoa64(ts) + `}]};`)),
			Header:     make(http.Header),
		}, nil
	})}, "JO_71")

	points, err := client.FetchGoldIntraday(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(points) != 1 || points[0].Price != 755.01 || points[0].Time.Format(time.RFC3339) != "2026-11-21T02:28:00+08:00" {
		t.Fatalf("unexpected points: %+v", points)
	}

	failClient := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusServiceUnavailable,
			Body:       io.NopCloser(strings.NewReader("unavailable")),
			Header:     make(http.Header),
		}, nil
	})}, "JO_71")
	if _, err := failClient.FetchGoldIntraday(context.Background()); err == nil {
		t.Fatal("expected HTTP 503 error")
	}
}

func itoa64(v int64) string {
	if v == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	return string(buf[i:])
}
