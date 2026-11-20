-- name: UpsertMacroSeries :exec
INSERT INTO macro_series (series_id, name_zh, section, unit, frequency, source, gold_relation, plain_note, display_order, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
ON CONFLICT (series_id) DO UPDATE SET
    name_zh = EXCLUDED.name_zh,
    section = EXCLUDED.section,
    unit = EXCLUDED.unit,
    frequency = EXCLUDED.frequency,
    source = EXCLUDED.source,
    gold_relation = EXCLUDED.gold_relation,
    plain_note = EXCLUDED.plain_note,
    display_order = EXCLUDED.display_order,
    updated_at = NOW();

-- name: ListMacroSeries :many
SELECT series_id, name_zh, section, unit, frequency, source, gold_relation, plain_note, display_order
FROM macro_series
ORDER BY section, display_order, series_id;

-- name: ListMacroSeriesBySection :many
SELECT series_id, name_zh, section, unit, frequency, source, gold_relation, plain_note, display_order
FROM macro_series
WHERE section = $1
ORDER BY display_order, series_id;

-- name: GetMacroSeries :one
SELECT series_id, name_zh, section, unit, frequency, source, gold_relation, plain_note, display_order
FROM macro_series
WHERE series_id = $1;

-- name: UpsertMacroObservations :exec
INSERT INTO macro_observations (series_id, obs_date, value, updated_at)
SELECT sqlc.arg(series_id)::text, unnest(sqlc.arg(obs_dates)::date[]), unnest(sqlc.arg(obs_values)::float8[]), NOW()
ON CONFLICT (series_id, obs_date) DO UPDATE SET
    value = EXCLUDED.value,
    updated_at = NOW()
WHERE macro_observations.value IS DISTINCT FROM EXCLUDED.value;

-- name: LoadMacroObservations :many
SELECT obs_date, value
FROM macro_observations
WHERE series_id = $1
ORDER BY obs_date ASC;

-- name: LoadMacroObservationsSince :many
SELECT obs_date, value
FROM macro_observations
WHERE series_id = $1 AND obs_date >= $2
ORDER BY obs_date ASC;

-- name: LoadMacroObservationsBySeriesIDs :many
SELECT series_id, obs_date, value
FROM macro_observations
WHERE series_id = ANY(sqlc.arg(series_ids)::text[])
ORDER BY series_id ASC, obs_date ASC;

-- name: UpsertMacroCotObservations :exec
INSERT INTO macro_cot_observations (
    series_id, obs_date, mm_long, mm_short, mm_net, swap_long, swap_short, swap_net, open_interest, updated_at
)
SELECT
    sqlc.arg(series_id)::text,
    unnest(sqlc.arg(obs_dates)::date[]),
    unnest(sqlc.arg(mm_longs)::float8[]),
    unnest(sqlc.arg(mm_shorts)::float8[]),
    unnest(sqlc.arg(mm_nets)::float8[]),
    unnest(sqlc.arg(swap_longs)::float8[]),
    unnest(sqlc.arg(swap_shorts)::float8[]),
    unnest(sqlc.arg(swap_nets)::float8[]),
    unnest(sqlc.arg(open_interests)::float8[]),
    NOW()
ON CONFLICT (series_id, obs_date) DO UPDATE SET
    mm_long = EXCLUDED.mm_long,
    mm_short = EXCLUDED.mm_short,
    mm_net = EXCLUDED.mm_net,
    swap_long = EXCLUDED.swap_long,
    swap_short = EXCLUDED.swap_short,
    swap_net = EXCLUDED.swap_net,
    open_interest = EXCLUDED.open_interest,
    updated_at = NOW();

-- name: LoadMacroCotObservations :many
SELECT obs_date, mm_long, mm_short, mm_net, swap_long, swap_short, swap_net, open_interest
FROM macro_cot_observations
WHERE series_id = $1
ORDER BY obs_date ASC;

-- name: UpsertMacroTemperatureDaily :exec
INSERT INTO macro_temperature_daily (
    model_version, obs_date, score, level, degraded, missing_factors, gold_price_usd, payload_json, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
ON CONFLICT (model_version, obs_date) DO UPDATE SET
    score = EXCLUDED.score,
    level = EXCLUDED.level,
    degraded = EXCLUDED.degraded,
    missing_factors = EXCLUDED.missing_factors,
    gold_price_usd = EXCLUDED.gold_price_usd,
    payload_json = EXCLUDED.payload_json,
    updated_at = NOW();

-- name: LoadMacroTemperatureHistory :many
SELECT obs_date, score, level, degraded, missing_factors, gold_price_usd, payload_json
FROM macro_temperature_daily
WHERE model_version = $1
ORDER BY obs_date ASC;

-- name: GetLatestMacroTemperature :one
SELECT obs_date, score, level, degraded, missing_factors, gold_price_usd, payload_json
FROM macro_temperature_daily
WHERE model_version = $1
ORDER BY obs_date DESC
LIMIT 1;

-- name: UpsertMacroSyncState :exec
INSERT INTO macro_sync_states (
    series_id, source, status, last_synced_at, last_success_at, last_error, row_count, latest_obs_date, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
ON CONFLICT (series_id) DO UPDATE SET
    source = EXCLUDED.source,
    status = EXCLUDED.status,
    last_synced_at = EXCLUDED.last_synced_at,
    last_success_at = COALESCE(EXCLUDED.last_success_at, macro_sync_states.last_success_at),
    last_error = EXCLUDED.last_error,
    row_count = CASE WHEN EXCLUDED.row_count > 0 THEN EXCLUDED.row_count ELSE macro_sync_states.row_count END,
    latest_obs_date = COALESCE(EXCLUDED.latest_obs_date, macro_sync_states.latest_obs_date),
    updated_at = NOW();

-- name: ListMacroSyncStates :many
SELECT series_id, source, status, last_synced_at, last_success_at, last_error, row_count, latest_obs_date
FROM macro_sync_states
ORDER BY series_id ASC;

-- name: GetMacroSyncState :one
SELECT series_id, source, status, last_synced_at, last_success_at, last_error, row_count, latest_obs_date
FROM macro_sync_states
WHERE series_id = $1;

-- name: LoadSGEAU9999DailyCloses :many
SELECT trading_date, close
FROM gold_daily_bars
WHERE symbol = 'AU9999'
ORDER BY trading_date ASC;
