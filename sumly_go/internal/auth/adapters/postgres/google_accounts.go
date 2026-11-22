package postgres

import (
	"context"
	"errors"

	q "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"github.com/jackc/pgx/v5"
)

func (s *NativeStore) LinkGoogle(ctx context.Context, sessionID, subject string) error {
	return s.transaction(ctx, func(db *q.Queries) error {
		ss, err := lockLinkSession(ctx, db, sessionID, "email", "google:"+subject)
		if err != nil {
			return err
		}
		bound, err := credentialAlreadyBound(ctx, db, ss.UserID, "google", subject)
		if err != nil || bound {
			return err
		}
		return db.NativeInsertIdentity(ctx, q.NativeInsertIdentityParams{
			UserID: ss.UserID, Provider: "google", Subject: subject,
		})
	})
}

func (s *NativeStore) LinkEmail(ctx context.Context, sessionID, email, otpHash, passwordHash string) error {
	return s.transaction(ctx, func(db *q.Queries) error {
		if err := db.NativeLock(ctx, "email:"+email); err != nil {
			return err
		}
		ss, _, err := lockUserSession(ctx, db, sessionID)
		if err != nil {
			return err
		}
		if ss.Provider != "apple" && ss.Provider != "google" {
			return domain.ErrReauthenticate
		}
		if err = ss.RequireRecentAuthentication(ss.Provider); err != nil {
			return err
		}
		// Verify ownership before revealing a conflict, and consume the code even when the
		// credential is already bound. This route never updates an existing password.
		if err = consume(ctx, db, domain.LinkedEmailCodeKey(ss.UserID, email), otpHash); err != nil {
			if errors.Is(err, domain.ErrCredentials) {
				return domain.ErrLinkProof
			}
			return err
		}
		bound, err := credentialAlreadyBound(ctx, db, ss.UserID, "email", email)
		if err != nil || bound {
			return err
		}
		return db.NativeInsertIdentity(ctx, q.NativeInsertIdentityParams{
			UserID: ss.UserID, Provider: "email", Subject: email, PasswordHash: passwordHash,
		})
	})
}

func (s *NativeStore) ReauthenticateGoogle(ctx context.Context, sessionID, subject string, next domain.Session) (domain.User, error) {
	var account domain.User
	err := s.transaction(ctx, func(db *q.Queries) error {
		ss, u, err := lockUserSession(ctx, db, sessionID)
		if err != nil {
			return err
		}
		if err = ss.RequireProvider("google"); err != nil {
			return err
		}
		boundSubject, err := db.NativeSubjectByUser(ctx, q.NativeSubjectByUserParams{UserID: ss.UserID, Provider: "google"})
		if err != nil {
			return err
		}
		if boundSubject != subject {
			return domain.ErrAccountMismatch
		}
		// The calling client revokes its old family after persisting these credentials.
		next.UserID, next.Provider, next.FamilyID = ss.UserID, ss.Provider, next.ID
		if err = insertSession(ctx, db, next); err != nil {
			return err
		}
		account = u
		return nil
	})
	return account, err
}

func lockLinkSession(ctx context.Context, db *q.Queries, sessionID, sourceProvider, credentialLock string) (domain.Session, error) {
	if err := db.NativeLock(ctx, credentialLock); err != nil {
		return domain.Session{}, err
	}
	ss, _, err := lockUserSession(ctx, db, sessionID)
	if err != nil {
		return domain.Session{}, err
	}
	return ss, ss.RequireRecentAuthentication(sourceProvider)
}

func lockUserSession(ctx context.Context, db *q.Queries, sessionID string) (domain.Session, domain.User, error) {
	ss, _, err := session(ctx, db, sessionID)
	if err != nil {
		return domain.Session{}, domain.User{}, err
	}
	if err = userLock(ctx, db, ss.UserID); err != nil {
		return domain.Session{}, domain.User{}, err
	}
	return session(ctx, db, sessionID)
}

func credentialAlreadyBound(ctx context.Context, db *q.Queries, userID int64, provider, subject string) (bool, error) {
	current, err := db.NativeSubjectByUser(ctx, q.NativeSubjectByUserParams{UserID: userID, Provider: provider})
	switch {
	case err == nil && current == subject:
		return true, nil
	case err == nil:
		return false, domain.ErrConflict
	case !errors.Is(err, pgx.ErrNoRows):
		return false, err
	}
	_, err = identity(ctx, db, provider, subject)
	switch {
	case err == nil:
		return false, domain.ErrConflict
	case errors.Is(err, domain.ErrCredentials):
		return false, nil
	default:
		return false, err
	}
}
