package authhttp

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	"github.com/gin-gonic/gin"
)

type wechatHTTPGateway struct {
	ports.WechatGateway
	identity ports.WechatIdentity
	err      error
}

func (g wechatHTTPGateway) ExchangeCode(context.Context, string) (ports.WechatIdentity, error) {
	return g.identity, g.err
}

type wechatHTTPStore struct {
	ports.NativeStore
	user domain.User
	err  error
}

func (s wechatHTTPStore) LoginWechat(_ context.Context, _, _, _ string, _ domain.Session) (domain.User, error) {
	return s.user, s.err
}

type wechatHTTPCrypto struct{ ports.Cryptography }

func (wechatHTTPCrypto) Random() string { return "r" }
func (wechatHTTPCrypto) Digest(k, v string) string {
	return k + ":" + v
}

type wechatHTTPTokens struct{ ports.NativeTokens }

func (wechatHTTPTokens) IssueNative(context.Context, domain.Session) (string, error) {
	return "access", nil
}
func (wechatHTTPTokens) ParseNative(context.Context, string) (string, error) { return "sid", nil }

func wechatHandler(t *testing.T, user domain.User, gateway ports.WechatGateway) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	store := wechatHTTPStore{user: user}
	crypto := wechatHTTPCrypto{}
	tokens := wechatHTTPTokens{}
	sessions := application.Sessions{Crypto: crypto, Tokens: tokens}
	wechat := &application.WechatSessions{
		Wechat:   gateway,
		Store:    store,
		Crypto:   crypto,
		Tokens:   tokens,
		Sessions: sessions,
		AppID:    "wx-current",
	}
	accounts := application.Accounts{Wechat: wechat}
	r := gin.New()
	NewNativeHandler(accounts, sessions, wechat).RegisterRoutes(r.Group("/api/v1/app"))
	return r
}

func TestWechatSessionEndpointIssuesRefreshableSession(t *testing.T) {
	r := wechatHandler(t, domain.User{ID: 9, Status: "active", Provider: "wechat"},
		wechatHTTPGateway{identity: ports.WechatIdentity{OpenID: "o-1", SessionKey: "secret-key"}})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/wechat/session",
		bytes.NewBufferString(`{"js_code":"code-1"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	for _, want := range []string{`"token":"access"`, `"refresh_token"`, `"expires_in":900`, `"provider":"wechat"`} {
		if !strings.Contains(body, want) {
			t.Fatalf("body missing %s: %s", want, body)
		}
	}
	// 绝不下发 openid 或 session_key
	for _, forbidden := range []string{"openid", "session_key", "o-1", "secret-key"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("body leaked %s: %s", forbidden, body)
		}
	}
}

func TestWechatSessionEndpointRejectsEmptyCode(t *testing.T) {
	r := wechatHandler(t, domain.User{ID: 9, Status: "active"},
		wechatHTTPGateway{identity: ports.WechatIdentity{OpenID: "o"}})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/wechat/session",
		bytes.NewBufferString(`{"js_code":"  "}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422; body = %s", w.Code, w.Body.String())
	}
}

func TestWechatSessionEndpointRejectsUnknownFields(t *testing.T) {
	r := wechatHandler(t, domain.User{ID: 9, Status: "active"},
		wechatHTTPGateway{identity: ports.WechatIdentity{OpenID: "o"}})

	w := httptest.NewRecorder()
	// 客户端不得指定 openid
	req := httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/wechat/session",
		bytes.NewBufferString(`{"js_code":"c","openid":"attacker"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422; body = %s", w.Code, w.Body.String())
	}
}

func TestWechatSessionRouteAbsentWhenUnconfigured(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	NewNativeHandler(application.Accounts{}, application.Sessions{}, nil).RegisterRoutes(r.Group("/api/v1/app"))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/wechat/session",
		bytes.NewBufferString(`{"js_code":"c"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 when wechat unconfigured", w.Code)
	}
}

func TestWechatCapabilityAdvertisedWhenConfigured(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	crypto := wechatHTTPCrypto{}
	tokens := wechatHTTPTokens{}
	sessions := application.Sessions{Crypto: crypto, Tokens: tokens}
	wechat := &application.WechatSessions{
		Wechat: wechatHTTPGateway{}, Store: wechatHTTPStore{},
		Crypto: crypto, Tokens: tokens, Sessions: sessions, AppID: "wx-current",
	}
	NewNativeHandler(application.Accounts{Wechat: wechat}, sessions, wechat).
		RegisterRoutes(r.Group("/api/v1/app"))

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/app/auth/capabilities", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), `"wechat":true`) {
		t.Fatalf("capabilities missing wechat:true: %s", w.Body.String())
	}
}
