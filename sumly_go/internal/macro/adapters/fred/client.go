package fred

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/httpclient"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

const (
	DefaultEndpoint = "https://api.stlouisfed.org/fred/series/observations"
	// 120 req/min => 1 request per 500ms.
	DefaultMinInterval = 500 * time.Millisecond
)

var ErrNotConfigured = errors.New("FRED_API_KEY is not configured")

type Client struct {
	HTTP        *http.Client
	Endpoint    string
	APIKey      string
	MinInterval time.Duration

	mu          sync.Mutex
	lastRequest time.Time
}

var _ ports.FREDSource = (*Client)(nil)

func New(httpClient *http.Client, apiKey string) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}
	return &Client{
		HTTP:        httpClient,
		Endpoint:    DefaultEndpoint,
		APIKey:      strings.TrimSpace(apiKey),
		MinInterval: DefaultMinInterval,
	}
}

func (c *Client) Configured() bool {
	return strings.TrimSpace(c.APIKey) != ""
}

type apiResponse struct {
	Observations []struct {
		Date  string `json:"date"`
		Value string `json:"value"`
	} `json:"observations"`
}

func (c *Client) waitRateLimit(ctx context.Context) error {
	interval := c.MinInterval
	if interval <= 0 {
		return nil
	}
	c.mu.Lock()
	now := time.Now()
	var wait time.Duration
	if !c.lastRequest.IsZero() {
		nextAllowed := c.lastRequest.Add(interval)
		if nextAllowed.After(now) {
			wait = nextAllowed.Sub(now)
		}
	}
	c.lastRequest = now.Add(wait)
	c.mu.Unlock()

	if wait <= 0 {
		return nil
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func (c *Client) FetchSeries(ctx context.Context, seriesID string) ([]domain.Observation, error) {
	if !c.Configured() {
		return nil, ErrNotConfigured
	}
	if err := c.waitRateLimit(ctx); err != nil {
		return nil, err
	}
	endpoint := strings.TrimSpace(c.Endpoint)
	if endpoint == "" {
		endpoint = DefaultEndpoint
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}

	params := url.Values{}
	params.Set("series_id", seriesID)
	params.Set("api_key", strings.TrimSpace(c.APIKey))
	params.Set("file_type", "json")
	params.Set("observation_start", "1948-01-01")
	params.Set("sort_order", "asc")

	reqURL := endpoint + "?" + params.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create FRED request for %s: %w", seriesID, err)
	}
	req.Header.Set("Accept", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("FRED request failed for %s: %w", seriesID, err)
	}
	body, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		return nil, fmt.Errorf("read FRED response for %s: %w", seriesID, readErr)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("FRED API error %d for %s", resp.StatusCode, seriesID)
	}

	var parsed apiResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("decode FRED response for %s: %w", seriesID, err)
	}

	out := make([]domain.Observation, 0, len(parsed.Observations))
	for _, item := range parsed.Observations {
		rawVal := strings.TrimSpace(item.Value)
		if rawVal == "" || rawVal == "." {
			continue
		}
		dt, err := domain.ParseDate(item.Date)
		if err != nil {
			continue
		}
		val, err := strconv.ParseFloat(rawVal, 64)
		if err != nil || !domain.IsFinite(val) {
			continue
		}
		out = append(out, domain.Observation{Date: dt, Value: val})
	}
	return domain.SanitizeObservations(out), nil
}
