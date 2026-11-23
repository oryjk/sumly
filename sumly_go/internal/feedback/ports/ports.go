package ports

import (
	"context"
	"io"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
)

type CreateFeedbackParams struct {
	UserID           *int64
	DeviceHash       string
	Category         domain.Category
	Content          string
	Contact          string
	Attachments      []domain.Attachment
	AppVersion       string
	BuildNumber      string
	IOSVersion       string
	DeviceModel      string
	MarketMode       string
	CloudSyncEnabled bool
}

type AdminListFilter struct {
	Status   string
	Category string
	Query    string
	Limit    int
	Offset   int
}

type AdminListResult struct {
	Items  []domain.Feedback
	Total  int64
	Counts domain.StatusCounts
}

type AdminUpdateParams struct {
	Status     *domain.Status
	AdminNote  *string
	AdminReply *string
	UpdatedBy  string
}

type Repository interface {
	Create(ctx context.Context, params CreateFeedbackParams) (domain.Feedback, error)
	ListMine(ctx context.Context, userID *int64, deviceHash string, limit int) ([]domain.Feedback, error)
	ListAdmin(ctx context.Context, filter AdminListFilter) (AdminListResult, error)
	UpdateAdmin(ctx context.Context, id int64, patch AdminUpdateParams) (domain.Feedback, error)
}

type ObjectStream struct {
	Body          io.ReadCloser
	ContentType   string
	ContentLength int64
}

type AttachmentStorage interface {
	IsConfigured() bool
	PutObject(ctx context.Context, objectKey string, contentType string, data []byte) error
	GetObject(ctx context.Context, objectKey string) (ObjectStream, error)
}

type Notifier interface {
	NotifyNewFeedback(ctx context.Context, item domain.Feedback) error
}
