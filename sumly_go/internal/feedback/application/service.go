package application

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const (
	attachmentRandomBytes = 16
	notifyTimeout         = 8 * time.Second
)

type ServiceOptions struct {
	MinIOPublicURLPrefix string
	PublicBaseURL        string
	Now                  func() time.Time
	RandRead             func([]byte) (int, error)
	// AsyncRun 可在单元测试中注入以便确定性等待异步飞书通知结束。
	AsyncRun func(func())
}

type SubmitFeedbackCommand struct {
	UserID           *int64
	DeviceHash       string
	Category         string
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

type AdminListQuery struct {
	Status   string
	Category string
	Query    string
	Limit    int
	Offset   int
}

type AdminUpdateCommand struct {
	Status     *string
	AdminNote  *string
	AdminReply *string
	UpdatedBy  string
}

type Service struct {
	repo                 ports.Repository
	storage              ports.AttachmentStorage
	notifier             ports.Notifier
	minioPublicURLPrefix string
	publicBaseURL        string
	now                  func() time.Time
	randRead             func([]byte) (int, error)
	asyncRun             func(func())
}

func NewService(repo ports.Repository, storage ports.AttachmentStorage, notifier ports.Notifier, opts ServiceOptions) *Service {
	nowFn := opts.Now
	if nowFn == nil {
		nowFn = time.Now
	}
	randFn := opts.RandRead
	if randFn == nil {
		randFn = rand.Read
	}
	asyncFn := opts.AsyncRun
	if asyncFn == nil {
		asyncFn = func(fn func()) { go fn() }
	}
	return &Service{
		repo:                 repo,
		storage:              storage,
		notifier:             notifier,
		minioPublicURLPrefix: strings.TrimSpace(opts.MinIOPublicURLPrefix),
		publicBaseURL:        strings.TrimSpace(opts.PublicBaseURL),
		now:                  nowFn,
		randRead:             randFn,
		asyncRun:             asyncFn,
	}
}

func (s *Service) UploadAttachment(ctx context.Context, data []byte) (domain.UploadedAttachment, error) {
	if s.storage == nil || !s.storage.IsConfigured() {
		return domain.UploadedAttachment{}, domain.ErrStorageNotConfigured
	}
	if len(data) == 0 {
		return domain.UploadedAttachment{}, sharederror.New(sharederror.KindValidation, "attachment file is empty")
	}
	if len(data) > domain.MaxAttachmentSizeBytes {
		return domain.UploadedAttachment{}, sharederror.New(sharederror.KindValidation, "attachment file exceeds 3MB limit")
	}
	contentType, ext, ok := domain.DetectAllowedImageType(data)
	if !ok {
		return domain.UploadedAttachment{}, sharederror.New(sharederror.KindValidation, "only jpeg, png, and webp images are supported")
	}

	rawRand := make([]byte, attachmentRandomBytes)
	if _, err := s.randRead(rawRand); err != nil {
		return domain.UploadedAttachment{}, sharederror.Wrap(sharederror.KindInternal, "generate attachment filename", err)
	}
	date := s.now().UTC().Format("20060102")
	filename := hex.EncodeToString(rawRand) + ext
	objectKey := "feedback/" + date + "/" + filename

	if err := s.storage.PutObject(ctx, objectKey, contentType, data); err != nil {
		return domain.UploadedAttachment{}, sharederror.Wrap(sharederror.KindInternal, "upload attachment to storage", err)
	}

	return domain.UploadedAttachment{
		ObjectKey:   objectKey,
		URL:         domain.BuildAttachmentPublicURL(s.minioPublicURLPrefix, s.publicBaseURL, date, filename),
		ContentType: contentType,
		SizeBytes:   int64(len(data)),
	}, nil
}

func (s *Service) GetAttachment(ctx context.Context, date, filename string) (ports.ObjectStream, error) {
	objectKey, err := domain.ValidateAttachmentPath(date, filename)
	if err != nil {
		return ports.ObjectStream{}, err
	}
	if s.storage == nil || !s.storage.IsConfigured() {
		return ports.ObjectStream{}, domain.ErrStorageNotConfigured
	}
	stream, err := s.storage.GetObject(ctx, objectKey)
	if err != nil {
		return ports.ObjectStream{}, err
	}
	if !strings.HasPrefix(strings.ToLower(strings.TrimSpace(stream.ContentType)), "image/") {
		stream.ContentType = domain.ContentTypeFromFilename(filename)
	}
	return stream, nil
}

func (s *Service) SubmitFeedback(ctx context.Context, cmd SubmitFeedbackCommand) (domain.Feedback, error) {
	deviceHash, err := domain.ValidateDeviceHash(cmd.DeviceHash)
	if err != nil {
		return domain.Feedback{}, err
	}
	category, err := domain.ParseCategory(cmd.Category)
	if err != nil {
		return domain.Feedback{}, err
	}
	content, err := domain.ValidateContent(cmd.Content)
	if err != nil {
		return domain.Feedback{}, err
	}
	contact, err := domain.ValidateContact(cmd.Contact)
	if err != nil {
		return domain.Feedback{}, err
	}
	attachments, err := domain.ValidateAttachments(cmd.Attachments)
	if err != nil {
		return domain.Feedback{}, err
	}
	appVersion, err := domain.ValidateMetaField("app_version", cmd.AppVersion)
	if err != nil {
		return domain.Feedback{}, err
	}
	buildNumber, err := domain.ValidateMetaField("build_number", cmd.BuildNumber)
	if err != nil {
		return domain.Feedback{}, err
	}
	iosVersion, err := domain.ValidateMetaField("ios_version", cmd.IOSVersion)
	if err != nil {
		return domain.Feedback{}, err
	}
	deviceModel, err := domain.ValidateMetaField("device_model", cmd.DeviceModel)
	if err != nil {
		return domain.Feedback{}, err
	}
	marketMode, err := domain.ValidateMetaField("market_mode", cmd.MarketMode)
	if err != nil {
		return domain.Feedback{}, err
	}

	created, err := s.repo.Create(ctx, ports.CreateFeedbackParams{
		UserID:           cmd.UserID,
		DeviceHash:       deviceHash,
		Category:         category,
		Content:          content,
		Contact:          contact,
		Attachments:      attachments,
		AppVersion:       appVersion,
		BuildNumber:      buildNumber,
		IOSVersion:       iosVersion,
		DeviceModel:      deviceModel,
		MarketMode:       marketMode,
		CloudSyncEnabled: cmd.CloudSyncEnabled,
	})
	if err != nil {
		return domain.Feedback{}, sharederror.Wrap(sharederror.KindInternal, "create feedback", err)
	}

	if s.notifier != nil {
		itemCopy := created
		if len(created.Attachments) > 0 {
			itemCopy.Attachments = append([]domain.Attachment(nil), created.Attachments...)
		}
		s.asyncRun(func() {
			defer func() {
				if r := recover(); r != nil {
					slog.Warn("feedback notification panic recovered", "feedback_id", itemCopy.ID, "panic", fmt.Sprint(r))
				}
			}()
			notifyCtx, cancel := context.WithTimeout(context.Background(), notifyTimeout)
			defer cancel()
			if notifyErr := s.notifier.NotifyNewFeedback(notifyCtx, itemCopy); notifyErr != nil {
				slog.Warn("send feedback notification failed", "feedback_id", itemCopy.ID, "error", notifyErr)
			}
		})
	}

	return created, nil
}

func (s *Service) ListMine(ctx context.Context, userID *int64, deviceHash string, limit int) ([]domain.Feedback, error) {
	trimmedHash := strings.TrimSpace(deviceHash)
	if userID == nil && trimmedHash == "" {
		return nil, sharederror.New(sharederror.KindValidation, "device_hash is required when not authenticated")
	}
	if limit <= 0 || limit > domain.MaxMineLimit {
		limit = domain.DefaultMineLimit
	}
	items, err := s.repo.ListMine(ctx, userID, trimmedHash, limit)
	if err != nil {
		return nil, sharederror.Wrap(sharederror.KindInternal, "list user feedbacks", err)
	}
	if items == nil {
		return []domain.Feedback{}, nil
	}
	return items, nil
}

func (s *Service) ListAdmin(ctx context.Context, query AdminListQuery) (ports.AdminListResult, error) {
	statusFilter := strings.TrimSpace(query.Status)
	if statusFilter == "" || statusFilter == "all" {
		statusFilter = ""
	} else {
		parsed, err := domain.ParseStatus(statusFilter)
		if err != nil {
			return ports.AdminListResult{}, err
		}
		statusFilter = string(parsed)
	}

	categoryFilter := strings.TrimSpace(query.Category)
	if categoryFilter == "" || categoryFilter == "all" {
		categoryFilter = ""
	} else {
		parsed, err := domain.ParseCategory(categoryFilter)
		if err != nil {
			return ports.AdminListResult{}, err
		}
		categoryFilter = string(parsed)
	}

	limit := query.Limit
	if limit <= 0 {
		limit = domain.DefaultAdminLimit
	} else if limit > domain.MaxAdminLimit {
		limit = domain.MaxAdminLimit
	}
	if query.Offset < 0 {
		return ports.AdminListResult{}, sharederror.New(sharederror.KindValidation, "offset must be non-negative")
	}

	res, err := s.repo.ListAdmin(ctx, ports.AdminListFilter{
		Status:   statusFilter,
		Category: categoryFilter,
		Query:    strings.TrimSpace(query.Query),
		Limit:    limit,
		Offset:   query.Offset,
	})
	if err != nil {
		return ports.AdminListResult{}, sharederror.Wrap(sharederror.KindInternal, "list admin feedbacks", err)
	}
	if res.Items == nil {
		res.Items = []domain.Feedback{}
	}
	return res, nil
}

func (s *Service) UpdateAdmin(ctx context.Context, id int64, cmd AdminUpdateCommand) (domain.Feedback, error) {
	if id <= 0 {
		return domain.Feedback{}, sharederror.New(sharederror.KindValidation, "invalid feedback id")
	}
	if cmd.Status == nil && cmd.AdminNote == nil && cmd.AdminReply == nil {
		return domain.Feedback{}, sharederror.New(sharederror.KindValidation, "at least one field must be provided")
	}

	var params ports.AdminUpdateParams
	params.UpdatedBy = strings.TrimSpace(cmd.UpdatedBy)

	if cmd.Status != nil {
		parsed, err := domain.ParseStatus(*cmd.Status)
		if err != nil {
			return domain.Feedback{}, err
		}
		params.Status = &parsed
	}
	if cmd.AdminNote != nil {
		note, err := domain.ValidateAdminText("admin_note", *cmd.AdminNote)
		if err != nil {
			return domain.Feedback{}, err
		}
		params.AdminNote = &note
	}
	if cmd.AdminReply != nil {
		reply, err := domain.ValidateAdminText("admin_reply", *cmd.AdminReply)
		if err != nil {
			return domain.Feedback{}, err
		}
		params.AdminReply = &reply
	}

	updated, err := s.repo.UpdateAdmin(ctx, id, params)
	if err != nil {
		return domain.Feedback{}, err
	}
	return updated, nil
}
