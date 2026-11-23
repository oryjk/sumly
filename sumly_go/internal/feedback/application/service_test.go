package application

import (
	"bytes"
	"context"
	"errors"
	"io"
	"sync"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type stubRepo struct {
	createFn      func(context.Context, ports.CreateFeedbackParams) (domain.Feedback, error)
	listMineFn    func(context.Context, *int64, string, int) ([]domain.Feedback, error)
	listAdminFn   func(context.Context, ports.AdminListFilter) (ports.AdminListResult, error)
	updateAdminFn func(context.Context, int64, ports.AdminUpdateParams) (domain.Feedback, error)
}

func (s *stubRepo) Create(ctx context.Context, p ports.CreateFeedbackParams) (domain.Feedback, error) {
	return s.createFn(ctx, p)
}
func (s *stubRepo) ListMine(ctx context.Context, u *int64, h string, l int) ([]domain.Feedback, error) {
	return s.listMineFn(ctx, u, h, l)
}
func (s *stubRepo) ListAdmin(ctx context.Context, f ports.AdminListFilter) (ports.AdminListResult, error) {
	return s.listAdminFn(ctx, f)
}
func (s *stubRepo) UpdateAdmin(ctx context.Context, id int64, p ports.AdminUpdateParams) (domain.Feedback, error) {
	return s.updateAdminFn(ctx, id, p)
}

type stubStorage struct {
	configured bool
	putKey     string
	putType    string
	putData    []byte
	putErr     error
	getStream  ports.ObjectStream
	getErr     error
}

func (s *stubStorage) IsConfigured() bool { return s.configured }
func (s *stubStorage) PutObject(_ context.Context, key, ct string, data []byte) error {
	s.putKey = key
	s.putType = ct
	s.putData = append([]byte(nil), data...)
	return s.putErr
}
func (s *stubStorage) GetObject(_ context.Context, _ string) (ports.ObjectStream, error) {
	return s.getStream, s.getErr
}

type stubNotifier struct {
	mu       sync.Mutex
	notified []domain.Feedback
	err      error
}

func (n *stubNotifier) NotifyNewFeedback(_ context.Context, item domain.Feedback) error {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.notified = append(n.notified, item)
	return n.err
}

func TestServiceUploadAndGetAttachment(t *testing.T) {
	fixedTime := time.Date(2026, 11, 23, 15, 0, 0, 0, time.UTC)
	fixedRand := func(b []byte) (int, error) {
		for i := range b {
			b[i] = byte(i + 1)
		}
		return len(b), nil
	}

	// Unconfigured storage -> ErrStorageNotConfigured
	unconf := NewService(&stubRepo{}, &stubStorage{configured: false}, nil, ServiceOptions{})
	if _, err := unconf.UploadAttachment(context.Background(), []byte{0xFF, 0xD8, 0xFF, 0xE0}); !errors.Is(err, domain.ErrStorageNotConfigured) {
		t.Fatalf("expected ErrStorageNotConfigured, got %v", err)
	}

	// Configured storage with public base URL
	storage := &stubStorage{configured: true}
	svc := NewService(&stubRepo{}, storage, nil, ServiceOptions{
		PublicBaseURL: "https://oryjk.cn/sumly/",
		Now:           func() time.Time { return fixedTime },
		RandRead:      fixedRand,
	})

	pngBytes := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02}
	uploaded, err := svc.UploadAttachment(context.Background(), pngBytes)
	if err != nil {
		t.Fatalf("UploadAttachment error: %v", err)
	}
	wantKey := "feedback/20261123/0102030405060708090a0b0c0d0e0f10.png"
	if uploaded.ObjectKey != wantKey {
		t.Fatalf("object_key=%q want %q", uploaded.ObjectKey, wantKey)
	}
	wantURL := "https://oryjk.cn/sumly/api/v1/app/feedback/attachments/20261123/0102030405060708090a0b0c0d0e0f10.png"
	if uploaded.URL != wantURL {
		t.Fatalf("url=%q want %q", uploaded.URL, wantURL)
	}
	if uploaded.ContentType != "image/png" || uploaded.SizeBytes != int64(len(pngBytes)) {
		t.Fatalf("unexpected upload meta: %+v", uploaded)
	}

	// Reject unsupported file type
	if _, err := svc.UploadAttachment(context.Background(), []byte("not an image")); !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected validation error for non-image, got %v", err)
	}

	// GetAttachment fallback content-type and path traversal rejection
	storage.getStream = ports.ObjectStream{
		Body:          io.NopCloser(bytes.NewReader(pngBytes)),
		ContentType:   "application/octet-stream",
		ContentLength: int64(len(pngBytes)),
	}
	stream, err := svc.GetAttachment(context.Background(), "20261123", "test_1.png")
	if err != nil {
		t.Fatalf("GetAttachment error: %v", err)
	}
	defer stream.Body.Close()
	if stream.ContentType != "image/png" {
		t.Fatalf("expected fallback image/png, got %q", stream.ContentType)
	}

	if _, err := svc.GetAttachment(context.Background(), "20261123", "../etc/passwd"); !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected validation error for traversal, got %v", err)
	}
}

func TestServiceSubmitFeedbackTriggersAsyncNotification(t *testing.T) {
	var wg sync.WaitGroup
	notifier := &stubNotifier{err: errors.New("webhook down")}
	var gotParams ports.CreateFeedbackParams
	repo := &stubRepo{
		createFn: func(_ context.Context, p ports.CreateFeedbackParams) (domain.Feedback, error) {
			gotParams = p
			return domain.Feedback{
				ID:         99,
				UserID:     p.UserID,
				DeviceHash: p.DeviceHash,
				Category:   p.Category,
				Content:    p.Content,
				Status:     domain.StatusNew,
			}, nil
		},
	}

	svc := NewService(repo, nil, notifier, ServiceOptions{
		AsyncRun: func(fn func()) {
			wg.Add(1)
			go func() {
				defer wg.Done()
				fn()
			}()
		},
	})

	uid := int64(7)
	created, err := svc.SubmitFeedback(context.Background(), SubmitFeedbackCommand{
		UserID:      &uid,
		DeviceHash:  "  devhash_12345678  ",
		Category:    "bug",
		Content:     "  页面刷新偶尔卡顿  ",
		Contact:     "  wx:test ",
		AppVersion:  "1.2.0",
		DeviceModel: "iPhone16,2",
	})
	if err != nil {
		t.Fatalf("SubmitFeedback failed: %v", err)
	}
	if created.ID != 99 || gotParams.DeviceHash != "devhash_12345678" || gotParams.Content != "页面刷新偶尔卡顿" {
		t.Fatalf("unexpected created=%+v params=%+v", created, gotParams)
	}

	wg.Wait()
	notifier.mu.Lock()
	defer notifier.mu.Unlock()
	if len(notifier.notified) != 1 || notifier.notified[0].ID != 99 {
		t.Fatalf("expected 1 notification for id=99, got %+v", notifier.notified)
	}
}

func TestServiceListAndUpdateAdminValidation(t *testing.T) {
	var capturedFilter ports.AdminListFilter
	var capturedUpdate ports.AdminUpdateParams
	repo := &stubRepo{
		listAdminFn: func(_ context.Context, f ports.AdminListFilter) (ports.AdminListResult, error) {
			capturedFilter = f
			return ports.AdminListResult{Total: 1, Counts: domain.StatusCounts{All: 1, New: 1}}, nil
		},
		updateAdminFn: func(_ context.Context, id int64, p ports.AdminUpdateParams) (domain.Feedback, error) {
			capturedUpdate = p
			return domain.Feedback{ID: id, Status: *p.Status, UpdatedBy: p.UpdatedBy}, nil
		},
	}
	svc := NewService(repo, nil, nil, ServiceOptions{})

	if _, err := svc.ListAdmin(context.Background(), AdminListQuery{Status: "all", Category: "all", Limit: 500, Offset: 0}); err != nil {
		t.Fatalf("ListAdmin failed: %v", err)
	}
	if capturedFilter.Status != "" || capturedFilter.Category != "" || capturedFilter.Limit != domain.MaxAdminLimit {
		t.Fatalf("unexpected admin filter: %+v", capturedFilter)
	}

	if _, err := svc.ListAdmin(context.Background(), AdminListQuery{Status: "bogus"}); !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected invalid status error, got %v", err)
	}

	if _, err := svc.UpdateAdmin(context.Background(), 10, AdminUpdateCommand{}); !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected empty patch error, got %v", err)
	}

	st := "resolved"
	reply := "  已修复  "
	updated, err := svc.UpdateAdmin(context.Background(), 10, AdminUpdateCommand{
		Status:     &st,
		AdminReply: &reply,
		UpdatedBy:  "admin",
	})
	if err != nil {
		t.Fatalf("UpdateAdmin failed: %v", err)
	}
	if updated.Status != domain.StatusResolved || *capturedUpdate.AdminReply != "已修复" || capturedUpdate.UpdatedBy != "admin" {
		t.Fatalf("unexpected update: updated=%+v captured=%+v", updated, capturedUpdate)
	}
}
