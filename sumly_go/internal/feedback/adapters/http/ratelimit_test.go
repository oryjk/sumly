package feedbackhttp

import (
	"sync"
	"testing"
	"time"
)

func TestSlidingWindowLimiterAllowsAndExpires(t *testing.T) {
	current := time.Date(2026, 11, 23, 10, 0, 0, 0, time.UTC)
	limiter := NewSlidingWindowLimiter(3, time.Hour, func() time.Time { return current })

	for i := 0; i < 3; i++ {
		if !limiter.Allow("ip1|dev1") {
			t.Fatalf("attempt %d should be allowed", i+1)
		}
	}
	if limiter.Allow("ip1|dev1") {
		t.Fatal("4th attempt within window should be rejected")
	}
	// Separate key is independent
	if !limiter.Allow("ip1|dev2") {
		t.Fatal("different key should be allowed")
	}

	// Advance past window
	current = current.Add(time.Hour + time.Second)
	if !limiter.Allow("ip1|dev1") {
		t.Fatal("attempt after window expiration should be allowed")
	}
}

func TestSlidingWindowLimiterConcurrentSafety(t *testing.T) {
	limiter := NewSlidingWindowLimiter(10, time.Hour, nil)
	var wg sync.WaitGroup
	allowed := make(chan bool, 50)
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			allowed <- limiter.Allow("shared-key")
		}()
	}
	wg.Wait()
	close(allowed)

	count := 0
	for ok := range allowed {
		if ok {
			count++
		}
	}
	if count != 10 {
		t.Fatalf("expected exactly 10 allowed under concurrency, got %d", count)
	}
}
