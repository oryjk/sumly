package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"math"

	q "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct{ pool *pgxpool.Pool }

func NewRepository(p *pgxpool.Pool) *Repository { return &Repository{p} }
func decode(rev int64, b []byte) (domain.Snapshot, error) {
	var d storedDocument
	err := json.Unmarshal(b, &d)
	return domain.Snapshot{Revision: rev, Document: d.toDomain()}, err
}

// Locking the user row also serializes absent-snapshot inserts. Native hard
// deletion and account status updates both require this same row lock.
func (r *Repository) transaction(ctx context.Context, id int64, f func(*q.Queries) (domain.Snapshot, error)) (domain.Snapshot, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.Snapshot{}, err
	}
	defer tx.Rollback(ctx)
	db := q.New(tx)
	status, err := db.LockHoldingsUser(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) || err == nil && status != "active" {
		return domain.Snapshot{}, errs.ErrUnauthorized
	}
	if err != nil {
		return domain.Snapshot{}, err
	}
	got, err := f(db)
	if err != nil {
		return domain.Snapshot{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return domain.Snapshot{}, err
	}
	return got, nil
}
func (r *Repository) Get(ctx context.Context, id int64) (domain.Snapshot, error) {
	return r.transaction(ctx, id, func(db *q.Queries) (domain.Snapshot, error) {
		got, err := db.GetHoldingsSnapshot(ctx, id)
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.Snapshot{Revision: 0, Document: domain.EmptyDocument()}, nil
		}
		if err != nil {
			return domain.Snapshot{}, err
		}
		return decode(got.Revision, got.Document)
	})
}
func (r *Repository) Put(ctx context.Context, id, expected int64, d domain.Document) (domain.Snapshot, error) {
	if expected < 0 || expected == math.MaxInt64 {
		return domain.Snapshot{}, errs.ErrValidation
	}
	size, err := snapshotSize(expected+1, d)
	if err != nil || size+64 > domain.MaxBytes {
		return domain.Snapshot{}, errs.ErrValidation
	}
	bytes, err := encodeDocument(d)
	if err != nil {
		return domain.Snapshot{}, err
	}
	return r.transaction(ctx, id, func(db *q.Queries) (domain.Snapshot, error) {
		current, err := db.GetHoldingsSnapshot(ctx, id)
		if errors.Is(err, pgx.ErrNoRows) {
			if expected != 0 {
				return domain.Snapshot{}, errs.ErrConflict
			}
			got, err := db.InsertHoldingsSnapshot(ctx, q.InsertHoldingsSnapshotParams{UserID: id, Document: bytes})
			if err != nil {
				return domain.Snapshot{}, err
			}
			return decode(got.Revision, got.Document)
		}
		if err != nil {
			return domain.Snapshot{}, err
		}
		if current.Revision != expected {
			return domain.Snapshot{}, errs.ErrConflict
		}
		got, err := db.UpdateHoldingsSnapshot(ctx, q.UpdateHoldingsSnapshotParams{UserID: id, Revision: expected, Document: bytes})
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.Snapshot{}, errs.ErrConflict
		}
		if err != nil {
			return domain.Snapshot{}, err
		}
		return decode(got.Revision, got.Document)
	})
}
