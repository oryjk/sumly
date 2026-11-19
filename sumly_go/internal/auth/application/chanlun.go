package application

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

type ChanlunIdentity interface {
	Me(context.Context, string) (domain.User, error)
}

type ChanlunSessions struct {
	Identity ChanlunIdentity
	Tickets  ports.ChanlunTicketIssuer
}

func (s ChanlunSessions) Issue(ctx context.Context, token string) (string, error) {
	user, err := s.Identity.Me(ctx, token)
	if err != nil {
		return "", err
	}
	if user.ID <= 0 {
		return "", domain.ErrCredentials
	}
	return s.Tickets.Issue(ctx, user.ID)
}
