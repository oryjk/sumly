-- +goose Up
CREATE TABLE macro_series (
    series_id TEXT PRIMARY KEY,
    name_zh TEXT NOT NULL,
    section TEXT NOT NULL,
    unit TEXT NOT NULL,
    frequency TEXT NOT NULL,
    source TEXT NOT NULL,
    gold_relation TEXT NOT NULL DEFAULT 'neutral',
    plain_note TEXT NOT NULL DEFAULT '',
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX macro_series_section_order_idx ON macro_series (section, display_order, series_id);

CREATE TABLE macro_observations (
    series_id TEXT NOT NULL REFERENCES macro_series(series_id) ON DELETE CASCADE,
    obs_date DATE NOT NULL,
    value DOUBLE PRECISION NOT NULL CHECK (value > '-Infinity'::float8 AND value < 'Infinity'::float8),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (series_id, obs_date)
);

CREATE INDEX macro_observations_series_date_desc_idx ON macro_observations (series_id, obs_date DESC);

CREATE TABLE macro_cot_observations (
    series_id TEXT NOT NULL REFERENCES macro_series(series_id) ON DELETE CASCADE,
    obs_date DATE NOT NULL,
    mm_long DOUBLE PRECISION NOT NULL,
    mm_short DOUBLE PRECISION NOT NULL,
    mm_net DOUBLE PRECISION NOT NULL,
    swap_long DOUBLE PRECISION NOT NULL,
    swap_short DOUBLE PRECISION NOT NULL,
    swap_net DOUBLE PRECISION NOT NULL,
    open_interest DOUBLE PRECISION NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (series_id, obs_date)
);

CREATE INDEX macro_cot_observations_series_date_desc_idx ON macro_cot_observations (series_id, obs_date DESC);

CREATE TABLE macro_temperature_daily (
    model_version TEXT NOT NULL,
    obs_date DATE NOT NULL,
    score DOUBLE PRECISION NOT NULL,
    level TEXT NOT NULL,
    degraded BOOLEAN NOT NULL DEFAULT FALSE,
    missing_factors TEXT[] NOT NULL DEFAULT '{}',
    gold_price_usd DOUBLE PRECISION,
    payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (model_version, obs_date)
);

CREATE INDEX macro_temperature_daily_version_date_desc_idx ON macro_temperature_daily (model_version, obs_date DESC);

CREATE TABLE macro_sync_states (
    series_id TEXT PRIMARY KEY REFERENCES macro_series(series_id) ON DELETE CASCADE,
    source TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    last_synced_at TIMESTAMPTZ,
    last_success_at TIMESTAMPTZ,
    last_error TEXT NOT NULL DEFAULT '',
    row_count INT NOT NULL DEFAULT 0,
    latest_obs_date DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose Down
DROP TABLE macro_sync_states;
DROP TABLE macro_temperature_daily;
DROP TABLE macro_cot_observations;
DROP TABLE macro_observations;
DROP TABLE macro_series;
