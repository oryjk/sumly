package providers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

// NativeSessionClient delegates current-account validation to the existing Sumly API.
type NativeSessionClient struct {
	endpoint string
	client   http.Client
}

func NewNativeSessionClient(endpoint string) (*NativeSessionClient, error) {
	u, err := url.Parse(endpoint)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return nil, errors.New("invalid native session endpoint")
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	return &NativeSessionClient{endpoint: u.String(), client: http.Client{
		Transport:     transport,
		Timeout:       2 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}, nil
}

func (c *NativeSessionClient) Me(ctx context.Context, token string) (domain.User, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.endpoint, nil)
	if err != nil {
		return domain.User{}, domain.ErrUnavailable
	}
	req.Header.Set("Authorization", "Bearer "+token)
	response, err := c.client.Do(req)
	if err != nil {
		return domain.User{}, domain.ErrUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return domain.User{}, domain.ErrCredentials
	}
	var payload struct {
		Code *int `json:"code"`
		Data struct {
			ID     int64  `json:"id"`
			Status string `json:"status"`
		} `json:"data"`
	}
	if response.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(response.Body, 8192)).Decode(&payload) != nil ||
		payload.Code == nil || *payload.Code != 0 || payload.Data.ID <= 0 {
		return domain.User{}, domain.ErrUnavailable
	}
	if payload.Data.Status != "active" {
		return domain.User{}, domain.ErrCredentials
	}
	return domain.User{ID: payload.Data.ID, Status: payload.Data.Status}, nil
}
