-- +goose Up
CREATE TABLE market_latest_quotes (
 symbol TEXT PRIMARY KEY,
 currency TEXT NOT NULL,
 price DOUBLE PRECISION NOT NULL,
 open DOUBLE PRECISION NOT NULL,
 high DOUBLE PRECISION NOT NULL,
 low DOUBLE PRECISION NOT NULL,
 prev_close DOUBLE PRECISION NOT NULL,
 usd_cny DOUBLE PRECISION NOT NULL,
 as_of TIMESTAMPTZ NOT NULL,
 source_delay_seconds INTEGER NOT NULL DEFAULT 0
);

-- Each replacement is an atomic snapshot; failed ingestion keeps the last one.
CREATE TABLE market_intraday_snapshots (
 symbol TEXT PRIMARY KEY,
 event_at TIMESTAMPTZ NOT NULL,
 points JSONB NOT NULL CHECK (jsonb_typeof(points) = 'array')
);

-- +goose Down
DROP TABLE market_intraday_snapshots;
DROP TABLE market_latest_quotes;
