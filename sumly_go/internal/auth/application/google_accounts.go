package application

import (
	"context"
	"encoding/base64"
	"errors"
	"strconv"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

const googleLoginScope = "login:"

func googleLinkScope(ss domain.Session) string {
	return "link:" + ss.FamilyID + ":"
}

func googleReauthenticationScope(ss domain.Session) string {
	return "reauthenticate:" + strconv.FormatInt(ss.UserID, 10) + ":" + ss.FamilyID + ":"
}

func (a Accounts) GoogleChallenge(ctx context.Context, token, ip string) (domain.Challenge, error) {
	if !a.Capabilities().Google {
		return domain.Challenge{}, domain.ErrUnavailable
	}
	scope := googleLoginScope
	if token != "" {
		ss, err := a.linkSession(ctx, token, "email")
		if err != nil {
			return domain.Challenge{}, err
		}
		scope = googleLinkScope(ss)
	}
	return a.newGoogleChallenge(ctx, scope, ip)
}

func (a Accounts) newGoogleChallenge(ctx context.Context, scope, ip string) (domain.Challenge, error) {
	if err := a.googleQuota(ctx, "challenge", ip); err != nil {
		return domain.Challenge{}, err
	}
	ch := domain.Challenge{ID: a.Crypto.Random(), Nonce: a.Crypto.Random(), ExpiresIn: 300}
	return ch, a.Store.NewChallenge(ctx, a.Crypto.Digest("google-challenge", scope+ch.ID), a.Crypto.Digest("google-nonce", ch.Nonce), time.Now().Add(5*time.Minute))
}

func (a Accounts) GoogleReauthenticateChallenge(ctx context.Context, token, ip string) (domain.Challenge, error) {
	ss, err := a.googleReauthenticationSession(ctx, token)
	if err != nil {
		return domain.Challenge{}, err
	}
	return a.newGoogleChallenge(ctx, googleReauthenticationScope(ss), ip)
}

func (a Accounts) GoogleReauthenticate(ctx context.Context, token, id, identityToken, ip string) (domain.LoginResult, error) {
	ss, err := a.googleReauthenticationSession(ctx, token)
	if err != nil {
		return domain.LoginResult{}, err
	}
	identity, err := a.verifiedGoogle(ctx, googleReauthenticationScope(ss), id, identityToken, ip)
	if errors.Is(err, domain.ErrCredentials) {
		return domain.LoginResult{}, domain.ErrLinkProof
	}
	if err != nil {
		return domain.LoginResult{}, err
	}
	next, refreshToken := a.Sessions.New()
	user, err := a.Links.ReauthenticateGoogle(ctx, ss.ID, identity.Subject, next)
	if err != nil {
		return domain.LoginResult{}, err
	}
	return a.Sessions.Result(ctx, next, refreshToken, user)
}

func (a Accounts) googleReauthenticationSession(ctx context.Context, token string) (domain.Session, error) {
	if !a.Capabilities().Google {
		return domain.Session{}, domain.ErrUnavailable
	}
	ss, err := a.authenticatedSession(ctx, token)
	if err != nil {
		return domain.Session{}, err
	}
	return ss, ss.RequireProvider("google")
}

func (a Accounts) GoogleLogin(ctx context.Context, id, identityToken, ip string) (domain.LoginResult, error) {
	if !a.Capabilities().Google {
		return domain.LoginResult{}, domain.ErrUnavailable
	}
	identity, err := a.verifiedGoogle(ctx, googleLoginScope, id, identityToken, ip)
	if err != nil {
		return domain.LoginResult{}, err
	}
	return a.login(ctx, ports.LoginMutation{
		Provider: "google", Subject: identity.Subject, Nickname: identity.Nickname, GoogleVerifiedEmail: identity.VerifiedEmail,
	})
}

func (a Accounts) LinkGoogle(ctx context.Context, token, id, identityToken, ip string) error {
	if !a.Capabilities().Google {
		return domain.ErrUnavailable
	}
	ss, err := a.linkSession(ctx, token, "email")
	if err != nil {
		return err
	}
	identity, err := a.verifiedGoogle(ctx, googleLinkScope(ss), id, identityToken, ip)
	if errors.Is(err, domain.ErrCredentials) {
		return domain.ErrLinkProof
	}
	if err != nil {
		return err
	}
	return a.Links.LinkGoogle(ctx, ss.ID, identity.Subject)
}

func (a Accounts) verifiedGoogle(ctx context.Context, scope, id, token, ip string) (ports.GoogleIdentity, error) {
	if len(id) != 43 || len(token) == 0 || len(token) > 16384 {
		return ports.GoogleIdentity{}, domain.ErrInvalid
	}
	if _, err := base64.RawURLEncoding.Strict().DecodeString(id); err != nil {
		return ports.GoogleIdentity{}, domain.ErrInvalid
	}
	if err := a.googleQuota(ctx, "verify", ip); err != nil {
		return ports.GoogleIdentity{}, err
	}
	nonceHash, err := a.Store.ConsumeChallenge(ctx, a.Crypto.Digest("google-challenge", scope+id))
	if err != nil {
		return ports.GoogleIdentity{}, err
	}
	identity, err := a.Google.Verify(ctx, token, nonceHash)
	if err != nil {
		return ports.GoogleIdentity{}, err
	}
	if identity.Subject == "" {
		return ports.GoogleIdentity{}, domain.ErrCredentials
	}
	if err = a.Store.TakeQuota(ctx, []domain.Quota{
		{Key: "google:subject:" + a.Crypto.Digest("subject", identity.Subject), Limit: 20, Window: time.Hour},
	}); err != nil {
		return ports.GoogleIdentity{}, err
	}
	return identity, nil
}

func (a Accounts) googleQuota(ctx context.Context, action, ip string) error {
	return a.Store.TakeQuota(ctx, []domain.Quota{
		{Key: "google:" + action + ":ip:" + a.Crypto.Digest("ip", ip), Limit: 30, Window: time.Hour},
		{Key: "google:" + action + ":global", Limit: 2000, Window: time.Hour},
	})
}

func (a Accounts) SendLinkedEmailCode(ctx context.Context, token, email, ip string) error {
	ss, err := a.emailLinkSession(ctx, token)
	if err != nil {
		return err
	}
	email, err = domain.NormalizeEmail(email)
	if err != nil {
		return err
	}
	return a.Codes.send(ctx, a.Codes.Email, "email", email, "link", ip, domain.LinkedEmailCodeKey(ss.UserID, email))
}

func (a Accounts) LinkEmail(ctx context.Context, token, email, password, code, ip string) error {
	ss, err := a.emailLinkSession(ctx, token)
	if err != nil {
		return err
	}
	email, err = domain.NormalizeEmail(email)
	if err != nil {
		return err
	}
	if err = domain.ValidatePassword(password); err != nil {
		return err
	}
	if err = a.Store.TakeQuota(ctx, []domain.Quota{
		{Key: "email:link:attempt:ip:" + a.Crypto.Digest("ip", ip), Limit: 60, Window: time.Hour},
		{Key: "email:link:attempt:address:" + a.Crypto.Digest("subject", email), Limit: 20, Window: time.Hour},
	}); err != nil {
		return err
	}
	otpHash, err := a.Codes.CodeHash(domain.LinkedEmailCodeKey(ss.UserID, email), code)
	if err != nil {
		return domain.ErrLinkProof
	}
	passwordHash, err := a.Crypto.HashPassword(password)
	if err != nil {
		return err
	}
	return a.Links.LinkEmail(ctx, ss.ID, email, otpHash, passwordHash)
}

func (a Accounts) emailLinkSession(ctx context.Context, token string) (domain.Session, error) {
	caps := a.Capabilities()
	if !caps.Email || (!caps.Google && !caps.AppleEmailLink) {
		return domain.Session{}, domain.ErrUnavailable
	}
	ss, err := a.authenticatedSession(ctx, token)
	if err != nil {
		return domain.Session{}, err
	}
	switch ss.Provider {
	case "apple":
		if !caps.AppleEmailLink {
			return domain.Session{}, domain.ErrUnavailable
		}
	case "google":
		if !caps.Google {
			return domain.Session{}, domain.ErrUnavailable
		}
	default:
		return domain.Session{}, domain.ErrReauthenticate
	}
	return ss, ss.RequireRecentAuthentication(ss.Provider)
}

func (a Accounts) linkSession(ctx context.Context, token, provider string) (domain.Session, error) {
	ss, err := a.authenticatedSession(ctx, token)
	if err != nil {
		return domain.Session{}, err
	}
	return ss, ss.RequireRecentAuthentication(provider)
}

func (a Accounts) authenticatedSession(ctx context.Context, token string) (domain.Session, error) {
	id, err := a.Sessions.Tokens.ParseNative(ctx, token)
	if err != nil {
		return domain.Session{}, domain.ErrCredentials
	}
	ss, _, err := a.Store.Session(ctx, id)
	return ss, err
}
