package application

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

// GoldCollector owns ingestion; it never receives a read port or query service.
type GoldCollector struct {
	source  ports.GoldSource
	store   ports.GoldWriteStore
	native  bool
	now     func() time.Time
	dailyMu sync.Mutex
}

func NewGoldCollector(source ports.GoldSource, store ports.GoldWriteStore) *GoldCollector {
	return &GoldCollector{source: source, store: store, now: time.Now}
}
func NewNativeGoldCollector(source ports.GoldSource, store ports.GoldWriteStore) *GoldCollector {
	c := NewGoldCollector(source, store)
	c.native = true
	return c
}
func (c *GoldCollector) Sample(ctx context.Context) error {
	quote, err := c.source.FetchGoldQuote(ctx)
	if err != nil {
		return err
	}
	now := c.now()
	if !validPrice(quote.Price) || quote.AsOf.IsZero() || quote.AsOf.After(now.Add(5*time.Second)) {
		return fmt.Errorf("invalid source quote")
	}
	if err := c.store.SaveQuote(ctx, quote); err != nil {
		return err
	}
	if domain.ValidRealtime(quote, now, c.native) {
		point := domain.RealtimePoint{Time: domain.SampleTime(quote, now), SourceTime: quote.AsOf, Price: domain.RealtimePrice(quote, c.native)}
		if err := c.store.SaveRealtime(ctx, point); err != nil {
			return err
		}
	}
	return c.store.PruneRealtime(ctx)
}
func (c *GoldCollector) SyncIntraday(ctx context.Context) error {
	source, ok := c.source.(ports.GoldIntradaySource)
	if !ok {
		return nil
	}
	points, err := source.FetchGoldIntraday(ctx)
	if err != nil {
		return err
	}
	valid := make([]domain.IntradayPoint, 0, len(points))
	for _, p := range points {
		if !p.Time.IsZero() && !p.Time.After(c.now().Add(5*time.Second)) && validPrice(p.Price) {
			valid = append(valid, p)
		}
	}
	if len(valid) == 0 {
		return fmt.Errorf("source returned no valid intraday points")
	}
	return c.store.SaveIntraday(ctx, valid)
}
func collect(ctx context.Context, interval, timeout time.Duration, name string, run func(context.Context) error) {
	tick := time.NewTicker(interval)
	defer tick.Stop()
	refresh := func() {
		request, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()
		if err := run(request); err != nil && ctx.Err() == nil {
			slog.Warn(name, "error", err)
		}
	}
	refresh()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			refresh()
		}
	}
}
func (c *GoldCollector) CollectRealtime(ctx context.Context) {
	collect(ctx, RealtimeInterval, 4*time.Second, "collect gold realtime failed", c.Sample)
}
func (c *GoldCollector) CollectDaily(ctx context.Context) {
	collect(ctx, time.Minute, 30*time.Second, "collect gold daily failed", c.SyncDaily)
}
func (c *GoldCollector) CollectIntraday(ctx context.Context) {
	if _, ok := c.source.(ports.GoldIntradaySource); !ok {
		return
	}
	collect(ctx, 15*time.Second, 10*time.Second, "collect gold intraday failed", c.SyncIntraday)
}
