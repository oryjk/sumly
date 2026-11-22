package postgres

import (
	"context"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

func TestAdminAuthRepositoryLifecycle(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repo := NewAdminAuthRepository(pool)
	ctx := context.Background()

	// First ensure inserts admin user with must_change_password=true
	inserted, err := repo.EnsureAdminUser(ctx, "admin", "$2a$10$hash-initial", true)
	if err != nil || !inserted {
		t.Fatalf("first EnsureAdminUser inserted=%v err=%v", inserted, err)
	}

	// Second ensure with different hash does NOT overwrite existing record
	insertedAgain, err := repo.EnsureAdminUser(ctx, "admin", "$2a$10$hash-overwrite-attempt", true)
	if err != nil || insertedAgain {
		t.Fatalf("second EnsureAdminUser inserted=%v err=%v", insertedAgain, err)
	}

	user, found, err := repo.GetAdminUserByUsername(ctx, "admin")
	if err != nil || !found {
		t.Fatalf("GetAdminUserByUsername found=%v err=%v", found, err)
	}
	if user.PasswordHash != "$2a$10$hash-initial" || !user.MustChangePassword || user.PasswordChangedAt != nil {
		t.Fatalf("unexpected seeded admin user: %+v", user)
	}

	now := time.Now().UTC().Truncate(time.Second)
	s1 := domain.AdminSession{
		TokenHash:   "session-hash-1",
		AdminUserID: user.ID,
		ExpiresAt:   now.Add(24 * time.Hour),
		CreatedAt:   now,
	}
	s2 := domain.AdminSession{
		TokenHash:   "session-hash-2",
		AdminUserID: user.ID,
		ExpiresAt:   now.Add(24 * time.Hour),
		CreatedAt:   now,
	}
	expired := domain.AdminSession{
		TokenHash:   "session-hash-expired",
		AdminUserID: user.ID,
		ExpiresAt:   now.Add(-1 * time.Minute),
		CreatedAt:   now.Add(-25 * time.Hour),
	}
	for _, s := range []domain.AdminSession{s1, s2, expired} {
		if err := repo.CreateSession(ctx, s); err != nil {
			t.Fatalf("CreateSession %s failed: %v", s.TokenHash, err)
		}
	}

	// Valid session lookup succeeds; expired session returns not found
	gotSession, gotUser, ok, err := repo.GetValidSessionWithUser(ctx, s1.TokenHash, now)
	if err != nil || !ok || gotSession.TokenHash != s1.TokenHash || gotUser.ID != user.ID {
		t.Fatalf("GetValidSessionWithUser s1 ok=%v err=%v session=%+v user=%+v", ok, err, gotSession, gotUser)
	}
	if _, _, ok, err := repo.GetValidSessionWithUser(ctx, expired.TokenHash, now); err != nil || ok {
		t.Fatalf("expected expired session not found, ok=%v err=%v", ok, err)
	}

	// Change password atomically updates password, clears must_change_password, revokes s2, keeps s1
	changedAt := now.Add(2 * time.Minute)
	updated, err := repo.UpdatePasswordAndRevokeOtherSessions(ctx, user.ID, "$2a$10$hash-new", s1.TokenHash, changedAt)
	if err != nil {
		t.Fatalf("UpdatePasswordAndRevokeOtherSessions failed: %v", err)
	}
	if updated.PasswordHash != "$2a$10$hash-new" || updated.MustChangePassword || updated.PasswordChangedAt == nil {
		t.Fatalf("unexpected updated admin user: %+v", updated)
	}

	// s1 still valid with updated user state; s2 revoked
	_, userAfter, ok, err := repo.GetValidSessionWithUser(ctx, s1.TokenHash, changedAt)
	if err != nil || !ok || userAfter.MustChangePassword {
		t.Fatalf("expected s1 kept with must_change_password=false, ok=%v user=%+v err=%v", ok, userAfter, err)
	}
	if _, _, ok, err := repo.GetValidSessionWithUser(ctx, s2.TokenHash, changedAt); err != nil || ok {
		t.Fatalf("expected s2 revoked, ok=%v err=%v", ok, err)
	}

	// Restart ensure still does not overwrite updated password
	if insertedAfter, err := repo.EnsureAdminUser(ctx, "admin", "$2a$10$hash-initial", true); err != nil || insertedAfter {
		t.Fatalf("EnsureAdminUser after password change inserted=%v err=%v", insertedAfter, err)
	}
	reloaded, found, err := repo.GetAdminUserByID(ctx, user.ID)
	if err != nil || !found || reloaded.PasswordHash != "$2a$10$hash-new" || reloaded.MustChangePassword {
		t.Fatalf("expected persisted password preserved, found=%v user=%+v err=%v", found, reloaded, err)
	}

	// DeleteExpiredSessions & DeleteSession
	if err := repo.DeleteExpiredSessions(ctx, changedAt); err != nil {
		t.Fatalf("DeleteExpiredSessions failed: %v", err)
	}
	if err := repo.DeleteSession(ctx, s1.TokenHash); err != nil {
		t.Fatalf("DeleteSession failed: %v", err)
	}
	if _, _, ok, err := repo.GetValidSessionWithUser(ctx, s1.TokenHash, changedAt); err != nil || ok {
		t.Fatalf("expected deleted s1 not found, ok=%v err=%v", ok, err)
	}
}
