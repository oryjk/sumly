package application

import (
	"context"
	"errors"
	"math"
	"testing"

	domain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	auth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

// Persistence is external; this double detects calls made before authorization/validation.
type store struct {
	calls int
	err   error
	id    int64
}

func (s *store) Get(_ context.Context, id int64) (domain.Snapshot, error) {
	s.calls++
	s.id = id
	return domain.Snapshot{Revision: 3, Document: domain.EmptyDocument()}, s.err
}
func (s *store) Put(_ context.Context, id, rev int64, d domain.Document) (domain.Snapshot, error) {
	s.calls++
	s.id = id
	return domain.Snapshot{Revision: rev + 1, Document: d}, s.err
}
func TestServiceRejectsInvalidActorAndRevisionBeforePersistence(t *testing.T) {
	s := &store{}
	svc := NewService(s)
	ctx := context.Background()
	actor := auth.Actor{Kind: auth.ActorUser, ID: 42}
	for _, a := range []auth.Actor{{}, {Kind: auth.ActorAdmin, ID: 42}, {Kind: auth.ActorUser, ID: 0}} {
		if _, e := svc.Get(ctx, a); !errors.Is(e, errs.ErrUnauthorized) {
			t.Fatal(e)
		}
	}
	for _, rev := range []int64{-1, math.MaxInt64} {
		if _, e := svc.Put(ctx, actor, rev, domain.EmptyDocument()); !errors.Is(e, errs.ErrValidation) {
			t.Fatal(e)
		}
	}
	if _, e := svc.Put(ctx, actor, 0, domain.Document{}); !errors.Is(e, errs.ErrValidation) {
		t.Fatal(e)
	}
	if s.calls != 0 {
		t.Fatal("unauthorized/invalid input reached database")
	}
	got, e := svc.Put(ctx, actor, 0, domain.EmptyDocument())
	if e != nil || got.Revision != 1 || s.id != 42 {
		t.Fatal(got, e)
	}
	s.err = errs.ErrConflict
	if _, e := svc.Put(ctx, actor, 0, domain.EmptyDocument()); !errors.Is(e, errs.ErrConflict) {
		t.Fatal(e)
	}
}
