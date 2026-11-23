package feedbackhttp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/gin-gonic/gin"
)

type stubTokenParser struct {
	tokens map[string]sharedauth.Actor
}

func (s stubTokenParser) Parse(_ context.Context, raw string) (sharedauth.Actor, error) {
	if actor, ok := s.tokens[raw]; ok {
		return actor, nil
	}
	return sharedauth.Actor{}, errors.New("invalid token")
}

type fakeRepo struct {
	items      []domain.Feedback
	lastCreate ports.CreateFeedbackParams
	lastMineU  *int64
	lastMineH  string
	lastUpdate ports.AdminUpdateParams
}

func (r *fakeRepo) Create(_ context.Context, p ports.CreateFeedbackParams) (domain.Feedback, error) {
	r.lastCreate = p
	now := time.Date(2026, 11, 23, 15, 0, 0, 0, time.UTC)
	item := domain.Feedback{
		ID:               int64(len(r.items) + 1),
		UserID:           p.UserID,
		DeviceHash:       p.DeviceHash,
		Category:         p.Category,
		Content:          p.Content,
		Contact:          p.Contact,
		Attachments:      p.Attachments,
		AppVersion:       p.AppVersion,
		BuildNumber:      p.BuildNumber,
		IOSVersion:       p.IOSVersion,
		DeviceModel:      p.DeviceModel,
		MarketMode:       p.MarketMode,
		CloudSyncEnabled: p.CloudSyncEnabled,
		Status:           domain.StatusNew,
		AdminNote:        "SECRET_INTERNAL_NOTE",
		CreatedAt:        now,
		UpdatedAt:        now,
	}
	r.items = append(r.items, item)
	return item, nil
}

func (r *fakeRepo) ListMine(_ context.Context, userID *int64, deviceHash string, _ int) ([]domain.Feedback, error) {
	r.lastMineU = userID
	r.lastMineH = deviceHash
	return r.items, nil
}

func (r *fakeRepo) ListAdmin(_ context.Context, _ ports.AdminListFilter) (ports.AdminListResult, error) {
	return ports.AdminListResult{
		Items: r.items,
		Total: int64(len(r.items)),
		Counts: domain.StatusCounts{
			All: int64(len(r.items)),
			New: int64(len(r.items)),
		},
	}, nil
}

func (r *fakeRepo) UpdateAdmin(_ context.Context, id int64, patch ports.AdminUpdateParams) (domain.Feedback, error) {
	r.lastUpdate = patch
	for i := range r.items {
		if r.items[i].ID == id {
			if patch.Status != nil {
				r.items[i].Status = *patch.Status
			}
			if patch.AdminNote != nil {
				r.items[i].AdminNote = *patch.AdminNote
			}
			if patch.AdminReply != nil {
				if *patch.AdminReply != "" && *patch.AdminReply != r.items[i].AdminReply {
					now := time.Date(2026, 11, 23, 16, 0, 0, 0, time.UTC)
					r.items[i].RepliedAt = &now
				}
				r.items[i].AdminReply = *patch.AdminReply
			}
			r.items[i].UpdatedBy = patch.UpdatedBy
			return r.items[i], nil
		}
	}
	return domain.Feedback{}, sharederror.ErrNotFound
}

type memStorage struct {
	configured bool
	objects    map[string]struct {
		ct   string
		data []byte
	}
}

func (m *memStorage) IsConfigured() bool { return m.configured }
func (m *memStorage) PutObject(_ context.Context, key, ct string, data []byte) error {
	if m.objects == nil {
		m.objects = make(map[string]struct {
			ct   string
			data []byte
		})
	}
	m.objects[key] = struct {
		ct   string
		data []byte
	}{ct: ct, data: append([]byte(nil), data...)}
	return nil
}
func (m *memStorage) GetObject(_ context.Context, key string) (ports.ObjectStream, error) {
	obj, ok := m.objects[key]
	if !ok {
		return ports.ObjectStream{}, sharederror.ErrNotFound
	}
	return ports.ObjectStream{
		Body:          io.NopCloser(bytes.NewReader(obj.data)),
		ContentType:   obj.ct,
		ContentLength: int64(len(obj.data)),
	}, nil
}

func buildMultipartImageRequest(t *testing.T, url string, filename string, payload []byte) *http.Request {
	t.Helper()
	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)
	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, url, &buf)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	return req
}

func TestHandlerAttachmentUploadDownloadAndRateLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	storage := &memStorage{configured: true}
	svc := application.NewService(&fakeRepo{}, storage, nil, application.ServiceOptions{
		PublicBaseURL: "https://oryjk.cn/sumly",
		Now:           func() time.Time { return time.Date(2026, 11, 23, 12, 0, 0, 0, time.UTC) },
	})
	h := NewHandler(svc, HandlerOptions{
		AttachmentLimiter: NewSlidingWindowLimiter(2, time.Hour, nil),
	})

	router := gin.New()
	h.RegisterAppRoutes(router.Group("/api/v1/app"))

	jpegBytes := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46}

	// 1. Valid JPEG upload
	req := buildMultipartImageRequest(t, "/api/v1/app/feedback/attachments", "shot.jpg", jpegBytes)
	req.Header.Set("X-Device-ID", "dev-1")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("upload status=%d body=%s", rec.Code, rec.Body.String())
	}
	var uploadResp struct {
		Code int                      `json:"code"`
		Data uploadAttachmentResponse `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &uploadResp); err != nil {
		t.Fatal(err)
	}
	if uploadResp.Code != 0 || !strings.HasPrefix(uploadResp.Data.ObjectKey, "feedback/20261123/") || uploadResp.Data.ContentType != "image/jpeg" {
		t.Fatalf("unexpected upload response: %+v", uploadResp)
	}

	// 2. Download via proxy route
	parts := strings.Split(uploadResp.Data.ObjectKey, "/")
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/app/feedback/attachments/"+parts[1]+"/"+parts[2], nil)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)
	if getRec.Code != http.StatusOK {
		t.Fatalf("get attachment status=%d body=%s", getRec.Code, getRec.Body.String())
	}
	if getRec.Header().Get("Content-Type") != "image/jpeg" || !strings.Contains(getRec.Header().Get("Cache-Control"), "immutable") {
		t.Fatalf("unexpected headers: ct=%q cc=%q", getRec.Header().Get("Content-Type"), getRec.Header().Get("Cache-Control"))
	}
	if !bytes.Equal(getRec.Body.Bytes(), jpegBytes) {
		t.Fatalf("downloaded bytes mismatch")
	}

	// 3. Invalid date/filename rejected with 400
	badGet := httptest.NewRecorder()
	router.ServeHTTP(badGet, httptest.NewRequest(http.MethodGet, "/api/v1/app/feedback/attachments/bad-date/evil.svg", nil))
	if badGet.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid path, got %d", badGet.Code)
	}

	// 4. Reject non-image magic bytes (consumes 2nd token)
	badImg := buildMultipartImageRequest(t, "/api/v1/app/feedback/attachments", "fake.jpg", []byte("<html>not jpg</html>"))
	badImg.Header.Set("X-Device-ID", "dev-1")
	badImgRec := httptest.NewRecorder()
	router.ServeHTTP(badImgRec, badImg)
	if badImgRec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for non-image, got %d body=%s", badImgRec.Code, badImgRec.Body.String())
	}

	// 5. 3rd upload hits rate limit -> 429
	rateReq := buildMultipartImageRequest(t, "/api/v1/app/feedback/attachments", "shot2.jpg", jpegBytes)
	rateReq.Header.Set("X-Device-ID", "dev-1")
	rateRec := httptest.NewRecorder()
	router.ServeHTTP(rateRec, rateReq)
	if rateRec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 on 3rd upload, got %d body=%s", rateRec.Code, rateRec.Body.String())
	}

	// 6. Unconfigured MinIO returns 503
	unconfSvc := application.NewService(&fakeRepo{}, &memStorage{configured: false}, nil, application.ServiceOptions{})
	unconfH := NewHandler(unconfSvc, HandlerOptions{})
	unconfRouter := gin.New()
	unconfH.RegisterAppRoutes(unconfRouter.Group("/api/v1/app"))
	unconfRec := httptest.NewRecorder()
	unconfRouter.ServeHTTP(unconfRec, buildMultipartImageRequest(t, "/api/v1/app/feedback/attachments", "shot.jpg", jpegBytes))
	if unconfRec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when MinIO unconfigured, got %d body=%s", unconfRec.Code, unconfRec.Body.String())
	}
}

func TestHandlerSubmitMineAndAdminFlow(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &fakeRepo{}
	svc := application.NewService(repo, nil, nil, application.ServiceOptions{})
	h := NewHandler(svc, HandlerOptions{
		Tokens: stubTokenParser{tokens: map[string]sharedauth.Actor{
			"valid-user-jwt": {Kind: sharedauth.ActorUser, ID: 88},
		}},
		SubmitLimiter: NewSlidingWindowLimiter(2, time.Hour, nil),
	})

	router := gin.New()
	h.RegisterAppRoutes(router.Group("/api/v1/app"))
	h.RegisterAdminRoutes(router.Group("/api/v1/admin"), AdminRouteConfig{
		AuthMiddleware: func(c *gin.Context) {
			if c.GetHeader("X-Admin-Token") != "ok-admin" {
				c.AbortWithStatus(http.StatusUnauthorized)
				return
			}
			c.Set("admin_user", "superadmin")
			c.Next()
		},
		OperatorFromContext: func(c *gin.Context) string {
			v, _ := c.Get("admin_user")
			s, _ := v.(string)
			return s
		},
	})

	// 1. Guest submit with invalid/expired token still succeeds (does NOT return 401)
	guestBody := `{"device_hash":"device_guest_001","category":"suggestion","content":"希望增加金价提醒自定义声音","contact":"wx:123","app_version":"1.3.0","cloud_sync_enabled":false}`
	guestReq := httptest.NewRequest(http.MethodPost, "/api/v1/app/feedback", strings.NewReader(guestBody))
	guestReq.Header.Set("Authorization", "Bearer expired-or-invalid-token")
	guestRec := httptest.NewRecorder()
	router.ServeHTTP(guestRec, guestReq)
	if guestRec.Code != http.StatusOK {
		t.Fatalf("guest submit status=%d body=%s", guestRec.Code, guestRec.Body.String())
	}
	if repo.lastCreate.UserID != nil {
		t.Fatalf("expected nil user_id for guest, got %v", *repo.lastCreate.UserID)
	}
	if strings.Contains(guestRec.Body.String(), "admin_note") || strings.Contains(guestRec.Body.String(), "SECRET_INTERNAL_NOTE") {
		t.Fatalf("app response leaked admin_note: %s", guestRec.Body.String())
	}

	// 2. Authenticated submit extracts user_id=88
	authBody := `{"device_hash":"device_auth_002","category":"bug","content":"同步持仓记录时偶尔失败"}`
	authReq := httptest.NewRequest(http.MethodPost, "/api/v1/app/feedback", strings.NewReader(authBody))
	authReq.Header.Set("Authorization", "Bearer valid-user-jwt")
	authRec := httptest.NewRecorder()
	router.ServeHTTP(authRec, authReq)
	if authRec.Code != http.StatusOK {
		t.Fatalf("auth submit status=%d body=%s", authRec.Code, authRec.Body.String())
	}
	if repo.lastCreate.UserID == nil || *repo.lastCreate.UserID != 88 {
		t.Fatalf("expected user_id=88, got %v", repo.lastCreate.UserID)
	}

	// 3. Rate limit per IP + device_hash (2nd for device_guest_001 passes, 3rd returns 429)
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, httptest.NewRequest(http.MethodPost, "/api/v1/app/feedback", strings.NewReader(guestBody)))
	if rec2.Code != http.StatusOK {
		t.Fatalf("2nd submit status=%d", rec2.Code)
	}
	rec3 := httptest.NewRecorder()
	router.ServeHTTP(rec3, httptest.NewRequest(http.MethodPost, "/api/v1/app/feedback", strings.NewReader(guestBody)))
	if rec3.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 on 3rd submit, got %d body=%s", rec3.Code, rec3.Body.String())
	}

	// 4. ListMine returns 400 when both user_id and device_hash are missing
	mineBad := httptest.NewRecorder()
	router.ServeHTTP(mineBad, httptest.NewRequest(http.MethodGet, "/api/v1/app/feedback/mine", nil))
	if mineBad.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty mine query, got %d body=%s", mineBad.Code, mineBad.Body.String())
	}

	// 5. ListMine succeeds and never exposes admin_note
	mineReq := httptest.NewRequest(http.MethodGet, "/api/v1/app/feedback/mine?device_hash=device_guest_001", nil)
	mineReq.Header.Set("Authorization", "Bearer valid-user-jwt")
	mineRec := httptest.NewRecorder()
	router.ServeHTTP(mineRec, mineReq)
	if mineRec.Code != http.StatusOK {
		t.Fatalf("mine status=%d body=%s", mineRec.Code, mineRec.Body.String())
	}
	if repo.lastMineU == nil || *repo.lastMineU != 88 || repo.lastMineH != "device_guest_001" {
		t.Fatalf("unexpected ListMine args: user=%v hash=%q", repo.lastMineU, repo.lastMineH)
	}
	if strings.Contains(mineRec.Body.String(), "admin_note") || strings.Contains(mineRec.Body.String(), "SECRET_INTERNAL_NOTE") {
		t.Fatalf("ListMine leaked admin_note: %s", mineRec.Body.String())
	}

	// 6. Admin list & patch
	adminListReq := httptest.NewRequest(http.MethodGet, "/api/v1/admin/feedbacks?status=all&category=all", nil)
	adminListReq.Header.Set("X-Admin-Token", "ok-admin")
	adminListRec := httptest.NewRecorder()
	router.ServeHTTP(adminListRec, adminListReq)
	if adminListRec.Code != http.StatusOK || !strings.Contains(adminListRec.Body.String(), "SECRET_INTERNAL_NOTE") {
		t.Fatalf("admin list status=%d body=%s", adminListRec.Code, adminListRec.Body.String())
	}

	patchReq := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/feedbacks/1", strings.NewReader(`{"status":"resolved","admin_note":"已处理","admin_reply":"感谢反馈，已安排优化"}`))
	patchReq.Header.Set("X-Admin-Token", "ok-admin")
	patchRec := httptest.NewRecorder()
	router.ServeHTTP(patchRec, patchReq)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("admin patch status=%d body=%s", patchRec.Code, patchRec.Body.String())
	}
	if repo.lastUpdate.UpdatedBy != "superadmin" || !strings.Contains(patchRec.Body.String(), `"replied_at":"2026-11-23T16:00:00Z"`) {
		t.Fatalf("unexpected admin patch result: updatedBy=%q body=%s", repo.lastUpdate.UpdatedBy, patchRec.Body.String())
	}
}
