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
	if !validPrice(quote.Price) || quote.AsOf.IsZero() || quote.AsOf.After(now.Add(domain.MaxClockSkew)) {
		return fmt.Errorf("invalid source quote")
	}
	quote.AsOf = domain.ClampSourceTime(quote.AsOf, now)
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

const (
	intradayActiveInterval = time.Minute
	intradayIdleInterval   = 5 * time.Minute
	intradayMaxBackoff     = 5 * time.Minute
	intradayStaleThreshold = 10 * time.Minute
	intradayTimeout        = 15 * time.Second
)

func (c *GoldCollector) SyncIntraday(ctx context.Context) error {
	_, err := c.syncIntraday(ctx)
	return err
}

func (c *GoldCollector) syncIntraday(ctx context.Context) (time.Time, error) {
	source, ok := c.source.(ports.GoldIntradaySource)
	if !ok {
		return time.Time{}, nil
	}
	points, err := source.FetchGoldIntraday(ctx)
	if err != nil {
		return time.Time{}, err
	}
	now := c.now()
	valid := make([]domain.IntradayPoint, 0, len(points))
	for _, p := range points {
		if p.Time.IsZero() || p.Time.After(now.Add(domain.MaxClockSkew)) || !validPrice(p.Price) {
			continue
		}
		p.Time = domain.ClampSourceTime(p.Time, now)
		if len(valid) > 0 && valid[len(valid)-1].Time.Equal(p.Time) {
			valid[len(valid)-1] = p
			continue
		}
		valid = append(valid, p)
	}
	if len(valid) == 0 {
		return time.Time{}, fmt.Errorf("source returned no valid intraday points")
	}
	if err := c.store.SaveIntraday(ctx, valid); err != nil {
		return time.Time{}, err
	}
	return valid[len(valid)-1].Time, nil
}

func nextIntradayDelay(now, latestEvent time.Time, consecutiveErrs int) time.Duration {
	if consecutiveErrs > 0 {
		shift := consecutiveErrs - 1
		if shift > 4 {
			shift = 4
		}
		delay := intradayActiveInterval << shift
		if delay > intradayMaxBackoff {
			return intradayMaxBackoff
		}
		return delay
	}
	if !latestEvent.IsZero() && now.Sub(latestEvent) > intradayStaleThreshold {
		return intradayIdleInterval
	}
	return intradayActiveInterval
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
	consecutiveErrs := 0
	for {
		request, cancel := context.WithTimeout(ctx, intradayTimeout)
		latestEvent, err := c.syncIntraday(request)
		cancel()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			consecutiveErrs++
			slog.Warn("collect gold intraday failed", "error", err, "consecutive_errors", consecutiveErrs)
		} else {
			consecutiveErrs = 0
		}

		delay := nextIntradayDelay(c.now(), latestEvent, consecutiveErrs)
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}
