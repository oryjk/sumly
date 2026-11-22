package application

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const (
	DefaultAdminSessionTTL = 24 * time.Hour
	adminSessionTokenBytes = 32
)

// AdminAuthService 提供管理员账号引导、登录、会话鉴权、退出与改密用例。
type AdminAuthService struct {
	repo        ports.AdminAuthRepository
	hasher      ports.PasswordHasher
	staticToken string
	sessionTTL  time.Duration
	now         func() time.Time
	randRead    func([]byte) (int, error)
}

func NewAdminAuthService(repo ports.AdminAuthRepository, hasher ports.PasswordHasher, staticToken string) *AdminAuthService {
	return &AdminAuthService{
		repo:        repo,
		hasher:      hasher,
		staticToken: strings.TrimSpace(staticToken),
		sessionTTL:  DefaultAdminSessionTTL,
		now:         time.Now,
		randRead:    rand.Read,
	}
}

// HashSessionToken 计算会话令牌的 SHA-256 十六进制摘要，数据库仅存摘要绝不存明文令牌。
func HashSessionToken(rawToken string) string {
	sum := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(sum[:])
}

// EnsureBootstrapAdmin 仅在 admin_users 中尚无对应 username 时插入初始管理员并置 must_change_password=true。
// 若该账号已存在则绝不覆盖已持久化密码。
func (s *AdminAuthService) EnsureBootstrapAdmin(ctx context.Context, username, password string) error {
	if password == "" {
		return nil
	}
	trimmedUsername := strings.TrimSpace(username)
	if trimmedUsername == "" {
		trimmedUsername = domain.DefaultBootstrapAdminUsername
	}
	normalized, err := domain.NormalizeAdminUsername(trimmedUsername)
	if err != nil {
		return err
	}
	if len(password) > domain.MaxAdminPasswordBytes {
		return sharederror.New(sharederror.KindValidation, fmt.Sprintf("bootstrap admin password must not exceed %d bytes", domain.MaxAdminPasswordBytes))
	}

	_, exists, err := s.repo.GetAdminUserByUsername(ctx, normalized)
	if err != nil {
		return fmt.Errorf("check bootstrap admin user: %w", err)
	}
	if exists {
		return nil
	}

	passwordHash, err := s.hasher.Hash(password)
	if err != nil {
		return fmt.Errorf("hash bootstrap admin password: %w", err)
	}
	if _, err := s.repo.EnsureAdminUser(ctx, normalized, passwordHash, true); err != nil {
		return fmt.Errorf("ensure bootstrap admin user: %w", err)
	}
	return nil
}

// Login 校验管理员用户名与密码并签发 24 小时有效的数据库会话令牌。
func (s *AdminAuthService) Login(ctx context.Context, username, password string) (domain.AdminLoginResult, error) {
	normalized := strings.TrimSpace(username)
	if normalized == "" || password == "" {
		s.hasher.DummyCompare(password)
		return domain.AdminLoginResult{}, sharederror.New(sharederror.KindUnauthorized, "invalid username or password")
	}

	user, found, err := s.repo.GetAdminUserByUsername(ctx, normalized)
	if err != nil {
		return domain.AdminLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "load admin user", err)
	}
	if !found {
		s.hasher.DummyCompare(password)
		return domain.AdminLoginResult{}, sharederror.New(sharederror.KindUnauthorized, "invalid username or password")
	}
	if !s.hasher.Compare(user.PasswordHash, password) {
		return domain.AdminLoginResult{}, sharederror.New(sharederror.KindUnauthorized, "invalid username or password")
	}

	rawBytes := make([]byte, adminSessionTokenBytes)
	if _, err := s.randRead(rawBytes); err != nil {
		return domain.AdminLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "generate admin session token", err)
	}
	rawToken := hex.EncodeToString(rawBytes)
	tokenHash := HashSessionToken(rawToken)
	now := s.now().UTC()
	expiresAt := now.Add(s.sessionTTL)

	if err := s.repo.CreateSession(ctx, domain.AdminSession{
		TokenHash:   tokenHash,
		AdminUserID: user.ID,
		ExpiresAt:   expiresAt,
		CreatedAt:   now,
	}); err != nil {
		return domain.AdminLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "create admin session", err)
	}

	// 尽力清理已过期会话，失败不影响正常登录。
	_ = s.repo.DeleteExpiredSessions(ctx, now)

	return domain.AdminLoginResult{
		Token:              rawToken,
		Username:           user.Username,
		MustChangePassword: user.MustChangePassword,
		ExpiresAt:          expiresAt,
	}, nil
}

// Authenticate 优先校验未过期数据库会话，未命中时按常量时间校验可选 ADMIN_API_TOKEN 兜底。
func (s *AdminAuthService) Authenticate(ctx context.Context, rawToken string) (domain.AdminIdentity, error) {
	token := strings.TrimSpace(rawToken)
	if token == "" {
		return domain.AdminIdentity{}, sharederror.ErrUnauthorized
	}

	if s.repo != nil {
		tokenHash := HashSessionToken(token)
		session, user, found, err := s.repo.GetValidSessionWithUser(ctx, tokenHash, s.now().UTC())
		if err != nil {
			return domain.AdminIdentity{}, sharederror.Wrap(sharederror.KindInternal, "verify admin session", err)
		}
		if found {
			return domain.AdminIdentity{
				UserID:             user.ID,
				Username:           user.Username,
				MustChangePassword: user.MustChangePassword,
				IsStaticToken:      false,
				SessionTokenHash:   session.TokenHash,
			}, nil
		}
	}

	if s.staticToken != "" && subtle.ConstantTimeCompare([]byte(token), []byte(s.staticToken)) == 1 {
		return domain.AdminIdentity{
			Username:           domain.StaticTokenAdminUsername,
			MustChangePassword: false,
			IsStaticToken:      true,
		}, nil
	}

	return domain.AdminIdentity{}, sharederror.ErrUnauthorized
}

// Logout 删除当前登录会话；若使用静态兜底令牌则幂等返回成功。
func (s *AdminAuthService) Logout(ctx context.Context, identity domain.AdminIdentity) error {
	if identity.IsStaticToken || identity.SessionTokenHash == "" {
		return nil
	}
	if err := s.repo.DeleteSession(ctx, identity.SessionTokenHash); err != nil {
		return sharederror.Wrap(sharederror.KindInternal, "delete admin session", err)
	}
	return nil
}

// ChangePassword 校验当前密码与新密码规则，持久化新密码哈希、清除首次改密标记并吊销其他会话（保留当前会话）。
func (s *AdminAuthService) ChangePassword(ctx context.Context, identity domain.AdminIdentity, currentPassword, newPassword string) (domain.ChangePasswordResult, error) {
	if identity.IsStaticToken || identity.UserID <= 0 || identity.SessionTokenHash == "" {
		return domain.ChangePasswordResult{}, sharederror.New(sharederror.KindUnauthorized, "session token is required to change password")
	}

	user, found, err := s.repo.GetAdminUserByID(ctx, identity.UserID)
	if err != nil {
		return domain.ChangePasswordResult{}, sharederror.Wrap(sharederror.KindInternal, "load admin user", err)
	}
	if !found {
		return domain.ChangePasswordResult{}, sharederror.ErrUnauthorized
	}

	if !s.hasher.Compare(user.PasswordHash, currentPassword) {
		return domain.ChangePasswordResult{}, sharederror.New(sharederror.KindUnauthorized, "当前密码不正确")
	}

	if err := domain.ValidateNewAdminPassword(currentPassword, newPassword); err != nil {
		return domain.ChangePasswordResult{}, err
	}

	newHash, err := s.hasher.Hash(newPassword)
	if err != nil {
		return domain.ChangePasswordResult{}, sharederror.Wrap(sharederror.KindInternal, "hash new password", err)
	}

	updated, err := s.repo.UpdatePasswordAndRevokeOtherSessions(ctx, user.ID, newHash, identity.SessionTokenHash, s.now().UTC())
	if err != nil {
		return domain.ChangePasswordResult{}, err
	}
	return domain.ChangePasswordResult{
		Username:           updated.Username,
		MustChangePassword: updated.MustChangePassword,
	}, nil
}
