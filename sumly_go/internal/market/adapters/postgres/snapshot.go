package postgres

import "time"

// JSON belongs to the persistence adapter, independently of the HTTP format.
type intradayRow struct {
	Time  time.Time `json:"time"`
	Price float64   `json:"price"`
}
