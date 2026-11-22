package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// AdminAuthRepository 是管理员账号与会话表的 PostgreSQL 适配器。
type AdminAuthRepository struct {
	pool *pgxpool.Pool
}

func NewAdminAuthRepository(pool *pgxpool.Pool) *AdminAuthRepository {
	return &AdminAuthRepository{pool: pool}
}

func (r *AdminAuthRepository) EnsureAdminUser(ctx context.Context, username, passwordHash string, mustChangePassword bool) (bool, error) {
	tag, err := r.pool.Exec(ctx, `
		INSERT INTO admin_users (username, password_hash, must_change_password)
		VALUES ($1, $2, $3)
		ON CONFLICT (username) DO NOTHING
	`, username, passwordHash, mustChangePassword)
	if err != nil {
		return false, fmt.Errorf("ensure admin user %q: %w", username, err)
	}
	return tag.RowsAffected() > 0, nil
}

func (r *AdminAuthRepository) GetAdminUserByUsername(ctx context.Context, username string) (domain.AdminUser, bool, error) {
	var user domain.AdminUser
	err := r.pool.QueryRow(ctx, `
		SELECT id, username, password_hash, must_change_password, password_changed_at, created_at, updated_at
		FROM admin_users
		WHERE username = $1
	`, username).Scan(
		&user.ID,
		&user.Username,
		&user.PasswordHash,
		&user.MustChangePassword,
		&user.PasswordChangedAt,
		&user.CreatedAt,
		&user.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.AdminUser{}, false, nil
	}
	if err != nil {
		return domain.AdminUser{}, false, fmt.Errorf("get admin user by username %q: %w", username, err)
	}
	return user, true, nil
}

func (r *AdminAuthRepository) GetAdminUserByID(ctx context.Context, id int64) (domain.AdminUser, bool, error) {
	var user domain.AdminUser
	err := r.pool.QueryRow(ctx, `
		SELECT id, username, password_hash, must_change_password, password_changed_at, created_at, updated_at
		FROM admin_users
		WHERE id = $1
	`, id).Scan(
		&user.ID,
		&user.Username,
		&user.PasswordHash,
		&user.MustChangePassword,
		&user.PasswordChangedAt,
		&user.CreatedAt,
		&user.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.AdminUser{}, false, nil
	}
	if err != nil {
		return domain.AdminUser{}, false, fmt.Errorf("get admin user by id %d: %w", id, err)
	}
	return user, true, nil
}

func (r *AdminAuthRepository) CreateSession(ctx context.Context, session domain.AdminSession) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO admin_sessions (token_hash, admin_user_id, expires_at, created_at)
		VALUES ($1, $2, $3, $4)
	`, session.TokenHash, session.AdminUserID, session.ExpiresAt.UTC(), session.CreatedAt.UTC())
	if err != nil {
		return fmt.Errorf("create admin session: %w", err)
	}
	return nil
}

func (r *AdminAuthRepository) GetValidSessionWithUser(ctx context.Context, tokenHash string, now time.Time) (domain.AdminSession, domain.AdminUser, bool, error) {
	var session domain.AdminSession
	var user domain.AdminUser
	err := r.pool.QueryRow(ctx, `
		SELECT
			s.token_hash, s.admin_user_id, s.expires_at, s.created_at,
			u.id, u.username, u.password_hash, u.must_change_password, u.password_changed_at, u.created_at, u.updated_at
		FROM admin_sessions s
		JOIN admin_users u ON u.id = s.admin_user_id
		WHERE s.token_hash = $1 AND s.expires_at > $2
	`, tokenHash, now.UTC()).Scan(
		&session.TokenHash,
		&session.AdminUserID,
		&session.ExpiresAt,
		&session.CreatedAt,
		&user.ID,
		&user.Username,
		&user.PasswordHash,
		&user.MustChangePassword,
		&user.PasswordChangedAt,
		&user.CreatedAt,
		&user.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.AdminSession{}, domain.AdminUser{}, false, nil
	}
	if err != nil {
		return domain.AdminSession{}, domain.AdminUser{}, false, fmt.Errorf("get valid admin session: %w", err)
	}
	return session, user, true, nil
}

func (r *AdminAuthRepository) DeleteSession(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM admin_sessions
		WHERE token_hash = $1
	`, tokenHash)
	if err != nil {
		return fmt.Errorf("delete admin session: %w", err)
	}
	return nil
}

func (r *AdminAuthRepository) UpdatePasswordAndRevokeOtherSessions(
	ctx context.Context,
	userID int64,
	newPasswordHash string,
	keepTokenHash string,
	changedAt time.Time,
) (domain.AdminUser, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.AdminUser{}, fmt.Errorf("begin change password tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	ts := changedAt.UTC()
	var updated domain.AdminUser
	err = tx.QueryRow(ctx, `
		UPDATE admin_users
		SET password_hash = $1,
			must_change_password = FALSE,
			password_changed_at = $2,
			updated_at = $2
		WHERE id = $3
		RETURNING id, username, password_hash, must_change_password, password_changed_at, created_at, updated_at
	`, newPasswordHash, ts, userID).Scan(
		&updated.ID,
		&updated.Username,
		&updated.PasswordHash,
		&updated.MustChangePassword,
		&updated.PasswordChangedAt,
		&updated.CreatedAt,
		&updated.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.AdminUser{}, sharederror.ErrUnauthorized
	}
	if err != nil {
		return domain.AdminUser{}, fmt.Errorf("update admin password: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		DELETE FROM admin_sessions
		WHERE admin_user_id = $1 AND token_hash <> $2
	`, userID, keepTokenHash); err != nil {
		return domain.AdminUser{}, fmt.Errorf("revoke other admin sessions: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.AdminUser{}, fmt.Errorf("commit change password tx: %w", err)
	}
	return updated, nil
}

func (r *AdminAuthRepository) DeleteExpiredSessions(ctx context.Context, now time.Time) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM admin_sessions
		WHERE expires_at <= $1
	`, now.UTC())
	if err != nil {
		return fmt.Errorf("delete expired admin sessions: %w", err)
	}
	return nil
}
