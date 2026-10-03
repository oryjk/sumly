package domain

import "strings"

func trim(value string) string  { return strings.TrimSpace(value) }
func lower(value string) string { return strings.ToLower(value) }
func finite(value float64) bool {
	return !isNaN(value) && !isInf(value, 0)
}

func isNaN(value float64) bool { return value != value }
func isInf(value float64, sign int) bool {
	return sign > 0 && value > MaxFloat64 || sign < 0 && value < -MaxFloat64
}

// MaxFloat64 是 float64 上界。
const MaxFloat64 = 1.7976931348623157e308
