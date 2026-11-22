package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/ports"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Repository 是远程应用配置及变更审计日志的 PostgreSQL 适配器。
type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) GetByKey(ctx context.Context, key string) (domain.ConfigEntry, bool, error) {
	var entry domain.ConfigEntry
	var rawValue []byte
	err := r.pool.QueryRow(ctx, `
		SELECT key, value_json, description, updated_by, updated_at
		FROM app_configs
		WHERE key = $1
	`, key).Scan(&entry.Key, &rawValue, &entry.Description, &entry.UpdatedBy, &entry.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ConfigEntry{}, false, nil
	}
	if err != nil {
		return domain.ConfigEntry{}, false, fmt.Errorf("get app config %q: %w", key, err)
	}
	entry.ValueJSON = json.RawMessage(rawValue)
	return entry, true, nil
}

func (r *Repository) ListAll(ctx context.Context) ([]domain.ConfigEntry, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT key, value_json, description, updated_by, updated_at
		FROM app_configs
		ORDER BY key ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("list app configs: %w", err)
	}
	defer rows.Close()

	items := make([]domain.ConfigEntry, 0)
	for rows.Next() {
		var entry domain.ConfigEntry
		var rawValue []byte
		if err := rows.Scan(&entry.Key, &rawValue, &entry.Description, &entry.UpdatedBy, &entry.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan app config: %w", err)
		}
		entry.ValueJSON = json.RawMessage(rawValue)
		items = append(items, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate app configs: %w", err)
	}
	return items, nil
}

func (r *Repository) UpsertWithAudit(ctx context.Context, params ports.UpsertParams) (domain.ConfigEntry, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.ConfigEntry{}, fmt.Errorf("begin app config tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var oldValue []byte
	var existingDescription string
	err = tx.QueryRow(ctx, `
		SELECT value_json, description
		FROM app_configs
		WHERE key = $1
		FOR UPDATE
	`, params.Key).Scan(&oldValue, &existingDescription)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return domain.ConfigEntry{}, fmt.Errorf("lock app config %q: %w", params.Key, err)
	}

	description := existingDescription
	if params.Description != nil {
		description = *params.Description
	}

	var updated domain.ConfigEntry
	var updatedValue []byte
	err = tx.QueryRow(ctx, `
		INSERT INTO app_configs (key, value_json, description, updated_by, updated_at)
		VALUES ($1, $2::jsonb, $3, $4, NOW())
		ON CONFLICT (key) DO UPDATE SET
			value_json = EXCLUDED.value_json,
			description = EXCLUDED.description,
			updated_by = EXCLUDED.updated_by,
			updated_at = NOW()
		RETURNING key, value_json, description, updated_by, updated_at
	`, params.Key, []byte(params.ValueJSON), description, params.Operator).Scan(
		&updated.Key,
		&updatedValue,
		&updated.Description,
		&updated.UpdatedBy,
		&updated.UpdatedAt,
	)
	if err != nil {
		return domain.ConfigEntry{}, fmt.Errorf("upsert app config %q: %w", params.Key, err)
	}
	updated.ValueJSON = json.RawMessage(updatedValue)

	var oldValueArg any
	if len(oldValue) > 0 {
		oldValueArg = oldValue
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO app_config_audit_logs (config_key, old_value_json, new_value_json, operator, note)
		VALUES ($1, $2::jsonb, $3::jsonb, $4, $5)
	`, params.Key, oldValueArg, []byte(updated.ValueJSON), params.Operator, params.Note)
	if err != nil {
		return domain.ConfigEntry{}, fmt.Errorf("insert app config audit log %q: %w", params.Key, err)
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.ConfigEntry{}, fmt.Errorf("commit app config tx: %w", err)
	}
	return updated, nil
}

func (r *Repository) ListAuditLogs(ctx context.Context, limit int) ([]domain.AuditLog, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, config_key, old_value_json, new_value_json, operator, note, created_at
		FROM app_config_audit_logs
		ORDER BY created_at DESC, id DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, fmt.Errorf("list app config audit logs: %w", err)
	}
	defer rows.Close()

	logs := make([]domain.AuditLog, 0)
	for rows.Next() {
		var item domain.AuditLog
		var oldValue []byte
		var newValue []byte
		if err := rows.Scan(
			&item.ID,
			&item.ConfigKey,
			&oldValue,
			&newValue,
			&item.Operator,
			&item.Note,
			&item.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan app config audit log: %w", err)
		}
		if len(oldValue) > 0 {
			item.OldValueJSON = json.RawMessage(oldValue)
		}
		item.NewValueJSON = json.RawMessage(newValue)
		logs = append(logs, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate app config audit logs: %w", err)
	}
	return logs, nil
}
