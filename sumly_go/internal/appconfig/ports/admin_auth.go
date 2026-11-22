package ports

import (
	"context"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
)

// PasswordHasher 封装管理员密码哈希与常量耗时比对能力，隔离外部加密库依赖。
type PasswordHasher interface {
	Hash(password string) (string, error)
	Compare(hash, password string) bool
	DummyCompare(password string)
}

// AdminAuthRepository 定义管理员账号与会话的持久化端口。
type AdminAuthRepository interface {
	EnsureAdminUser(ctx context.Context, username, passwordHash string, mustChangePassword bool) (bool, error)
	GetAdminUserByUsername(ctx context.Context, username string) (domain.AdminUser, bool, error)
	GetAdminUserByID(ctx context.Context, id int64) (domain.AdminUser, bool, error)
	CreateSession(ctx context.Context, session domain.AdminSession) error
	GetValidSessionWithUser(ctx context.Context, tokenHash string, now time.Time) (domain.AdminSession, domain.AdminUser, bool, error)
	DeleteSession(ctx context.Context, tokenHash string) error
	UpdatePasswordAndRevokeOtherSessions(ctx context.Context, userID int64, newPasswordHash, keepTokenHash string, changedAt time.Time) (domain.AdminUser, error)
	DeleteExpiredSessions(ctx context.Context, now time.Time) error
}
