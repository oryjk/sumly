# Go Market Read/Write Refactoring Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; steps track RED/GREEN evidence.

**Goal:** Separate market ingestion and queries, restore application sync boundary, isolate holdings serialization.
**Architecture:** Independent query/collector and Postgres Reader/Writer communicate only through durable data. Adapter-owned holdings DTOs preserve existing API and JSONB.
**Tech Stack:** Go 1.26.5, pgx, Gin, goose, sqlc v1.31.1.
**Spec:** docs/superpowers/specs/2026-10-01-go-market-read-write-design.md

## Global Constraints
Preserve existing dirty working tree; leave changes reviewable and uncommitted. No live migration. Tests only use explicit TEST_DATABASE_URL. Keep existing API fields/status, units, precision, CAS, limits.

## Review Focus
Cold database (no on-demand fetch); stopped/delayed sources and restart; intraday atomic replacement and empty/failure handling; historical holdings JSONB compatibility and escaping size; sync cursor isolation and unchanged revisions.

### Task 1: Holdings DTO boundary
Files: holdings domain/document.go, application/service.go, adapters/http/dto.go and handler.go, adapters/postgres/document.go and repository.go, related tests.
Interfaces: domain.Document/Snapshot remain semantic models. HTTP documentDTO has toDomain/documentFromDomain; Postgres storedDocument independently encodes/decodes the existing JSONB contract.
- [x] RED: domain structs have no json tags; full adapter roundtrip covers every field, fractional dates, optional values, nested required/null/unknown rejection and oversize escaping before persistence.
- [x] GREEN: add adapter DTOs/conversion, remove core JSON serialization, enforce persisted response size in adapter before transaction.
- [x] Run go test ./internal/holdings/... .

### Task 2: Market queries and ingestion
Files: market/ports, application query/collector/realtime/daily/instruments/sync, postgres reader/writer/sync, migration 00008, db/queries/market.sql, bootstrap/dependencies.go and related tests.
Interfaces: GoldReadStore LoadQuote/LoadIntraday/LoadRealtime/LoadDaily; GoldWriteStore SaveQuote/SaveIntraday/SaveRealtime/PruneRealtime/SaveDaily; GoldQuery receives only GoldReadStore; GoldCollector receives source and GoldWriteStore; HistorySync receives HistorySyncReader and catalog; reader.SyncHistory(ctx, domain.HistorySeries, cursor).
- [x] RED: read-only fake serves all reads without fetching/mutating; write-only fake accepts validated ingest without reads; sync maps IDs/units in use case and validates before storage.
- [x] GREEN: independent services/adapters, additive durable quote/intraday tables; preserve windows/time/FX; DB idempotent daily upsert; separate bootstrap read handlers from workers.
- [x] sqlc generate, migrate affected regressions to independent services, go test ./internal/market/... ./internal/bootstrap/... ./db.

### Task 3: Integration and architecture verification
Files: market postgres integration and architecture tests, holdings integration, README/AGENTS/docs.
- [x] Test durable values after reader recreation, readonly transactions, per-symbol isolation, failed/empty ingestion preserving data, no reader mutation methods or writer load methods, core import boundaries.
- [x] Run gofmt, go test ./..., go vet ./..., go build -o /tmp/sumly-go-api ./cmd/api, key package go test -race; inspect skips and baseline-relative diff; final independent reviewer.
