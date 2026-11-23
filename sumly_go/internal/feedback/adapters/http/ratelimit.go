package feedbackhttp

import (
	"sync"
	"time"
)

// SlidingWindowLimiter 是一个并发安全的内存滑动窗口限流器。
type SlidingWindowLimiter struct {
	mu        sync.Mutex
	window    time.Duration
	limit     int
	buckets   map[string][]time.Time
	now       func() time.Time
	lastSweep time.Time
}

func NewSlidingWindowLimiter(limit int, window time.Duration, now func() time.Time) *SlidingWindowLimiter {
	if now == nil {
		now = time.Now
	}
	return &SlidingWindowLimiter{
		window:    window,
		limit:     limit,
		buckets:   make(map[string][]time.Time),
		now:       now,
		lastSweep: now(),
	}
}

func (l *SlidingWindowLimiter) Allow(key string) bool {
	if l == nil || l.limit <= 0 || l.window <= 0 {
		return true
	}
	now := l.now()
	cutoff := now.Add(-l.window)

	l.mu.Lock()
	defer l.mu.Unlock()

	if now.Sub(l.lastSweep) >= l.window/2 || len(l.buckets) > 2048 {
		l.sweepLocked(cutoff)
		l.lastSweep = now
	}

	timestamps := pruneTimestamps(l.buckets[key], cutoff)
	if len(timestamps) >= l.limit {
		l.buckets[key] = timestamps
		return false
	}
	timestamps = append(timestamps, now)
	l.buckets[key] = timestamps
	return true
}

func (l *SlidingWindowLimiter) sweepLocked(cutoff time.Time) {
	for k, ts := range l.buckets {
		kept := pruneTimestamps(ts, cutoff)
		if len(kept) == 0 {
			delete(l.buckets, k)
		} else {
			l.buckets[k] = kept
		}
	}
}

func pruneTimestamps(ts []time.Time, cutoff time.Time) []time.Time {
	if len(ts) == 0 {
		return nil
	}
	idx := 0
	for idx < len(ts) && !ts[idx].After(cutoff) {
		idx++
	}
	if idx == 0 {
		return ts
	}
	if idx == len(ts) {
		return nil
	}
	kept := make([]time.Time, len(ts)-idx)
	copy(kept, ts[idx:])
	return kept
}
