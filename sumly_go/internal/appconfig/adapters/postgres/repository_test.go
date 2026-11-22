package postgres

import (
	"context"
	"encoding/json"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

func TestRepositorySeedAndUpsertWithAudit(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	seeded, found, err := repo.GetByKey(ctx, domain.KeyMembershipPaywall)
	if err != nil || !found {
		t.Fatalf("expected seeded membership_paywall row, found=%v err=%v", found, err)
	}
	cfg := domain.DecodeMembershipPaywallOrDefault(seeded.ValueJSON)
	if !cfg.ChanlunRequiresMembership || !cfg.MembershipEntryVisible || cfg.FreeAccessNotice != "" {
		t.Fatalf("unexpected seeded membership_paywall: %+v", cfg)
	}

	updated, err := repo.UpsertWithAudit(ctx, ports.UpsertParams{
		Key:       domain.KeyMembershipPaywall,
		ValueJSON: json.RawMessage(`{"chanlun_requires_membership":false,"membership_entry_visible":true,"free_access_notice":"限时免费"}`),
		Operator:  "admin",
		Note:      "切换为限时免费",
	})
	if err != nil {
		t.Fatalf("UpsertWithAudit update failed: %v", err)
	}
	if updated.Description != seeded.Description {
		t.Fatalf("expected preserved description %q, got %q", seeded.Description, updated.Description)
	}

	extDesc := "扩展开关"
	if _, err := repo.UpsertWithAudit(ctx, ports.UpsertParams{
		Key:         "home_banner",
		ValueJSON:   json.RawMessage(`{"enabled":true}`),
		Description: &extDesc,
		Operator:    "admin",
		Note:        "新增扩展配置",
	}); err != nil {
		t.Fatalf("UpsertWithAudit insert failed: %v", err)
	}

	all, err := repo.ListAll(ctx)
	if err != nil {
		t.Fatalf("ListAll failed: %v", err)
	}
	if len(all) < 2 {
		t.Fatalf("expected at least 2 configs, got %d", len(all))
	}

	logs, err := repo.ListAuditLogs(ctx, 10)
	if err != nil {
		t.Fatalf("ListAuditLogs failed: %v", err)
	}
	if len(logs) != 2 {
		t.Fatalf("expected 2 audit logs, got %d", len(logs))
	}
	if logs[0].ConfigKey != "home_banner" || logs[0].OldValueJSON != nil {
		t.Fatalf("unexpected newest audit log: %+v", logs[0])
	}
	if logs[1].ConfigKey != domain.KeyMembershipPaywall || len(logs[1].OldValueJSON) == 0 {
		t.Fatalf("unexpected previous audit log: %+v", logs[1])
	}
}
