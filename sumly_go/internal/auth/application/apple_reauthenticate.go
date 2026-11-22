package application

import (
	"context"
	"encoding/base64"
	"errors"
	"strconv"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

func (a Accounts) AppleReauthenticateChallenge(ctx context.Context, token, ip string) (domain.Challenge, error) {
	ss, err := a.appleReauthenticationSession(ctx, token)
	if err != nil {
		return domain.Challenge{}, err
	}
	if err = a.appleThrottle(ctx, "reauthenticate-challenge", ip); err != nil {
		return domain.Challenge{}, err
	}
	ch := domain.Challenge{ID: a.Crypto.Random(), Nonce: a.Crypto.Random(), ExpiresIn: 300}
	return ch, a.Store.NewChallenge(ctx, a.appleReauthenticationKey(ss, ch.ID), a.Crypto.Digest("apple-nonce", ch.Nonce), time.Now().Add(5*time.Minute))
}

func (a Accounts) AppleReauthenticate(ctx context.Context, token, challengeID, identityToken, code, ip string) (domain.LoginResult, error) {
	ss, err := a.appleReauthenticationSession(ctx, token)
	if err != nil {
		return domain.LoginResult{}, err
	}
	if len(challengeID) != 43 || len(identityToken) == 0 || len(identityToken) > 16384 || len(code) == 0 || len(code) > 4096 {
		return domain.LoginResult{}, domain.ErrInvalid
	}
	if _, err = base64.RawURLEncoding.Strict().DecodeString(challengeID); err != nil {
		return domain.LoginResult{}, domain.ErrInvalid
	}
	i, cipher, err := a.verifyAppleProof(ctx, "reauthenticate", a.appleReauthenticationKey(ss, challengeID), identityToken, code, ip)
	if errors.Is(err, domain.ErrCredentials) {
		return domain.LoginResult{}, domain.ErrLinkProof
	}
	if err != nil {
		return domain.LoginResult{}, err
	}
	next, refresh := a.Sessions.New()
	user, err := a.Links.ReauthenticateApple(ctx, ss.ID, i.Subject, i.IssuedAt, cipher, next)
	if err != nil {
		return domain.LoginResult{}, err
	}
	return a.Sessions.Result(ctx, next, refresh, user)
}

func (a Accounts) appleReauthenticationSession(ctx context.Context, token string) (domain.Session, error) {
	if !a.Capabilities().AppleEmailLink {
		return domain.Session{}, domain.ErrUnavailable
	}
	ss, err := a.authenticatedSession(ctx, token)
	if err != nil {
		return domain.Session{}, err
	}
	return ss, ss.RequireProvider("apple")
}

func (a Accounts) appleReauthenticationKey(ss domain.Session, id string) string {
	return "apple-reauthenticate:" + a.Crypto.Digest("apple-reauthenticate", strconv.FormatInt(ss.UserID, 10)+":"+ss.FamilyID+":"+id)
}
