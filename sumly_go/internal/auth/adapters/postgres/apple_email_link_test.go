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
	holdingpostgres "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/postgres"
	holdingdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

type appleEmailLinkGateway struct {
	crypto      ports.Cryptography
	revoked     string
	revokeError error
}

func (*appleEmailLinkGateway) Enabled() bool { return true }

func (g *appleEmailLinkGateway) Verify(_ context.Context, token, code, nonceHash string) (ports.AppleIdentity, error) {
	subject, nonce, ok := strings.Cut(token, " ")
	if !ok || code != "issued-code" || g.crypto.Digest("apple-nonce", nonce) != nonceHash {
		return ports.AppleIdentity{}, domain.ErrCredentials
	}
	return ports.AppleIdentity{Subject: subject, RefreshToken: "refresh-" + subject, IssuedAt: time.Now()}, nil
}

func (g *appleEmailLinkGateway) Revoke(_ context.Context, token string) error {
	g.revoked = token
	return g.revokeError
}

func (*appleEmailLinkGateway) VerifyNotification(context.Context, string) (domain.AppleNotification, error) {
	return domain.AppleNotification{}, domain.ErrCredentials
}

func TestAppleEmailLinkRetainsUserHoldingsAndProviderContracts(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	store := postgres.NewNativeStore(pool)
	crypto, err := credentials.New(strings.Repeat("c", 32))
	if err != nil {
		t.Fatal(err)
	}
	tokens, err := nativejwt.NewService(strings.Repeat("t", 32), time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	apple := &appleEmailLinkGateway{crypto: crypto}
	delivery := &fakeDelivery{}
	sessions := application.Sessions{Store: store, Crypto: crypto, Tokens: tokens, Apple: apple}
	accounts := application.Accounts{
		Store: store, Crypto: crypto, Sessions: sessions, Links: store, Apple: apple,
		Codes: application.Codes{Store: store, Crypto: crypto, Email: delivery},
	}
	ctx := context.Background()
	const ip = "127.0.0.1"
	const verifiedEmail = "linked@example.test"
	const occupiedEmail = "occupied@example.test"
	const password = "verified-password-long"

	check := func(operation string, got, want error) {
		t.Helper()
		if !errors.Is(got, want) {
			t.Fatalf("%s: got %v, want %v", operation, got, want)
		}
	}
	appleLogin := func(subject string) domain.LoginResult {
		t.Helper()
		challenge, err := accounts.Challenge(ctx, ip)
		check("Apple login challenge", err, nil)
		result, err := accounts.AppleLogin(ctx, challenge.ID, subject+" "+challenge.Nonce, "issued-code", "", ip)
		check("original Apple login", err, nil)
		return result
	}
	original := appleLogin("long-time-apple-user")
	otherApple := appleLogin("different-apple-user")
	if original.User.Email != nil || original.User.Provider != "apple" || accounts.Capabilities().AppleEmailLink {
		t.Fatal("Apple-only account or disabled capability changed")
	}
	check("link disabled by default", accounts.SendLinkedEmailCode(ctx, original.Token, verifiedEmail, ip), domain.ErrUnavailable)

	repo := holdingpostgres.NewRepository(pool)
	document := holdingdomain.EmptyDocument()
	document.Books = append(document.Books, "existing-iOS-holdings")
	_, err = repo.Put(ctx, original.User.ID, 0, document)
	check("seed Apple-account holdings", err, nil)

	accounts.AppleEmailLinkEnabled = true
	if caps := accounts.Capabilities(); !caps.AppleEmailLink || caps.Google {
		t.Fatal("Apple email linking must work without Google")
	}
	disabledSMTP := accounts
	disabledSMTP.Codes.Email = nil
	if disabledSMTP.Capabilities().AppleEmailLink {
		t.Fatal("link capability exposed without email delivery")
	}
	check("link cannot send without SMTP", disabledSMTP.SendLinkedEmailCode(ctx, original.Token, verifiedEmail, ip), domain.ErrUnavailable)

	sessionID, err := tokens.ParseNative(ctx, original.Token)
	check("read original JWT", err, nil)
	_, err = pool.Exec(ctx, "UPDATE auth_sessions SET authenticated_at = now() - interval '10 minutes' WHERE id=$1", sessionID)
	check("age original session", err, nil)
	original, err = sessions.Refresh(ctx, original.RefreshToken)
	check("refresh without new Apple verification", err, nil)
	check("refreshed old session cannot send", accounts.SendLinkedEmailCode(ctx, original.Token, verifiedEmail, ip), domain.ErrReauthenticate)
	check("stale bearer cannot confirm link", accounts.LinkEmail(ctx, original.Token, verifiedEmail, password, "000000", ip), domain.ErrReauthenticate)

	bound, err := accounts.AppleReauthenticateChallenge(ctx, original.Token, ip)
	check("obtain same-account reauth challenge", err, nil)
	_, err = accounts.AppleLogin(ctx, bound.ID, "long-time-apple-user "+bound.Nonce, "issued-code", "", ip)
	check("bound challenge cannot be spent through login", err, domain.ErrCredentials)
	_, err = accounts.AppleReauthenticate(ctx, otherApple.Token, bound.ID, "different-apple-user "+bound.Nonce, "issued-code", ip)
	check("bound challenge cannot be used by another user", err, domain.ErrLinkProof)
	_, err = accounts.AppleReauthenticate(ctx, original.Token, bound.ID, "unknown-apple-id "+bound.Nonce, "issued-code", ip)
	check("unknown Apple subject is rejected", err, domain.ErrAppleAccountMismatch)
	_, err = store.FindIdentity(ctx, "apple", "unknown-apple-id")
	check("unrelated Apple identity was never created", err, domain.ErrCredentials)
	_, err = accounts.AppleReauthenticate(ctx, original.Token, bound.ID, "long-time-apple-user "+bound.Nonce, "issued-code", ip)
	check("reauthentication proof cannot be replayed", err, domain.ErrLinkProof)

	bound, err = accounts.AppleReauthenticateChallenge(ctx, original.Token, ip)
	check("obtain a new reauth challenge", err, nil)
	fresh, err := accounts.AppleReauthenticate(ctx, original.Token, bound.ID, "long-time-apple-user "+bound.Nonce, "issued-code", ip)
	check("refresh primary Apple authentication for same user", err, nil)
	if fresh.User.ID != original.User.ID || fresh.User.Provider != "apple" {
		t.Fatal("reauthentication changed account identity")
	}
	check("retire replaced refresh family", sessions.Logout(ctx, original.RefreshToken), nil)
	_, err = sessions.Me(ctx, fresh.Token)
	check("retiring old family kept new bearer active", err, nil)

	check("email verification delivery", accounts.SendLinkedEmailCode(ctx, fresh.Token, " Linked@EXAMPLE.test ", ip), nil)
	proof := delivery.code
	check("another Apple account cannot spend proof", accounts.LinkEmail(ctx, otherApple.Token, verifiedEmail, password, proof, ip), domain.ErrLinkProof)
	_, err = accounts.Register(ctx, verifiedEmail, password, proof, ip)
	check("link proof cannot register a separate account", err, domain.ErrCredentials)
	check("verified email link", accounts.LinkEmail(ctx, fresh.Token, verifiedEmail, password, proof, ip), nil)
	check("link proof cannot be replayed", accounts.LinkEmail(ctx, fresh.Token, verifiedEmail, password, proof, ip), domain.ErrLinkProof)
	me, err := sessions.Me(ctx, fresh.Token)
	check("check Apple account's linked email", err, nil)
	if me.ID != original.User.ID || me.Provider != "apple" || me.Email == nil || *me.Email != verifiedEmail {
		t.Fatal("Apple session's profile did not report verified linked email")
	}
	appleResult := appleLogin("long-time-apple-user")
	if appleResult.User.ID != original.User.ID || appleResult.User.Email == nil || *appleResult.User.Email != verifiedEmail {
		t.Fatal("returning Apple login did not report the existing linked user")
	}
	appleResult, err = sessions.Refresh(ctx, appleResult.RefreshToken)
	check("refresh linked Apple", err, nil)
	if appleResult.User.Email == nil || *appleResult.User.Email != verifiedEmail {
		t.Fatal("refreshed Apple session lost linked email")
	}
	emailResult, err := accounts.EmailLogin(ctx, verifiedEmail, password, ip)
	check("linked email login", err, nil)
	if emailResult.User.ID != original.User.ID || emailResult.User.Provider != "email" {
		t.Fatal("email credential did not sign in as same account")
	}
	snapshot, err := repo.Get(ctx, emailResult.User.ID)
	check("existing holdings via email credential", err, nil)
	if snapshot.Revision != 1 || !strings.Contains(strings.Join(snapshot.Document.Books, "|"), "existing-iOS-holdings") {
		t.Fatal("email session has not inherited the original Apple account's holdings")
	}

	check("existing different email verification", accounts.Codes.Send(ctx, "email", occupiedEmail, "register", ip), nil)
	occupied, err := accounts.Register(ctx, occupiedEmail, password, delivery.code, ip)
	check("create separately owned email", err, nil)
	key := domain.LinkedEmailCodeKey(otherApple.User.ID, occupiedEmail)
	hash, err := accounts.Codes.CodeHash(key, "123456")
	check("prepare separate link proof", err, nil)
	check("persist link proof", store.PutCode(ctx, key, hash, time.Now().Add(time.Minute)), nil)
	check("activate link proof", store.ActivateCode(ctx, key, hash), nil)
	check("verified receipt cannot auto-merge existing account", accounts.LinkEmail(ctx, otherApple.Token, occupiedEmail, password, "123456", ip), domain.ErrConflict)
	occupiedIdentity, err := store.FindIdentity(ctx, "email", occupiedEmail)
	check("other account survived collision", err, nil)
	if occupiedIdentity.User.ID != occupied.User.ID || occupiedIdentity.User.ID == otherApple.User.ID {
		t.Fatal("occupied credential moved to Apple account")
	}

	apple.revokeError = domain.ErrUnavailable
	check("account deletion cannot skip a failed Apple revocation", sessions.Delete(ctx, emailResult.Token, "DELETE"), domain.ErrUnavailable)
	_, err = repo.Get(ctx, original.User.ID)
	check("failed revocation preserves original account holdings", err, nil)
	apple.revokeError = nil
	check("deletion through linked email revokes Apple and deletes original account", sessions.Delete(ctx, emailResult.Token, "DELETE"), nil)
	if apple.revoked != "refresh-long-time-apple-user" {
		t.Fatal("account deletion through email failed to revoke the linked Apple grant")
	}
	_, err = store.FindIdentity(ctx, "apple", "long-time-apple-user")
	check("Apple credential deleted by account deletion", err, domain.ErrCredentials)
	_, err = store.FindIdentity(ctx, "email", verifiedEmail)
	check("email credential deleted by account deletion", err, domain.ErrCredentials)

	const revokedEmail = "consent-revoked@example.test"
	check("send another Apple link proof", accounts.SendLinkedEmailCode(ctx, otherApple.Token, revokedEmail, ip), nil)
	check("link another Apple account", accounts.LinkEmail(ctx, otherApple.Token, revokedEmail, password, delivery.code, ip), nil)
	emailBeforeRevoke, err := accounts.EmailLogin(ctx, revokedEmail, password, ip)
	check("sign in before Apple revocation", err, nil)
	check("apply Apple consent revocation", store.ApplyAppleEvent(ctx, domain.AppleNotification{
		ID: "consent-revoke-for-link-test", Type: "consent-revoked", Subject: "different-apple-user", IssuedAt: time.Now().Add(time.Second),
	}), nil)
	_, err = sessions.Me(ctx, emailBeforeRevoke.Token)
	check("preserve whole-account session revocation", err, domain.ErrCredentials)
	emailAfterRevoke, err := accounts.EmailLogin(ctx, revokedEmail, password, ip)
	check("verified email remains a valid login after Apple consent revoked", err, nil)
	apple.revoked = ""
	apple.revokeError = domain.ErrUnavailable
	check("delete via email when Apple consent already revoked", sessions.Delete(ctx, emailAfterRevoke.Token, "DELETE"), nil)
	if apple.revoked != "" {
		t.Fatal("deletion tried to revoke a previously cleared Apple credential")
	}
}
