package appconfighttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/adapters/password"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/gin-gonic/gin"
)

type stubRepo struct {
	entries map[string]domain.ConfigEntry
	logs    []domain.AuditLog
	nextID  int64
	now     time.Time
}

func newStubRepo() *stubRepo {
	return &stubRepo{
		entries: map[string]domain.ConfigEntry{},
		now:     time.Date(2026, 11, 22, 10, 35, 0, 0, time.UTC),
	}
}

func (r *stubRepo) GetByKey(_ context.Context, key string) (domain.ConfigEntry, bool, error) {
	e, ok := r.entries[key]
	return e, ok, nil
}

func (r *stubRepo) ListAll(_ context.Context) ([]domain.ConfigEntry, error) {
	out := make([]domain.ConfigEntry, 0, len(r.entries))
	for _, e := range r.entries {
		out = append(out, e)
	}
	return out, nil
}

func (r *stubRepo) UpsertWithAudit(_ context.Context, params ports.UpsertParams) (domain.ConfigEntry, error) {
	oldEntry, exists := r.entries[params.Key]
	var oldVal json.RawMessage
	desc := ""
	if exists {
		oldVal = append(json.RawMessage(nil), oldEntry.ValueJSON...)
		desc = oldEntry.Description
	}
	if params.Description != nil {
		desc = *params.Description
	}
	updated := domain.ConfigEntry{
		Key:         params.Key,
		ValueJSON:   append(json.RawMessage(nil), params.ValueJSON...),
		Description: desc,
		UpdatedBy:   params.Operator,
		UpdatedAt:   r.now,
	}
	r.entries[params.Key] = updated

	r.nextID++
	r.logs = append([]domain.AuditLog{{
		ID:           r.nextID,
		ConfigKey:    params.Key,
		OldValueJSON: oldVal,
		NewValueJSON: append(json.RawMessage(nil), params.ValueJSON...),
		Operator:     params.Operator,
		Note:         params.Note,
		CreatedAt:    r.now,
	}}, r.logs...)
	return updated, nil
}

func (r *stubRepo) ListAuditLogs(_ context.Context, limit int) ([]domain.AuditLog, error) {
	if limit > len(r.logs) {
		limit = len(r.logs)
	}
	return append([]domain.AuditLog(nil), r.logs[:limit]...), nil
}

func newTestRouter(repo ports.Repository, opts HandlerOptions) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	svc := application.NewService(repo)
	h := NewHandler(svc, opts)
	v1 := r.Group("/api/v1")
	h.RegisterPublicRoutes(v1.Group("/app"))
	h.RegisterAdminRoutes(v1.Group("/admin"))
	return r
}

func TestPublicAppConfigDefaultAndNoStore(t *testing.T) {
	router := newTestRouter(newStubRepo(), HandlerOptions{})

	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/app/config", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control=%q, want no-store", got)
	}

	var envelope struct {
		Code int                  `json:"code"`
		Data PublicConfigResponse `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if envelope.Code != 0 {
		t.Fatalf("code=%d, want 0", envelope.Code)
	}
	if !envelope.Data.MembershipPaywall.ChanlunRequiresMembership || !envelope.Data.MembershipPaywall.MembershipEntryVisible || envelope.Data.MembershipPaywall.FreeAccessNotice != "" {
		t.Fatalf("unexpected default paywall config: %+v", envelope.Data.MembershipPaywall)
	}
	if envelope.Data.UpdatedAt == "" {
		t.Fatal("expected non-empty updated_at")
	}
}

func TestAdminEndpointsFailClosedWhenTokenUnconfigured(t *testing.T) {
	router := newTestRouter(newStubRepo(), HandlerOptions{AdminToken: ""})

	endpoints := []struct {
		method string
		path   string
		body   string
	}{
		{http.MethodGet, "/api/v1/admin/auth/verify", ""},
		{http.MethodGet, "/api/v1/admin/configs", ""},
		{http.MethodPut, "/api/v1/admin/configs/membership_paywall", `{"value":{"chanlun_requires_membership":false,"membership_entry_visible":true}}`},
		{http.MethodGet, "/api/v1/admin/configs/audit-logs", ""},
	}
	for _, ep := range endpoints {
		req := httptest.NewRequest(ep.method, ep.path, strings.NewReader(ep.body))
		req.Header.Set("Authorization", "Bearer anything")
		req.Header.Set("X-Admin-Token", "anything")
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s %s status=%d want 503 body=%s", ep.method, ep.path, rec.Code, rec.Body.String())
		}
	}
}

func TestAdminAuthRejectsWrongOrMissingTokenAndAcceptsBothHeaders(t *testing.T) {
	router := newTestRouter(newStubRepo(), HandlerOptions{AdminToken: "super-secret-admin-token"})

	cases := []struct {
		name   string
		header string
		value  string
		want   int
	}{
		{name: "missing", want: http.StatusUnauthorized},
		{name: "wrong bearer", header: "Authorization", value: "Bearer wrong-token", want: http.StatusUnauthorized},
		{name: "wrong custom header", header: "X-Admin-Token", value: "wrong-token", want: http.StatusUnauthorized},
		{name: "valid bearer", header: "Authorization", value: "Bearer super-secret-admin-token", want: http.StatusOK},
		{name: "valid custom header", header: "X-Admin-Token", value: "super-secret-admin-token", want: http.StatusOK},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
			if tc.header != "" {
				req.Header.Set(tc.header, tc.value)
			}
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("status=%d want=%d body=%s", rec.Code, tc.want, rec.Body.String())
			}
		})
	}
}

func TestAdminUpdateConfigWritesAuditAndUpdatesPublicConfig(t *testing.T) {
	repo := newStubRepo()
	router := newTestRouter(repo, HandlerOptions{AdminToken: "secret-123"})

	// Update membership_paywall to free access
	putReq := httptest.NewRequest(http.MethodPut, "/api/v1/admin/configs/membership_paywall", strings.NewReader(`{
		"value": {
			"chanlun_requires_membership": false,
			"membership_entry_visible": false,
			"free_access_notice": "  端午限时免费  "
		},
		"description": "会员订阅与功能付费开关配置",
		"operator": "admin",
		"note": "切换为限时免费"
	}`))
	putReq.Header.Set("Authorization", "Bearer secret-123")
	putRec := httptest.NewRecorder()
	router.ServeHTTP(putRec, putReq)
	if putRec.Code != http.StatusOK {
		t.Fatalf("PUT status=%d body=%s", putRec.Code, putRec.Body.String())
	}

	// Verify public endpoint reflects updated value
	pubRec := httptest.NewRecorder()
	router.ServeHTTP(pubRec, httptest.NewRequest(http.MethodGet, "/api/v1/app/config", nil))
	if pubRec.Code != http.StatusOK {
		t.Fatalf("GET public config status=%d body=%s", pubRec.Code, pubRec.Body.String())
	}
	var pubEnv struct {
		Code int                  `json:"code"`
		Data PublicConfigResponse `json:"data"`
	}
	if err := json.Unmarshal(pubRec.Body.Bytes(), &pubEnv); err != nil {
		t.Fatalf("unmarshal public config: %v", err)
	}
	if pubEnv.Data.MembershipPaywall.ChanlunRequiresMembership || pubEnv.Data.MembershipPaywall.MembershipEntryVisible || pubEnv.Data.MembershipPaywall.FreeAccessNotice != "端午限时免费" {
		t.Fatalf("unexpected updated public config: %+v", pubEnv.Data)
	}

	// Verify GET /api/v1/admin/configs
	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/configs", nil)
	listReq.Header.Set("X-Admin-Token", "secret-123")
	listRec := httptest.NewRecorder()
	router.ServeHTTP(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("GET configs status=%d body=%s", listRec.Code, listRec.Body.String())
	}
	var listEnv struct {
		Code int                   `json:"code"`
		Data []ConfigEntryResponse `json:"data"`
	}
	if err := json.Unmarshal(listRec.Body.Bytes(), &listEnv); err != nil {
		t.Fatalf("unmarshal configs: %v", err)
	}
	if len(listEnv.Data) != 1 || listEnv.Data[0].Key != "membership_paywall" || listEnv.Data[0].UpdatedBy != "admin" {
		t.Fatalf("unexpected configs list: %+v", listEnv.Data)
	}

	// Verify GET /api/v1/admin/configs/audit-logs
	auditReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/configs/audit-logs?limit=30", nil)
	auditReq.Header.Set("Authorization", "Bearer secret-123")
	auditRec := httptest.NewRecorder()
	router.ServeHTTP(auditRec, auditReq)
	if auditRec.Code != http.StatusOK {
		t.Fatalf("GET audit-logs status=%d body=%s", auditRec.Code, auditRec.Body.String())
	}
	var auditEnv struct {
		Code int                `json:"code"`
		Data []AuditLogResponse `json:"data"`
	}
	if err := json.Unmarshal(auditRec.Body.Bytes(), &auditEnv); err != nil {
		t.Fatalf("unmarshal audit logs: %v", err)
	}
	if len(auditEnv.Data) != 1 || auditEnv.Data[0].ConfigKey != "membership_paywall" || auditEnv.Data[0].Note != "切换为限时免费" {
		t.Fatalf("unexpected audit logs: %+v", auditEnv.Data)
	}
	if string(auditEnv.Data[0].OldValue) != "null" {
		t.Fatalf("expected old_value null on initial write, got %s", string(auditEnv.Data[0].OldValue))
	}
}

func TestAdminUpdateRejectsInvalidJSONAndTooLongNotice(t *testing.T) {
	router := newTestRouter(newStubRepo(), HandlerOptions{AdminToken: "secret-123"})

	badBodies := []struct {
		name string
		key  string
		body string
	}{
		{name: "malformed json", key: "membership_paywall", body: `{broken`},
		{name: "notice too long", key: "membership_paywall", body: `{"value":{"chanlun_requires_membership":false,"membership_entry_visible":true,"free_access_notice":"` + strings.Repeat("限", 121) + `"}}`},
		{name: "missing required boolean", key: "membership_paywall", body: `{"value":{"chanlun_requires_membership":false}}`},
		{name: "non-object extension value", key: "custom_flag", body: `{"value":[1,2,3]}`},
	}
	for _, tc := range badBodies {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/configs/"+tc.key, strings.NewReader(tc.body))
			req.Header.Set("Authorization", "Bearer secret-123")
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != http.StatusUnprocessableEntity {
				t.Fatalf("status=%d want 422 body=%s", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestAdminCORSPreflightAndOriginFiltering(t *testing.T) {
	router := newTestRouter(newStubRepo(), HandlerOptions{AdminToken: "secret-123"})

	for _, allowed := range DefaultAdminCORSOrigins {
		req := httptest.NewRequest(http.MethodOptions, "/api/v1/admin/configs", nil)
		req.Header.Set("Origin", allowed)
		req.Header.Set("Access-Control-Request-Method", http.MethodPut)
		req.Header.Set("Access-Control-Request-Headers", "Authorization,X-Admin-Token,Content-Type")
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusNoContent {
			t.Fatalf("origin %s preflight status=%d, want 204", allowed, rec.Code)
		}
		if got := rec.Header().Get("Access-Control-Allow-Origin"); got != allowed {
			t.Fatalf("origin %s allow-origin=%q", allowed, got)
		}
		if !strings.Contains(rec.Header().Get("Access-Control-Allow-Headers"), "X-Admin-Token") {
			t.Fatalf("expected X-Admin-Token in allow-headers, got %q", rec.Header().Get("Access-Control-Allow-Headers"))
		}
	}

	disallowedReq := httptest.NewRequest(http.MethodOptions, "/api/v1/admin/configs", nil)
	disallowedReq.Header.Set("Origin", "https://evil.example.com")
	disallowedRec := httptest.NewRecorder()
	router.ServeHTTP(disallowedRec, disallowedReq)
	if disallowedRec.Code != http.StatusNoContent {
		t.Fatalf("disallowed preflight status=%d, want 204", disallowedRec.Code)
	}
	if got := disallowedRec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("disallowed origin should not get allow-origin header, got %q", got)
	}
}

func TestRegisterStaticRoutesSPAAndPathTraversalProtection(t *testing.T) {
	gin.SetMode(gin.TestMode)

	parentDir := t.TempDir()
	secretFile := filepath.Join(parentDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("TOP_SECRET_VALUE"), 0o600); err != nil {
		t.Fatal(err)
	}

	staticDir := filepath.Join(parentDir, "dist")
	if err := os.MkdirAll(filepath.Join(staticDir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staticDir, "index.html"), []byte("<!doctype html><html><body>SUMLY_ADMIN_SPA</body></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staticDir, "assets", "app.js"), []byte("console.log('sumly-admin');"), 0o644); err != nil {
		t.Fatal(err)
	}
	// Symlink escaping staticDir must also be blocked
	if err := os.Symlink(secretFile, filepath.Join(staticDir, "leak.txt")); err != nil {
		t.Fatal(err)
	}

	// Empty or non-existent dir does not mount routes
	emptyRouter := gin.New()
	if RegisterStaticRoutes(emptyRouter, "") {
		t.Fatal("expected empty dir not to mount")
	}
	if RegisterStaticRoutes(emptyRouter, filepath.Join(parentDir, "does-not-exist")) {
		t.Fatal("expected missing dir not to mount")
	}

	router := gin.New()
	if !RegisterStaticRoutes(router, staticDir) {
		t.Fatal("expected existing dir to mount")
	}

	// /admin and /admin/ serve index.html
	for _, p := range []string{"/admin", "/admin/", "/admin/configs/audit"} {
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, p, nil))
		if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "SUMLY_ADMIN_SPA") {
			t.Fatalf("GET %s status=%d body=%q", p, rec.Code, rec.Body.String())
		}
	}

	// Static asset served properly
	assetRec := httptest.NewRecorder()
	router.ServeHTTP(assetRec, httptest.NewRequest(http.MethodGet, "/admin/assets/app.js", nil))
	if assetRec.Code != http.StatusOK || !strings.Contains(assetRec.Body.String(), "sumly-admin") {
		t.Fatalf("GET /admin/assets/app.js status=%d body=%q", assetRec.Code, assetRec.Body.String())
	}

	// Path traversal and symlink escape must be blocked (403) and never leak secret
	for _, attack := range []string{
		"/admin/../secret.txt",
		"/admin/%2e%2e/secret.txt",
		"/admin/assets/../../secret.txt",
		"/admin/leak.txt",
	} {
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, attack, nil))
		if rec.Code != http.StatusForbidden {
			t.Fatalf("attack %s status=%d want 403 body=%q", attack, rec.Code, rec.Body.String())
		}
		if strings.Contains(rec.Body.String(), "TOP_SECRET_VALUE") {
			t.Fatalf("attack %s leaked secret!", attack)
		}
	}
}

type stubAdminAuthRepo struct {
	usersByID       map[int64]domain.AdminUser
	usersByUsername map[string]int64
	sessions        map[string]domain.AdminSession
	nextUserID      int64
}

func newStubAdminAuthRepo() *stubAdminAuthRepo {
	return &stubAdminAuthRepo{
		usersByID:       map[int64]domain.AdminUser{},
		usersByUsername: map[string]int64{},
		sessions:        map[string]domain.AdminSession{},
	}
}

func (r *stubAdminAuthRepo) EnsureAdminUser(_ context.Context, username, passwordHash string, mustChangePassword bool) (bool, error) {
	if _, exists := r.usersByUsername[username]; exists {
		return false, nil
	}
	r.nextUserID++
	now := time.Now().UTC()
	u := domain.AdminUser{
		ID:                 r.nextUserID,
		Username:           username,
		PasswordHash:       passwordHash,
		MustChangePassword: mustChangePassword,
		CreatedAt:          now,
		UpdatedAt:          now,
	}
	r.usersByID[u.ID] = u
	r.usersByUsername[username] = u.ID
	return true, nil
}

func (r *stubAdminAuthRepo) GetAdminUserByUsername(_ context.Context, username string) (domain.AdminUser, bool, error) {
	id, ok := r.usersByUsername[username]
	if !ok {
		return domain.AdminUser{}, false, nil
	}
	return r.usersByID[id], true, nil
}

func (r *stubAdminAuthRepo) GetAdminUserByID(_ context.Context, id int64) (domain.AdminUser, bool, error) {
	u, ok := r.usersByID[id]
	return u, ok, nil
}

func (r *stubAdminAuthRepo) CreateSession(_ context.Context, session domain.AdminSession) error {
	r.sessions[session.TokenHash] = session
	return nil
}

func (r *stubAdminAuthRepo) GetValidSessionWithUser(_ context.Context, tokenHash string, now time.Time) (domain.AdminSession, domain.AdminUser, bool, error) {
	s, ok := r.sessions[tokenHash]
	if !ok || !s.ExpiresAt.After(now) {
		return domain.AdminSession{}, domain.AdminUser{}, false, nil
	}
	u, ok := r.usersByID[s.AdminUserID]
	if !ok {
		return domain.AdminSession{}, domain.AdminUser{}, false, nil
	}
	return s, u, true, nil
}

func (r *stubAdminAuthRepo) DeleteSession(_ context.Context, tokenHash string) error {
	delete(r.sessions, tokenHash)
	return nil
}

func (r *stubAdminAuthRepo) UpdatePasswordAndRevokeOtherSessions(_ context.Context, userID int64, newPasswordHash, keepTokenHash string, changedAt time.Time) (domain.AdminUser, error) {
	u, ok := r.usersByID[userID]
	if !ok {
		return domain.AdminUser{}, sharederror.ErrUnauthorized
	}
	ts := changedAt.UTC()
	u.PasswordHash = newPasswordHash
	u.MustChangePassword = false
	u.PasswordChangedAt = &ts
	u.UpdatedAt = ts
	r.usersByID[userID] = u
	for hash, sess := range r.sessions {
		if sess.AdminUserID == userID && hash != keepTokenHash {
			delete(r.sessions, hash)
		}
	}
	return u, nil
}

func (r *stubAdminAuthRepo) DeleteExpiredSessions(_ context.Context, now time.Time) error {
	for hash, sess := range r.sessions {
		if !sess.ExpiresAt.After(now) {
			delete(r.sessions, hash)
		}
	}
	return nil
}

func TestAdminPasswordAuthFullLifecycleHTTP(t *testing.T) {
	cfgRepo := newStubRepo()
	authRepo := newStubAdminAuthRepo()
	hasher := password.NewBcryptHasher()
	authSvc := application.NewAdminAuthService(authRepo, hasher, "fallback-cli-token")

	ctx := context.Background()
	if err := authSvc.EnsureBootstrapAdmin(ctx, "admin", "InitialSecret#1"); err != nil {
		t.Fatalf("EnsureBootstrapAdmin failed: %v", err)
	}

	router := newTestRouter(cfgRepo, HandlerOptions{
		AdminAuth:  authSvc,
		AdminToken: "fallback-cli-token",
	})

	// 1. Login with wrong password / unknown user returns 401
	for _, body := range []string{
		`{"username":"admin","password":"wrong-password"}`,
		`{"username":"unknown","password":"InitialSecret#1"}`,
	} {
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/login", strings.NewReader(body)))
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("bad login %s status=%d want 401 body=%s", body, rec.Code, rec.Body.String())
		}
	}

	// 2. Successful login returns token + must_change_password=true + expires_at
	loginRec := httptest.NewRecorder()
	router.ServeHTTP(loginRec, httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/login", strings.NewReader(`{"username":"admin","password":"InitialSecret#1"}`)))
	if loginRec.Code != http.StatusOK {
		t.Fatalf("login status=%d body=%s", loginRec.Code, loginRec.Body.String())
	}
	var loginEnv struct {
		Code int                `json:"code"`
		Data AdminLoginResponse `json:"data"`
	}
	if err := json.Unmarshal(loginRec.Body.Bytes(), &loginEnv); err != nil {
		t.Fatalf("unmarshal login response: %v", err)
	}
	if loginEnv.Code != 0 || len(loginEnv.Data.Token) != 64 || loginEnv.Data.Username != "admin" || !loginEnv.Data.MustChangePassword || loginEnv.Data.ExpiresAt == "" {
		t.Fatalf("unexpected login response: %+v", loginEnv)
	}
	token1 := loginEnv.Data.Token

	// Second login creates another active session
	loginRec2 := httptest.NewRecorder()
	router.ServeHTTP(loginRec2, httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/login", strings.NewReader(`{"username":"admin","password":"InitialSecret#1"}`)))
	if loginRec2.Code != http.StatusOK {
		t.Fatalf("second login status=%d body=%s", loginRec2.Code, loginRec2.Body.String())
	}
	var loginEnv2 struct {
		Data AdminLoginResponse `json:"data"`
	}
	if err := json.Unmarshal(loginRec2.Body.Bytes(), &loginEnv2); err != nil {
		t.Fatal(err)
	}
	token2 := loginEnv2.Data.Token

	// 3. Verify returns valid=true, username=admin, must_change_password=true
	verifyReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	verifyReq.Header.Set("Authorization", "Bearer "+token1)
	verifyRec := httptest.NewRecorder()
	router.ServeHTTP(verifyRec, verifyReq)
	if verifyRec.Code != http.StatusOK {
		t.Fatalf("verify status=%d body=%s", verifyRec.Code, verifyRec.Body.String())
	}
	var verifyEnv struct {
		Code int                `json:"code"`
		Data VerifyAuthResponse `json:"data"`
	}
	if err := json.Unmarshal(verifyRec.Body.Bytes(), &verifyEnv); err != nil {
		t.Fatal(err)
	}
	if !verifyEnv.Data.Valid || verifyEnv.Data.Username != "admin" || !verifyEnv.Data.MustChangePassword {
		t.Fatalf("unexpected verify data: %+v", verifyEnv.Data)
	}

	// 4. First-login constraint: PUT /configs/:key is blocked with 403 + code 40301 until password is changed
	putPayload := `{"value":{"chanlun_requires_membership":false,"membership_entry_visible":true,"free_access_notice":"测试"},"note":"首次改密前尝试"}`
	blockedPut := httptest.NewRequest(http.MethodPut, "/api/v1/admin/configs/membership_paywall", strings.NewReader(putPayload))
	blockedPut.Header.Set("Authorization", "Bearer "+token1)
	blockedRec := httptest.NewRecorder()
	router.ServeHTTP(blockedRec, blockedPut)
	if blockedRec.Code != http.StatusForbidden {
		t.Fatalf("PUT before password change status=%d want 403 body=%s", blockedRec.Code, blockedRec.Body.String())
	}
	var errEnv struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(blockedRec.Body.Bytes(), &errEnv); err != nil {
		t.Fatal(err)
	}
	if errEnv.Code != 40301 || errEnv.Message != "请先修改初始密码后再变更配置" {
		t.Fatalf("unexpected 403 body: %+v", errEnv)
	}

	// GET /configs remains readable while must_change_password=true
	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/configs", nil)
	listReq.Header.Set("Authorization", "Bearer "+token1)
	listRec := httptest.NewRecorder()
	router.ServeHTTP(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("GET /configs status=%d want 200 body=%s", listRec.Code, listRec.Body.String())
	}

	// 5. Change password validation checks (401 wrong current, 422 short/too-long/same, 401 static token)
	badChangeCases := []struct {
		name  string
		token string
		body  string
		want  int
	}{
		{name: "wrong current password", token: token1, body: `{"current_password":"Wrong","new_password":"NewStrongPass#2"}`, want: http.StatusUnauthorized},
		{name: "new password too short", token: token1, body: `{"current_password":"InitialSecret#1","new_password":"1234567"}`, want: http.StatusUnprocessableEntity},
		{name: "new password over 72 bytes", token: token1, body: `{"current_password":"InitialSecret#1","new_password":"` + strings.Repeat("a", 73) + `"}`, want: http.StatusUnprocessableEntity},
		{name: "new password equals current", token: token1, body: `{"current_password":"InitialSecret#1","new_password":"InitialSecret#1"}`, want: http.StatusUnprocessableEntity},
		{name: "static fallback token rejected for change-password", token: "fallback-cli-token", body: `{"current_password":"InitialSecret#1","new_password":"NewStrongPass#2"}`, want: http.StatusUnauthorized},
	}
	for _, tc := range badChangeCases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/change-password", strings.NewReader(tc.body))
			req.Header.Set("Authorization", "Bearer "+tc.token)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("status=%d want %d body=%s", rec.Code, tc.want, rec.Body.String())
			}
		})
	}

	// 6. Valid change password updates DB, clears must_change_password, revokes token2, keeps token1
	changeReq := httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/change-password", strings.NewReader(`{"current_password":"InitialSecret#1","new_password":"RotatedStrongPass#2026"}`))
	changeReq.Header.Set("Authorization", "Bearer "+token1)
	changeRec := httptest.NewRecorder()
	router.ServeHTTP(changeRec, changeReq)
	if changeRec.Code != http.StatusOK {
		t.Fatalf("change-password status=%d body=%s", changeRec.Code, changeRec.Body.String())
	}
	var changeEnv struct {
		Code int                    `json:"code"`
		Data ChangePasswordResponse `json:"data"`
	}
	if err := json.Unmarshal(changeRec.Body.Bytes(), &changeEnv); err != nil {
		t.Fatal(err)
	}
	if changeEnv.Code != 0 || changeEnv.Data.Username != "admin" || changeEnv.Data.MustChangePassword {
		t.Fatalf("unexpected change-password response: %+v", changeEnv)
	}

	// token2 was revoked
	revokedReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	revokedReq.Header.Set("Authorization", "Bearer "+token2)
	revokedRec := httptest.NewRecorder()
	router.ServeHTTP(revokedRec, revokedReq)
	if revokedRec.Code != http.StatusUnauthorized {
		t.Fatalf("revoked session status=%d want 401 body=%s", revokedRec.Code, revokedRec.Body.String())
	}

	// token1 still works and reports must_change_password=false
	verifyAfterReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	verifyAfterReq.Header.Set("Authorization", "Bearer "+token1)
	verifyAfterRec := httptest.NewRecorder()
	router.ServeHTTP(verifyAfterRec, verifyAfterReq)
	if verifyAfterRec.Code != http.StatusOK {
		t.Fatalf("verify after change status=%d body=%s", verifyAfterRec.Code, verifyAfterRec.Body.String())
	}
	var verifyAfterEnv struct {
		Data VerifyAuthResponse `json:"data"`
	}
	if err := json.Unmarshal(verifyAfterRec.Body.Bytes(), &verifyAfterEnv); err != nil {
		t.Fatal(err)
	}
	if !verifyAfterEnv.Data.Valid || verifyAfterEnv.Data.MustChangePassword {
		t.Fatalf("expected must_change_password=false after change, got %+v", verifyAfterEnv.Data)
	}

	// Restart bootstrap does not overwrite updated password
	if err := authSvc.EnsureBootstrapAdmin(ctx, "admin", "InitialSecret#1"); err != nil {
		t.Fatalf("EnsureBootstrapAdmin on restart failed: %v", err)
	}
	oldLoginRec := httptest.NewRecorder()
	router.ServeHTTP(oldLoginRec, httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/login", strings.NewReader(`{"username":"admin","password":"InitialSecret#1"}`)))
	if oldLoginRec.Code != http.StatusUnauthorized {
		t.Fatalf("old password must fail after change+restart, got %d", oldLoginRec.Code)
	}
	newLoginRec := httptest.NewRecorder()
	router.ServeHTTP(newLoginRec, httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/login", strings.NewReader(`{"username":"admin","password":"RotatedStrongPass#2026"}`)))
	if newLoginRec.Code != http.StatusOK {
		t.Fatalf("new password login failed: status=%d body=%s", newLoginRec.Code, newLoginRec.Body.String())
	}

	// 7. PUT /configs/:key now succeeds and defaults operator to logged-in username "admin"
	allowedPut := httptest.NewRequest(http.MethodPut, "/api/v1/admin/configs/membership_paywall", strings.NewReader(putPayload))
	allowedPut.Header.Set("Authorization", "Bearer "+token1)
	allowedRec := httptest.NewRecorder()
	router.ServeHTTP(allowedRec, allowedPut)
	if allowedRec.Code != http.StatusOK {
		t.Fatalf("PUT after password change status=%d body=%s", allowedRec.Code, allowedRec.Body.String())
	}
	var putEnv struct {
		Data ConfigEntryResponse `json:"data"`
	}
	if err := json.Unmarshal(allowedRec.Body.Bytes(), &putEnv); err != nil {
		t.Fatal(err)
	}
	if putEnv.Data.UpdatedBy != "admin" {
		t.Fatalf("expected default operator 'admin', got %q", putEnv.Data.UpdatedBy)
	}

	// 8. Logout invalidates token1
	logoutReq := httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/logout", nil)
	logoutReq.Header.Set("Authorization", "Bearer "+token1)
	logoutRec := httptest.NewRecorder()
	router.ServeHTTP(logoutRec, logoutReq)
	if logoutRec.Code != http.StatusOK || !strings.Contains(logoutRec.Body.String(), `"logged_out":true`) {
		t.Fatalf("logout status=%d body=%s", logoutRec.Code, logoutRec.Body.String())
	}
	afterLogoutReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	afterLogoutReq.Header.Set("Authorization", "Bearer "+token1)
	afterLogoutRec := httptest.NewRecorder()
	router.ServeHTTP(afterLogoutRec, afterLogoutReq)
	if afterLogoutRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 after logout, got %d body=%s", afterLogoutRec.Code, afterLogoutRec.Body.String())
	}

	// 9. Expired session returns 401
	var newLoginEnv struct {
		Data AdminLoginResponse `json:"data"`
	}
	if err := json.Unmarshal(newLoginRec.Body.Bytes(), &newLoginEnv); err != nil {
		t.Fatal(err)
	}
	expiredHash := application.HashSessionToken(newLoginEnv.Data.Token)
	sess := authRepo.sessions[expiredHash]
	sess.ExpiresAt = time.Now().UTC().Add(-1 * time.Second)
	authRepo.sessions[expiredHash] = sess

	expiredReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	expiredReq.Header.Set("Authorization", "Bearer "+newLoginEnv.Data.Token)
	expiredRec := httptest.NewRecorder()
	router.ServeHTTP(expiredRec, expiredReq)
	if expiredRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for expired session, got %d body=%s", expiredRec.Code, expiredRec.Body.String())
	}

	// 10. Fallback ADMIN_API_TOKEN compatibility
	fallbackVerifyReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil)
	fallbackVerifyReq.Header.Set("Authorization", "Bearer fallback-cli-token")
	fallbackVerifyRec := httptest.NewRecorder()
	router.ServeHTTP(fallbackVerifyRec, fallbackVerifyReq)
	if fallbackVerifyRec.Code != http.StatusOK {
		t.Fatalf("fallback token verify status=%d body=%s", fallbackVerifyRec.Code, fallbackVerifyRec.Body.String())
	}
	var fallbackEnv struct {
		Data VerifyAuthResponse `json:"data"`
	}
	if err := json.Unmarshal(fallbackVerifyRec.Body.Bytes(), &fallbackEnv); err != nil {
		t.Fatal(err)
	}
	if !fallbackEnv.Data.Valid || fallbackEnv.Data.Username != "token-admin" || fallbackEnv.Data.MustChangePassword {
		t.Fatalf("unexpected fallback verify payload: %+v", fallbackEnv.Data)
	}

	// Fallback token can PUT config without operator and attributes to token-admin
	fallbackPut := httptest.NewRequest(http.MethodPut, "/api/v1/admin/configs/membership_paywall", strings.NewReader(putPayload))
	fallbackPut.Header.Set("X-Admin-Token", "fallback-cli-token")
	fallbackPutRec := httptest.NewRecorder()
	router.ServeHTTP(fallbackPutRec, fallbackPut)
	if fallbackPutRec.Code != http.StatusOK {
		t.Fatalf("fallback PUT status=%d body=%s", fallbackPutRec.Code, fallbackPutRec.Body.String())
	}
	var fallbackPutEnv struct {
		Data ConfigEntryResponse `json:"data"`
	}
	if err := json.Unmarshal(fallbackPutRec.Body.Bytes(), &fallbackPutEnv); err != nil {
		t.Fatal(err)
	}
	if fallbackPutEnv.Data.UpdatedBy != "token-admin" {
		t.Fatalf("expected fallback operator 'token-admin', got %q", fallbackPutEnv.Data.UpdatedBy)
	}
}

func TestAdminAuthWorksWithoutStaticAPITokenAndCORSOnAuthRoutes(t *testing.T) {
	authRepo := newStubAdminAuthRepo()
	authSvc := application.NewAdminAuthService(authRepo, password.NewBcryptHasher(), "")
	if err := authSvc.EnsureBootstrapAdmin(context.Background(), "admin", "OnlyDBPass#2026"); err != nil {
		t.Fatal(err)
	}
	router := newTestRouter(newStubRepo(), HandlerOptions{
		AdminAuth: authSvc,
	})

	// Missing token returns 401 (NOT 503) because DB admin auth is enabled
	unauthRec := httptest.NewRecorder()
	router.ServeHTTP(unauthRec, httptest.NewRequest(http.MethodGet, "/api/v1/admin/auth/verify", nil))
	if unauthRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 when AdminAuth enabled without ADMIN_API_TOKEN, got %d body=%s", unauthRec.Code, unauthRec.Body.String())
	}

	// CORS preflight succeeds on all /api/v1/admin/auth/* paths
	for _, p := range []string{
		"/api/v1/admin/auth/login",
		"/api/v1/admin/auth/logout",
		"/api/v1/admin/auth/verify",
		"/api/v1/admin/auth/change-password",
	} {
		req := httptest.NewRequest(http.MethodOptions, p, nil)
		req.Header.Set("Origin", "https://oryjk.cn")
		req.Header.Set("Access-Control-Request-Method", http.MethodPost)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusNoContent || rec.Header().Get("Access-Control-Allow-Origin") != "https://oryjk.cn" {
			t.Fatalf("OPTIONS %s status=%d allow-origin=%q", p, rec.Code, rec.Header().Get("Access-Control-Allow-Origin"))
		}
	}
}
