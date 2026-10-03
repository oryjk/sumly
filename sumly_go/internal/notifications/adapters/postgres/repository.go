package postgres

import (
	"context"
	"errors"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/ports"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store 是通知模块的 PostgreSQL 实现。
type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

func (s *Store) PutGrant(ctx context.Context, g ports.Grant) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO notification_grants(hash,device_id,workspace,user_id,template_id,openid,expires_at)
		VALUES($1,$2,$3,NULLIF($4,0),$5,$6,$7)
		ON CONFLICT (hash) DO NOTHING`, g.Hash, g.DeviceID, g.Workspace, g.UserID, g.TemplateID, g.OpenID, g.ExpiresAt)
	return err
}

func (s *Store) Grant(ctx context.Context, hash string, now time.Time) (ports.Grant, error) {
	var g ports.Grant
	var userID *int64
	err := s.pool.QueryRow(ctx, `
		SELECT hash,device_id,workspace,user_id,template_id,openid,expires_at
		FROM notification_grants WHERE hash=$1 AND expires_at > $2`, hash, now).
		Scan(&g.Hash, &g.DeviceID, &g.Workspace, &userID, &g.TemplateID, &g.OpenID, &g.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return g, domain.ErrGrantNotFound
	}
	if err != nil {
		return g, err
	}
	if userID != nil {
		g.UserID = *userID
	}
	return g, nil
}

func (s *Store) Event(ctx context.Context, deviceID, workspace, requestID, alertID string) (domain.Event, bool, error) {
	if requestID == "" {
		return domain.Event{}, false, nil
	}
	var e domain.Event
	var status string
	err := s.pool.QueryRow(ctx, `
		SELECT id,status,created_at,expires_at FROM notification_events
		WHERE device_id=$1 AND workspace=$2 AND request_id=$3 AND alert_id=$4`,
		deviceID, workspace, requestID, alertID).
		Scan(&e.ID, &status, &e.CreatedAt, &e.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return e, false, nil
	}
	if err != nil {
		return e, false, err
	}
	e.Status = domain.EventStatus(status)
	return e, true, nil
}

func (s *Store) EventByID(ctx context.Context, deviceID, workspace, eventID string) (domain.Event, bool, error) {
	var e domain.Event
	var status string
	err := s.pool.QueryRow(ctx, `
		SELECT id,status,created_at,expires_at FROM notification_events
		WHERE device_id=$1 AND workspace=$2 AND id=$3`, deviceID, workspace, eventID).
		Scan(&e.ID, &status, &e.CreatedAt, &e.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return e, false, nil
	}
	if err != nil {
		return e, false, err
	}
	e.Status = domain.EventStatus(status)
	return e, true, nil
}

func (s *Store) PutEvent(ctx context.Context, e domain.Event, deviceID, workspace, requestID, alertID string) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO notification_events(id,device_id,workspace,request_id,alert_id,status,created_at,expires_at)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8)
		ON CONFLICT (device_id,request_id,alert_id) DO NOTHING`,
		e.ID, deviceID, workspace, requestID, alertID, string(e.Status), e.CreatedAt, e.ExpiresAt)
	return err
}

func (s *Store) Baselines(ctx context.Context, deviceID, workspace string) (map[string]ports.Baseline, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT config_hash,previous_price,previous_as_of,armed,last_triggered_at
		FROM notification_device_baselines WHERE device_id=$1 AND workspace=$2`, deviceID, workspace)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]ports.Baseline{}
	for rows.Next() {
		var hash string
		var b ports.Baseline
		if err := rows.Scan(&hash, &b.PreviousPrice, &b.PreviousAsOf, &b.Armed, &b.LastTriggeredAt); err != nil {
			return nil, err
		}
		out[hash] = b
	}
	return out, rows.Err()
}

func (s *Store) PutBaseline(ctx context.Context, deviceID, workspace, configHash string, b ports.Baseline) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO notification_device_baselines(device_id,workspace,config_hash,previous_price,previous_as_of,armed,last_triggered_at)
		VALUES($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT (device_id,workspace,config_hash) DO UPDATE SET
			previous_price=EXCLUDED.previous_price, previous_as_of=EXCLUDED.previous_as_of,
			armed=EXCLUDED.armed, last_triggered_at=EXCLUDED.last_triggered_at`,
		deviceID, workspace, configHash, b.PreviousPrice, b.PreviousAsOf, b.Armed, b.LastTriggeredAt)
	return err
}

func (s *Store) Purge(ctx context.Context, now time.Time) error {
	for _, query := range []string{
		`DELETE FROM notification_grants WHERE expires_at <= $1`,
		`DELETE FROM notification_events WHERE expires_at <= $1`,
		`DELETE FROM notification_device_baselines WHERE previous_as_of <= $1`,
	} {
		if _, err := s.pool.Exec(ctx, query, now); err != nil {
			return err
		}
	}
	return nil
}
