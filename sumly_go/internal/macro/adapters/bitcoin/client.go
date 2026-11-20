package bitcoin

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/httpclient"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

const DefaultBaseURL = "https://api.blockchain.info/charts"

type Client struct {
	HTTP    *http.Client
	BaseURL string
}

var _ ports.BitcoinSource = (*Client)(nil)

func New(httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}
	return &Client{HTTP: httpClient, BaseURL: DefaultBaseURL}
}

type chartResponse struct {
	Values []struct {
		X int64   `json:"x"`
		Y float64 `json:"y"`
	} `json:"values"`
}

func (c *Client) FetchBTCPrice(ctx context.Context) ([]domain.Observation, error) {
	return c.fetchChart(ctx, "market-price", 1.0, 2)
}

func (c *Client) FetchBTCMarketCap(ctx context.Context) ([]domain.Observation, error) {
	// Convert USD market cap to billion_usd.
	return c.fetchChart(ctx, "market-cap", 1e9, 4)
}

func (c *Client) fetchChart(ctx context.Context, chartName string, scaleDiv float64, decimals int) ([]domain.Observation, error) {
	base := strings.TrimRight(strings.TrimSpace(c.BaseURL), "/")
	if base == "" {
		base = DefaultBaseURL
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}

	reqURL := fmt.Sprintf("%s/%s?timespan=all&format=json", base, chartName)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create blockchain.com request: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Sumly Macro Bitcoin Fetcher)")
	req.Header.Set("Accept", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("blockchain.com request failed: %w", err)
	}
	body, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		return nil, fmt.Errorf("read blockchain.com response: %w", readErr)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("blockchain.com API status %d", resp.StatusCode)
	}

	var parsed chartResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("decode blockchain.com response: %w", err)
	}

	out := make([]domain.Observation, 0, len(parsed.Values))
	for _, pt := range parsed.Values {
		if !domain.IsFinite(pt.Y) || pt.Y <= 0 {
			continue
		}
		dt := domain.NormalizeDate(time.Unix(pt.X, 0).UTC())
		val := domain.RoundTo(pt.Y/scaleDiv, decimals)
		out = append(out, domain.Observation{Date: dt, Value: val})
	}
	return domain.SanitizeObservations(out), nil
}
