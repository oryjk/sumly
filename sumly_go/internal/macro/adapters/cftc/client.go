package cftc

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/httpclient"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

const DefaultEndpoint = "https://publicreporting.cftc.gov/resource/72hh-3qpy.json"

type Client struct {
	HTTP     *http.Client
	Endpoint string
}

var _ ports.CFTCSource = (*Client)(nil)

func New(httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(60 * time.Second)
	}
	return &Client{HTTP: httpClient, Endpoint: DefaultEndpoint}
}

type rawRecord struct {
	ReportDate   string `json:"report_date_as_yyyy_mm_dd"`
	SwapLong     string `json:"swap_positions_long_all"`
	SwapShort    string `json:"swap__positions_short_all"`
	MMLong       string `json:"m_money_positions_long_all"`
	MMShort      string `json:"m_money_positions_short_all"`
	OpenInterest string `json:"open_interest_all"`
}

func (c *Client) FetchGoldCot(ctx context.Context) ([]domain.CotObservation, error) {
	endpoint := strings.TrimSpace(c.Endpoint)
	if endpoint == "" {
		endpoint = DefaultEndpoint
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(60 * time.Second)
	}

	params := url.Values{}
	params.Set("$where", "commodity_name='GOLD' AND contract_market_name='GOLD'")
	params.Set("$order", "report_date_as_yyyy_mm_dd ASC")
	params.Set("$limit", "50000")
	params.Set("$select", "report_date_as_yyyy_mm_dd,swap_positions_long_all,swap__positions_short_all,m_money_positions_long_all,m_money_positions_short_all,open_interest_all")

	reqURL := endpoint + "?" + params.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create CFTC request: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Sumly Macro CFTC Fetcher)")
	req.Header.Set("Accept", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("CFTC request failed: %w", err)
	}
	body, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		return nil, fmt.Errorf("read CFTC response: %w", readErr)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("CFTC API status %d", resp.StatusCode)
	}

	return ParseCotJSON(body)
}

func ParseCotJSON(data []byte) ([]domain.CotObservation, error) {
	var records []rawRecord
	if err := json.Unmarshal(data, &records); err != nil {
		return nil, fmt.Errorf("decode CFTC response: %w", err)
	}
	out := make([]domain.CotObservation, 0, len(records))
	for _, rec := range records {
		dt, err := domain.ParseDate(rec.ReportDate)
		if err != nil {
			continue
		}
		mmLong := parseFloatOrZero(rec.MMLong)
		mmShort := parseFloatOrZero(rec.MMShort)
		swapLong := parseFloatOrZero(rec.SwapLong)
		swapShort := parseFloatOrZero(rec.SwapShort)
		oi := parseFloatOrZero(rec.OpenInterest)
		out = append(out, domain.CotObservation{
			Date:         dt,
			MMLong:       mmLong,
			MMShort:      mmShort,
			MMNet:        mmLong - mmShort,
			SwapLong:     swapLong,
			SwapShort:    swapShort,
			SwapNet:      swapLong - swapShort,
			OpenInterest: oi,
		})
	}
	return domain.SanitizeCotObservations(out), nil
}

func parseFloatOrZero(raw string) float64 {
	v, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
	if err != nil || !domain.IsFinite(v) {
		return 0
	}
	return v
}
