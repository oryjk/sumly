package application

import (
	"context"
	"errors"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

type syncReader struct {
	calls  int
	series domain.HistorySeries
	err    error
}

func (r *syncReader) SyncHistory(_ context.Context, s domain.HistorySeries, _ string) (domain.HistorySync, error) {
	r.calls++
	r.series = s
	return domain.HistorySync{Series: s.ID, Unit: s.Unit, Points: []domain.HistoryChange{}}, r.err
}
func TestSyncUseCaseOwnsSeriesMappingAndValidation(t *testing.T) {
	r := &syncReader{}
	q := NewHistorySync(r, []domain.Instrument{{ID: "au9999", Symbol: "AU9999", Unit: "CNY/g"}, {ID: "comex-gold", Symbol: "NEW-CONTRACT", Unit: "USD/troy_oz"}})
	for _, tc := range []struct{ id, symbol, unit string }{{"xauusd", "XAUUSD", "USD/troy_oz"}, {"au9999", "AU9999", "CNY/g"}, {"comex-gold", "NEW-CONTRACT", "USD/troy_oz"}} {
		if _, e := q.Sync(context.Background(), tc.id, ""); e != nil {
			t.Fatal(e)
		}
		if r.series.Symbol != tc.symbol || r.series.Unit != tc.unit {
			t.Fatal(r.series)
		}
	}
	calls := r.calls
	for _, tc := range []struct{ id, cursor string }{{"unknown", ""}, {"xauusd", strings.Repeat("x", 161)}} {
		if _, e := q.Sync(context.Background(), tc.id, tc.cursor); !errors.Is(e, domain.ErrInvalidSyncQuery) {
			t.Fatal(e)
		}
	}
	if r.calls != calls {
		t.Fatal("invalid query reached persistence")
	}
}
