package providers

import (
	"strings"
	"testing"
)

func TestChanlunBridgeAcceptsPrivateTunnelButNotPublicHTTP(t *testing.T) {
	secret := strings.Repeat("s", 32)
	for _, allowed := range []string{"http://10.8.10.2:8001/api/auth/sumly/tickets", "http://127.0.0.1/tickets", "https://chanlun.example/tickets"} {
		if _, err := NewChanlunBridge(allowed, secret); err != nil {
			t.Errorf("rejects %s: %v", allowed, err)
		}
	}
	for _, denied := range []string{"http://192.0.2.20/tickets", "http://public.example/tickets", "http://user@10.8.10.2/tickets"} {
		if _, err := NewChanlunBridge(denied, secret); err == nil {
			t.Errorf("accepts %s", denied)
		}
	}
}
