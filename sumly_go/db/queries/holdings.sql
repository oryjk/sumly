-- name: LockHoldingsUser :one
SELECT status FROM users WHERE id = $1 FOR UPDATE;

-- name: GetHoldingsSnapshot :one
SELECT revision, document FROM holdings_snapshots WHERE user_id = $1;

-- name: InsertHoldingsSnapshot :one
INSERT INTO holdings_snapshots (user_id, revision, document)
VALUES ($1, 1, $2)
RETURNING revision, document;

-- name: UpdateHoldingsSnapshot :one
UPDATE holdings_snapshots
SET revision = revision + 1, document = $3, updated_at = NOW()
WHERE user_id = $1 AND revision = $2
RETURNING revision, document;
