package domain

import (
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const (
	DefaultBootstrapAdminUsername = "admin"
	StaticTokenAdminUsername      = "token-admin"

	MaxAdminUsernameRunes = 64
	MinAdminPasswordRunes = 8
	MaxAdminPasswordBytes = 72
)

// AdminUser 对应 admin_users 表中的持久化管理员账号。
type AdminUser struct {
	ID                 int64
	Username           string
	PasswordHash       string
	MustChangePassword bool
	PasswordChangedAt  *time.Time
	CreatedAt          time.Time
	UpdatedAt          time.Time
}

// AdminSession 对应 admin_sessions 表中的管理员登录会话。
type AdminSession struct {
	TokenHash   string
	AdminUserID int64
	ExpiresAt   time.Time
	CreatedAt   time.Time
}

// AdminIdentity 表示通过管理后台鉴权后的当前管理员身份。
type AdminIdentity struct {
	UserID             int64
	Username           string
	MustChangePassword bool
	IsStaticToken      bool
	SessionTokenHash   string
}

// AdminLoginResult 表示管理员账号密码登录成功后的签发结果。
type AdminLoginResult struct {
	Token              string
	Username           string
	MustChangePassword bool
	ExpiresAt          time.Time
}

// ChangePasswordResult 表示管理员修改密码成功后的状态摘要。
type ChangePasswordResult struct {
	Username           string
	MustChangePassword bool
}

// NormalizeAdminUsername 规范化并校验管理员用户名。
func NormalizeAdminUsername(raw string) (string, error) {
	username := strings.TrimSpace(raw)
	if username == "" {
		return "", sharederror.New(sharederror.KindValidation, "username is required")
	}
	if utf8.RuneCountInString(username) > MaxAdminUsernameRunes {
		return "", sharederror.New(sharederror.KindValidation, fmt.Sprintf("username must not exceed %d characters", MaxAdminUsernameRunes))
	}
	return username, nil
}

// ValidateNewAdminPassword 校验修改密码时的新密码：长度 ≥ 8 且 ≤ 72 字节，且与当前密码不同。
func ValidateNewAdminPassword(currentPassword, newPassword string) error {
	if len(newPassword) < MinAdminPasswordRunes || utf8.RuneCountInString(newPassword) < MinAdminPasswordRunes {
		return sharederror.New(sharederror.KindValidation, fmt.Sprintf("new password must be at least %d characters", MinAdminPasswordRunes))
	}
	if len(newPassword) > MaxAdminPasswordBytes {
		return sharederror.New(sharederror.KindValidation, fmt.Sprintf("new password must not exceed %d bytes", MaxAdminPasswordBytes))
	}
	if newPassword == currentPassword {
		return sharederror.New(sharederror.KindValidation, "new password must be different from current password")
	}
	return nil
}
