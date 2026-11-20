package providers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

func TestNativeSessionClientUsesOnlyVerifiedActiveIdentity(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		body   string
		err    error
	}{
		{"active", 200, `{"code":0,"data":{"id":42,"status":"active"}}`, nil},
		{"frozen", 200, `{"code":0,"data":{"id":42,"status":"frozen"}}`, domain.ErrCredentials},
		{"revoked", 401, `{}`, domain.ErrCredentials},
		{"missing envelope", 200, `{"data":{"id":42,"status":"active"}}`, domain.ErrUnavailable},
		{"unavailable", 503, `{}`, domain.ErrUnavailable},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodGet || r.URL.Path != "/api/v1/app/auth/me" || r.Header.Get("Authorization") != "Bearer test-token" {
					t.Error("unexpected session validation request")
				}
				w.WriteHeader(tc.status)
				_, _ = fmt.Fprint(w, tc.body)
			}))
			defer server.Close()
			client, err := NewNativeSessionClient(server.URL + "/api/v1/app/auth/me")
			if err != nil {
				t.Fatal(err)
			}
			user, err := client.Me(context.Background(), "test-token")
			if !errors.Is(err, tc.err) || (tc.err == nil && user.ID != 42) || (tc.err != nil && user.ID != 0) {
				t.Errorf("identity=%d error=%v; expected %v", user.ID, err, tc.err)
			}
		})
	}
}
