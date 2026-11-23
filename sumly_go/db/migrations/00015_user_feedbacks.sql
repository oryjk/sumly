-- +goose Up
CREATE TABLE user_feedbacks (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NULL,
    device_hash TEXT NOT NULL,
    category TEXT NOT NULL,
    content TEXT NOT NULL,
    contact TEXT NOT NULL DEFAULT '',
    attachments_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    app_version TEXT NOT NULL DEFAULT '',
    build_number TEXT NOT NULL DEFAULT '',
    ios_version TEXT NOT NULL DEFAULT '',
    device_model TEXT NOT NULL DEFAULT '',
    market_mode TEXT NOT NULL DEFAULT '',
    cloud_sync_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    status TEXT NOT NULL DEFAULT 'new',
    admin_note TEXT NOT NULL DEFAULT '',
    admin_reply TEXT NOT NULL DEFAULT '',
    replied_at TIMESTAMPTZ NULL,
    updated_by TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_feedbacks_status_created_at
    ON user_feedbacks (status, created_at DESC);

CREATE INDEX idx_user_feedbacks_device_hash_created_at
    ON user_feedbacks (device_hash, created_at DESC);

CREATE INDEX idx_user_feedbacks_user_id_created_at
    ON user_feedbacks (user_id, created_at DESC)
    WHERE user_id IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS idx_user_feedbacks_user_id_created_at;
DROP INDEX IF EXISTS idx_user_feedbacks_device_hash_created_at;
DROP INDEX IF EXISTS idx_user_feedbacks_status_created_at;
DROP TABLE IF EXISTS user_feedbacks;
