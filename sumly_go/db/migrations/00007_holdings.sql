-- +goose Up
CREATE TABLE holdings_snapshots (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    revision BIGINT NOT NULL CHECK (revision > 0),
    document JSONB NOT NULL CHECK (jsonb_typeof(document) = 'object'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose Down
DROP TABLE IF EXISTS holdings_snapshots;
