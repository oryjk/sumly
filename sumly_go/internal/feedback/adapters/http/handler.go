package feedbackhttp

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

const (
	maxJSONRequestBodyBytes  = 64 * 1024
	maxMultipartRequestBytes = domain.MaxAttachmentSizeBytes + 512*1024

	defaultAttachmentRateLimit = 30
	defaultSubmitRateLimit     = 10
	defaultRateLimitWindow     = time.Hour
)

type UseCase interface {
	UploadAttachment(ctx context.Context, data []byte) (domain.UploadedAttachment, error)
	GetAttachment(ctx context.Context, date, filename string) (ports.ObjectStream, error)
	SubmitFeedback(ctx context.Context, cmd application.SubmitFeedbackCommand) (domain.Feedback, error)
	ListMine(ctx context.Context, userID *int64, deviceHash string, limit int) ([]domain.Feedback, error)
	ListAdmin(ctx context.Context, query application.AdminListQuery) (ports.AdminListResult, error)
	UpdateAdmin(ctx context.Context, id int64, cmd application.AdminUpdateCommand) (domain.Feedback, error)
}

type TokenParser interface {
	Parse(ctx context.Context, rawToken string) (sharedauth.Actor, error)
}

type AdminRouteConfig struct {
	AuthMiddleware         gin.HandlerFunc
	RequirePasswordChanged gin.HandlerFunc
	OperatorFromContext    func(c *gin.Context) string
}

type HandlerOptions struct {
	Tokens            TokenParser
	AttachmentLimiter *SlidingWindowLimiter
	SubmitLimiter     *SlidingWindowLimiter
}

type Handler struct {
	useCase           UseCase
	tokens            TokenParser
	attachmentLimiter *SlidingWindowLimiter
	submitLimiter     *SlidingWindowLimiter
}

func NewHandler(useCase UseCase, opts HandlerOptions) *Handler {
	attachmentLimiter := opts.AttachmentLimiter
	if attachmentLimiter == nil {
		attachmentLimiter = NewSlidingWindowLimiter(defaultAttachmentRateLimit, defaultRateLimitWindow, nil)
	}
	submitLimiter := opts.SubmitLimiter
	if submitLimiter == nil {
		submitLimiter = NewSlidingWindowLimiter(defaultSubmitRateLimit, defaultRateLimitWindow, nil)
	}
	return &Handler{
		useCase:           useCase,
		tokens:            opts.Tokens,
		attachmentLimiter: attachmentLimiter,
		submitLimiter:     submitLimiter,
	}
}

func (h *Handler) RegisterAppRoutes(group *gin.RouterGroup) {
	group.POST("/feedback/attachments", h.UploadAttachment)
	group.GET("/feedback/attachments/:date/:filename", h.GetAttachment)
	group.POST("/feedback", h.SubmitFeedback)
	group.GET("/feedback/mine", h.ListMine)
}

func (h *Handler) RegisterAdminRoutes(group *gin.RouterGroup, cfg AdminRouteConfig) {
	authMW := cfg.AuthMiddleware
	if authMW == nil {
		// Fail-closed：未提供管理员鉴权中间件时明确返回 503，绝不裸奔放行。
		authMW = func(c *gin.Context) {
			c.AbortWithStatusJSON(http.StatusServiceUnavailable, sharedhttp.Response[any]{
				Code:    http.StatusServiceUnavailable,
				Message: "admin api is not configured",
				Data:    nil,
			})
		}
	}
	operatorFn := cfg.OperatorFromContext
	if operatorFn == nil {
		operatorFn = func(*gin.Context) string { return "" }
	}

	protected := group.Group("")
	protected.Use(authMW)
	protected.GET("/feedbacks", h.ListAdmin)
	if cfg.RequirePasswordChanged != nil {
		protected.PATCH("/feedbacks/:id", cfg.RequirePasswordChanged, h.updateAdminWithOperator(operatorFn))
	} else {
		protected.PATCH("/feedbacks/:id", h.updateAdminWithOperator(operatorFn))
	}
}

type attachmentDTO struct {
	ObjectKey string `json:"object_key"`
	URL       string `json:"url"`
}

type uploadAttachmentResponse struct {
	ObjectKey   string `json:"object_key"`
	URL         string `json:"url"`
	ContentType string `json:"content_type"`
	SizeBytes   int64  `json:"size_bytes"`
}

type submitFeedbackRequest struct {
	DeviceHash       string          `json:"device_hash"`
	Category         string          `json:"category"`
	Content          string          `json:"content"`
	Contact          string          `json:"contact"`
	Attachments      []attachmentDTO `json:"attachments"`
	AppVersion       string          `json:"app_version"`
	BuildNumber      string          `json:"build_number"`
	IOSVersion       string          `json:"ios_version"`
	DeviceModel      string          `json:"device_model"`
	MarketMode       string          `json:"market_mode"`
	CloudSyncEnabled bool            `json:"cloud_sync_enabled"`
}

// AppFeedbackItem 是 App 端返回的反馈对象，严格不包含 admin_note。
type AppFeedbackItem struct {
	ID          int64           `json:"id"`
	Category    string          `json:"category"`
	Content     string          `json:"content"`
	Contact     string          `json:"contact"`
	Attachments []attachmentDTO `json:"attachments"`
	Status      string          `json:"status"`
	AdminReply  string          `json:"admin_reply"`
	RepliedAt   *string         `json:"replied_at"`
	CreatedAt   string          `json:"created_at"`
	UpdatedAt   string          `json:"updated_at"`
}

type listMineResponse struct {
	Items []AppFeedbackItem `json:"items"`
}

type AdminFeedbackItem struct {
	ID               int64           `json:"id"`
	UserID           *int64          `json:"user_id"`
	DeviceHash       string          `json:"device_hash"`
	Category         string          `json:"category"`
	Content          string          `json:"content"`
	Contact          string          `json:"contact"`
	Attachments      []attachmentDTO `json:"attachments"`
	AppVersion       string          `json:"app_version"`
	BuildNumber      string          `json:"build_number"`
	IOSVersion       string          `json:"ios_version"`
	DeviceModel      string          `json:"device_model"`
	MarketMode       string          `json:"market_mode"`
	CloudSyncEnabled bool            `json:"cloud_sync_enabled"`
	Status           string          `json:"status"`
	AdminNote        string          `json:"admin_note"`
	AdminReply       string          `json:"admin_reply"`
	RepliedAt        *string         `json:"replied_at"`
	UpdatedBy        string          `json:"updated_by"`
	CreatedAt        string          `json:"created_at"`
	UpdatedAt        string          `json:"updated_at"`
}

type statusCountsResponse struct {
	All        int64 `json:"all"`
	New        int64 `json:"new"`
	InProgress int64 `json:"in_progress"`
	Resolved   int64 `json:"resolved"`
	Archived   int64 `json:"archived"`
}

type adminListResponse struct {
	Items  []AdminFeedbackItem  `json:"items"`
	Total  int64                `json:"total"`
	Counts statusCountsResponse `json:"counts"`
}

type adminUpdateRequest struct {
	Status     *string `json:"status"`
	AdminNote  *string `json:"admin_note"`
	AdminReply *string `json:"admin_reply"`
}

func (h *Handler) UploadAttachment(c *gin.Context) {
	rateKey := c.ClientIP() + "|" + strings.TrimSpace(c.GetHeader("X-Device-ID"))
	if !h.attachmentLimiter.Allow(rateKey) {
		writeStatusError(c, http.StatusTooManyRequests, "上传过于频繁，请稍后再试")
		return
	}

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxMultipartRequestBytes)
	fileHeader, err := c.FormFile("file")
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			writeStatusError(c, http.StatusRequestEntityTooLarge, "attachment file exceeds 3MB limit")
			return
		}
		writeStatusError(c, http.StatusBadRequest, "missing multipart file field")
		return
	}
	if fileHeader.Size > domain.MaxAttachmentSizeBytes {
		writeStatusError(c, http.StatusRequestEntityTooLarge, "attachment file exceeds 3MB limit")
		return
	}

	file, err := fileHeader.Open()
	if err != nil {
		sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "open uploaded file", err))
		return
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, domain.MaxAttachmentSizeBytes+1))
	if err != nil {
		sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "read uploaded file", err))
		return
	}
	if len(data) > domain.MaxAttachmentSizeBytes {
		writeStatusError(c, http.StatusRequestEntityTooLarge, "attachment file exceeds 3MB limit")
		return
	}

	uploaded, err := h.useCase.UploadAttachment(c.Request.Context(), data)
	if err != nil {
		if errors.Is(err, domain.ErrStorageNotConfigured) {
			writeStatusError(c, http.StatusServiceUnavailable, "attachment storage is not configured")
			return
		}
		sharedhttpapi.WriteError(c, err)
		return
	}

	sharedhttpapi.WriteSuccess(c, uploadAttachmentResponse{
		ObjectKey:   uploaded.ObjectKey,
		URL:         uploaded.URL,
		ContentType: uploaded.ContentType,
		SizeBytes:   uploaded.SizeBytes,
	})
}

func (h *Handler) GetAttachment(c *gin.Context) {
	date := c.Param("date")
	filename := c.Param("filename")
	if _, err := domain.ValidateAttachmentPath(date, filename); err != nil {
		writeStatusError(c, http.StatusBadRequest, err.Error())
		return
	}

	stream, err := h.useCase.GetAttachment(c.Request.Context(), date, filename)
	if err != nil {
		if errors.Is(err, domain.ErrStorageNotConfigured) {
			writeStatusError(c, http.StatusServiceUnavailable, "attachment storage is not configured")
			return
		}
		sharedhttpapi.WriteError(c, err)
		return
	}
	defer stream.Body.Close()

	c.Header("Content-Type", stream.ContentType)
	c.Header("Cache-Control", "public, max-age=31536000, immutable")
	c.Header("X-Content-Type-Options", "nosniff")
	if stream.ContentLength >= 0 {
		c.Header("Content-Length", strconv.FormatInt(stream.ContentLength, 10))
	}
	c.Status(http.StatusOK)
	_, _ = io.Copy(c.Writer, stream.Body)
}

func (h *Handler) SubmitFeedback(c *gin.Context) {
	body, err := io.ReadAll(io.LimitReader(c.Request.Body, maxJSONRequestBodyBytes+1))
	if err != nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "failed to read request body"))
		return
	}
	if len(body) > maxJSONRequestBodyBytes {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "request body too large"))
		return
	}

	var req submitFeedbackRequest
	if err := json.Unmarshal(body, &req); err != nil {
		sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "invalid JSON request body", err))
		return
	}

	rateKey := c.ClientIP() + "|" + strings.TrimSpace(req.DeviceHash)
	if !h.submitLimiter.Allow(rateKey) {
		writeStatusError(c, http.StatusTooManyRequests, "提交过于频繁，请稍后再试")
		return
	}

	userID := h.optionalUserID(c)
	attachments := make([]domain.Attachment, 0, len(req.Attachments))
	for _, att := range req.Attachments {
		attachments = append(attachments, domain.Attachment{
			ObjectKey: att.ObjectKey,
			URL:       att.URL,
		})
	}

	created, err := h.useCase.SubmitFeedback(c.Request.Context(), application.SubmitFeedbackCommand{
		UserID:           userID,
		DeviceHash:       req.DeviceHash,
		Category:         req.Category,
		Content:          req.Content,
		Contact:          req.Contact,
		Attachments:      attachments,
		AppVersion:       req.AppVersion,
		BuildNumber:      req.BuildNumber,
		IOSVersion:       req.IOSVersion,
		DeviceModel:      req.DeviceModel,
		MarketMode:       req.MarketMode,
		CloudSyncEnabled: req.CloudSyncEnabled,
	})
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, toAppFeedbackItem(created))
}

func (h *Handler) ListMine(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	userID := h.optionalUserID(c)
	deviceHash := strings.TrimSpace(c.Query("device_hash"))
	if userID == nil && deviceHash == "" {
		writeStatusError(c, http.StatusBadRequest, "device_hash is required when not authenticated")
		return
	}

	limit := domain.DefaultMineLimit
	if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			writeStatusError(c, http.StatusBadRequest, "limit must be a positive integer")
			return
		}
		limit = parsed
	}

	items, err := h.useCase.ListMine(c.Request.Context(), userID, deviceHash, limit)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	out := make([]AppFeedbackItem, 0, len(items))
	for _, item := range items {
		out = append(out, toAppFeedbackItem(item))
	}
	sharedhttpapi.WriteSuccess(c, listMineResponse{Items: out})
}

func (h *Handler) ListAdmin(c *gin.Context) {
	c.Header("Cache-Control", "no-store")

	limit := domain.DefaultAdminLimit
	if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			writeStatusError(c, http.StatusBadRequest, "limit must be a positive integer")
			return
		}
		limit = parsed
	}
	offset := 0
	if raw := strings.TrimSpace(c.Query("offset")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 0 {
			writeStatusError(c, http.StatusBadRequest, "offset must be a non-negative integer")
			return
		}
		offset = parsed
	}

	result, err := h.useCase.ListAdmin(c.Request.Context(), application.AdminListQuery{
		Status:   c.Query("status"),
		Category: c.Query("category"),
		Query:    c.Query("q"),
		Limit:    limit,
		Offset:   offset,
	})
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}

	out := make([]AdminFeedbackItem, 0, len(result.Items))
	for _, item := range result.Items {
		out = append(out, toAdminFeedbackItem(item))
	}
	sharedhttpapi.WriteSuccess(c, adminListResponse{
		Items: out,
		Total: result.Total,
		Counts: statusCountsResponse{
			All:        result.Counts.All,
			New:        result.Counts.New,
			InProgress: result.Counts.InProgress,
			Resolved:   result.Counts.Resolved,
			Archived:   result.Counts.Archived,
		},
	})
}

func (h *Handler) updateAdminWithOperator(operatorFn func(*gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Cache-Control", "no-store")
		id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
		if err != nil || id <= 0 {
			writeStatusError(c, http.StatusBadRequest, "invalid feedback id")
			return
		}

		body, err := io.ReadAll(io.LimitReader(c.Request.Body, maxJSONRequestBodyBytes+1))
		if err != nil {
			sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "failed to read request body"))
			return
		}
		if len(body) > maxJSONRequestBodyBytes {
			sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "request body too large"))
			return
		}

		var req adminUpdateRequest
		if err := json.Unmarshal(body, &req); err != nil {
			sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindValidation, "invalid JSON request body", err))
			return
		}

		updated, err := h.useCase.UpdateAdmin(c.Request.Context(), id, application.AdminUpdateCommand{
			Status:     req.Status,
			AdminNote:  req.AdminNote,
			AdminReply: req.AdminReply,
			UpdatedBy:  operatorFn(c),
		})
		if err != nil {
			sharedhttpapi.WriteError(c, err)
			return
		}
		sharedhttpapi.WriteSuccess(c, toAdminFeedbackItem(updated))
	}
}

func (h *Handler) optionalUserID(c *gin.Context) *int64 {
	if h.tokens == nil {
		return nil
	}
	token, ok := bearerToken(c.GetHeader("Authorization"))
	if !ok {
		return nil
	}
	actor, err := h.tokens.Parse(c.Request.Context(), token)
	if err != nil || !actor.IsUser() || actor.ID <= 0 {
		return nil
	}
	id := actor.ID
	return &id
}

func bearerToken(header string) (string, bool) {
	prefix, token, ok := strings.Cut(strings.TrimSpace(header), " ")
	if !ok || !strings.EqualFold(prefix, "Bearer") || strings.TrimSpace(token) == "" {
		return "", false
	}
	return strings.TrimSpace(token), true
}

func writeStatusError(c *gin.Context, status int, message string) {
	c.JSON(status, sharedhttp.Response[any]{
		Code:    status,
		Message: message,
		Data:    nil,
	})
}

func toAttachmentDTOs(items []domain.Attachment) []attachmentDTO {
	out := make([]attachmentDTO, 0, len(items))
	for _, item := range items {
		out = append(out, attachmentDTO{
			ObjectKey: item.ObjectKey,
			URL:       item.URL,
		})
	}
	return out
}

func toAppFeedbackItem(item domain.Feedback) AppFeedbackItem {
	return AppFeedbackItem{
		ID:          item.ID,
		Category:    string(item.Category),
		Content:     item.Content,
		Contact:     item.Contact,
		Attachments: toAttachmentDTOs(item.Attachments),
		Status:      string(item.Status),
		AdminReply:  item.AdminReply,
		RepliedAt:   formatOptionalRFC3339(item.RepliedAt),
		CreatedAt:   formatRFC3339(item.CreatedAt),
		UpdatedAt:   formatRFC3339(item.UpdatedAt),
	}
}

func toAdminFeedbackItem(item domain.Feedback) AdminFeedbackItem {
	return AdminFeedbackItem{
		ID:               item.ID,
		UserID:           item.UserID,
		DeviceHash:       item.DeviceHash,
		Category:         string(item.Category),
		Content:          item.Content,
		Contact:          item.Contact,
		Attachments:      toAttachmentDTOs(item.Attachments),
		AppVersion:       item.AppVersion,
		BuildNumber:      item.BuildNumber,
		IOSVersion:       item.IOSVersion,
		DeviceModel:      item.DeviceModel,
		MarketMode:       item.MarketMode,
		CloudSyncEnabled: item.CloudSyncEnabled,
		Status:           string(item.Status),
		AdminNote:        item.AdminNote,
		AdminReply:       item.AdminReply,
		RepliedAt:        formatOptionalRFC3339(item.RepliedAt),
		UpdatedBy:        item.UpdatedBy,
		CreatedAt:        formatRFC3339(item.CreatedAt),
		UpdatedAt:        formatRFC3339(item.UpdatedAt),
	}
}

func formatRFC3339(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

func formatOptionalRFC3339(t *time.Time) *string {
	if t == nil || t.IsZero() {
		return nil
	}
	s := t.UTC().Format(time.RFC3339)
	return &s
}
