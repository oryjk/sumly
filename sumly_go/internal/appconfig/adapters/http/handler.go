package appconfighttp

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

const (
	maxUpdateRequestBodyBytes = 64 * 1024
	maxAuthRequestBodyBytes   = 16 * 1024

	codeMustChangePassword = 40301
	adminIdentityCtxKey    = "sumly_admin_identity"
)

// DefaultAdminCORSOrigins 是管理后台默认允许的跨域来源。
var DefaultAdminCORSOrigins = []string{
	"http://localhost:5173",
	"http://127.0.0.1:5173",
	"https://oryjk.cn",
}

// UseCase 定义 HTTP 层依赖的远程配置业务能力。
type UseCase interface {
	GetPublicConfig(ctx context.Context) (domain.PublicAppConfig, error)
	ListConfigs(ctx context.Context) ([]domain.ConfigEntry, error)
	UpdateConfig(ctx context.Context, cmd application.UpdateConfigCommand) (domain.ConfigEntry, error)
	ListAuditLogs(ctx context.Context, limit int) ([]domain.AuditLog, error)
}

// AdminAuthUseCase 定义 HTTP 层依赖的管理员账号登录、会话校验与改密能力。
type AdminAuthUseCase interface {
	Login(ctx context.Context, username, password string) (domain.AdminLoginResult, error)
	Authenticate(ctx context.Context, rawToken string) (domain.AdminIdentity, error)
	Logout(ctx context.Context, identity domain.AdminIdentity) error
	ChangePassword(ctx context.Context, identity domain.AdminIdentity, currentPassword, newPassword string) (domain.ChangePasswordResult, error)
}

type HandlerOptions struct {
	AdminAuth   AdminAuthUseCase
	AdminToken  string
	CORSOrigins []string
}

type Handler struct {
	useCase     UseCase
	adminAuth   AdminAuthUseCase
	adminToken  string
	corsOrigins map[string]struct{}
}

func NewHandler(useCase UseCase, opts HandlerOptions) *Handler {
	origins := opts.CORSOrigins
	if len(origins) == 0 {
		origins = DefaultAdminCORSOrigins
	}
	allowed := make(map[string]struct{}, len(origins))
	for _, raw := range origins {
		normalized := strings.TrimRight(strings.TrimSpace(raw), "/")
		if normalized != "" {
			allowed[normalized] = struct{}{}
		}
	}
	return &Handler{
		useCase:     useCase,
		adminAuth:   opts.AdminAuth,
		adminToken:  strings.TrimSpace(opts.AdminToken),
		corsOrigins: allowed,
	}
}

func (h *Handler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.GET("/config", h.GetPublicConfig)
}

func (h *Handler) RegisterAdminRoutes(group *gin.RouterGroup) {
	group.Use(h.CORSMiddleware())
	group.OPTIONS("/*path", func(c *gin.Context) {
		c.AbortWithStatus(http.StatusNoContent)
	})

	group.POST("/auth/login", h.Login)

	protected := group.Group("")
	protected.Use(h.AdminAuthMiddleware())
	protected.POST("/auth/logout", h.Logout)
	protected.GET("/auth/verify", h.VerifyAuth)
	protected.POST("/auth/change-password", h.ChangePassword)
	protected.GET("/configs", h.ListConfigs)
	protected.PUT("/configs/:key", h.RequirePasswordChangedMiddleware(), h.UpdateConfig)
	protected.GET("/configs/audit-logs", h.ListAuditLogs)
}

func (h *Handler) CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Vary", "Origin")
		origin := strings.TrimRight(strings.TrimSpace(c.GetHeader("Origin")), "/")
		if origin != "" {
			if _, ok := h.corsOrigins[origin]; ok {
				c.Header("Access-Control-Allow-Origin", origin)
				c.Header("Access-Control-Allow-Methods", "GET,POST,PATCH,PUT,DELETE,OPTIONS")
				c.Header("Access-Control-Allow-Headers", "Authorization,Content-Type,X-Admin-Token")
				c.Header("Access-Control-Allow-Credentials", "true")
				c.Header("Access-Control-Max-Age", "600")
			}
		}

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func (h *Handler) AdminAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Fail-closed：既未启用账号会话鉴权也未配置 ADMIN_API_TOKEN 时明确返回 503，绝不放行。
		if h.adminAuth == nil && h.adminToken == "" {
			c.AbortWithStatusJSON(http.StatusServiceUnavailable, sharedhttp.Response[any]{
				Code:    http.StatusServiceUnavailable,
				Message: "admin api is not configured",
				Data:    nil,
			})
			return
		}

		candidate := extractAdminToken(c)
		if candidate == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, sharedhttp.Response[any]{
				Code:    http.StatusUnauthorized,
				Message: "unauthorized",
				Data:    nil,
			})
			return
		}

		if h.adminAuth != nil {
			identity, err := h.adminAuth.Authenticate(c.Request.Context(), candidate)
			if err != nil {
				sharedhttpapi.WriteError(c, err)
				c.Abort()
				return
			}
			c.Set(adminIdentityCtxKey, identity)
			c.Next()
			return
		}

		if subtle.ConstantTimeCompare([]byte(candidate), []byte(h.adminToken)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, sharedhttp.Response[any]{
				Code:    http.StatusUnauthorized,
				Message: "unauthorized",
				Data:    nil,
			})
			return
		}
		c.Set(adminIdentityCtxKey, domain.AdminIdentity{
			Username:           domain.StaticTokenAdminUsername,
			MustChangePassword: false,
			IsStaticToken:      true,
		})
		c.Next()
	}
}

func (h *Handler) RequirePasswordChangedMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		identity, ok := adminIdentityFromContext(c)
		if ok && identity.MustChangePassword {
			c.AbortWithStatusJSON(http.StatusForbidden, sharedhttp.Response[any]{
				Code:    codeMustChangePassword,
				Message: "请先修改初始密码后再变更配置",
				Data:    nil,
			})
			return
		}
		c.Next()
	}
}

type PublicConfigResponse struct {
	MembershipPaywall domain.MembershipPaywallConfig `json:"membership_paywall"`
	UpdatedAt         string                         `json:"updated_at"`
}

type AdminLoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type AdminLoginResponse struct {
	Token              string `json:"token"`
	Username           string `json:"username"`
	MustChangePassword bool   `json:"must_change_password"`
	ExpiresAt          string `json:"expires_at"`
}

type AdminLogoutResponse struct {
	LoggedOut bool `json:"logged_out"`
}

type VerifyAuthResponse struct {
	Valid              bool   `json:"valid"`
	Username           string `json:"username"`
	MustChangePassword bool   `json:"must_change_password"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

type ChangePasswordResponse struct {
	Username           string `json:"username"`
	MustChangePassword bool   `json:"must_change_password"`
}

type ConfigEntryResponse struct {
	Key         string          `json:"key"`
	Value       json.RawMessage `json:"value"`
	Description string          `json:"description"`
	UpdatedBy   string          `json:"updated_by"`
	UpdatedAt   string          `json:"updated_at"`
}

type AuditLogResponse struct {
	ID        int64           `json:"id"`
	ConfigKey string          `json:"config_key"`
	OldValue  json.RawMessage `json:"old_value"`
	NewValue  json.RawMessage `json:"new_value"`
	Operator  string          `json:"operator"`
	Note      string          `json:"note"`
	CreatedAt string          `json:"created_at"`
}

type updateConfigRequest struct {
	Value       json.RawMessage `json:"value"`
	Description *string         `json:"description"`
	Operator    string          `json:"operator"`
	Note        string          `json:"note"`
}

func (h *Handler) GetPublicConfig(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	cfg, err := h.useCase.GetPublicConfig(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, PublicConfigResponse{
		MembershipPaywall: cfg.MembershipPaywall,
		UpdatedAt:         formatRFC3339(cfg.UpdatedAt),
	})
}

func (h *Handler) Login(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	if h.adminAuth == nil {
		c.AbortWithStatusJSON(http.StatusServiceUnavailable, sharedhttp.Response[any]{
			Code:    http.StatusServiceUnavailable,
			Message: "admin auth is not configured",
			Data:    nil,
		})
		return
	}
	body, err := io.ReadAll(io.LimitReader(c.Request.Body, maxAuthRequestBodyBytes+1))
	if err != nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "failed to read request body"))
		return
	}
	if len(body) > maxAuthRequestBodyBytes {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "request body too large"))
		return
	}
	var req AdminLoginRequest
	if err := json.Unmarshal(body, &req); err != nil {
		sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "invalid JSON request body", err))
		return
	}

	result, err := h.adminAuth.Login(c.Request.Context(), req.Username, req.Password)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, AdminLoginResponse{
		Token:              result.Token,
		Username:           result.Username,
		MustChangePassword: result.MustChangePassword,
		ExpiresAt:          formatRFC3339(result.ExpiresAt),
	})
}

func (h *Handler) Logout(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	identity, _ := adminIdentityFromContext(c)
	if h.adminAuth != nil {
		if err := h.adminAuth.Logout(c.Request.Context(), identity); err != nil {
			sharedhttpapi.WriteError(c, err)
			return
		}
	}
	sharedhttpapi.WriteSuccess(c, AdminLogoutResponse{LoggedOut: true})
}

func (h *Handler) VerifyAuth(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	identity, _ := adminIdentityFromContext(c)
	sharedhttpapi.WriteSuccess(c, VerifyAuthResponse{
		Valid:              true,
		Username:           identity.Username,
		MustChangePassword: identity.MustChangePassword,
	})
}

func (h *Handler) ChangePassword(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	if h.adminAuth == nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindUnauthorized, "session token is required to change password"))
		return
	}
	identity, ok := adminIdentityFromContext(c)
	if !ok {
		sharedhttpapi.WriteError(c, sharederror.ErrUnauthorized)
		return
	}

	body, err := io.ReadAll(io.LimitReader(c.Request.Body, maxAuthRequestBodyBytes+1))
	if err != nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "failed to read request body"))
		return
	}
	if len(body) > maxAuthRequestBodyBytes {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "request body too large"))
		return
	}
	var req ChangePasswordRequest
	if err := json.Unmarshal(body, &req); err != nil {
		sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "invalid JSON request body", err))
		return
	}

	result, err := h.adminAuth.ChangePassword(c.Request.Context(), identity, req.CurrentPassword, req.NewPassword)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, ChangePasswordResponse{
		Username:           result.Username,
		MustChangePassword: result.MustChangePassword,
	})
}

func (h *Handler) ListConfigs(c *gin.Context) {
	items, err := h.useCase.ListConfigs(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	out := make([]ConfigEntryResponse, 0, len(items))
	for _, item := range items {
		out = append(out, toConfigEntryResponse(item))
	}
	sharedhttpapi.WriteSuccess(c, out)
}

func (h *Handler) UpdateConfig(c *gin.Context) {
	body, err := io.ReadAll(io.LimitReader(c.Request.Body, maxUpdateRequestBodyBytes+1))
	if err != nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "failed to read request body"))
		return
	}
	if len(body) > maxUpdateRequestBodyBytes {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "request body too large"))
		return
	}

	var req updateConfigRequest
	if err := json.Unmarshal(body, &req); err != nil {
		sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "invalid JSON request body", err))
		return
	}

	operator := strings.TrimSpace(req.Operator)
	if operator == "" {
		if identity, ok := adminIdentityFromContext(c); ok {
			operator = identity.Username
		}
	}

	updated, err := h.useCase.UpdateConfig(c.Request.Context(), application.UpdateConfigCommand{
		Key:         c.Param("key"),
		ValueJSON:   req.Value,
		Description: req.Description,
		Operator:    operator,
		Note:        req.Note,
	})
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, toConfigEntryResponse(updated))
}

func (h *Handler) ListAuditLogs(c *gin.Context) {
	limit := 0
	if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil {
			sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "limit must be an integer"))
			return
		}
		limit = parsed
	}
	logs, err := h.useCase.ListAuditLogs(c.Request.Context(), limit)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	out := make([]AuditLogResponse, 0, len(logs))
	for _, item := range logs {
		out = append(out, toAuditLogResponse(item))
	}
	sharedhttpapi.WriteSuccess(c, out)
}

func toConfigEntryResponse(entry domain.ConfigEntry) ConfigEntryResponse {
	val := json.RawMessage(`{}`)
	if len(bytes.TrimSpace(entry.ValueJSON)) > 0 {
		val = entry.ValueJSON
	}
	return ConfigEntryResponse{
		Key:         entry.Key,
		Value:       val,
		Description: entry.Description,
		UpdatedBy:   entry.UpdatedBy,
		UpdatedAt:   formatRFC3339(entry.UpdatedAt),
	}
}

func toAuditLogResponse(item domain.AuditLog) AuditLogResponse {
	var oldVal json.RawMessage
	if len(bytes.TrimSpace(item.OldValueJSON)) > 0 {
		oldVal = item.OldValueJSON
	}
	newVal := json.RawMessage(`{}`)
	if len(bytes.TrimSpace(item.NewValueJSON)) > 0 {
		newVal = item.NewValueJSON
	}
	return AuditLogResponse{
		ID:        item.ID,
		ConfigKey: item.ConfigKey,
		OldValue:  oldVal,
		NewValue:  newVal,
		Operator:  item.Operator,
		Note:      item.Note,
		CreatedAt: formatRFC3339(item.CreatedAt),
	}
}

func formatRFC3339(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

func extractAdminToken(c *gin.Context) string {
	if token := strings.TrimSpace(c.GetHeader("X-Admin-Token")); token != "" {
		return token
	}
	auth := strings.TrimSpace(c.GetHeader("Authorization"))
	if len(auth) >= 7 && strings.EqualFold(auth[:7], "bearer ") {
		return strings.TrimSpace(auth[7:])
	}
	return ""
}

func adminIdentityFromContext(c *gin.Context) (domain.AdminIdentity, bool) {
	raw, exists := c.Get(adminIdentityCtxKey)
	if !exists {
		return domain.AdminIdentity{}, false
	}
	identity, ok := raw.(domain.AdminIdentity)
	return identity, ok
}

// AdminUsernameFromContext 提取经 AdminAuthMiddleware 鉴权后的管理员用户名。
func AdminUsernameFromContext(c *gin.Context) string {
	identity, ok := adminIdentityFromContext(c)
	if !ok {
		return ""
	}
	return identity.Username
}
