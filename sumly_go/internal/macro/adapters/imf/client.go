package imf

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

const DefaultBaseURL = "https://dataservices.imf.org/REST/SDMX_JSON.svc"

type Client struct {
	HTTP     *http.Client
	BaseURL  string
	Fallback ports.SeedCSVSource
}

var _ ports.IMFSource = (*Client)(nil)

func New(httpClient *http.Client, fallback ports.SeedCSVSource) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}
	return &Client{HTTP: httpClient, BaseURL: DefaultBaseURL, Fallback: fallback}
}

type sdmxResponse struct {
	CompactData struct {
		DataSet struct {
			Series json.RawMessage `json:"Series"`
		} `json:"DataSet"`
	} `json:"CompactData"`
}

type sdmxSeries struct {
	Obs json.RawMessage `json:"Obs"`
}

type sdmxObs struct {
	TimePeriod string `json:"@TIME_PERIOD"`
	ObsValue   string `json:"@OBS_VALUE"`
}

func (c *Client) FetchUSDReserveShare(ctx context.Context) ([]domain.Observation, error) {
	candidates := [][4]string{
		{"COFER", "Q", "W00", "RA_USD"},
		{"COFER", "Q", "W00", "USD_SHARE"},
		{"COFER", "Q", "1C_998", "RA_USD"},
	}
	var lastErr error
	for _, cand := range candidates {
		obs, err := c.fetchSeries(ctx, cand[0], cand[1], cand[2], cand[3])
		if err == nil && len(obs) > 0 {
			return obs, nil
		}
		lastErr = err
	}
	if c.Fallback != nil {
		if obs, err := c.Fallback.LoadSeries(domain.SeriesUSDReserveShare); err == nil && len(obs) > 0 {
			return obs, nil
		}
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("IMF COFER returned empty observations and no fallback available")
}

func (c *Client) fetchSeries(ctx context.Context, database, freq, area, indicator string) ([]domain.Observation, error) {
	base := strings.TrimRight(strings.TrimSpace(c.BaseURL), "/")
	if base == "" {
		base = DefaultBaseURL
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(30 * time.Second)
	}

	reqURL := fmt.Sprintf("%s/CompactData/%s/%s.%s.%s", base, database, freq, area, indicator)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Sumly Macro IMF Fetcher)")
	req.Header.Set("Accept", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	body, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		return nil, readErr
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("IMF API status %d", resp.StatusCode)
	}
	return ParseSDMXJSON(body)
}

func ParseSDMXJSON(data []byte) ([]domain.Observation, error) {
	var parsed sdmxResponse
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, fmt.Errorf("decode IMF SDMX response: %w", err)
	}
	rawSeries := bytesTrimSpace(parsed.CompactData.DataSet.Series)
	if len(rawSeries) == 0 || string(rawSeries) == "null" {
		return nil, fmt.Errorf("missing Series in IMF SDMX response")
	}

	var seriesList []sdmxSeries
	if rawSeries[0] == '[' {
		if err := json.Unmarshal(rawSeries, &seriesList); err != nil {
			return nil, err
		}
	} else {
		var single sdmxSeries
		if err := json.Unmarshal(rawSeries, &single); err != nil {
			return nil, err
		}
		seriesList = []sdmxSeries{single}
	}

	out := make([]domain.Observation, 0, 64)
	for _, s := range seriesList {
		rawObs := bytesTrimSpace(s.Obs)
		if len(rawObs) == 0 || string(rawObs) == "null" {
			continue
		}
		var obsList []sdmxObs
		if rawObs[0] == '[' {
			if err := json.Unmarshal(rawObs, &obsList); err != nil {
				return nil, err
			}
		} else {
			var single sdmxObs
			if err := json.Unmarshal(rawObs, &single); err != nil {
				return nil, err
			}
			obsList = []sdmxObs{single}
		}
		for _, item := range obsList {
			dt, err := ParseIMFDate(item.TimePeriod)
			if err != nil {
				continue
			}
			val, err := strconv.ParseFloat(strings.TrimSpace(item.ObsValue), 64)
			if err != nil || !domain.IsFinite(val) {
				continue
			}
			out = append(out, domain.Observation{Date: dt, Value: domain.RoundTo(val, 2)})
		}
	}
	return domain.SanitizeObservations(out), nil
}

func ParseIMFDate(period string) (time.Time, error) {
	p := strings.TrimSpace(period)
	if strings.Contains(p, "-Q") {
		parts := strings.SplitN(p, "-Q", 2)
		if len(parts) == 2 {
			year, err1 := strconv.Atoi(parts[0])
			quarter, err2 := strconv.Atoi(parts[1])
			if err1 == nil && err2 == nil && quarter >= 1 && quarter <= 4 {
				month := time.Month((quarter-1)*3 + 1)
				return time.Date(year, month, 1, 0, 0, 0, 0, time.UTC), nil
			}
		}
	}
	if len(p) == 4 {
		if year, err := strconv.Atoi(p); err == nil {
			return time.Date(year, 1, 1, 0, 0, 0, 0, time.UTC), nil
		}
	}
	return domain.ParseDate(p)
}

func bytesTrimSpace(b []byte) []byte {
	return []byte(strings.TrimSpace(string(b)))
}
