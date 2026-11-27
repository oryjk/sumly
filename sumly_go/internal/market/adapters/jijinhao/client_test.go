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
	wantPage1 := "https://api.jijinhao.com/quoteCenter/history.htm?code=JO_71&style=0&currentPage=1&pageSize=500"
	wantPage2 := "https://api.jijinhao.com/quoteCenter/history.htm?code=JO_71&style=0&currentPage=2&pageSize=500"
	tz := time.FixedZone("CST", 8*3600)
	ts1 := time.Date(2026, 11, 21, 2, 28, 0, 0, tz).UnixMilli()
	ts2 := time.Date(2026, 11, 20, 9, 0, 0, 0, tz).UnixMilli()
	var seenURLs []string

	client := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method != http.MethodGet {
			t.Fatalf("method = %s", r.Method)
		}
		if r.Header.Get("User-Agent") == "" || r.Header.Get("Referer") == "" {
			t.Fatalf("missing required headers: ua=%q referer=%q", r.Header.Get("User-Agent"), r.Header.Get("Referer"))
		}
		seenURLs = append(seenURLs, r.URL.String())
		switch r.URL.String() {
		case wantPage1:
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(strings.NewReader(`var quote_json = {"flag":true,"data":[{"q2":755.01,"time":` + itoa64(ts1) + `}]};`)),
				Header:     make(http.Header),
			}, nil
		case wantPage2:
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(strings.NewReader(`var quote_json = {"flag":true,"data":[{"q2":770.00,"time":` + itoa64(ts2) + `}]};`)),
				Header:     make(http.Header),
			}, nil
		default:
			t.Fatalf("unexpected url = %s", r.URL.String())
			return nil, nil
		}
	})}, "JO_71")

	points, err := client.FetchGoldIntraday(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(seenURLs) != 2 || seenURLs[0] != wantPage1 || seenURLs[1] != wantPage2 {
		t.Fatalf("seen urls = %v", seenURLs)
	}
	if len(points) != 2 ||
		points[0].Price != 770.00 || points[0].Time.Format(time.RFC3339) != "2026-11-20T09:00:00+08:00" ||
		points[1].Price != 755.01 || points[1].Time.Format(time.RFC3339) != "2026-11-21T02:28:00+08:00" {
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

func TestFetchGoldIntradayMergesTwoPagesOverFullDayAndPrefersPage1OnOverlap(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	dayStart := time.Date(2026, 11, 27, 9, 0, 0, 0, tz)    // 09:00..15:30 = 391 根连续日盘
	nightStart := time.Date(2026, 11, 27, 20, 0, 0, 0, tz) // 20:00..02:30 = 391 根夜盘

	allTimes := make([]time.Time, 0, 782)
	for m := 0; m <= 390; m++ {
		allTimes = append(allTimes, dayStart.Add(time.Duration(m)*time.Minute))
	}
	for m := 0; m <= 390; m++ {
		allTimes = append(allTimes, nightStart.Add(time.Duration(m)*time.Minute))
	}

	// 模拟上游单页上限 500 条：page1 为最新 500 条，page2 为更早 300 条（含 18 条重叠）
	page1Times := allTimes[len(allTimes)-500:]
	page2Times := allTimes[:300]

	buildPayload := func(times []time.Time, basePrice float64) string {
		var b strings.Builder
		b.WriteString(`var quote_json = {"flag":true,"data":[`)
		for i, ts := range times {
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(`{"q2":`)
			if basePrice > 780 {
				b.WriteString(`781.5`)
			} else {
				b.WriteString(`775.0`)
			}
			b.WriteString(`,"time":`)
			b.WriteString(itoa64(ts.UnixMilli()))
			b.WriteByte('}')
		}
		b.WriteString(`]};`)
		return b.String()
	}

	client := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		switch r.URL.Query().Get("currentPage") {
		case "1":
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(strings.NewReader(buildPayload(page1Times, 781.5))),
				Header:     make(http.Header),
			}, nil
		case "2":
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(strings.NewReader(buildPayload(page2Times, 775.0))),
				Header:     make(http.Header),
			}, nil
		default:
			t.Fatalf("unexpected page query: %s", r.URL.RawQuery)
			return nil, nil
		}
	})}, "JO_71")

	points, err := client.FetchGoldIntraday(context.Background())
	if err != nil {
		t.Fatalf("FetchGoldIntraday: %v", err)
	}
	if len(points) != 782 {
		t.Fatalf("merged points = %d, want 782", len(points))
	}
	if !points[0].Time.Equal(dayStart) || !points[len(points)-1].Time.Equal(nightStart.Add(390*time.Minute)) {
		t.Fatalf("range = [%v, %v]", points[0].Time, points[len(points)-1].Time)
	}
	// 重叠区间（索引 282..299）应采用较新的 page1 价格 781.5
	if points[290].Price != 781.5 {
		t.Fatalf("overlap point price = %v, want 781.5 from page1", points[290].Price)
	}
	// 仅在 page2 出现的早盘首点保留 775.0
	if points[0].Price != 775.0 {
		t.Fatalf("early day point price = %v, want 775.0 from page2", points[0].Price)
	}
}

func TestFetchGoldIntradayDegradesGracefullyWhenSecondPageFailsOrTimesOut(t *testing.T) {
	tz := time.FixedZone("CST", 8*3600)
	ts := time.Date(2026, 11, 27, 23, 20, 0, 0, tz).UnixMilli()

	t.Run("page 2 HTTP 503 degrades to page 1", func(t *testing.T) {
		client := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
			if r.URL.Query().Get("currentPage") == "1" {
				return &http.Response{
					StatusCode: http.StatusOK,
					Body:       io.NopCloser(strings.NewReader(`var quote_json = {"flag":true,"data":[{"q2":780.2,"time":` + itoa64(ts) + `}]};`)),
					Header:     make(http.Header),
				}, nil
			}
			return &http.Response{
				StatusCode: http.StatusServiceUnavailable,
				Body:       io.NopCloser(strings.NewReader("busy")),
				Header:     make(http.Header),
			}, nil
		})}, "JO_71")

		points, err := client.FetchGoldIntraday(context.Background())
		if err != nil {
			t.Fatalf("expected graceful degradation, got err: %v", err)
		}
		if len(points) != 1 || points[0].Price != 780.2 {
			t.Fatalf("unexpected degraded points: %+v", points)
		}
	})

	t.Run("page 2 timeout degrades without cancelling parent context", func(t *testing.T) {
		client := NewClient(&http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
			if r.URL.Query().Get("currentPage") == "1" {
				return &http.Response{
					StatusCode: http.StatusOK,
					Body:       io.NopCloser(strings.NewReader(`var quote_json = {"flag":true,"data":[{"q2":780.5,"time":` + itoa64(ts) + `}]};`)),
					Header:     make(http.Header),
				}, nil
			}
			<-r.Context().Done()
			return nil, r.Context().Err()
		})}, "JO_71")
		client.PageTimeout = 50 * time.Millisecond

		parentCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		points, err := client.FetchGoldIntraday(parentCtx)
		if err != nil {
			t.Fatalf("expected graceful degradation on page 2 timeout, got err: %v", err)
		}
		if parentCtx.Err() != nil {
			t.Fatalf("parent context must remain alive after page 2 timeout: %v", parentCtx.Err())
		}
		if len(points) != 1 || points[0].Price != 780.5 {
			t.Fatalf("unexpected points: %+v", points)
		}
	})
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
