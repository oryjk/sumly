package domain

import (
	"errors"
	"net/mail"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	ErrInvalid              = errors.New("invalid request")
	ErrCredentials          = errors.New("invalid credentials")
	ErrUnavailable          = errors.New("authentication provider unavailable")
	ErrLimited              = errors.New("too many attempts; retry later")
	ErrConflict             = errors.New("registration unavailable")
	ErrAccountMismatch      = errors.New("Google identity does not belong to the authenticated account")
	ErrAppleAccountMismatch = errors.New("Apple identity does not belong to the authenticated account")
	ErrReauthenticate       = errors.New("reauthentication required")
	ErrLinkProof            = errors.New("invalid or expired verification proof")
)
var mobile = regexp.MustCompile(`^1[3-9][0-9]{9}$`)

func NormalizePhone(s string) (string, error) {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "+86")
	if !mobile.MatchString(s) {
		return "", ErrInvalid
	}
	return "+86" + s, nil
}
func NormalizeEmail(s string) (string, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	a, e := mail.ParseAddress(s)
	if e != nil || a.Address != s || len(s) > 254 || !strings.Contains(s, ".") || strings.ContainsAny(s, "\r\n") {
		return "", ErrInvalid
	}
	return s, nil
}
func ValidatePassword(s string) error {
	n := utf8.RuneCountInString(s)
	if !utf8.ValidString(s) || n < 12 || n > 128 || len(s) > 512 {
		return ErrInvalid
	}
	return nil
}

type User struct {
	ID          int64   `json:"id"`
	Nickname    string  `json:"nickname"`
	AvatarURL   string  `json:"avatar_url"`
	Email       *string `json:"email"`
	PhoneNumber *string `json:"phone_number"`
	Status      string  `json:"status"`
	Provider    string  `json:"provider"`
}
type Identity struct {
	User                  User
	Subject, PasswordHash string
	AppleRefresh          []byte
}
type Session struct {
	ID                         string
	FamilyID                   string
	UserID                     int64
	Provider                   string
	RefreshHash                string
	AuthenticatedAt, ExpiresAt time.Time
}

func (s Session) RequireProvider(provider string) error {
	if s.UserID <= 0 || s.FamilyID == "" {
		return ErrCredentials
	}
	if s.Provider != provider {
		return ErrReauthenticate
	}
	return nil
}

func (s Session) RequireRecentAuthentication(provider string) error {
	if err := s.RequireProvider(provider); err != nil {
		return err
	}
	if time.Since(s.AuthenticatedAt) > 5*time.Minute {
		return ErrReauthenticate
	}
	return nil
}

// LinkedEmailCodeKey separates account-bound verification from registration and reset codes.
func LinkedEmailCodeKey(userID int64, email string) string {
	return "email:link:" + strconv.FormatInt(userID, 10) + ":" + email
}

type LoginResult struct {
	Token        string `json:"token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	User         User   `json:"user"`
}
type Capabilities struct {
	Apple          bool   `json:"apple"`
	Wechat         bool   `json:"wechat"`
	Phone          bool   `json:"phone"`
	Email          bool   `json:"email"`
	Google         bool   `json:"google,omitempty"`
	GoogleClientID string `json:"google_client_id,omitempty"`
	AppleEmailLink bool   `json:"apple_email_link,omitempty"`
}
type Challenge struct {
	ID        string `json:"challenge_id"`
	Nonce     string `json:"nonce"`
	ExpiresIn int    `json:"expires_in"`
}
type AppleNotification struct {
	ID        string    `json:"-"`
	Type      string    `json:"type"`
	Subject   string    `json:"sub"`
	EventTime int64     `json:"event_time"`
	IssuedAt  time.Time `json:"-"`
}
type Quota struct {
	Key    string
	Limit  int
	Window time.Duration
}
