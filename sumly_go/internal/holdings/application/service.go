package application

import (
	"context"
	"math"

	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/ports"
	auth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type Service struct{ repository ports.Repository }

func NewService(r ports.Repository) *Service { return &Service{r} }
func (s *Service) Get(ctx context.Context, a auth.Actor) (domain.Snapshot, error) {
	if !a.IsUser() || a.ID <= 0 {
		return domain.Snapshot{}, errs.ErrUnauthorized
	}
	return s.repository.Get(ctx, a.ID)
}
func (s *Service) Put(ctx context.Context, a auth.Actor, rev int64, d domain.Document) (domain.Snapshot, error) {
	if !a.IsUser() || a.ID <= 0 {
		return domain.Snapshot{}, errs.ErrUnauthorized
	}
	if rev < 0 || rev == math.MaxInt64 {
		return domain.Snapshot{}, errs.ErrValidation
	}
	if err := d.Validate(); err != nil {
		return domain.Snapshot{}, err
	}
	return s.repository.Put(ctx, a.ID, rev, d)
}
