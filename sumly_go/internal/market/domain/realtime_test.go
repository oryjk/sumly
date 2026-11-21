package domain

import (
	"testing"
	"time"
)

func TestClampSourceTimeAndValidRealtimeSkewTolerance(t *testing.T) {
	now := time.Date(2026, 11, 21, 2, 20, 0, 0, time.FixedZone("CST", 8*3600))

	for _, skew := range []time.Duration{15 * time.Second, 60 * time.Second, MaxClockSkew} {
		asOf := now.Add(skew)
		q := GoldQuote{Price: 760.5, Currency: "CNY", AsOf: asOf}
		if !ValidRealtime(q, now, true) {
			t.Fatalf("expected skew %v to be valid", skew)
		}
		clamped := ClampSourceTime(asOf, now)
		if !clamped.Equal(now) {
			t.Fatalf("expected skew %v to clamp to now, got %v", skew, clamped)
		}
		delayed := GoldQuote{Price: 760.5, Currency: "CNY", AsOf: asOf, SourceDelaySeconds: 1800}
		if got := SampleTime(delayed, now); !got.Equal(now) {
			t.Fatalf("expected delayed future SampleTime to clamp to now, got %v", got)
		}
	}

	past := now.Add(-10 * time.Second)
	if got := ClampSourceTime(past, now); !got.Equal(past) {
		t.Fatalf("expected past time unchanged, got %v", got)
	}

	tooFuture := now.Add(120 * time.Second)
	if ValidRealtime(GoldQuote{Price: 760.5, Currency: "CNY", AsOf: tooFuture}, now, true) {
		t.Fatal("expected +120s quote to be rejected")
	}
	if got := ClampSourceTime(tooFuture, now); !got.Equal(tooFuture) {
		t.Fatalf("expected >MaxClockSkew not silently clamped, got %v", got)
	}
}

func TestParseRealtimeWindowMode(t *testing.T) {
	cases := []struct {
		raw  string
		want RealtimeWindowMode
		ok   bool
	}{
		{"", RealtimeWindowMode20m, true},
		{"   ", RealtimeWindowMode20m, true},
		{"20m", RealtimeWindowMode20m, true},
		{"20M", RealtimeWindowMode20m, true},
		{"session", RealtimeWindowModeSession, true},
		{" SESSION ", RealtimeWindowModeSession, true},
		{"1h", "", false},
		{"day", "", false},
	}
	for _, tc := range cases {
		got, ok := ParseRealtimeWindowMode(tc.raw)
		if ok != tc.ok || got != tc.want {
			t.Errorf("ParseRealtimeWindowMode(%q) = (%q, %v), want (%q, %v)", tc.raw, got, ok, tc.want, tc.ok)
		}
	}
}
