-- +goose Up
CREATE TABLE app_configs (
    key TEXT PRIMARY KEY,
    value_json JSONB NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    updated_by TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE app_config_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    config_key TEXT NOT NULL,
    old_value_json JSONB,
    new_value_json JSONB NOT NULL,
    operator TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_app_config_audit_logs_created_at
    ON app_config_audit_logs (created_at DESC);

INSERT INTO app_configs (key, value_json, description)
VALUES (
    'membership_paywall',
    '{"chanlun_requires_membership": true, "membership_entry_visible": true, "free_access_notice": ""}'::jsonb,
    '会员订阅与功能付费开关配置'
)
ON CONFLICT (key) DO NOTHING;

-- +goose Down
DROP INDEX IF EXISTS idx_app_config_audit_logs_created_at;
DROP TABLE IF EXISTS app_config_audit_logs;
DROP TABLE IF EXISTS app_configs;
