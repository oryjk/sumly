package eastmoney

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

const (
	defaultEndpoint = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
	defaultSecID    = "118.AU9999"
	defaultLimit    = 480
	defaultTimeout  = 10 * time.Second
	maxBodyBytes    = 8 << 20
	userAgent       = "Mozilla/5.0"
	referer         = "https://quote.eastmoney.com/"
)

// shanghaiZone 东方财富 1 分钟 K 线时间戳按 Asia/Shanghai（UTC+8）给出；
// 若运行环境缺失 tzdata 则回退固定 UTC+8，保证最小容器镜像同样可用。
var shanghaiZone = loadShanghaiZone()

func loadShanghaiZone() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}

// Client 从东方财富拉取 1 分钟真实分时 K 线（如上金所 118.AU9999）。
type Client struct {
	HTTP     *http.Client
	SecID    string
	Endpoint string
}

var _ ports.GoldIntradaySource = (*Client)(nil)

func NewClient(httpClient *http.Client, secID string) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultTimeout}
	}
	if strings.TrimSpace(secID) == "" {
		secID = defaultSecID
	}
	return &Client{
		HTTP:     httpClient,
		SecID:    secID,
		Endpoint: defaultEndpoint,
	}
}

func (c *Client) FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.requestURL(), nil)
	if err != nil {
		return nil, fmt.Errorf("create eastmoney request: %w", err)
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Referer", referer)

	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultTimeout}
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call eastmoney intraday: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("eastmoney intraday HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBodyBytes))
	if err != nil {
		return nil, fmt.Errorf("read eastmoney intraday: %w", err)
	}
	return parseIntraday(body)
}

func (c *Client) requestURL() string {
	base := strings.TrimSpace(c.Endpoint)
	if base == "" {
		base = defaultEndpoint
	}
	secID := strings.TrimSpace(c.SecID)
	if secID == "" {
		secID = defaultSecID
	}
	return fmt.Sprintf(
		"%s?secid=%s&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56&klt=1&fqt=1&lmt=%d&end=20500101",
		base,
		url.QueryEscape(secID),
		defaultLimit,
	)
}

func parseIntraday(body []byte) ([]domain.IntradayPoint, error) {
	var envelope struct {
		Data *struct {
			KLines []string `json:"klines"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return nil, fmt.Errorf("decode eastmoney intraday: %w", err)
	}
	if envelope.Data == nil || len(envelope.Data.KLines) == 0 {
		return nil, fmt.Errorf("eastmoney intraday missing klines")
	}
	byTime := make(map[int64]domain.IntradayPoint, len(envelope.Data.KLines))
	for _, line := range envelope.Data.KLines {
		fields := strings.Split(line, ",")
		if len(fields) < 3 {
			continue
		}
		stamp, err := time.ParseInLocation("2006-01-02 15:04", strings.TrimSpace(fields[0]), shanghaiZone)
		if err != nil {
			continue
		}
		// fields2=f51,f52,f53,f54,f55,f56 -> f51=时间, f52=开, f53=收, f54=高, f55=低, f56=量
		closePrice, err := strconv.ParseFloat(strings.TrimSpace(fields[2]), 64)
		if err != nil || closePrice <= 0 || math.IsNaN(closePrice) || math.IsInf(closePrice, 0) {
			continue
		}
		byTime[stamp.Unix()] = domain.IntradayPoint{Time: stamp, Price: closePrice}
	}
	if len(byTime) == 0 {
		return nil, fmt.Errorf("eastmoney intraday contains no valid points")
	}
	points := make([]domain.IntradayPoint, 0, len(byTime))
	for _, p := range byTime {
		points = append(points, p)
	}
	sort.Slice(points, func(i, j int) bool { return points[i].Time.Before(points[j].Time) })
	return points, nil
}
