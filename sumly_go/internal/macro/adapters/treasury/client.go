package treasury

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/httpclient"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

const DefaultEndpoint = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v2/accounting/od/debt_to_penny"

type Client struct {
	HTTP     *http.Client
	Endpoint string
}

var _ ports.TreasurySource = (*Client)(nil)

func New(httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}
	return &Client{HTTP: httpClient, Endpoint: DefaultEndpoint}
}

type apiResponse struct {
	Data []apiRecord `json:"data"`
	Meta struct {
		TotalPages int `json:"total-pages"`
	} `json:"meta"`
}

type apiRecord struct {
	RecordDate      string `json:"record_date"`
	TotPubDebtOutAm string `json:"tot_pub_debt_out_amt"`
}

// FetchUSDebtDaily fetches daily US total public debt and converts raw USD to trillion_usd (4 decimals).
func (c *Client) FetchUSDebtDaily(ctx context.Context) ([]domain.Observation, error) {
	endpoint := strings.TrimSpace(c.Endpoint)
	if endpoint == "" {
		endpoint = DefaultEndpoint
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}

	var all []domain.Observation
	page := 1
	const maxPages = 20
	for page <= maxPages {
		url := fmt.Sprintf("%s?fields=record_date,tot_pub_debt_out_amt&sort=record_date&page[size]=10000&page[number]=%d&format=json", endpoint, page)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, fmt.Errorf("create treasury request: %w", err)
		}
		req.Header.Set("User-Agent", "Mozilla/5.0 (Sumly Macro Treasury Fetcher)")
		req.Header.Set("Accept", "application/json")

		resp, err := httpClient.Do(req)
		if err != nil {
			return nil, fmt.Errorf("treasury request failed: %w", err)
		}
		body, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			return nil, fmt.Errorf("read treasury response: %w", readErr)
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return nil, fmt.Errorf("treasury API status %d: %s", resp.StatusCode, truncate(string(body), 200))
		}

		var parsed apiResponse
		if err := json.Unmarshal(body, &parsed); err != nil {
			return nil, fmt.Errorf("decode treasury response: %w", err)
		}
		for _, rec := range parsed.Data {
			dt, err := domain.ParseDate(rec.RecordDate)
			if err != nil {
				continue
			}
			rawUSD, err := strconv.ParseFloat(strings.TrimSpace(rec.TotPubDebtOutAm), 64)
			if err != nil || !domain.IsFinite(rawUSD) || rawUSD <= 0 {
				continue
			}
			// Raw Fiscal Data API value is in USD; convert accurately to trillion USD (4 decimal places).
			trillionUSD := domain.RoundTo(rawUSD/1e12, 4)
			all = append(all, domain.Observation{Date: dt, Value: trillionUSD})
		}

		if parsed.Meta.TotalPages <= 0 || page >= parsed.Meta.TotalPages || len(parsed.Data) == 0 {
			break
		}
		page++
	}
	return domain.SanitizeObservations(all), nil
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}
