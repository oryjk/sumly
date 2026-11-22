package providers

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	jwt "github.com/golang-jwt/jwt/v5"
)

type googleTestTransport func(*http.Request) (*http.Response, error)

func (f googleTestTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestGoogleVerifiesSignatureIssuerAudienceAndNonce(t *testing.T) {
	const clientID = "web-client.apps.googleusercontent.com"
	const nonce = "challenge-nonce"
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	otherKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	crypto, err := credentials.New(strings.Repeat("s", 32))
	if err != nil {
		t.Fatal(err)
	}
	jwks, err := json.Marshal(map[string]any{"keys": []map[string]string{{
		"kid": "google-key", "kty": "RSA", "alg": "RS256", "use": "sig",
		"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
	}}})
	if err != nil {
		t.Fatal(err)
	}
	calls := 0
	client := &http.Client{Transport: googleTestTransport(func(r *http.Request) (*http.Response, error) {
		calls++
		if r.Method != http.MethodGet || r.URL.String() != "https://www.googleapis.com/oauth2/v3/certs" {
			t.Errorf("unexpected JWKS request: %s %s", r.Method, r.URL)
		}
		return &http.Response{StatusCode: http.StatusOK, Header: http.Header{"Cache-Control": {"public, max-age=4800"}}, Body: io.NopCloser(strings.NewReader(string(jwks)))}, nil
	})}
	provider := NewGoogle(clientID, client, crypto)
	for _, tc := range []struct {
		name   string
		edit   func(jwt.MapClaims)
		signer *rsa.PrivateKey
		want   error
		email  string
	}{
		{"valid", nil, key, nil, "verified@example.com"},
		{"valid legacy issuer", func(c jwt.MapClaims) { c["iss"] = "accounts.google.com" }, key, nil, "verified@example.com"},
		{"unverified email unused", func(c jwt.MapClaims) { c["email_verified"] = false }, key, nil, ""},
		{"wrong audience", func(c jwt.MapClaims) { c["aud"] = "another-client" }, key, domain.ErrCredentials, ""},
		{"foreign issuer", func(c jwt.MapClaims) { c["iss"] = "https://example.com" }, key, domain.ErrCredentials, ""},
		{"bad nonce", func(c jwt.MapClaims) { c["nonce"] = "another-challenge" }, key, domain.ErrCredentials, ""},
		{"expired", func(c jwt.MapClaims) { c["exp"] = time.Now().Add(-time.Minute).Unix() }, key, domain.ErrCredentials, ""},
		{"missing expiration", func(c jwt.MapClaims) { delete(c, "exp") }, key, domain.ErrCredentials, ""},
		{"forged signature", nil, otherKey, domain.ErrCredentials, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			claims := jwt.MapClaims{"iss": "https://accounts.google.com", "aud": clientID, "sub": "constant-google-id", "nonce": nonce,
				"exp": time.Now().Add(time.Hour).Unix(), "iat": time.Now().Add(-time.Second).Unix(),
				"name": "Google User", "email": "Verified@example.com", "email_verified": true}
			if tc.edit != nil {
				tc.edit(claims)
			}
			token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
			token.Header["kid"] = "google-key"
			raw, err := token.SignedString(tc.signer)
			if err != nil {
				t.Fatal(err)
			}
			got, err := provider.Verify(context.Background(), raw, crypto.Digest("google-nonce", nonce))
			if !errors.Is(err, tc.want) {
				t.Fatalf("got %v, want %v", err, tc.want)
			}
			if tc.want == nil && (got.Subject != "constant-google-id" || got.Nickname != "Google User" || got.VerifiedEmail != tc.email) {
				t.Fatalf("unexpected verified identity: %+v", got)
			}
		})
	}
	if calls != 1 {
		t.Fatalf("JWKS cache made %d calls", calls)
	}
}
