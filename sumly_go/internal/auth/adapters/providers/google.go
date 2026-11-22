package providers

import (
	"context"
	"crypto/rsa"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"math/big"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	jwt "github.com/golang-jwt/jwt/v5"
)

const googleJWKS = "https://www.googleapis.com/oauth2/v3/certs"

var googleOAuthClientID = regexp.MustCompile(`^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$`)

type Google struct {
	clientID      string
	http          *http.Client
	crypto        ports.Cryptography
	mu            sync.Mutex
	keys          map[string]*rsa.PublicKey
	cacheUntil    time.Time
	lastAttempt   time.Time
	refreshFailed bool
}

func NewGoogle(clientID string, h *http.Client, crypto ports.Cryptography) *Google {
	return &Google{clientID: strings.TrimSpace(clientID), http: boundedClient(h), crypto: crypto}
}

func (g *Google) ClientID() string {
	if g == nil || g.crypto == nil || len(g.clientID) > 255 || !googleOAuthClientID.MatchString(g.clientID) {
		return ""
	}
	return g.clientID
}

type googleClaims struct {
	Nonce         string `json:"nonce"`
	Name          string `json:"name"`
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	jwt.RegisteredClaims
}

func (g *Google) Verify(ctx context.Context, raw, nonceHash string) (ports.GoogleIdentity, error) {
	if g.ClientID() == "" {
		return ports.GoogleIdentity{}, domain.ErrUnavailable
	}
	if len(raw) == 0 || len(raw) > 16384 || nonceHash == "" {
		return ports.GoogleIdentity{}, domain.ErrCredentials
	}
	claims := &googleClaims{}
	token, err := jwt.ParseWithClaims(raw, claims, func(token *jwt.Token) (any, error) {
		kid, ok := token.Header["kid"].(string)
		if !ok || kid == "" || len(kid) > 128 {
			return nil, domain.ErrCredentials
		}
		return g.publicKey(ctx, kid)
	}, jwt.WithValidMethods([]string{"RS256"}), jwt.WithExpirationRequired(), jwt.WithAudience(g.clientID), jwt.WithIssuedAt())
	if errors.Is(err, domain.ErrUnavailable) {
		return ports.GoogleIdentity{}, domain.ErrUnavailable
	}
	if err != nil || !token.Valid || (claims.Issuer != "https://accounts.google.com" && claims.Issuer != "accounts.google.com") ||
		len(claims.Audience) != 1 || claims.IssuedAt == nil || !validGoogleSubject(claims.Subject) ||
		claims.Nonce == "" || len(claims.Nonce) > 256 ||
		subtle.ConstantTimeCompare([]byte(g.crypto.Digest("google-nonce", claims.Nonce)), []byte(nonceHash)) != 1 {
		return ports.GoogleIdentity{}, domain.ErrCredentials
	}
	identity := ports.GoogleIdentity{Subject: claims.Subject}
	name := strings.TrimSpace(claims.Name)
	if utf8.RuneCountInString(name) <= 120 && !strings.ContainsRune(name, 0) {
		identity.Nickname = name
	}
	if claims.EmailVerified {
		// Used only to reject accidental duplicate registrations, never to resolve an account.
		identity.VerifiedEmail, _ = domain.NormalizeEmail(claims.Email)
	}
	return identity, nil
}

func validGoogleSubject(subject string) bool {
	if len(subject) == 0 || len(subject) > 255 {
		return false
	}
	for _, ch := range []byte(subject) {
		if ch < 0x21 || ch > 0x7e {
			return false
		}
	}
	return true
}

func (g *Google) publicKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if key := g.keys[kid]; key != nil && time.Now().Before(g.cacheUntil) {
		return key, nil
	}
	// Limit fetches for unrecognized key IDs while still allowing Google's rotation.
	if time.Since(g.lastAttempt) < 30*time.Second {
		if g.refreshFailed || !time.Now().Before(g.cacheUntil) {
			return nil, domain.ErrUnavailable
		}
		return nil, domain.ErrCredentials
	}
	g.lastAttempt = time.Now()
	keys, ttl, err := g.fetchKeys(ctx)
	g.refreshFailed = err != nil
	if err != nil {
		return nil, err
	}
	g.keys, g.cacheUntil = keys, time.Now().Add(ttl)
	key, ok := keys[kid]
	if !ok {
		return nil, domain.ErrCredentials
	}
	return key, nil
}

func (g *Google) fetchKeys(ctx context.Context) (map[string]*rsa.PublicKey, time.Duration, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, googleJWKS, nil)
	if err != nil {
		return nil, 0, domain.ErrUnavailable
	}
	res, err := g.http.Do(req)
	if err != nil {
		return nil, 0, domain.ErrUnavailable
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, 0, domain.ErrUnavailable
	}
	var document struct {
		Keys []struct{ Kty, Alg, Use, Kid, N, E string }
	}
	if err = decodeBounded(res.Body, &document); err != nil || len(document.Keys) > 32 {
		return nil, 0, domain.ErrUnavailable
	}
	keys := make(map[string]*rsa.PublicKey)
	for _, jwk := range document.Keys {
		if jwk.Kty != "RSA" || jwk.Alg != "RS256" || jwk.Use != "sig" || jwk.Kid == "" || len(jwk.Kid) > 128 {
			continue
		}
		n, nErr := base64.RawURLEncoding.DecodeString(jwk.N)
		e, eErr := base64.RawURLEncoding.DecodeString(jwk.E)
		if nErr != nil || eErr != nil || len(n) < 256 || len(n) > 512 || len(e) == 0 || len(e) > 4 {
			continue
		}
		modulus, exponent := new(big.Int).SetBytes(n), new(big.Int).SetBytes(e).Int64()
		if modulus.BitLen() < 2048 || exponent < 3 || exponent > 2147483647 || exponent%2 == 0 {
			continue
		}
		if _, duplicate := keys[jwk.Kid]; duplicate {
			return nil, 0, domain.ErrUnavailable
		}
		keys[jwk.Kid] = &rsa.PublicKey{N: modulus, E: int(exponent)}
	}
	if len(keys) == 0 {
		return nil, 0, domain.ErrUnavailable
	}
	return keys, googleKeyTTL(res.Header), nil
}

func googleKeyTTL(headers http.Header) time.Duration {
	seconds := int64(300)
	for _, directive := range strings.Split(strings.ToLower(headers.Get("Cache-Control")), ",") {
		key, value, _ := strings.Cut(strings.TrimSpace(directive), "=")
		switch key {
		case "no-cache", "no-store":
			return 0
		case "max-age":
			if age, err := strconv.ParseInt(strings.Trim(value, `"`), 10, 64); err == nil && age >= 0 {
				seconds = min(age, 86_400)
			}
		}
	}
	if age, err := strconv.ParseInt(headers.Get("Age"), 10, 64); err == nil && age > 0 {
		seconds = max(0, seconds-age)
	}
	return time.Duration(seconds) * time.Second
}
