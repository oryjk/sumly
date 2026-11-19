package authhttp

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"github.com/gin-gonic/gin"
)

type chanlunTestBridge struct{ userID int64 }

func (g *chanlunTestBridge) Issue(_ context.Context, userID int64) (string, error) {
	g.userID = userID
	return "one-time-code", nil
}

type chanlunTestSessions struct{}

func (chanlunTestSessions) Me(_ context.Context, token string) (domain.User, error) {
	if token != "valid" {
		return domain.User{}, domain.ErrCredentials
	}
	return domain.User{ID: 42}, nil
}

func TestChanlunTicketUsesAuthenticatedIdentity(t *testing.T) {
	r := gin.New()
	gateway := &chanlunTestBridge{}
	NewChanlunHandler(chanlunTestSessions{}, gateway).RegisterRoutes(r.Group("/api/v1/app"))
	for _, c := range []struct {
		token string
		want  int
	}{{"", 401}, {"invalid", 401}, {"valid", 200}} {
		req := httptest.NewRequest("POST", "/api/v1/app/auth/chanlun/session", strings.NewReader(`{"user_id":89}`))
		if c.token != "" {
			req.Header.Set("Authorization", "Bearer "+c.token)
		}
		out := httptest.NewRecorder()
		r.ServeHTTP(out, req)
		if out.Code != c.want {
			t.Fatalf("token %q: status %d, want %d", c.token, out.Code, c.want)
		}
		if c.want != 200 && gateway.userID != 0 {
			t.Fatal("issued a ticket to an unauthorized request")
		}
		if c.want == 200 && (gateway.userID != 42 || !strings.Contains(out.Body.String(), `"code":"one-time-code"`) || out.Header().Get("Cache-Control") != "no-store") {
			t.Fatalf("ticket must use native identity and be uncacheable: %d", gateway.userID)
		}
	}
}
