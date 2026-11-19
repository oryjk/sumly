package providers

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

type ChanlunBridge struct {
	endpoint string
	secret   string
	client   http.Client
}

func NewChanlunBridge(endpoint, secret string) (*ChanlunBridge, error) {
	u, err := url.Parse(endpoint)
	if err != nil || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || len(secret) < 32 {
		return nil, errors.New("invalid Chanlun bridge configuration")
	}
	ip := net.ParseIP(u.Hostname())
	if u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "localhost" || ip.IsLoopback())) {
		return nil, errors.New("Chanlun bridge requires HTTPS or loopback HTTP")
	}
	return &ChanlunBridge{endpoint: u.String(), secret: secret, client: http.Client{
		Timeout:       6 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}, nil
}

func (b *ChanlunBridge) Issue(ctx context.Context, userID int64) (string, error) {
	payload, err := json.Marshal(struct {
		UserID int64 `json:"user_id"`
	}{userID})
	if err != nil {
		return "", domain.ErrUnavailable
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, b.endpoint, bytes.NewReader(payload))
	if err != nil {
		return "", domain.ErrUnavailable
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+b.secret)
	response, err := b.client.Do(req)
	if err != nil {
		return "", domain.ErrUnavailable
	}
	defer response.Body.Close()
	var data struct {
		Code string `json:"code"`
	}
	if response.StatusCode != http.StatusCreated || json.NewDecoder(io.LimitReader(response.Body, 2048)).Decode(&data) != nil {
		return "", domain.ErrUnavailable
	}
	if raw, err := base64.RawURLEncoding.Strict().DecodeString(data.Code); err != nil || len(raw) != 32 {
		return "", domain.ErrUnavailable
	}
	return data.Code, nil
}
