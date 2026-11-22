package domain

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

func TestDefaultMembershipPaywallConfigIsFailClosed(t *testing.T) {
	cfg := DefaultMembershipPaywallConfig()
	if !cfg.ChanlunRequiresMembership {
		t.Fatal("expected chanlun_requires_membership default to be true")
	}
	if !cfg.MembershipEntryVisible {
		t.Fatal("expected membership_entry_visible default to be true")
	}
	if cfg.FreeAccessNotice != "" {
		t.Fatalf("expected empty free_access_notice, got %q", cfg.FreeAccessNotice)
	}
}

func TestValidateKey(t *testing.T) {
	valid := []string{"membership_paywall", "feature.v2-flag", "a", "0_test"}
	for _, key := range valid {
		got, err := ValidateKey(key)
		if err != nil || got != key {
			t.Fatalf("ValidateKey(%q) = (%q, %v), want (%q, nil)", key, got, err, key)
		}
	}

	invalid := []string{
		"",
		"   ",
		"Membership_Paywall",
		"_leading_underscore",
		"../etc/passwd",
		"a/b",
		"with space",
		"audit-logs",
		strings.Repeat("a", MaxConfigKeyLength+1),
	}
	for _, key := range invalid {
		if _, err := ValidateKey(key); !errors.Is(err, sharederror.ErrValidation) {
			t.Fatalf("ValidateKey(%q) expected validation error, got %v", key, err)
		}
	}
}

func TestValidateMembershipPaywall(t *testing.T) {
	t.Run("valid payload trims notice", func(t *testing.T) {
		raw := json.RawMessage(`{"chanlun_requires_membership": false, "membership_entry_visible": true, "free_access_notice": "  限时免费开放中  "}`)
		cfg, normalized, err := ValidateMembershipPaywall(raw)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if cfg.ChanlunRequiresMembership || !cfg.MembershipEntryVisible || cfg.FreeAccessNotice != "限时免费开放中" {
			t.Fatalf("unexpected cfg: %+v", cfg)
		}
		if !strings.Contains(string(normalized), `"free_access_notice":"限时免费开放中"`) {
			t.Fatalf("unexpected normalized json: %s", string(normalized))
		}
	})

	t.Run("exact 120 chinese runes allowed", func(t *testing.T) {
		notice := strings.Repeat("免", MaxFreeAccessNoticeRunes)
		raw := json.RawMessage(`{"chanlun_requires_membership": false, "membership_entry_visible": false, "free_access_notice": "  ` + notice + `  "}`)
		cfg, _, err := ValidateMembershipPaywall(raw)
		if err != nil {
			t.Fatalf("expected 120 runes to pass, got %v", err)
		}
		if cfg.FreeAccessNotice != notice {
			t.Fatalf("unexpected notice length: %d", len([]rune(cfg.FreeAccessNotice)))
		}
	})

	t.Run("121 chinese runes rejected", func(t *testing.T) {
		notice := strings.Repeat("免", MaxFreeAccessNoticeRunes+1)
		raw := json.RawMessage(`{"chanlun_requires_membership": false, "membership_entry_visible": false, "free_access_notice": "` + notice + `"}`)
		if _, _, err := ValidateMembershipPaywall(raw); !errors.Is(err, sharederror.ErrValidation) {
			t.Fatalf("expected validation error for >120 runes, got %v", err)
		}
	})

	cases := []struct {
		name string
		raw  string
	}{
		{name: "empty", raw: ""},
		{name: "null", raw: "null"},
		{name: "array", raw: "[]"},
		{name: "missing chanlun_requires_membership", raw: `{"membership_entry_visible": true}`},
		{name: "missing membership_entry_visible", raw: `{"chanlun_requires_membership": true}`},
		{name: "wrong type string for bool", raw: `{"chanlun_requires_membership": "true", "membership_entry_visible": true}`},
		{name: "wrong type number for notice", raw: `{"chanlun_requires_membership": true, "membership_entry_visible": true, "free_access_notice": 123}`},
		{name: "unknown field", raw: `{"chanlun_requires_membership": true, "membership_entry_visible": true, "extra": 1}`},
		{name: "trailing json", raw: `{"chanlun_requires_membership": true, "membership_entry_visible": true} {}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, _, err := ValidateMembershipPaywall(json.RawMessage(tc.raw)); !errors.Is(err, sharederror.ErrValidation) {
				t.Fatalf("expected validation error for %s, got %v", tc.name, err)
			}
		})
	}
}

func TestValidateConfigValueExtensionKeys(t *testing.T) {
	got, err := ValidateConfigValue("custom_banner", json.RawMessage(`{ "enabled": true, "title": "公告" }`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(got) != `{"enabled":true,"title":"公告"}` {
		t.Fatalf("unexpected compacted json: %s", string(got))
	}

	for _, invalid := range []string{
		"",
		"null",
		`["not","an","object"]`,
		`"string"`,
		`123`,
		`{broken`,
		`{"a":1}{"b":2}`,
	} {
		if _, err := ValidateConfigValue("custom_banner", json.RawMessage(invalid)); !errors.Is(err, sharederror.ErrValidation) {
			t.Fatalf("expected validation error for %q, got %v", invalid, err)
		}
	}

	oversized := `{"pad":"` + strings.Repeat("x", MaxConfigValueBytes) + `"}`
	if _, err := ValidateConfigValue("custom_banner", json.RawMessage(oversized)); !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected validation error for >16KB object, got %v", err)
	}
}

func TestDecodeMembershipPaywallOrDefault(t *testing.T) {
	// Missing fields remain safe true
	partial := DecodeMembershipPaywallOrDefault(json.RawMessage(`{"free_access_notice":"  hi  "}`))
	if !partial.ChanlunRequiresMembership || !partial.MembershipEntryVisible || partial.FreeAccessNotice != "hi" {
		t.Fatalf("expected safe defaults for missing booleans, got %+v", partial)
	}

	// Corrupted JSON falls back safely to paid default
	corrupt := DecodeMembershipPaywallOrDefault(json.RawMessage(`{corrupt`))
	if corrupt != DefaultMembershipPaywallConfig() {
		t.Fatalf("expected safe default for corrupt JSON, got %+v", corrupt)
	}
}
