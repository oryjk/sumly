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

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
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
