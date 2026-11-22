package bootstrap

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	appconfighttp "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/adapters/http"
	appconfigapp "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/application"
	appconfigdomain "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	authapplication "gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	holdingshttp "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/http"
	holdingsdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	macrohttp "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/http"
	macrodomain "gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	userhttp "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/http"
	userapplication "gitee.com/oryjk/sumly/sumly_go/internal/user/application"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"github.com/gin-gonic/gin"
)

const routerTestSecret = "01234567890123456789012345678901"

func TestHealthRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{})
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}
	const expected = `{"code":0,"message":"ok","data":{"status":"ok"}}`
	if response.Body.String() != expected {
		t.Fatalf("expected body %s, got %s", expected, response.Body.String())
	}
}

func TestWechatLoginRouteIsPublicAndVersioned(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{UserAuth: authhttp.NewHandler(routerWechatLogin{}, nil)})

	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/wechat/login", nil))
	if unauthorized.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected validation status %d, got %d", http.StatusUnprocessableEntity, unauthorized.Code)
	}

	unversioned := httptest.NewRecorder()
	router.ServeHTTP(unversioned, httptest.NewRequest(http.MethodPost, "/api/app/auth/wechat/login", nil))
	if unversioned.Code != http.StatusNotFound {
		t.Fatalf("unversioned route status=%d", unversioned.Code)
	}
}

func TestAppUserRoutesAreProtected(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	middleware := authhttp.NewMiddleware(tokens)
	router := NewRouter(Dependencies{
		AuthMiddleware: &middleware,
		AppUsers:       userhttp.NewAppHandler(routerAppUsers{}),
	})

	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/app/users/me", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status=%d body=%s", unauthorized.Code, unauthorized.Body.String())
	}

	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	request := httptest.NewRequest(http.MethodGet, "/api/v1/app/users/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("authorized status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestAppUserRoutesRejectFrozenUsers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	middleware := authhttp.NewMiddleware(tokens)
	router := NewRouter(Dependencies{
		AuthMiddleware: &middleware,
		ActiveUsers:    routerActiveUsers{err: sharederror.ErrUnauthorized},
		AppUsers:       userhttp.NewAppHandler(routerAppUsers{}),
	})
	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/app/users/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("frozen user status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestLocalH5PreflightIsAllowed(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{})
	request := httptest.NewRequest(http.MethodOptions, "/api/v1/app/auth/wechat/login", nil)
	request.Header.Set("Origin", "http://localhost:5173")
	request.Header.Set("Access-Control-Request-Method", http.MethodPost)
	request.Header.Set("Access-Control-Request-Headers", "authorization,content-type")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("expected preflight status %d, got %d", http.StatusNoContent, response.Code)
	}
	if response.Header().Get("Access-Control-Allow-Origin") != "http://localhost:5173" {
		t.Fatalf("unexpected allow origin %q", response.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestSwaggerRoutesServeEmbeddedOpenAPI(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{})

	redirect := httptest.NewRecorder()
	router.ServeHTTP(redirect, httptest.NewRequest(http.MethodGet, "/api/docs", nil))
	if redirect.Code < 300 || redirect.Code >= 400 || redirect.Header().Get("Location") != "/api/docs/" {
		t.Fatalf("docs redirect status=%d location=%q", redirect.Code, redirect.Header().Get("Location"))
	}

	for _, test := range []struct {
		path        string
		contentType string
		contains    string
	}{
		{path: "/api/docs/", contentType: "text/html", contains: "Swagger UI"},
		{path: "/api/docs/openapi.yaml", contentType: "application/yaml", contains: "openapi: 3.0.3"},
		{path: "/api/docs/swagger-ui.css", contentType: "text/css"},
	} {
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, test.path, nil))
		if response.Code != http.StatusOK || !strings.Contains(response.Header().Get("Content-Type"), test.contentType) {
			t.Fatalf("GET %s status=%d content-type=%q", test.path, response.Code, response.Header().Get("Content-Type"))
		}
		if test.contains != "" && !strings.Contains(response.Body.String(), test.contains) {
			t.Fatalf("GET %s body does not contain %q", test.path, test.contains)
		}
	}
}

type routerWechatLogin struct{}

func (routerWechatLogin) Execute(context.Context, string) (authapplication.WechatLoginResult, error) {
	return authapplication.WechatLoginResult{}, nil
}

type routerAppUsers struct{}

func (routerAppUsers) GetMe(context.Context, sharedauth.Actor) (userdomain.User, error) {
	return userdomain.User{}, nil
}

func (routerAppUsers) UpdateMe(context.Context, sharedauth.Actor, userapplication.UpdateMeCommand) (userdomain.User, error) {
	return userdomain.User{}, nil
}

type routerActiveUsers struct {
	err error
}

func (r routerActiveUsers) EnsureActive(context.Context, int64) error {
	return r.err
}

func TestDevLoginRouteRegisteredOnlyWhenEnabled(t *testing.T) {
	gin.SetMode(gin.TestMode)
	enabled := NewRouter(Dependencies{UserAuth: authhttp.NewHandler(routerWechatLogin{}, routerDevLogin{})})
	enabledResp := httptest.NewRecorder()
	enabled.ServeHTTP(enabledResp, httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/dev/login", nil))
	if enabledResp.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected dev login route to exist with validation status %d, got %d", http.StatusUnprocessableEntity, enabledResp.Code)
	}

	disabled := NewRouter(Dependencies{UserAuth: authhttp.NewHandler(routerWechatLogin{}, nil)})
	disabledResp := httptest.NewRecorder()
	disabled.ServeHTTP(disabledResp, httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/dev/login", nil))
	if disabledResp.Code != http.StatusNotFound {
		t.Fatalf("expected dev login route to be absent (404), got %d", disabledResp.Code)
	}
}

type routerDevLogin struct{}

func (routerDevLogin) Execute(context.Context, string) (authapplication.DevLoginResult, error) {
	return authapplication.DevLoginResult{}, nil
}

func TestHoldingsRoutesRequireJWTAndActiveUser(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	middleware := authhttp.NewMiddleware(tokens)
	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatal(err)
	}
	for _, frozen := range []bool{false, true} {
		checker := routerActiveUsers{}
		if frozen {
			checker.err = sharederror.ErrUnauthorized
		}
		router := NewRouter(Dependencies{AuthMiddleware: &middleware, ActiveUsers: checker, Holdings: holdingshttp.NewHandler(routerHoldings{})})
		for _, method := range []string{http.MethodGet, http.MethodPut} {
			for _, authorized := range []bool{false, true} {
				req := httptest.NewRequest(method, "/api/v1/app/holdings", strings.NewReader(`{"expectedRevision":0,"document":{"schemaVersion":1,"books":["默认账本"],"records":[]}}`))
				if authorized {
					req.Header.Set("Authorization", "Bearer "+token)
				}
				out := httptest.NewRecorder()
				router.ServeHTTP(out, req)
				want := 200
				if !authorized || frozen {
					want = 401
				}
				if out.Code != want {
					t.Fatalf("%s authorized=%v frozen=%v status=%d", method, authorized, frozen, out.Code)
				}
			}
		}
	}
}

type routerHoldings struct{}

func (routerHoldings) Get(_ context.Context, a sharedauth.Actor) (holdingsdomain.Snapshot, error) {
	if a.ID != 42 {
		return holdingsdomain.Snapshot{}, sharederror.ErrUnauthorized
	}
	return holdingsdomain.Snapshot{Document: holdingsdomain.EmptyDocument()}, nil
}
func (routerHoldings) Put(ctx context.Context, a sharedauth.Actor, _ int64, _ holdingsdomain.Document) (holdingsdomain.Snapshot, error) {
	return routerHoldings{}.Get(ctx, a)
}

func TestMacroRoutesArePublicAndVersioned(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{Macro: macrohttp.NewHandler(routerMacroQuery{})})
	for _, path := range []string{
		"/api/v1/app/macro/temperature",
		"/api/v1/app/macro/temperature/history",
		"/api/v1/app/macro/treasury",
		"/api/v1/app/macro/indicators",
		"/api/v1/app/macro/indicators/DFII10",
		"/api/v1/app/macro/cot/gold",
		"/api/v1/app/macro/sync/status",
	} {
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s status=%d body=%s", path, rec.Code, rec.Body.String())
		}
	}
}

type routerMacroQuery struct{}

func (routerMacroQuery) GetTemperature(context.Context) (macrodomain.TemperatureSnapshot, error) {
	return macrodomain.EmptyTemperatureSnapshot(), nil
}
func (routerMacroQuery) GetTemperatureHistory(context.Context, string) (macrodomain.Range, []macrodomain.TemperatureDailyPoint, error) {
	return macrodomain.Range3Y, []macrodomain.TemperatureDailyPoint{}, nil
}
func (routerMacroQuery) GetTreasuryDashboard(context.Context, string) (macrodomain.TreasuryDashboard, error) {
	return macrodomain.TreasuryDashboard{}, nil
}
func (routerMacroQuery) ListIndicators(context.Context, string) ([]macrodomain.SectionWithIndicators, error) {
	return []macrodomain.SectionWithIndicators{}, nil
}
func (routerMacroQuery) GetIndicatorDetail(context.Context, string, string) (macrodomain.IndicatorDetail, error) {
	return macrodomain.IndicatorDetail{Range: macrodomain.Range5Y, SyncStatus: "pending"}, nil
}
func (routerMacroQuery) GetGoldCot(context.Context, string) (macrodomain.CotDashboard, error) {
	return macrodomain.CotDashboard{SeriesID: macrodomain.SeriesGoldCOT, Range: macrodomain.Range3Y}, nil
}
func (routerMacroQuery) GetSyncStatus(context.Context) (macrodomain.SyncStatusOverview, error) {
	return macrodomain.SyncStatusOverview{}, nil
}
func (routerMacroQuery) GetStrategyBrief(_ context.Context, officialAccountName string) (macrodomain.StrategyBrief, error) {
	return macrodomain.BuildStrategyBrief(macrodomain.StrategyBriefInput{
		Snapshot:            macrodomain.EmptyTemperatureSnapshot(),
		OfficialAccountName: officialAccountName,
	}), nil
}

func TestMacroInternalStrategyBriefRouteAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)

	// Unconfigured token -> 404 even if caller sends a header
	unconfigured := NewRouter(Dependencies{Macro: macrohttp.NewHandler(routerMacroQuery{})})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil)
	req.Header.Set("X-Macro-Internal-Token", "anything")
	rec := httptest.NewRecorder()
	unconfigured.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 when internal token is unconfigured, got %d body=%s", rec.Code, rec.Body.String())
	}

	// Configured token -> rejects missing/wrong token with 401, accepts exact token with 200
	configured := NewRouter(Dependencies{
		Macro: macrohttp.NewHandlerWithOptions(routerMacroQuery{}, macrohttp.HandlerOptions{
			OfficialAccountName: "测试宏观号",
			InternalToken:       "macro-secret-123",
		}),
	})

	for _, tc := range []struct {
		name   string
		header string
		value  string
		want   int
	}{
		{name: "missing auth", want: http.StatusUnauthorized},
		{name: "wrong custom header", header: "X-Macro-Internal-Token", value: "wrong", want: http.StatusUnauthorized},
		{name: "wrong bearer", header: "Authorization", value: "Bearer wrong", want: http.StatusUnauthorized},
		{name: "valid custom header", header: "X-Macro-Internal-Token", value: "macro-secret-123", want: http.StatusOK},
		{name: "valid bearer", header: "Authorization", value: "Bearer macro-secret-123", want: http.StatusOK},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/api/v1/internal/macro/strategy-brief", nil)
			if tc.header != "" {
				r.Header.Set(tc.header, tc.value)
			}
			w := httptest.NewRecorder()
			configured.ServeHTTP(w, r)
			if w.Code != tc.want {
				t.Fatalf("status=%d want=%d body=%s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}

type routerAppConfigUseCase struct{}

func (routerAppConfigUseCase) GetPublicConfig(context.Context) (appconfigdomain.PublicAppConfig, error) {
	return appconfigdomain.PublicAppConfig{
		MembershipPaywall: appconfigdomain.DefaultMembershipPaywallConfig(),
		UpdatedAt:         time.Date(2026, 11, 22, 10, 35, 0, 0, time.UTC),
	}, nil
}
func (routerAppConfigUseCase) ListConfigs(context.Context) ([]appconfigdomain.ConfigEntry, error) {
	return []appconfigdomain.ConfigEntry{}, nil
}
func (routerAppConfigUseCase) UpdateConfig(_ context.Context, cmd appconfigapp.UpdateConfigCommand) (appconfigdomain.ConfigEntry, error) {
	return appconfigdomain.ConfigEntry{Key: cmd.Key, ValueJSON: cmd.ValueJSON, UpdatedAt: time.Now().UTC()}, nil
}
func (routerAppConfigUseCase) ListAuditLogs(context.Context, int) ([]appconfigdomain.AuditLog, error) {
	return []appconfigdomain.AuditLog{}, nil
}

func TestAppConfigPublicAdminCORSAndStaticRoutes(t *testing.T) {
	gin.SetMode(gin.TestMode)
	staticDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(staticDir, "index.html"), []byte("<html>ADMIN_INDEX</html>"), 0o644); err != nil {
		t.Fatal(err)
	}

	router := NewRouter(Dependencies{
		AppConfig: appconfighttp.NewHandler(routerAppConfigUseCase{}, appconfighttp.HandlerOptions{
			AdminToken: "admin-router-token",
		}),
		AdminStaticDir: staticDir,
	})

	// Public endpoint works without auth and sets no-store
	pubRec := httptest.NewRecorder()
	router.ServeHTTP(pubRec, httptest.NewRequest(http.MethodGet, "/api/v1/app/config", nil))
	if pubRec.Code != http.StatusOK || pubRec.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("GET /api/v1/app/config status=%d cache=%q body=%s", pubRec.Code, pubRec.Header().Get("Cache-Control"), pubRec.Body.String())
	}

	// Admin CORS preflight from https://oryjk.cn is NOT swallowed by localDevelopmentCORS
	optReq := httptest.NewRequest(http.MethodOptions, "/api/v1/admin/configs/membership_paywall", nil)
	optReq.Header.Set("Origin", "https://oryjk.cn")
	optReq.Header.Set("Access-Control-Request-Method", http.MethodPut)
	optReq.Header.Set("Access-Control-Request-Headers", "Authorization,X-Admin-Token,Content-Type")
	optRec := httptest.NewRecorder()
	router.ServeHTTP(optRec, optReq)
	if optRec.Code != http.StatusNoContent || optRec.Header().Get("Access-Control-Allow-Origin") != "https://oryjk.cn" {
		t.Fatalf("admin preflight status=%d allow-origin=%q", optRec.Code, optRec.Header().Get("Access-Control-Allow-Origin"))
	}

	// Admin verify rejects wrong token and accepts valid token
	badRec := httptest.NewRecorder()
	router.ServeHTTP(badRec, httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil))
	if badRec.Code != http.StatusUnauthorized {
		t.Fatalf("unauth verify status=%d want 401", badRec.Code)
	}

	okReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	okReq.Header.Set("Authorization", "Bearer admin-router-token")
	okRec := httptest.NewRecorder()
	router.ServeHTTP(okRec, okReq)
	if okRec.Code != http.StatusOK || !strings.Contains(okRec.Body.String(), `"valid":true`) || !strings.Contains(okRec.Body.String(), `"username":"token-admin"`) || !strings.Contains(okRec.Body.String(), `"must_change_password":false`) {
		t.Fatalf("auth verify status=%d body=%s", okRec.Code, okRec.Body.String())
	}

	// Static SPA mounted on /admin
	spaRec := httptest.NewRecorder()
	router.ServeHTTP(spaRec, httptest.NewRequest(http.MethodGet, "/admin", nil))
	if spaRec.Code != http.StatusOK || !strings.Contains(spaRec.Body.String(), "ADMIN_INDEX") {
		t.Fatalf("GET /admin status=%d body=%s", spaRec.Code, spaRec.Body.String())
	}
}
