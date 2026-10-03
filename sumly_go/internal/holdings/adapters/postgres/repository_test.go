package postgres_test

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	native "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres"
	nd "gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	np "gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

func TestCASIsolationAndDeletion(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	r := postgres.NewRepository(p)
	var a, b int64
	if e := p.QueryRow(ctx, "INSERT INTO users(openid) VALUES('holdings-a') RETURNING id").Scan(&a); e != nil {
		t.Fatal(e)
	}
	if e := p.QueryRow(ctx, "INSERT INTO users(openid) VALUES('holdings-b') RETURNING id").Scan(&b); e != nil {
		t.Fatal(e)
	}
	got, e := r.Get(ctx, a)
	if e != nil || got.Revision != 0 || len(got.Document.Records) != 0 || got.Document.Books[0] != "默认账本" {
		t.Fatal(got, e)
	}
	var count int
	if e := p.QueryRow(ctx, "SELECT count(*) FROM holdings_snapshots").Scan(&count); e != nil || count != 0 {
		t.Fatal("GET wrote snapshot", count, e)
	}
	d := domain.EmptyDocument()
	d.Books = append(d.Books, "账户A")
	var wins atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Go(func() {
			_, e := r.Put(ctx, a, 0, d)
			if e == nil {
				wins.Add(1)
			} else if !errors.Is(e, errs.ErrConflict) {
				t.Errorf("unexpected CAS error: %v", e)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 1 {
		t.Fatal("CAS winners", wins.Load())
	}
	got, e = r.Get(ctx, a)
	if e != nil || got.Revision != 1 || got.Document.Books[1] != "账户A" {
		t.Fatal(got, e)
	}
	got, e = r.Get(ctx, b)
	if e != nil || got.Revision != 0 || len(got.Document.Books) != 1 {
		t.Fatal("user data leaked", got, e)
	}
	if _, e = r.Put(ctx, a, 0, domain.EmptyDocument()); !errors.Is(e, errs.ErrConflict) {
		t.Fatal("stale write accepted", e)
	}
	if _, e = p.Exec(ctx, "UPDATE users SET status='frozen' WHERE id=$1", a); e != nil {
		t.Fatal(e)
	}
	if e = p.QueryRow(ctx, "SELECT count(*) FROM holdings_snapshots WHERE user_id=$1", a).Scan(&count); e != nil || count != 1 {
		t.Fatal("freezing erased holdings", count, e)
	}
	if _, e = r.Put(ctx, a, 1, d); !errors.Is(e, errs.ErrUnauthorized) {
		t.Fatal("frozen account recreated snapshot", e)
	}
	if _, e = r.Get(ctx, a); !errors.Is(e, errs.ErrUnauthorized) {
		t.Fatal("frozen account read", e)
	}
	if _, e = r.Put(ctx, b, 0, d); e != nil {
		t.Fatal(e)
	}
	if _, e = p.Exec(ctx, "DELETE FROM users WHERE id=$1", b); e != nil {
		t.Fatal(e)
	}
	if e = p.QueryRow(ctx, "SELECT count(*) FROM holdings_snapshots WHERE user_id=$1", b).Scan(&count); e != nil || count != 0 {
		t.Fatal("hard deletion retained document", count, e)
	}
}
func TestNativeDeleteRemovesHoldingsAtomically(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	s := native.NewNativeStore(p)
	session := nd.Session{ID: "holdings-delete", RefreshHash: "delete-refresh", AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}
	u, e := s.Login(ctx, np.LoginMutation{Provider: "email", Subject: "holdings@example.com", Register: true, PasswordHash: "hash", OpenID: "holdings-native", Session: session})
	if e != nil {
		t.Fatal(e)
	}
	r := postgres.NewRepository(p)
	if _, e = r.Put(ctx, u.ID, 0, domain.EmptyDocument()); e != nil {
		t.Fatal(e)
	}
	if e = s.Delete(ctx, session.ID, nil); e != nil {
		t.Fatal(e)
	}
	var count int
	if e = p.QueryRow(ctx, "SELECT count(*) FROM holdings_snapshots WHERE user_id=$1", u.ID).Scan(&count); e != nil || count != 0 {
		t.Fatal(count, e)
	}
	if _, e = r.Put(ctx, u.ID, 0, domain.EmptyDocument()); !errors.Is(e, errs.ErrUnauthorized) {
		t.Fatal("deleted user restored holdings", e)
	}
}

func TestPutWaitsForAccountDeletionAndCannotRecreateSnapshot(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	r := postgres.NewRepository(p)
	var id int64
	if e := p.QueryRow(ctx, "INSERT INTO users(openid) VALUES('deletion-race') RETURNING id").Scan(&id); e != nil {
		t.Fatal(e)
	}
	if _, e := r.Put(ctx, id, 0, domain.EmptyDocument()); e != nil {
		t.Fatal(e)
	}
	tx, e := p.Begin(ctx)
	if e != nil {
		t.Fatal(e)
	}
	defer tx.Rollback(ctx)
	if _, e = tx.Exec(ctx, "DELETE FROM users WHERE id=$1", id); e != nil {
		t.Fatal(e)
	}
	pending := make(chan error, 1)
	go func() { _, err := r.Put(ctx, id, 1, domain.EmptyDocument()); pending <- err }()
	select {
	case e := <-pending:
		t.Fatal("write escaped uncommitted account deletion", e)
	case <-time.After(100 * time.Millisecond):
	}
	if e = tx.Commit(ctx); e != nil {
		t.Fatal(e)
	}
	select {
	case e := <-pending:
		if !errors.Is(e, errs.ErrUnauthorized) {
			t.Fatal("write recreated deleted account", e)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("write never resumed after deletion")
	}
	var count int
	if e = p.QueryRow(ctx, "SELECT count(*) FROM holdings_snapshots WHERE user_id=$1", id).Scan(&count); e != nil || count != 0 {
		t.Fatal(count, e)
	}
}

func TestFailedAppleDeletionRetainsSnapshotAndAccountDeletedEventCleansIt(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	s := native.NewNativeStore(p)
	r := postgres.NewRepository(p)
	session := nd.Session{ID: "holdings-apple", RefreshHash: "apple-refresh", AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}
	u, e := s.Login(ctx, np.LoginMutation{Provider: "apple", Subject: "holdings-apple-subject", OpenID: "holdings-apple-openid", AppleRefresh: []byte("test-only-ciphertext"), Session: session})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = r.Put(ctx, u.ID, 0, domain.EmptyDocument()); e != nil {
		t.Fatal(e)
	}
	failed := errors.New("provider revocation unavailable")
	if e = s.Delete(ctx, session.ID, func(context.Context, []byte) error { return failed }); !errors.Is(e, failed) {
		t.Fatal(e)
	}
	got, e := r.Get(ctx, u.ID)
	if e != nil || got.Revision != 1 {
		t.Fatal("failed deletion lost holdings", got, e)
	}
	if e = s.ApplyAppleEvent(ctx, nd.AppleNotification{ID: "holdings-apple-event", Subject: "holdings-apple-subject", Type: "account-deleted", IssuedAt: time.Now(), EventTime: time.Now().Unix()}); e != nil {
		t.Fatal(e)
	}
	var count int
	if e = p.QueryRow(ctx, "SELECT count(*) FROM holdings_snapshots WHERE user_id=$1", u.ID).Scan(&count); e != nil || count != 0 {
		t.Fatal("Apple account deleted left holdings", count, e)
	}
}
