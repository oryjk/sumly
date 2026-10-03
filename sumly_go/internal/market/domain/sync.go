package domain

import "errors"

var ErrInvalidSyncQuery = errors.New("invalid market sync query")

// HistorySeries is resolved by the application catalog, independently of storage.
type HistorySeries struct{ ID, Symbol, Unit string }

// HistoryChange is a canonical market observation or a tombstone, never a live quote.
type HistoryChange struct {
	Date        string  `json:"date"`
	Granularity string  `json:"granularity"`
	Open        float64 `json:"open"`
	High        float64 `json:"high"`
	Low         float64 `json:"low"`
	Close       float64 `json:"close"`
	Source      string  `json:"source"`
	Deleted     bool    `json:"deleted"`
}
type HistorySync struct {
	Series string          `json:"series"`
	Unit   string          `json:"unit"`
	Cursor string          `json:"cursor"`
	Reset  bool            `json:"reset"`
	Points []HistoryChange `json:"points"`
}
