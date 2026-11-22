package authhttp

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"github.com/gin-gonic/gin"
)

func TestNativeContractDisabledAndBounded(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := NewNativeHandler(application.Accounts{}, application.Sessions{}, nil)
	h.RegisterRoutes(r.Group("/api/v1/app"))
	for _, tc := range []struct {
		method, path, body string
		status             int
	}{
		{"GET", "/capabilities", "", 200}, {"POST", "/phone/code", `{"phone_number":"13800138000"}`, 503},
		{"POST", "/email/register", `{"email":"a@example.com","password":"abcdefghijkl","code":"123456"}`, 503},
		{"POST", "/apple/challenge", `{}`, 503}, {"GET", "/me", "", 401}, {"DELETE", "/account", `{"confirmation":"DELETE"}`, 401},
		{"POST", "/apple/reauthenticate/challenge", `{}`, 401},
		{"POST", "/apple/reauthenticate", `{"challenge_id":"test","identity_token":"fake","authorization_code":"fake"}`, 401},
		{"POST", "/google/challenge", `{}`, 503},
		{"POST", "/google/challenge", `null`, 422},
		{"POST", "/google/challenge", `{}{}`, 422},
		{"POST", "/google/login", `{"challenge_id":"test","identity_token":"fake"}`, 503},
		{"POST", "/google/login", `{"email":"a@example.com"}`, 422},
		{"POST", "/google/link", `{"challenge_id":"test","identity_token":"fake"}`, 401},
		{"POST", "/google/reauthenticate/challenge", `{}`, 401},
		{"POST", "/google/reauthenticate", `{"challenge_id":"test","identity_token":"fake"}`, 401},
		{"POST", "/email/link/code", `{"email":"a@example.com"}`, 401},
		{"POST", "/email/link", `{"email":"a@example.com","password":"abcdefghijkl","code":"123456"}`, 401},
		{"POST", "/phone/login", strings.Repeat("x", 40000), 422},
	} {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(tc.method, "/api/v1/app/auth"+tc.path, strings.NewReader(tc.body))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)
		if w.Code != tc.status {
			t.Fatalf("%s %s: %d %s", tc.method, tc.path, w.Code, w.Body.String())
		}
		if tc.path == "/capabilities" && w.Body.String() != `{"code":0,"message":"ok","data":{"apple":false,"wechat":false,"phone":false,"email":false}}` {
			t.Fatal(w.Body.String())
		}
	}
	_ = http.MethodPost
}

func TestNativeLinkProofFailureKeepsBearerAuthenticated(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	nativeError(c, domain.ErrLinkProof)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("link proof error produced %d, want 422", w.Code)
	}
}

func TestNativeReauthenticationMismatchResponse(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, err := range []error{domain.ErrAccountMismatch, domain.ErrAppleAccountMismatch} {
		w := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(w)
		nativeError(c, err)
		if w.Code != http.StatusConflict || !strings.Contains(w.Body.String(), err.Error()) {
			t.Fatalf("unexpected mismatch response: %d %s", w.Code, w.Body.String())
		}
	}
}
