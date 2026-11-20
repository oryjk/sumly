package yahoo

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/httpclient"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

const DefaultBaseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

type Client struct {
	HTTP    *http.Client
	BaseURL string
	Now     func() time.Time
}

var _ ports.YahooSource = (*Client)(nil)

func New(httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}
	return &Client{HTTP: httpClient, BaseURL: DefaultBaseURL, Now: time.Now}
}

type chartResponse struct {
	Chart struct {
		Result []struct {
			Timestamp  []int64 `json:"timestamp"`
			Indicators struct {
				Quote []struct {
					Close    []*float64 `json:"close"`
					AdjClose []*float64 `json:"adjclose"`
				} `json:"quote"`
				AdjClose []struct {
					AdjClose []*float64 `json:"adjclose"`
				} `json:"adjclose"`
			} `json:"indicators"`
		} `json:"result"`
	} `json:"chart"`
}

func (c *Client) FetchTicker(ctx context.Context, ticker string) ([]domain.Observation, error) {
	base := strings.TrimRight(strings.TrimSpace(c.BaseURL), "/")
	if base == "" {
		base = DefaultBaseURL
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}
	nowFn := c.Now
	if nowFn == nil {
		nowFn = time.Now
	}

	nowUTC := nowFn().UTC()
	todayMidnight := time.Date(nowUTC.Year(), nowUTC.Month(), nowUTC.Day(), 0, 0, 0, 0, time.UTC)
	period2 := todayMidnight.Unix()
	period1 := todayMidnight.AddDate(-20, 0, 0).Unix()

	reqURL := fmt.Sprintf("%s/%s?period1=%d&period2=%d&interval=1d", base, url.PathEscape(ticker), period1, period2)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create yahoo request for %s: %w", ticker, err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Referer", "https://finance.yahoo.com/")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("yahoo request failed for %s: %w", ticker, err)
	}
	body, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		return nil, fmt.Errorf("read yahoo response for %s: %w", ticker, readErr)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("yahoo API status %d for %s", resp.StatusCode, ticker)
	}

	return ParseChartJSON(body)
}

func ParseChartJSON(data []byte) ([]domain.Observation, error) {
	var parsed chartResponse
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, fmt.Errorf("decode yahoo chart response: %w", err)
	}
	if len(parsed.Chart.Result) == 0 {
		return nil, fmt.Errorf("empty yahoo chart result")
	}
	res := parsed.Chart.Result[0]
	var prices []*float64
	if len(res.Indicators.AdjClose) > 0 && len(res.Indicators.AdjClose[0].AdjClose) > 0 {
		prices = res.Indicators.AdjClose[0].AdjClose
	} else if len(res.Indicators.Quote) > 0 {
		if len(res.Indicators.Quote[0].AdjClose) > 0 {
			prices = res.Indicators.Quote[0].AdjClose
		} else {
			prices = res.Indicators.Quote[0].Close
		}
	}
	if len(prices) == 0 {
		return nil, fmt.Errorf("no price data in yahoo chart response")
	}
	limit := len(res.Timestamp)
	if len(prices) < limit {
		limit = len(prices)
	}
	out := make([]domain.Observation, 0, limit)
	for i := 0; i < limit; i++ {
		p := prices[i]
		if p == nil || !domain.IsFinite(*p) || *p <= 0 {
			continue
		}
		dt := domain.NormalizeDate(time.Unix(res.Timestamp[i], 0).UTC())
		out = append(out, domain.Observation{Date: dt, Value: domain.RoundTo(*p, 4)})
	}
	return domain.SanitizeObservations(out), nil
}
