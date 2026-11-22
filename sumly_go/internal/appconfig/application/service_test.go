package application

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type memoryRepo struct {
	entries map[string]domain.ConfigEntry
	logs    []domain.AuditLog
	nextID  int64
	now     time.Time

	lastAuditLimit int
}

func newMemoryRepo(now time.Time) *memoryRepo {
	return &memoryRepo{
		entries: map[string]domain.ConfigEntry{},
		now:     now,
	}
}

func (r *memoryRepo) GetByKey(_ context.Context, key string) (domain.ConfigEntry, bool, error) {
	entry, ok := r.entries[key]
	return entry, ok, nil
}

func (r *memoryRepo) ListAll(_ context.Context) ([]domain.ConfigEntry, error) {
	out := make([]domain.ConfigEntry, 0, len(r.entries))
	for _, entry := range r.entries {
		out = append(out, entry)
	}
	return out, nil
}

func (r *memoryRepo) UpsertWithAudit(_ context.Context, params ports.UpsertParams) (domain.ConfigEntry, error) {
	oldEntry, exists := r.entries[params.Key]
	var oldVal json.RawMessage
	desc := ""
	if exists {
		oldVal = append(json.RawMessage(nil), oldEntry.ValueJSON...)
		desc = oldEntry.Description
	}
	if params.Description != nil {
		desc = *params.Description
	}
	updated := domain.ConfigEntry{
		Key:         params.Key,
		ValueJSON:   append(json.RawMessage(nil), params.ValueJSON...),
		Description: desc,
		UpdatedBy:   params.Operator,
		UpdatedAt:   r.now,
	}
	r.entries[params.Key] = updated

	r.nextID++
	r.logs = append([]domain.AuditLog{{
		ID:           r.nextID,
		ConfigKey:    params.Key,
		OldValueJSON: oldVal,
		NewValueJSON: append(json.RawMessage(nil), params.ValueJSON...),
		Operator:     params.Operator,
		Note:         params.Note,
		CreatedAt:    r.now,
	}}, r.logs...)
	return updated, nil
}

func (r *memoryRepo) ListAuditLogs(_ context.Context, limit int) ([]domain.AuditLog, error) {
	r.lastAuditLimit = limit
	if limit > len(r.logs) {
		limit = len(r.logs)
	}
	return append([]domain.AuditLog(nil), r.logs[:limit]...), nil
}

func TestGetPublicConfigFallsBackToDefaultWhenMissing(t *testing.T) {
	fixedNow := time.Date(2026, 11, 22, 10, 35, 0, 0, time.UTC)
	repo := newMemoryRepo(fixedNow)
	svc := NewService(repo)
	svc.now = func() time.Time { return fixedNow }

	cfg, err := svc.GetPublicConfig(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.MembershipPaywall != domain.DefaultMembershipPaywallConfig() {
		t.Fatalf("expected default fail-closed config, got %+v", cfg.MembershipPaywall)
	}
	if !cfg.UpdatedAt.Equal(fixedNow) {
		t.Fatalf("expected fallback updated_at %v, got %v", fixedNow, cfg.UpdatedAt)
	}
}

func TestUpdateConfigNormalizesAndWritesAuditLog(t *testing.T) {
	fixedNow := time.Date(2026, 11, 22, 10, 35, 0, 0, time.UTC)
	repo := newMemoryRepo(fixedNow)
	svc := NewService(repo)

	desc := "  会员开关配置  "
	entry, err := svc.UpdateConfig(context.Background(), UpdateConfigCommand{
		Key:         domain.KeyMembershipPaywall,
		ValueJSON:   json.RawMessage(`{"chanlun_requires_membership": false, "membership_entry_visible": true, "free_access_notice": "  限时免费体验  "}`),
		Description: &desc,
		Operator:    "  admin  ",
		Note:        "  切换为限时免费  ",
	})
	if err != nil {
		t.Fatalf("UpdateConfig failed: %v", err)
	}
	if entry.Description != "会员开关配置" || entry.UpdatedBy != "admin" {
		t.Fatalf("unexpected updated entry: %+v", entry)
	}

	pub, err := svc.GetPublicConfig(context.Background())
	if err != nil {
		t.Fatalf("GetPublicConfig failed: %v", err)
	}
	if pub.MembershipPaywall.ChanlunRequiresMembership || !pub.MembershipPaywall.MembershipEntryVisible || pub.MembershipPaywall.FreeAccessNotice != "限时免费体验" {
		t.Fatalf("unexpected public config: %+v", pub.MembershipPaywall)
	}

	// Second update without description should preserve existing description and record old_value
	entry2, err := svc.UpdateConfig(context.Background(), UpdateConfigCommand{
		Key:       domain.KeyMembershipPaywall,
		ValueJSON: json.RawMessage(`{"chanlun_requires_membership": true, "membership_entry_visible": true, "free_access_notice": ""}`),
		Operator:  "ops",
		Note:      "恢复收费",
	})
	if err != nil {
		t.Fatalf("second UpdateConfig failed: %v", err)
	}
	if entry2.Description != "会员开关配置" {
		t.Fatalf("expected preserved description, got %q", entry2.Description)
	}

	logs, err := svc.ListAuditLogs(context.Background(), 0)
	if err != nil {
		t.Fatalf("ListAuditLogs failed: %v", err)
	}
	if repo.lastAuditLimit != DefaultAuditLogLimit {
		t.Fatalf("expected default limit %d, got %d", DefaultAuditLogLimit, repo.lastAuditLimit)
	}
	if len(logs) != 2 {
		t.Fatalf("expected 2 audit logs, got %d", len(logs))
	}
	if logs[0].Operator != "ops" || logs[0].Note != "恢复收费" || len(logs[0].OldValueJSON) == 0 {
		t.Fatalf("unexpected latest audit log: %+v", logs[0])
	}
	if logs[1].OldValueJSON != nil {
		t.Fatalf("expected first audit log old_value to be nil, got %s", string(logs[1].OldValueJSON))
	}
}

func TestUpdateConfigRejectsInvalidPayloadAndClampsAuditLimit(t *testing.T) {
	repo := newMemoryRepo(time.Now().UTC())
	svc := NewService(repo)

	_, err := svc.UpdateConfig(context.Background(), UpdateConfigCommand{
		Key:       domain.KeyMembershipPaywall,
		ValueJSON: json.RawMessage(`{"chanlun_requires_membership": false, "membership_entry_visible": true, "free_access_notice": "` + strings.Repeat("a", 121) + `"}`),
	})
	if !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected validation error, got %v", err)
	}

	if _, err := svc.ListAuditLogs(context.Background(), 500); err != nil {
		t.Fatalf("ListAuditLogs failed: %v", err)
	}
	if repo.lastAuditLimit != MaxAuditLogLimit {
		t.Fatalf("expected clamped limit %d, got %d", MaxAuditLogLimit, repo.lastAuditLimit)
	}
}
