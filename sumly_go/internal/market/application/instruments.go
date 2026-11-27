package application

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

// InstrumentQueries exposes only query use cases.
type InstrumentQueries interface {
	GetGoldQuote(context.Context) (domain.GoldQuote, error)
	GetGoldDailyKLines(context.Context) ([]domain.DailyBar, error)
	GetGoldRealtime(context.Context) ([]domain.RealtimePoint, int, error)
	GetGoldRealtimeWindow(context.Context, domain.RealtimeWindowMode) (domain.GoldWindow, error)
}

type InstrumentMarket struct {
	Instrument domain.Instrument
	Service    InstrumentQueries
}
type Instruments struct{ markets []InstrumentMarket }

func NewInstruments(markets []InstrumentMarket) *Instruments {
	return &Instruments{append([]InstrumentMarket(nil), markets...)}
}
func (s *Instruments) Catalog() []domain.Instrument {
	result := make([]domain.Instrument, 0, len(s.markets))
	for _, m := range s.markets {
		result = append(result, m.Instrument)
	}
	return result
}
func (s *Instruments) lookup(id string) (InstrumentMarket, error) {
	for _, m := range s.markets {
		if m.Instrument.ID == id {
			return m, nil
		}
	}
	return InstrumentMarket{}, sharederror.New(sharederror.KindNotFound, "行情品种不存在")
}
func (s *Instruments) Quote(ctx context.Context, id string) (domain.Instrument, domain.GoldQuote, error) {
	m, e := s.lookup(id)
	if e != nil {
		return domain.Instrument{}, domain.GoldQuote{}, e
	}
	q, e := m.Service.GetGoldQuote(ctx)
	return m.Instrument, q, e
}
func (s *Instruments) Daily(ctx context.Context, id string) (domain.Instrument, []domain.DailyBar, error) {
	m, e := s.lookup(id)
	if e != nil {
		return domain.Instrument{}, nil, e
	}
	p, e := m.Service.GetGoldDailyKLines(ctx)
	return m.Instrument, p, e
}
func (s *Instruments) Realtime(ctx context.Context, id string) (domain.Instrument, domain.GoldWindow, error) {
	return s.RealtimeWindow(ctx, id, domain.RealtimeWindowMode20m)
}

func (s *Instruments) RealtimeWindow(ctx context.Context, id string, mode domain.RealtimeWindowMode) (domain.Instrument, domain.GoldWindow, error) {
	m, e := s.lookup(id)
	if e != nil {
		return domain.Instrument{}, domain.GoldWindow{}, e
	}
	if mode != domain.RealtimeWindowModeSession && mode != domain.RealtimeWindowModeDay {
		points, interval, e := m.Service.GetGoldRealtime(ctx)
		window := domain.GoldWindow{Points: points, IntervalSeconds: interval, WindowSeconds: int(RealtimeWindow.Seconds())}
		if len(points) > 0 {
			window.End = points[len(points)-1].Time
			window.Start = window.End.Add(-RealtimeWindow)
		}
		return m.Instrument, window, e
	}
	if q, ok := m.Service.(*GoldQuery); ok {
		window, e := q.getGoldRealtimeWindowForInstrument(ctx, m.Instrument, mode)
		return m.Instrument, window, e
	}
	window, e := m.Service.GetGoldRealtimeWindow(ctx, mode)
	return m.Instrument, window, e
}
