package ports

import "context"

type ChanlunTicketIssuer interface {
	Issue(context.Context, int64) (string, error)
}
