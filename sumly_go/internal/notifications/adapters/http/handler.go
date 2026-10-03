package http

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

// GrantHeader 承载订阅授权令牌。刻意不复用登录 token——
// 授权只允许发消息，不授予任何账户访问权。
const GrantHeader = "X-Holding-Notification-Grant"

type Handler struct {
	alerts application.HoldingAlerts
	// ActorUserID 从会话提取；游客为 0。
	ActorUserID func(*gin.Context) int64
	// Workspace 由请求方给出（guest 或 user:<id>）。
	Workspace func(*gin.Context) string
}

func NewHandler(alerts application.HoldingAlerts) *Handler {
	return &Handler{
		alerts:      alerts,
		ActorUserID: func(*gin.Context) int64 { return 0 },
		Workspace: func(c *gin.Context) string {
			if c.Query("workspace") == "guest" {
				return "guest"
			}
			return "user"
		},
	}
}

func (h *Handler) RegisterRoutes(group *gin.RouterGroup) {
	group.GET("/notifications/holding/capabilities", h.capabilities)
	group.POST("/notifications/holding/grants", h.grants)
	group.POST("/notifications/holding/evaluate", h.evaluate)
	group.GET("/notifications/holding/events/:id", h.event)
}

type grantsRequest struct {
	JsCode     string `json:"js_code"`
	DeviceID   string `json:"device_id"`
	TemplateID string `json:"template_id"`
}

type evaluateRequest struct {
	DeviceID           string                   `json:"device_id"`
	RequestID          string                   `json:"request_id"`
	GuestConfiguration []domain.ValidatedRecord `json:"guest_configuration"`
}

type eventRequest struct {
	DeviceID string `json:"device_id"`
}

func writeError(c *gin.Context, err error) {
	status, message := 500, "通知服务异常"
	switch {
	case errors.Is(err, domain.ErrInvalidDeviceID), errors.Is(err, domain.ErrInvalidRequest),
		errors.Is(err, domain.ErrInvalid):
		status, message = 422, err.Error()
	case errors.Is(err, domain.ErrPayloadTooLarge):
		status, message = 413, err.Error()
	case errors.Is(err, domain.ErrGrantNotFound), errors.Is(err, domain.ErrCredentials):
		status, message = 401, err.Error()
	case errors.Is(err, domain.ErrUnavailable):
		status, message = 503, err.Error()
	}
	c.JSON(status, sharedhttp.Response[any]{Code: status, Message: message})
}

func (h *Handler) capabilities(c *gin.Context) {
	c.JSON(http.StatusOK, sharedhttp.Success(h.alerts.Capability()))
}

func (h *Handler) grants(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 20*time.Second)
	defer cancel()
	var req grantsRequest
	if !decode(c, &req) {
		return
	}
	result, err := h.alerts.Grants(ctx, req.JsCode, req.DeviceID, req.TemplateID, h.ActorUserID(c), h.Workspace(c))
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(http.StatusOK, sharedhttp.Success(result))
}

func (h *Handler) evaluate(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 20*time.Second)
	defer cancel()
	grant := c.GetHeader(GrantHeader)
	if strings.TrimSpace(grant) == "" {
		writeError(c, domain.ErrGrantNotFound)
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, domain.MaxBytes)
	var req evaluateRequest
	if !decode(c, &req) {
		return
	}
	workspace := h.Workspace(c)
	config := domain.GuestConfiguration(req.GuestConfiguration)
	// 游客提交受限配置；账户一律从云文档重读，不接受客户端内容
	if workspace == "guest" {
		if err := config.Validate(); err != nil {
			writeError(c, err)
			return
		}
	} else {
		config = nil
	}
	result, err := h.alerts.Evaluate(ctx, application.EvaluateInput{
		DeviceID:  req.DeviceID,
		RequestID: req.RequestID,
		Grant:     grant,
		Workspace: workspace,
		Guest:     config,
	})
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(http.StatusOK, sharedhttp.Success(result))
}

func (h *Handler) event(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 20*time.Second)
	defer cancel()
	grant := c.GetHeader(GrantHeader)
	deviceID := c.Query("device_id")
	if strings.TrimSpace(grant) == "" || deviceID == "" {
		writeError(c, domain.ErrGrantNotFound)
		return
	}
	result, err := h.alerts.Event(ctx, grant, deviceID, h.Workspace(c), c.Param("id"))
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(http.StatusOK, sharedhttp.Success(result))
}

func decode(c *gin.Context, target any) bool {
	decoder := json.NewDecoder(c.Request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(c, domain.ErrInvalid)
		return false
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		writeError(c, domain.ErrInvalid)
		return false
	}
	return true
}
