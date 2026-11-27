package jijinhao

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

const (
	defaultEndpoint      = "https://api.jijinhao.com/quoteCenter/history.htm"
	defaultCode          = "JO_71" // 上海黄金交易所 Au99.99
	defaultPageSize      = 500     // 集金号单页硬上限为 500 条
	defaultPages         = 2       // 双页合计最多 1000 根，覆盖日盘(391)+夜盘(391)=782 根以上
	defaultTimeout       = 10 * time.Second
	defaultPageTimeout   = 5 * time.Second
	secondaryPageReserve = time.Second
	maxBodyBytes         = 8 << 20
	userAgent            = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
	referer              = "https://quote.cngold.org/"
)

var shanghaiZone = loadShanghaiZone()

func loadShanghaiZone() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}

// Client 从集金号拉取上金所品种（如 JO_71 对应 Au99.99）的 1 分钟真实成交 K 线。
type Client struct {
	HTTP        *http.Client
	Code        string
	Endpoint    string
	PageSize    int
	Pages       int
	PageTimeout time.Duration
}

var _ ports.GoldIntradaySource = (*Client)(nil)

func NewClient(httpClient *http.Client, code string) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultTimeout}
	}
	if strings.TrimSpace(code) == "" {
		code = defaultCode
	}
	return &Client{
		HTTP:        httpClient,
		Code:        code,
		Endpoint:    defaultEndpoint,
		PageSize:    defaultPageSize,
		Pages:       defaultPages,
		PageTimeout: defaultPageTimeout,
	}
}

func (c *Client) FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	pageTimeout := c.pageTimeout()
	merged, err := c.fetchPage(ctx, 1, pageTimeout)
	if err != nil {
		return nil, err
	}

	pages := c.Pages
	if pages <= 0 {
		pages = defaultPages
	}
	for page := 2; page <= pages; page++ {
		if ctx.Err() != nil {
			break
		}
		budget := pageTimeout
		if deadline, ok := ctx.Deadline(); ok {
			remaining := time.Until(deadline) - secondaryPageReserve
			if remaining <= 0 {
				break
			}
			if remaining < budget {
				budget = remaining
			}
		}
		older, pageErr := c.fetchPage(ctx, page, budget)
		if pageErr != nil {
			slog.Warn("jijinhao secondary intraday page failed; degrading to fetched pages",
				"code", c.Code, "page", page, "error", pageErr)
			break
		}
		merged = mergeIntradayPoints(older, merged)
	}
	return merged, nil
}

func (c *Client) pageTimeout() time.Duration {
	if c.PageTimeout > 0 {
		return c.PageTimeout
	}
	return defaultPageTimeout
}

func (c *Client) fetchPage(ctx context.Context, page int, timeout time.Duration) ([]domain.IntradayPoint, error) {
	pageCtx := ctx
	var cancel context.CancelFunc
	if timeout > 0 {
		pageCtx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}

	req, err := http.NewRequestWithContext(pageCtx, http.MethodGet, c.requestURL(page), nil)
	if err != nil {
		return nil, fmt.Errorf("create jijinhao request: %w", err)
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Referer", referer)

	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultTimeout}
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call jijinhao intraday page %d: %w", page, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("jijinhao intraday page %d HTTP %d", page, resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBodyBytes))
	if err != nil {
		return nil, fmt.Errorf("read jijinhao intraday page %d: %w", page, err)
	}
	return parseIntraday(body)
}

func (c *Client) requestURL(page int) string {
	base := strings.TrimSpace(c.Endpoint)
	if base == "" {
		base = defaultEndpoint
	}
	code := strings.TrimSpace(c.Code)
	if code == "" {
		code = defaultCode
	}
	pageSize := c.PageSize
	if pageSize <= 0 {
		pageSize = defaultPageSize
	}
	if page <= 0 {
		page = 1
	}
	return fmt.Sprintf(
		"%s?code=%s&style=0&currentPage=%d&pageSize=%d",
		base,
		url.QueryEscape(code),
		page,
		pageSize,
	)
}

func mergeIntradayPoints(older, newer []domain.IntradayPoint) []domain.IntradayPoint {
	byTime := make(map[int64]domain.IntradayPoint, len(older)+len(newer))
	for _, p := range older {
		byTime[p.Time.Unix()] = p
	}
	for _, p := range newer {
		byTime[p.Time.Unix()] = p
	}
	points := make([]domain.IntradayPoint, 0, len(byTime))
	for _, p := range byTime {
		points = append(points, p)
	}
	sort.Slice(points, func(i, j int) bool { return points[i].Time.Before(points[j].Time) })
	return points
}

func parseIntraday(body []byte) ([]domain.IntradayPoint, error) {
	text := string(body)
	start := strings.Index(text, "{")
	end := strings.LastIndex(text, "}")
	if start < 0 || end <= start {
		return nil, fmt.Errorf("jijinhao intraday missing JSON object")
	}

	var envelope struct {
		Flag bool `json:"flag"`
		Data []struct {
			Time  int64   `json:"time"` // Unix 毫秒时间戳
			Close float64 `json:"q2"`   // 收盘价
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(text[start:end+1]), &envelope); err != nil {
		return nil, fmt.Errorf("decode jijinhao intraday: %w", err)
	}
	if !envelope.Flag || len(envelope.Data) == 0 {
		return nil, fmt.Errorf("jijinhao intraday missing data")
	}

	byTime := make(map[int64]domain.IntradayPoint, len(envelope.Data))
	for _, row := range envelope.Data {
		if row.Time <= 0 || row.Close <= 0 || math.IsNaN(row.Close) || math.IsInf(row.Close, 0) {
			continue
		}
		stamp := time.UnixMilli(row.Time).In(shanghaiZone).Truncate(time.Minute)
		byTime[stamp.Unix()] = domain.IntradayPoint{
			Time:  stamp,
			Price: row.Close,
		}
	}
	if len(byTime) == 0 {
		return nil, fmt.Errorf("jijinhao intraday contains no valid points")
	}

	points := make([]domain.IntradayPoint, 0, len(byTime))
	for _, p := range byTime {
		points = append(points, p)
	}
	sort.Slice(points, func(i, j int) bool { return points[i].Time.Before(points[j].Time) })
	return points, nil
}
