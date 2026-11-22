package application

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type fakePasswordHasher struct {
	dummyCalls int
}

func (f *fakePasswordHasher) Hash(password string) (string, error) {
	if len(password) > 72 {
		return "", errors.New("too long")
	}
	return "hashed:" + password, nil
}

func (f *fakePasswordHasher) Compare(hash, password string) bool {
	return hash == "hashed:"+password
}

func (f *fakePasswordHasher) DummyCompare(_ string) {
	f.dummyCalls++
}

type memoryAdminAuthRepo struct {
	usersByID       map[int64]domain.AdminUser
	usersByUsername map[string]int64
	sessions        map[string]domain.AdminSession
	nextUserID      int64
	now             func() time.Time
}

func newMemoryAdminAuthRepo(now func() time.Time) *memoryAdminAuthRepo {
	return &memoryAdminAuthRepo{
		usersByID:       map[int64]domain.AdminUser{},
		usersByUsername: map[string]int64{},
		sessions:        map[string]domain.AdminSession{},
		now:             now,
	}
}

func (r *memoryAdminAuthRepo) EnsureAdminUser(_ context.Context, username, passwordHash string, mustChangePassword bool) (bool, error) {
	if _, exists := r.usersByUsername[username]; exists {
		return false, nil
	}
	r.nextUserID++
	ts := r.now().UTC()
	user := domain.AdminUser{
		ID:                 r.nextUserID,
		Username:           username,
		PasswordHash:       passwordHash,
		MustChangePassword: mustChangePassword,
		CreatedAt:          ts,
		UpdatedAt:          ts,
	}
	r.usersByID[user.ID] = user
	r.usersByUsername[username] = user.ID
	return true, nil
}

func (r *memoryAdminAuthRepo) GetAdminUserByUsername(_ context.Context, username string) (domain.AdminUser, bool, error) {
	id, ok := r.usersByUsername[username]
	if !ok {
		return domain.AdminUser{}, false, nil
	}
	return r.usersByID[id], true, nil
}

func (r *memoryAdminAuthRepo) GetAdminUserByID(_ context.Context, id int64) (domain.AdminUser, bool, error) {
	u, ok := r.usersByID[id]
	return u, ok, nil
}

func (r *memoryAdminAuthRepo) CreateSession(_ context.Context, session domain.AdminSession) error {
	r.sessions[session.TokenHash] = session
	return nil
}

func (r *memoryAdminAuthRepo) GetValidSessionWithUser(_ context.Context, tokenHash string, now time.Time) (domain.AdminSession, domain.AdminUser, bool, error) {
	s, ok := r.sessions[tokenHash]
	if !ok || !s.ExpiresAt.After(now) {
		return domain.AdminSession{}, domain.AdminUser{}, false, nil
	}
	u, ok := r.usersByID[s.AdminUserID]
	if !ok {
		return domain.AdminSession{}, domain.AdminUser{}, false, nil
	}
	return s, u, true, nil
}

func (r *memoryAdminAuthRepo) DeleteSession(_ context.Context, tokenHash string) error {
	delete(r.sessions, tokenHash)
	return nil
}

func (r *memoryAdminAuthRepo) UpdatePasswordAndRevokeOtherSessions(_ context.Context, userID int64, newPasswordHash, keepTokenHash string, changedAt time.Time) (domain.AdminUser, error) {
	u, ok := r.usersByID[userID]
	if !ok {
		return domain.AdminUser{}, sharederror.ErrUnauthorized
	}
	ts := changedAt.UTC()
	u.PasswordHash = newPasswordHash
	u.MustChangePassword = false
	u.PasswordChangedAt = &ts
	u.UpdatedAt = ts
	r.usersByID[userID] = u

	for hash, sess := range r.sessions {
		if sess.AdminUserID == userID && hash != keepTokenHash {
			delete(r.sessions, hash)
		}
	}
	return u, nil
}

func (r *memoryAdminAuthRepo) DeleteExpiredSessions(_ context.Context, now time.Time) error {
	for hash, sess := range r.sessions {
		if !sess.ExpiresAt.After(now) {
			delete(r.sessions, hash)
		}
	}
	return nil
}

func TestEnsureBootstrapAdminSeedsOnceAndNeverOverwritesPersistedPassword(t *testing.T) {
	now := time.Date(2026, 11, 22, 10, 0, 0, 0, time.UTC)
	repo := newMemoryAdminAuthRepo(func() time.Time { return now })
	hasher := &fakePasswordHasher{}
	svc := NewAdminAuthService(repo, hasher, "")
	svc.now = func() time.Time { return now }

	ctx := context.Background()

	// Empty password does nothing
	if err := svc.EnsureBootstrapAdmin(ctx, "", ""); err != nil {
		t.Fatalf("empty bootstrap password should be no-op, got %v", err)
	}
	if len(repo.usersByID) != 0 {
		t.Fatalf("expected 0 users when bootstrap password is empty, got %d", len(repo.usersByID))
	}

	// First startup seeds default "admin" with must_change_password=true
	if err := svc.EnsureBootstrapAdmin(ctx, "", "InitialPass#1"); err != nil {
		t.Fatalf("EnsureBootstrapAdmin first run failed: %v", err)
	}
	login1, err := svc.Login(ctx, "admin", "InitialPass#1")
	if err != nil {
		t.Fatalf("login with initial password failed: %v", err)
	}
	if !login1.MustChangePassword {
		t.Fatal("expected must_change_password=true for bootstrap admin")
	}

	// Admin changes password
	id1, err := svc.Authenticate(ctx, login1.Token)
	if err != nil {
		t.Fatalf("authenticate failed: %v", err)
	}
	if _, err := svc.ChangePassword(ctx, id1, "InitialPass#1", "PersistedNewPass#2"); err != nil {
		t.Fatalf("ChangePassword failed: %v", err)
	}

	// Simulated server restart with original bootstrap env vars MUST NOT overwrite persisted password
	if err := svc.EnsureBootstrapAdmin(ctx, "admin", "InitialPass#1"); err != nil {
		t.Fatalf("EnsureBootstrapAdmin restart failed: %v", err)
	}

	if _, err := svc.Login(ctx, "admin", "InitialPass#1"); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("initial password must remain rejected after restart, got %v", err)
	}
	login2, err := svc.Login(ctx, "admin", "PersistedNewPass#2")
	if err != nil {
		t.Fatalf("persisted new password should still work after restart: %v", err)
	}
	if login2.MustChangePassword {
		t.Fatal("expected must_change_password=false to persist across restart")
	}
}

func TestAdminAuthLoginSessionExpiryLogoutAndDummyCompare(t *testing.T) {
	now := time.Date(2026, 11, 22, 10, 0, 0, 0, time.UTC)
	repo := newMemoryAdminAuthRepo(func() time.Time { return now })
	hasher := &fakePasswordHasher{}
	svc := NewAdminAuthService(repo, hasher, "")
	svc.now = func() time.Time { return now }

	ctx := context.Background()
	if err := svc.EnsureBootstrapAdmin(ctx, "admin", "InitPass#2026"); err != nil {
		t.Fatal(err)
	}

	// Non-existent user runs DummyCompare to resist username enumeration
	if _, err := svc.Login(ctx, "ghost", "anything"); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected ErrUnauthorized for unknown user, got %v", err)
	}
	if hasher.dummyCalls != 1 {
		t.Fatalf("expected 1 DummyCompare call, got %d", hasher.dummyCalls)
	}

	// Wrong password fails with 401
	if _, err := svc.Login(ctx, "admin", "WrongPass"); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected ErrUnauthorized for wrong password, got %v", err)
	}

	// Successful login stores SHA-256 hash, never raw token
	res, err := svc.Login(ctx, "admin", "InitPass#2026")
	if err != nil {
		t.Fatalf("Login failed: %v", err)
	}
	if len(res.Token) != 64 {
		t.Fatalf("expected 64-char hex token (32 bytes), got len=%d", len(res.Token))
	}
	if !res.ExpiresAt.Equal(now.Add(24 * time.Hour)) {
		t.Fatalf("expires_at=%v want %v", res.ExpiresAt, now.Add(24*time.Hour))
	}
	if _, rawStored := repo.sessions[res.Token]; rawStored {
		t.Fatal("raw token must never be stored in admin_sessions")
	}
	if _, hashStored := repo.sessions[HashSessionToken(res.Token)]; !hashStored {
		t.Fatal("expected sha256(token) to be stored in admin_sessions")
	}

	// Authenticate succeeds before expiry
	ident, err := svc.Authenticate(ctx, res.Token)
	if err != nil || ident.Username != "admin" || !ident.MustChangePassword || ident.IsStaticToken {
		t.Fatalf("unexpected identity: %+v err=%v", ident, err)
	}

	// Logout invalidates session immediately
	if err := svc.Logout(ctx, ident); err != nil {
		t.Fatalf("Logout failed: %v", err)
	}
	if _, err := svc.Authenticate(ctx, res.Token); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected logged out token to be rejected, got %v", err)
	}

	// Login again and advance clock past 24h TTL
	res2, err := svc.Login(ctx, "admin", "InitPass#2026")
	if err != nil {
		t.Fatalf("second Login failed: %v", err)
	}
	now = now.Add(24 * time.Hour)
	if _, err := svc.Authenticate(ctx, res2.Token); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected expired session to be rejected, got %v", err)
	}
}

func TestAdminAuthChangePasswordRevokesOtherSessionsAndKeepsCurrent(t *testing.T) {
	now := time.Date(2026, 11, 22, 10, 0, 0, 0, time.UTC)
	repo := newMemoryAdminAuthRepo(func() time.Time { return now })
	hasher := &fakePasswordHasher{}
	svc := NewAdminAuthService(repo, hasher, "fallback-script-token")
	svc.now = func() time.Time { return now }

	ctx := context.Background()
	if err := svc.EnsureBootstrapAdmin(ctx, "admin", "InitPass#2026"); err != nil {
		t.Fatal(err)
	}

	// Two concurrent sessions for the same admin
	s1, err := svc.Login(ctx, "admin", "InitPass#2026")
	if err != nil {
		t.Fatal(err)
	}
	s2, err := svc.Login(ctx, "admin", "InitPass#2026")
	if err != nil {
		t.Fatal(err)
	}

	id1, err := svc.Authenticate(ctx, s1.Token)
	if err != nil {
		t.Fatal(err)
	}

	// Wrong current password -> 401
	if _, err := svc.ChangePassword(ctx, id1, "WrongCurrent", "ValidNewPass#1"); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected unauthorized for wrong current password, got %v", err)
	}

	// Invalid new password -> 422
	for _, badNew := range []string{"short", strings.Repeat("a", 73), "InitPass#2026"} {
		if _, err := svc.ChangePassword(ctx, id1, "InitPass#2026", badNew); !errors.Is(err, sharederror.ErrValidation) {
			t.Fatalf("expected validation error for new password %q, got %v", badNew, err)
		}
	}

	// Static fallback token cannot change password -> 401
	staticID, err := svc.Authenticate(ctx, "fallback-script-token")
	if err != nil || !staticID.IsStaticToken || staticID.Username != domain.StaticTokenAdminUsername || staticID.MustChangePassword {
		t.Fatalf("unexpected static fallback identity: %+v err=%v", staticID, err)
	}
	if _, err := svc.ChangePassword(ctx, staticID, "InitPass#2026", "ValidNewPass#1"); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected static token ChangePassword to fail with unauthorized, got %v", err)
	}

	// Valid change password
	now = now.Add(5 * time.Minute)
	changed, err := svc.ChangePassword(ctx, id1, "InitPass#2026", "BrandNewPass#99")
	if err != nil {
		t.Fatalf("ChangePassword failed: %v", err)
	}
	if changed.Username != "admin" || changed.MustChangePassword {
		t.Fatalf("unexpected change password result: %+v", changed)
	}

	// Current session s1 stays valid and now reports must_change_password=false
	id1After, err := svc.Authenticate(ctx, s1.Token)
	if err != nil {
		t.Fatalf("current session should remain valid after ChangePassword, got %v", err)
	}
	if id1After.MustChangePassword {
		t.Fatal("expected current session to reflect must_change_password=false")
	}

	// Other session s2 is revoked
	if _, err := svc.Authenticate(ctx, s2.Token); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected other session s2 to be revoked, got %v", err)
	}

	// Old password fails, new password succeeds
	if _, err := svc.Login(ctx, "admin", "InitPass#2026"); !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected old password login to fail, got %v", err)
	}
	s3, err := svc.Login(ctx, "admin", "BrandNewPass#99")
	if err != nil || s3.MustChangePassword {
		t.Fatalf("expected new password login to succeed with must_change_password=false, got %+v err=%v", s3, err)
	}
}
