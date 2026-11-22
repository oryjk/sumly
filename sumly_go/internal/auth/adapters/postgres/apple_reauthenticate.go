package postgres

import (
	"context"
	"errors"
	"time"

	q "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"github.com/jackc/pgx/v5"
)

func (s *NativeStore) ReauthenticateApple(ctx context.Context, sessionID, subject string, issuedAt time.Time, encryptedRefresh []byte, next domain.Session) (domain.User, error) {
	var account domain.User
	err := s.transaction(ctx, func(db *q.Queries) error {
		if err := db.NativeLock(ctx, "apple:"+subject); err != nil {
			return err
		}
		ss, u, err := lockUserSession(ctx, db, sessionID)
		if err != nil {
			return err
		}
		if err = ss.RequireProvider("apple"); err != nil {
			return err
		}
		boundSubject, err := db.NativeSubjectByUser(ctx, q.NativeSubjectByUserParams{UserID: ss.UserID, Provider: "apple"})
		if err != nil {
			return err
		}
		if boundSubject != subject {
			return domain.ErrAppleAccountMismatch
		}
		if issuedAt.IsZero() || len(encryptedRefresh) == 0 {
			return domain.ErrLinkProof
		}
		if err = checkAppleCredentialAfterAccountEvent(ctx, db, subject, issuedAt); err != nil {
			if errors.Is(err, domain.ErrCredentials) {
				return domain.ErrLinkProof
			}
			return err
		}
		if err = db.NativeUpdateApple(ctx, q.NativeUpdateAppleParams{Provider: "apple", Subject: subject, AppleRefresh: encryptedRefresh}); err != nil {
			return err
		}
		if err = db.NativeRememberAppleAuthentication(ctx, q.NativeRememberAppleAuthenticationParams{Subject: subject, Column2: ts(issuedAt)}); err != nil {
			return err
		}
		// Preserve the previous family until the client securely saves the new session.
		next.UserID, next.Provider, next.FamilyID = ss.UserID, ss.Provider, next.ID
		if err = insertSession(ctx, db, next); err != nil {
			return err
		}
		account = u
		return nil
	})
	return account, err
}

func checkAppleCredentialAfterAccountEvent(ctx context.Context, db *q.Queries, subject string, issuedAt time.Time) error {
	latest, err := db.NativeLatestAppleAccountEvent(ctx, appleNotificationDigest(subject))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if issuedAt.IsZero() || !issuedAt.After(latest.Time) {
		return domain.ErrCredentials
	}
	return nil
}
