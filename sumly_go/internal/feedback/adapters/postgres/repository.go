package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type attachmentRow struct {
	ObjectKey string `json:"object_key"`
	URL       string `json:"url"`
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, params ports.CreateFeedbackParams) (domain.Feedback, error) {
	rawAttachments, err := encodeAttachments(params.Attachments)
	if err != nil {
		return domain.Feedback{}, fmt.Errorf("encode feedback attachments: %w", err)
	}

	row := r.pool.QueryRow(ctx, `
		INSERT INTO user_feedbacks (
			user_id, device_hash, category, content, contact, attachments_json,
			app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled
		)
		VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, $10, $11, $12)
		RETURNING id, user_id, device_hash, category, content, contact, attachments_json,
			app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
			status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
	`,
		params.UserID,
		params.DeviceHash,
		string(params.Category),
		params.Content,
		params.Contact,
		rawAttachments,
		params.AppVersion,
		params.BuildNumber,
		params.IOSVersion,
		params.DeviceModel,
		params.MarketMode,
		params.CloudSyncEnabled,
	)
	item, err := scanFeedback(row)
	if err != nil {
		return domain.Feedback{}, fmt.Errorf("insert user feedback: %w", err)
	}
	return item, nil
}

func (r *Repository) ListMine(ctx context.Context, userID *int64, deviceHash string, limit int) ([]domain.Feedback, error) {
	var (
		rows pgx.Rows
		err  error
	)
	switch {
	case userID != nil && deviceHash != "":
		rows, err = r.pool.Query(ctx, `
			SELECT id, user_id, device_hash, category, content, contact, attachments_json,
				app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
				status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
			FROM user_feedbacks
			WHERE user_id = $1 OR device_hash = $2
			ORDER BY created_at DESC, id DESC
			LIMIT $3
		`, *userID, deviceHash, limit)
	case userID != nil:
		rows, err = r.pool.Query(ctx, `
			SELECT id, user_id, device_hash, category, content, contact, attachments_json,
				app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
				status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
			FROM user_feedbacks
			WHERE user_id = $1
			ORDER BY created_at DESC, id DESC
			LIMIT $2
		`, *userID, limit)
	default:
		rows, err = r.pool.Query(ctx, `
			SELECT id, user_id, device_hash, category, content, contact, attachments_json,
				app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
				status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
			FROM user_feedbacks
			WHERE device_hash = $1
			ORDER BY created_at DESC, id DESC
			LIMIT $2
		`, deviceHash, limit)
	}
	if err != nil {
		return nil, fmt.Errorf("query my feedbacks: %w", err)
	}
	defer rows.Close()

	items := make([]domain.Feedback, 0)
	for rows.Next() {
		item, err := scanFeedback(rows)
		if err != nil {
			return nil, fmt.Errorf("scan my feedback: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate my feedbacks: %w", err)
	}
	return items, nil
}

func (r *Repository) ListAdmin(ctx context.Context, filter ports.AdminListFilter) (ports.AdminListResult, error) {
	whereParts := make([]string, 0, 3)
	args := make([]any, 0, 6)
	nextArg := func(v any) string {
		args = append(args, v)
		return "$" + strconv.Itoa(len(args))
	}

	if filter.Status != "" {
		whereParts = append(whereParts, "status = "+nextArg(filter.Status))
	}
	if filter.Category != "" {
		whereParts = append(whereParts, "category = "+nextArg(filter.Category))
	}
	if filter.Query != "" {
		likePattern := "%" + escapeILIKE(filter.Query) + "%"
		p := nextArg(likePattern)
		exact := nextArg(filter.Query)
		whereParts = append(whereParts, fmt.Sprintf(
			`(content ILIKE %s ESCAPE '\' OR contact ILIKE %s ESCAPE '\' OR device_hash ILIKE %s ESCAPE '\' OR device_model ILIKE %s ESCAPE '\' OR admin_note ILIKE %s ESCAPE '\' OR admin_reply ILIKE %s ESCAPE '\' OR CAST(id AS TEXT) = %s)`,
			p, p, p, p, p, p, exact,
		))
	}

	whereSQL := ""
	if len(whereParts) > 0 {
		whereSQL = " WHERE " + strings.Join(whereParts, " AND ")
	}

	var total int64
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM user_feedbacks"+whereSQL, args...).Scan(&total); err != nil {
		return ports.AdminListResult{}, fmt.Errorf("count admin feedbacks: %w", err)
	}

	counts, err := r.loadStatusCounts(ctx)
	if err != nil {
		return ports.AdminListResult{}, err
	}

	limitPlaceholder := nextArg(filter.Limit)
	offsetPlaceholder := nextArg(filter.Offset)
	querySQL := `
		SELECT id, user_id, device_hash, category, content, contact, attachments_json,
			app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
			status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
		FROM user_feedbacks` + whereSQL + `
		ORDER BY created_at DESC, id DESC
		LIMIT ` + limitPlaceholder + ` OFFSET ` + offsetPlaceholder

	rows, err := r.pool.Query(ctx, querySQL, args...)
	if err != nil {
		return ports.AdminListResult{}, fmt.Errorf("list admin feedbacks: %w", err)
	}
	defer rows.Close()

	items := make([]domain.Feedback, 0)
	for rows.Next() {
		item, err := scanFeedback(rows)
		if err != nil {
			return ports.AdminListResult{}, fmt.Errorf("scan admin feedback: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return ports.AdminListResult{}, fmt.Errorf("iterate admin feedbacks: %w", err)
	}

	return ports.AdminListResult{
		Items:  items,
		Total:  total,
		Counts: counts,
	}, nil
}

func (r *Repository) loadStatusCounts(ctx context.Context) (domain.StatusCounts, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT status, COUNT(*)
		FROM user_feedbacks
		GROUP BY status
	`)
	if err != nil {
		return domain.StatusCounts{}, fmt.Errorf("count feedbacks by status: %w", err)
	}
	defer rows.Close()

	var counts domain.StatusCounts
	for rows.Next() {
		var status string
		var cnt int64
		if err := rows.Scan(&status, &cnt); err != nil {
			return domain.StatusCounts{}, fmt.Errorf("scan feedback status count: %w", err)
		}
		counts.All += cnt
		switch domain.Status(status) {
		case domain.StatusNew:
			counts.New = cnt
		case domain.StatusInProgress:
			counts.InProgress = cnt
		case domain.StatusResolved:
			counts.Resolved = cnt
		case domain.StatusArchived:
			counts.Archived = cnt
		}
	}
	if err := rows.Err(); err != nil {
		return domain.StatusCounts{}, fmt.Errorf("iterate feedback status counts: %w", err)
	}
	return counts, nil
}

func (r *Repository) UpdateAdmin(ctx context.Context, id int64, patch ports.AdminUpdateParams) (domain.Feedback, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.Feedback{}, fmt.Errorf("begin update feedback tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var (
		existingStatus string
		existingNote   string
		existingReply  string
		existingRepled *time.Time
	)
	err = tx.QueryRow(ctx, `
		SELECT status, admin_note, admin_reply, replied_at
		FROM user_feedbacks
		WHERE id = $1
		FOR UPDATE
	`, id).Scan(&existingStatus, &existingNote, &existingReply, &existingRepled)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Feedback{}, sharederror.ErrNotFound
	}
	if err != nil {
		return domain.Feedback{}, fmt.Errorf("lock user feedback %d: %w", id, err)
	}

	nextStatus := existingStatus
	if patch.Status != nil {
		nextStatus = string(*patch.Status)
	}
	nextNote := existingNote
	if patch.AdminNote != nil {
		nextNote = *patch.AdminNote
	}
	nextReply := existingReply
	updateRepliedAt := false
	if patch.AdminReply != nil {
		nextReply = *patch.AdminReply
		if nextReply != "" && nextReply != existingReply {
			updateRepliedAt = true
		}
	}

	var row pgx.Row
	if updateRepliedAt {
		row = tx.QueryRow(ctx, `
			UPDATE user_feedbacks
			SET status = $2,
				admin_note = $3,
				admin_reply = $4,
				replied_at = NOW(),
				updated_by = $5,
				updated_at = NOW()
			WHERE id = $1
			RETURNING id, user_id, device_hash, category, content, contact, attachments_json,
				app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
				status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
		`, id, nextStatus, nextNote, nextReply, patch.UpdatedBy)
	} else {
		row = tx.QueryRow(ctx, `
			UPDATE user_feedbacks
			SET status = $2,
				admin_note = $3,
				admin_reply = $4,
				updated_by = $5,
				updated_at = NOW()
			WHERE id = $1
			RETURNING id, user_id, device_hash, category, content, contact, attachments_json,
				app_version, build_number, ios_version, device_model, market_mode, cloud_sync_enabled,
				status, admin_note, admin_reply, replied_at, updated_by, created_at, updated_at
		`, id, nextStatus, nextNote, nextReply, patch.UpdatedBy)
	}

	updated, err := scanFeedback(row)
	if err != nil {
		return domain.Feedback{}, fmt.Errorf("update user feedback %d: %w", id, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.Feedback{}, fmt.Errorf("commit update feedback tx: %w", err)
	}
	return updated, nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanFeedback(scanner rowScanner) (domain.Feedback, error) {
	var (
		item           domain.Feedback
		categoryRaw    string
		statusRaw      string
		rawAttachments []byte
	)
	err := scanner.Scan(
		&item.ID,
		&item.UserID,
		&item.DeviceHash,
		&categoryRaw,
		&item.Content,
		&item.Contact,
		&rawAttachments,
		&item.AppVersion,
		&item.BuildNumber,
		&item.IOSVersion,
		&item.DeviceModel,
		&item.MarketMode,
		&item.CloudSyncEnabled,
		&statusRaw,
		&item.AdminNote,
		&item.AdminReply,
		&item.RepliedAt,
		&item.UpdatedBy,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if err != nil {
		return domain.Feedback{}, err
	}
	item.Category = domain.Category(categoryRaw)
	item.Status = domain.Status(statusRaw)
	attachments, err := decodeAttachments(rawAttachments)
	if err != nil {
		return domain.Feedback{}, err
	}
	item.Attachments = attachments
	return item, nil
}

func encodeAttachments(items []domain.Attachment) ([]byte, error) {
	if len(items) == 0 {
		return []byte("[]"), nil
	}
	rows := make([]attachmentRow, 0, len(items))
	for _, item := range items {
		rows = append(rows, attachmentRow{
			ObjectKey: item.ObjectKey,
			URL:       item.URL,
		})
	}
	return json.Marshal(rows)
}

func decodeAttachments(raw []byte) ([]domain.Attachment, error) {
	if len(raw) == 0 {
		return []domain.Attachment{}, nil
	}
	var rows []attachmentRow
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, fmt.Errorf("decode attachments_json: %w", err)
	}
	out := make([]domain.Attachment, 0, len(rows))
	for _, row := range rows {
		out = append(out, domain.Attachment{
			ObjectKey: row.ObjectKey,
			URL:       row.URL,
		})
	}
	return out, nil
}

func escapeILIKE(s string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return replacer.Replace(s)
}
