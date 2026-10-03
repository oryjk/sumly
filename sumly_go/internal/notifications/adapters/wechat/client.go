package wechat

import (
	"bytes"
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
)

// 微信订阅消息相关端点。真实字段名由部署方在配置里提供映射，
// 这里只负责按契约调用，不猜测模板结构。
const (
	code2SessionEndpoint = "https://api.weixin.qq.com/sns/jscode2session"
	tokenEndpoint        = "https://api.weixin.qq.com/cgi-bin/token"
	sendMessageEndpoint  = "https://api.weixin.qq.com/cgi-bin/message/subscribe/send"
)

// Client 实现订阅消息发送与 code 换取 openid。
type Client struct {
	httpClient *http.Client
	appID      string
	appSecret  string

	mu        sync.Mutex
	token     string
	tokenTill time.Time
}

// New 构造客户端。未配置 appid 时所有方法返回不可用。
func New(httpClient *http.Client, appID, appSecret string) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 10 * time.Second}
	}
	return &Client{httpClient: httpClient, appID: appID, appSecret: appSecret}
}

// Enabled 报告是否配置了 appid。
func (c *Client) Enabled() bool {
	return strings.TrimSpace(c.appID) != "" && strings.TrimSpace(c.appSecret) != ""
}

// ExchangeCode 用服务端验证过的 code 换取 openid。
func (c *Client) ExchangeCode(ctx context.Context, code string) (string, error) {
	if !c.Enabled() {
		return "", errors.New("wechat not configured")
	}
	query := url.Values{}
	query.Set("appid", c.appID)
	query.Set("secret", c.appSecret)
	query.Set("js_code", code)
	query.Set("grant_type", "authorization_code")

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, code2SessionEndpoint+"?"+query.Encode(), nil)
	if err != nil {
		return "", err
	}
	response, err := c.httpClient.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return "", err
	}
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("wechat jscode2session returned HTTP %d", response.StatusCode)
	}
	var payload struct {
		OpenID     string `json:"openid"`
		ErrCode    int    `json:"errcode"`
		ErrMessage string `json:"errmsg"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "", err
	}
	if payload.ErrCode != 0 {
		return "", fmt.Errorf("wechat jscode2session error %d", payload.ErrCode)
	}
	if strings.TrimSpace(payload.OpenID) == "" {
		return "", errors.New("wechat returned empty openid")
	}
	return payload.OpenID, nil
}

// accessToken 走服务端缓存，不在日志或响应中暴露。
func (c *Client) accessToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token != "" && time.Now().Before(c.tokenTill) {
		return c.token, nil
	}
	query := url.Values{}
	query.Set("grant_type", "client_credential")
	query.Set("appid", c.appID)
	query.Set("secret", c.appSecret)
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, tokenEndpoint+"?"+query.Encode(), nil)
	if err != nil {
		return "", err
	}
	response, err := c.httpClient.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return "", err
	}
	var payload struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
		ErrCode     int    `json:"errcode"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "", err
	}
	if payload.ErrCode != 0 || payload.AccessToken == "" {
		return "", fmt.Errorf("wechat token error %d", payload.ErrCode)
	}
	c.token = payload.AccessToken
	// 提前 5 分钟过期，避免边界失效
	c.tokenTill = time.Now().Add(time.Duration(payload.ExpiresIn-300) * time.Second)
	return c.token, nil
}

// Send 发送订阅消息。收件人由服务端指定，客户端无法干预。
func (c *Client) Send(ctx context.Context, recipient, template string, fields map[string]string) error {
	if !c.Enabled() {
		return errors.New("wechat not configured")
	}
	if strings.TrimSpace(recipient) == "" || strings.TrimSpace(template) == "" {
		return errors.New("wechat send requires recipient and template")
	}
	token, err := c.accessToken(ctx)
	if err != nil {
		return err
	}

	// 字段名由配置提供；未在 fields 中出现的键不参与构造，
	// 避免把任意客户端文本当作模板内容。
	data := map[string]any{}
	for key, name := range fields {
		if name == "" {
			continue
		}
		data[name] = map[string]any{"value": fields[key]}
	}
	payload := map[string]any{
		"touser":            recipient,
		"template_id":       template,
		"data":              data,
		"miniprogram_state": "formal",
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	endpoint := sendMessageEndpoint + "?access_token=" + url.QueryEscape(token)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(encoded))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := c.httpClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return err
	}
	var result struct {
		ErrCode int    `json:"errcode"`
		Msg     string `json:"errmsg"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return err
	}
	if result.ErrCode != 0 {
		return fmt.Errorf("wechat send error %d", result.ErrCode)
	}
	return nil
}

var _ = strconv.Itoa
