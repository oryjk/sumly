package postgres

import (
	"context"
	"errors"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

func TestRepositoryCreateListAndAdminUpdate(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	uid := int64(101)
	first, err := repo.Create(ctx, ports.CreateFeedbackParams{
		UserID:           &uid,
		DeviceHash:       "device_hash_alpha",
		Category:         domain.CategoryBug,
		Content:          "实时金价图表偶发空白",
		Contact:          "alpha@example.com",
		Attachments:      []domain.Attachment{{ObjectKey: "feedback/20261123/a.jpg", URL: "/api/v1/app/feedback/attachments/20261123/a.jpg"}},
		AppVersion:       "1.3.0",
		BuildNumber:      "105",
		IOSVersion:       "18.1",
		DeviceModel:      "iPhone16,2",
		MarketMode:       "domestic",
		CloudSyncEnabled: true,
	})
	if err != nil {
		t.Fatalf("Create first failed: %v", err)
	}
	if first.ID <= 0 || first.Status != domain.StatusNew || len(first.Attachments) != 1 {
		t.Fatalf("unexpected created feedback: %+v", first)
	}

	second, err := repo.Create(ctx, ports.CreateFeedbackParams{
		DeviceHash: "device_hash_beta",
		Category:   domain.CategorySuggestion,
		Content:    "希望支持自定义首页排序",
	})
	if err != nil {
		t.Fatalf("Create second failed: %v", err)
	}

	// ListMine by userID OR deviceHash
	mine, err := repo.ListMine(ctx, &uid, "device_hash_beta", 50)
	if err != nil {
		t.Fatalf("ListMine failed: %v", err)
	}
	if len(mine) != 2 || mine[0].ID != second.ID || mine[1].ID != first.ID {
		t.Fatalf("unexpected ListMine result: %+v", mine)
	}

	// ListMine guest
	guestMine, err := repo.ListMine(ctx, nil, "device_hash_beta", 50)
	if err != nil || len(guestMine) != 1 || guestMine[0].ID != second.ID {
		t.Fatalf("unexpected guest ListMine: items=%+v err=%v", guestMine, err)
	}

	// UpdateAdmin sets replied_at when reply is non-empty and changed
	st := domain.StatusResolved
	note := "已核查日志"
	reply := "问题已在 1.3.1 修复"
	updated, err := repo.UpdateAdmin(ctx, first.ID, ports.AdminUpdateParams{
		Status:     &st,
		AdminNote:  &note,
		AdminReply: &reply,
		UpdatedBy:  "admin",
	})
	if err != nil {
		t.Fatalf("UpdateAdmin failed: %v", err)
	}
	if updated.Status != domain.StatusResolved || updated.AdminNote != note || updated.AdminReply != reply || updated.RepliedAt == nil || updated.UpdatedBy != "admin" {
		t.Fatalf("unexpected updated feedback: %+v", updated)
	}
	firstRepliedAt := *updated.RepliedAt

	// Updating note only (or same reply) preserves replied_at
	note2 := "补充内部备注"
	updated2, err := repo.UpdateAdmin(ctx, first.ID, ports.AdminUpdateParams{
		AdminNote:  &note2,
		AdminReply: &reply,
		UpdatedBy:  "admin2",
	})
	if err != nil {
		t.Fatalf("UpdateAdmin second failed: %v", err)
	}
	if updated2.RepliedAt == nil || !updated2.RepliedAt.Equal(firstRepliedAt) {
		t.Fatalf("expected preserved replied_at=%v, got %v", firstRepliedAt, updated2.RepliedAt)
	}

	// ListAdmin counts & filtering
	listed, err := repo.ListAdmin(ctx, ports.AdminListFilter{
		Status: "resolved",
		Query:  "金价",
		Limit:  50,
		Offset: 0,
	})
	if err != nil {
		t.Fatalf("ListAdmin failed: %v", err)
	}
	if listed.Total != 1 || len(listed.Items) != 1 || listed.Counts.All != 2 || listed.Counts.New != 1 || listed.Counts.Resolved != 1 {
		t.Fatalf("unexpected ListAdmin result: %+v", listed)
	}

	// UpdateAdmin non-existent returns ErrNotFound
	if _, err := repo.UpdateAdmin(ctx, 999999, ports.AdminUpdateParams{AdminNote: &note}); !errors.Is(err, sharederror.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
