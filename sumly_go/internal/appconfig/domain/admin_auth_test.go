package domain

import (
	"errors"
	"strings"
	"testing"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

func TestNormalizeAdminUsername(t *testing.T) {
	got, err := NormalizeAdminUsername("  admin  ")
	if err != nil || got != "admin" {
		t.Fatalf("NormalizeAdminUsername got (%q, %v), want (admin, nil)", got, err)
	}

	for _, invalid := range []string{"", "   ", strings.Repeat("a", MaxAdminUsernameRunes+1)} {
		if _, err := NormalizeAdminUsername(invalid); !errors.Is(err, sharederror.ErrValidation) {
			t.Fatalf("NormalizeAdminUsername(%q) expected validation error, got %v", invalid, err)
		}
	}
}

func TestValidateNewAdminPassword(t *testing.T) {
	// Valid cases including exact boundary 8 chars and exact 72 bytes
	if err := ValidateNewAdminPassword("OldPass123!", "NewPass1"); err != nil {
		t.Fatalf("expected 8-char password valid, got %v", err)
	}
	if err := ValidateNewAdminPassword("OldPass123!", strings.Repeat("p", 72)); err != nil {
		t.Fatalf("expected 72-byte password valid, got %v", err)
	}

	cases := []struct {
		name    string
		current string
		next    string
	}{
		{name: "empty", current: "OldPass123!", next: ""},
		{name: "too short ascii", current: "OldPass123!", next: "1234567"},
		{name: "too short multibyte runes", current: "OldPass123!", next: "密码一"},
		{name: "exceeds 72 bytes ascii", current: "OldPass123!", next: strings.Repeat("x", 73)},
		{name: "exceeds 72 bytes multibyte", current: "OldPass123!", next: strings.Repeat("密", 25)},
		{name: "same as current", current: "SamePass123!", next: "SamePass123!"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := ValidateNewAdminPassword(tc.current, tc.next); !errors.Is(err, sharederror.ErrValidation) {
				t.Fatalf("expected validation error, got %v", err)
			}
		})
	}
}
