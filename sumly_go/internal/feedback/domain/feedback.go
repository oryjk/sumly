package domain

import (
	"bytes"
	"errors"
	"fmt"
	"path"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type Category string

const (
	CategorySuggestion Category = "suggestion"
	CategoryBug        Category = "bug"
	CategoryData       Category = "data"
	CategoryOther      Category = "other"
)

type Status string

const (
	StatusNew        Status = "new"
	StatusInProgress Status = "in_progress"
	StatusResolved   Status = "resolved"
	StatusArchived   Status = "archived"
)

const (
	MaxAttachmentSizeBytes    = 3 * 1024 * 1024
	MaxAttachmentsPerFeedback = 3
	MinDeviceHashRunes        = 8
	MaxDeviceHashRunes        = 128
	MinContentRunes           = 5
	MaxContentRunes           = 1000
	MaxContactRunes           = 120
	MaxMetaFieldRunes         = 64
	MaxAdminTextRunes         = 2000
	MaxAttachmentURLRunes     = 512
	DefaultMineLimit          = 50
	MaxMineLimit              = 50
	DefaultAdminLimit         = 50
	MaxAdminLimit             = 100
)

var (
	// ErrStorageNotConfigured 表示对象存储未配置，由 HTTP 适配层映射为 503。
	ErrStorageNotConfigured = errors.New("attachment storage is not configured")

	attachmentDatePattern      = regexp.MustCompile(`^\d{8}$`)
	attachmentFilenamePattern  = regexp.MustCompile(`^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$`)
	attachmentObjectKeyPattern = regexp.MustCompile(`^feedback/\d{8}/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$`)

	pngMagic  = []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	jpegMagic = []byte{0xFF, 0xD8, 0xFF}
)

type Attachment struct {
	ObjectKey string
	URL       string
}

type UploadedAttachment struct {
	ObjectKey   string
	URL         string
	ContentType string
	SizeBytes   int64
}

type Feedback struct {
	ID               int64
	UserID           *int64
	DeviceHash       string
	Category         Category
	Content          string
	Contact          string
	Attachments      []Attachment
	AppVersion       string
	BuildNumber      string
	IOSVersion       string
	DeviceModel      string
	MarketMode       string
	CloudSyncEnabled bool
	Status           Status
	AdminNote        string
	AdminReply       string
	RepliedAt        *time.Time
	UpdatedBy        string
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

type StatusCounts struct {
	All        int64
	New        int64
	InProgress int64
	Resolved   int64
	Archived   int64
}

func ParseCategory(raw string) (Category, error) {
	cat := Category(strings.TrimSpace(raw))
	switch cat {
	case CategorySuggestion, CategoryBug, CategoryData, CategoryOther:
		return cat, nil
	default:
		return "", sharederror.New(sharederror.KindValidation, "invalid feedback category")
	}
}

func CategoryLabel(cat Category) string {
	switch cat {
	case CategorySuggestion:
		return "功能建议"
	case CategoryBug:
		return "问题反馈"
	case CategoryData:
		return "行情与数据异常"
	case CategoryOther:
		return "其他反馈"
	default:
		return string(cat)
	}
}

func ParseStatus(raw string) (Status, error) {
	status := Status(strings.TrimSpace(raw))
	switch status {
	case StatusNew, StatusInProgress, StatusResolved, StatusArchived:
		return status, nil
	default:
		return "", sharederror.New(sharederror.KindValidation, "invalid feedback status")
	}
}

func ValidateDeviceHash(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	n := utf8.RuneCountInString(trimmed)
	if n < MinDeviceHashRunes || n > MaxDeviceHashRunes {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("device_hash must be %d to %d characters", MinDeviceHashRunes, MaxDeviceHashRunes))
	}
	return trimmed, nil
}

func ValidateContent(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	n := utf8.RuneCountInString(trimmed)
	if n < MinContentRunes || n > MaxContentRunes {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("content must be %d to %d characters", MinContentRunes, MaxContentRunes))
	}
	return trimmed, nil
}

func ValidateContact(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if utf8.RuneCountInString(trimmed) > MaxContactRunes {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("contact must not exceed %d characters", MaxContactRunes))
	}
	return trimmed, nil
}

func ValidateMetaField(name, raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if utf8.RuneCountInString(trimmed) > MaxMetaFieldRunes {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("%s must not exceed %d characters", name, MaxMetaFieldRunes))
	}
	return trimmed, nil
}

func ValidateAdminText(name, raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if utf8.RuneCountInString(trimmed) > MaxAdminTextRunes {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("%s must not exceed %d characters", name, MaxAdminTextRunes))
	}
	return trimmed, nil
}

func ValidateAttachments(raw []Attachment) ([]Attachment, error) {
	if len(raw) == 0 {
		return []Attachment{}, nil
	}
	if len(raw) > MaxAttachmentsPerFeedback {
		return nil, sharederror.New(sharederror.KindValidation, fmt.Sprintf("attachments must not exceed %d items", MaxAttachmentsPerFeedback))
	}
	out := make([]Attachment, 0, len(raw))
	for _, item := range raw {
		key := strings.TrimSpace(item.ObjectKey)
		if !attachmentObjectKeyPattern.MatchString(key) {
			return nil, sharederror.New(sharederror.KindValidation, "invalid attachment object_key")
		}
		rawURL := strings.TrimSpace(item.URL)
		if rawURL == "" {
			return nil, sharederror.New(sharederror.KindValidation, "attachment url is required")
		}
		if utf8.RuneCountInString(rawURL) > MaxAttachmentURLRunes {
			return nil, sharederror.New(sharederror.KindValidation, "attachment url is too long")
		}
		if !isSafeAttachmentURL(rawURL) {
			return nil, sharederror.New(sharederror.KindValidation, "invalid attachment url")
		}
		out = append(out, Attachment{
			ObjectKey: key,
			URL:       rawURL,
		})
	}
	return out, nil
}

func isSafeAttachmentURL(raw string) bool {
	if strings.ContainsAny(raw, "\r\n\t ") {
		return false
	}
	return strings.HasPrefix(raw, "https://") ||
		strings.HasPrefix(raw, "http://") ||
		strings.HasPrefix(raw, "/api/v1/app/feedback/attachments/")
}

func ValidateAttachmentPath(date, filename string) (string, error) {
	if !attachmentDatePattern.MatchString(date) {
		return "", sharederror.New(sharederror.KindValidation, "invalid attachment date")
	}
	if !attachmentFilenamePattern.MatchString(filename) {
		return "", sharederror.New(sharederror.KindValidation, "invalid attachment filename")
	}
	return "feedback/" + date + "/" + filename, nil
}

// DetectAllowedImageType 基于文件头魔数严格识别允许的图片格式（JPEG / PNG / WebP）。
func DetectAllowedImageType(data []byte) (contentType string, ext string, ok bool) {
	if len(data) >= len(jpegMagic) && bytes.HasPrefix(data, jpegMagic) {
		return "image/jpeg", ".jpg", true
	}
	if len(data) >= len(pngMagic) && bytes.HasPrefix(data, pngMagic) {
		return "image/png", ".png", true
	}
	if len(data) >= 12 && string(data[:4]) == "RIFF" && string(data[8:12]) == "WEBP" {
		return "image/webp", ".webp", true
	}
	return "", "", false
}

func ContentTypeFromFilename(filename string) string {
	switch strings.ToLower(path.Ext(filename)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	default:
		return "application/octet-stream"
	}
}

func BuildAttachmentPublicURL(minioPublicURLPrefix, publicBaseURL, date, filename string) string {
	objectKey := "feedback/" + date + "/" + filename
	if prefix := strings.TrimRight(strings.TrimSpace(minioPublicURLPrefix), "/"); prefix != "" {
		return prefix + "/" + objectKey
	}
	rel := "/api/v1/app/feedback/attachments/" + date + "/" + filename
	if base := strings.TrimRight(strings.TrimSpace(publicBaseURL), "/"); base != "" {
		return base + rel
	}
	return rel
}
