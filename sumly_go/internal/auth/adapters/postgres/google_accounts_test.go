package postgres_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	nativejwt "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

type testGoogleIDTokens struct {
	crypto     ports.Cryptography
	identities map[string]ports.GoogleIdentity
}

func (testGoogleIDTokens) ClientID() string { return "test.apps.googleusercontent.com" }

func (g testGoogleIDTokens) Verify(_ context.Context, raw, nonceHash string) (ports.GoogleIdentity, error) {
	sub, nonce, ok := strings.Cut(raw, " ")
	if !ok || nonceHash != g.crypto.Digest("google-nonce", nonce) {
		return ports.GoogleIdentity{}, domain.ErrCredentials
	}
	identity, ok := g.identities[sub]
	if !ok {
		return ports.GoogleIdentity{}, domain.ErrCredentials
	}
	return identity, nil
}

func TestGoogleAndEmailUseTheSameNativeAccount(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	store := postgres.NewNativeStore(pool)
	ctx := context.Background()
	crypto, err := credentials.New(strings.Repeat("a", 32))
	if err != nil {
		t.Fatal(err)
	}
	tokens, err := nativejwt.NewService(strings.Repeat("b", 32), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	delivery := &fakeDelivery{}
	sessions := application.Sessions{Store: store, Crypto: crypto, Tokens: tokens}
	accounts := application.Accounts{
		Store: store, Crypto: crypto, Sessions: sessions, Links: store,
		Codes: application.Codes{Store: store, Crypto: crypto, Email: delivery},
		Google: testGoogleIDTokens{crypto: crypto, identities: map[string]ports.GoogleIdentity{
			"same-address": {Subject: "same-address", VerifiedEmail: "ios@example.com"},
			"new":          {Subject: "new", VerifiedEmail: "new@example.com"},
			"other":        {Subject: "other"},
			"unregistered": {Subject: "unregistered"},
		}},
	}
	const (
		ip       = "127.0.0.1"
		password = "long-valid-password"
	)
	register := func(email string) domain.LoginResult {
		t.Helper()
		if err := accounts.Codes.Send(ctx, "email", email, "register", ip); err != nil {
			t.Fatal(err)
		}
		result, err := accounts.Register(ctx, email, password, delivery.code, ip)
		if err != nil {
			t.Fatal(err)
		}
		return result
	}
	challenge := func(accessToken string) domain.Challenge {
		t.Helper()
		challenge, err := accounts.GoogleChallenge(ctx, accessToken, ip)
		if err != nil {
			t.Fatal(err)
		}
		return challenge
	}
	requireError := func(operation string, got, want error) {
		t.Helper()
		if !errors.Is(got, want) {
			t.Fatalf("%s: got %v, want %v", operation, got, want)
		}
	}

	ios := register("ios@example.com")
	anotherEmail := register("another@example.com")
	anon := challenge("")
	// Historical Apple challenges store the public challenge ID directly. Google IDs
	// cannot be consumed by choosing arbitrary Apple challenge IDs.
	_, err = store.ConsumeChallenge(ctx, anon.ID)
	requireError("Google challenge address is private to Google", err, domain.ErrCredentials)
	_, err = accounts.GoogleLogin(ctx, anon.ID, "same-address "+anon.Nonce, ip)
	requireError("email collision", err, domain.ErrConflict)
	_, err = accounts.GoogleLogin(ctx, anon.ID, "same-address "+anon.Nonce, ip)
	requireError("replayed challenge", err, domain.ErrCredentials)
	_, err = store.FindIdentity(ctx, "google", "same-address")
	requireError("collision created an identity", err, domain.ErrCredentials)

	binding := challenge(ios.Token)
	_, err = accounts.GoogleLogin(ctx, binding.ID, "same-address "+binding.Nonce, ip)
	requireError("link challenge used for login", err, domain.ErrCredentials)
	err = accounts.LinkGoogle(ctx, anotherEmail.Token, binding.ID, "same-address "+binding.Nonce, ip)
	requireError("cross-session challenge", err, domain.ErrLinkProof)
	refreshed, err := sessions.Refresh(ctx, ios.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	err = accounts.LinkGoogle(ctx, ios.Token, binding.ID, "same-address "+binding.Nonce, ip)
	requireError("rotated bearer", err, domain.ErrCredentials)
	err = accounts.LinkGoogle(ctx, refreshed.Token, binding.ID, "same-address "+binding.Nonce, ip)
	requireError("same-family link after refresh", err, nil)
	anon = challenge("")
	android, err := accounts.GoogleLogin(ctx, anon.ID, "same-address "+anon.Nonce, ip)
	if err != nil || android.User.Provider != "google" || android.User.ID != ios.User.ID || android.User.Email == nil || *android.User.Email != "ios@example.com" {
		t.Fatalf("Android Google login: %v, got user %d, want %d", err, android.User.ID, ios.User.ID)
	}
	binding = challenge(anotherEmail.Token)
	err = accounts.LinkGoogle(ctx, anotherEmail.Token, binding.ID, "same-address "+binding.Nonce, ip)
	requireError("claim a Google identity owned by another account", err, domain.ErrConflict)
	binding = challenge(refreshed.Token)
	err = accounts.LinkGoogle(ctx, refreshed.Token, binding.ID, "other "+binding.Nonce, ip)
	requireError("replace the account's existing Google identity", err, domain.ErrConflict)

	anon = challenge("")
	newGoogle, err := accounts.GoogleLogin(ctx, anon.ID, "new "+anon.Nonce, ip)
	if err != nil || newGoogle.User.Email != nil {
		t.Fatalf("verified Google profile email is not a linked login: %v", err)
	}
	err = accounts.SendLinkedEmailCode(ctx, refreshed.Token, "mobile@example.com", ip)
	requireError("Google-only email-link action", err, domain.ErrReauthenticate)
	err = accounts.SendLinkedEmailCode(ctx, newGoogle.Token, " MOBILE@example.com ", ip)
	requireError("send email link verification", err, nil)
	code := delivery.code
	err = accounts.LinkEmail(ctx, android.Token, "mobile@example.com", password, code, ip)
	requireError("another account's email OTP", err, domain.ErrLinkProof)
	_, err = accounts.Register(ctx, "mobile@example.com", password, code, ip)
	requireError("link code used to register separately", err, domain.ErrCredentials)
	err = accounts.LinkEmail(ctx, newGoogle.Token, "mobile@example.com", password, code, ip)
	requireError("link email to the Google account", err, nil)
	googleMe, err := sessions.Me(ctx, newGoogle.Token)
	if err != nil || googleMe.Email == nil || *googleMe.Email != "mobile@example.com" {
		t.Fatalf("Google /me omitted linked email: %v", err)
	}
	newGoogle, err = sessions.Refresh(ctx, newGoogle.RefreshToken)
	if err != nil || newGoogle.User.Email == nil || *newGoogle.User.Email != "mobile@example.com" {
		t.Fatalf("Google refresh omitted linked email: %v", err)
	}
	err = accounts.LinkEmail(ctx, newGoogle.Token, "mobile@example.com", password, code, ip)
	requireError("replayed email OTP", err, domain.ErrLinkProof)
	iosFromGoogle, err := accounts.EmailLogin(ctx, "mobile@example.com", password, ip)
	if err != nil || iosFromGoogle.User.Provider != "email" || iosFromGoogle.User.ID != newGoogle.User.ID {
		t.Fatalf("iOS email login: %v, got user %d, want %d", err, iosFromGoogle.User.ID, newGoogle.User.ID)
	}

	// A proof issued for a registered mailbox still cannot claim its existing account.
	key := domain.LinkedEmailCodeKey(newGoogle.User.ID, "another@example.com")
	if err := store.PutCode(ctx, key, "hash", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err := store.ActivateCode(ctx, key, "hash"); err != nil {
		t.Fatal(err)
	}
	sessionID, err := tokens.ParseNative(ctx, newGoogle.Token)
	if err != nil {
		t.Fatal(err)
	}
	err = store.LinkEmail(ctx, sessionID, "another@example.com", "hash", "new-hash")
	requireError("claim already registered email", err, domain.ErrConflict)

	key = domain.LinkedEmailCodeKey(newGoogle.User.ID, "attempts@example.com")
	if err := store.PutCode(ctx, key, "hash", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err := store.ActivateCode(ctx, key, "hash"); err != nil {
		t.Fatal(err)
	}
	for range 5 {
		err = store.LinkEmail(ctx, sessionID, "attempts@example.com", "wrong", "new-hash")
		requireError("incorrect link code", err, domain.ErrLinkProof)
	}
	err = store.LinkEmail(ctx, sessionID, "attempts@example.com", "hash", "new-hash")
	requireError("link code guesses commit and enforce attempt limit", err, domain.ErrLinkProof)

	if _, err := pool.Exec(ctx, "UPDATE auth_sessions SET authenticated_at=$1 WHERE id=$2", time.Now().Add(-6*time.Minute), sessionID); err != nil {
		t.Fatal(err)
	}
	err = accounts.SendLinkedEmailCode(ctx, newGoogle.Token, "unused@example.com", ip)
	requireError("stale Google authentication", err, domain.ErrReauthenticate)
	err = store.LinkEmail(ctx, sessionID, "unused@example.com", "hash", "new-hash")
	requireError("stale Google authentication in database", err, domain.ErrReauthenticate)

	_, err = accounts.GoogleReauthenticateChallenge(ctx, refreshed.Token, ip)
	requireError("email bearer cannot start Google reauthentication", err, domain.ErrReauthenticate)
	reauthChallenge, err := accounts.GoogleReauthenticateChallenge(ctx, newGoogle.Token, ip)
	requireError("an active Google session can reauthenticate after five minutes", err, nil)
	_, err = accounts.GoogleReauthenticate(ctx, newGoogle.Token, reauthChallenge.ID, "unregistered "+reauthChallenge.Nonce, ip)
	requireError("selecting an unfamiliar Google account fails", err, domain.ErrAccountMismatch)
	_, err = store.FindIdentity(ctx, "google", "unregistered")
	requireError("reauthentication never creates an account", err, domain.ErrCredentials)
	_, err = accounts.GoogleReauthenticate(ctx, newGoogle.Token, reauthChallenge.ID, "new "+reauthChallenge.Nonce, ip)
	requireError("a reauthentication challenge is single-use even on mismatch", err, domain.ErrLinkProof)
	reauthChallenge, err = accounts.GoogleReauthenticateChallenge(ctx, newGoogle.Token, ip)
	requireError("create another Google reauthentication challenge", err, nil)
	_, err = accounts.GoogleLogin(ctx, reauthChallenge.ID, "new "+reauthChallenge.Nonce, ip)
	requireError("reauth challenge is unusable for Google sign-in", err, domain.ErrCredentials)
	_, err = accounts.GoogleReauthenticate(ctx, android.Token, reauthChallenge.ID, "new "+reauthChallenge.Nonce, ip)
	requireError("a reauthentication challenge stays in its session family", err, domain.ErrLinkProof)
	previous, err := sessions.Refresh(ctx, newGoogle.RefreshToken)
	requireError("rotate the starting Google session", err, nil)
	_, err = accounts.GoogleReauthenticate(ctx, newGoogle.Token, reauthChallenge.ID, "new "+reauthChallenge.Nonce, ip)
	requireError("Google reauthentication refuses rotated bearer", err, domain.ErrCredentials)
	reauthenticated, err := accounts.GoogleReauthenticate(ctx, previous.Token, reauthChallenge.ID, "new "+reauthChallenge.Nonce, ip)
	requireError("Google reauthentication survives same-family refresh", err, nil)
	if reauthenticated.User.ID != newGoogle.User.ID || reauthenticated.User.Provider != "google" ||
		reauthenticated.User.Email == nil || *reauthenticated.User.Email != "mobile@example.com" {
		t.Fatalf("verification changed the account: %+v", reauthenticated.User)
	}
	err = sessions.Logout(ctx, previous.RefreshToken)
	requireError("revoke old family after replacing session", err, nil)
	_, err = sessions.Me(ctx, reauthenticated.Token)
	requireError("revoking the old family cannot revoke the new one", err, nil)
	err = accounts.SendLinkedEmailCode(ctx, reauthenticated.Token, "new-candidate@example.com", ip)
	requireError("reauthenticated session can add credentials", err, nil)

	concurrent := register("concurrent@example.com")
	otherBinding := challenge(anotherEmail.Token)
	concurrentBinding := challenge(concurrent.Token)
	results := make(chan error, 2)
	go func() {
		results <- accounts.LinkGoogle(ctx, anotherEmail.Token, otherBinding.ID, "other "+otherBinding.Nonce, ip)
	}()
	go func() {
		results <- accounts.LinkGoogle(ctx, concurrent.Token, concurrentBinding.ID, "other "+concurrentBinding.Nonce, ip)
	}()
	first, second := <-results, <-results
	if first != nil && second != nil || first == nil && second == nil {
		t.Fatalf("exactly one Google link must win: %v, %v", first, second)
	}
	if first != nil {
		requireError("competing Google claim", first, domain.ErrConflict)
	} else {
		requireError("competing Google claim", second, domain.ErrConflict)
	}
}
