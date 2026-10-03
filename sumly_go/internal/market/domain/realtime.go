package domain

import (
	"math"
	"time"
)

const RealtimeInterval = 5 * time.Second
const RealtimeWindow = 20 * time.Minute

func RealtimePrice(q GoldQuote, native bool) float64 {
	if native {
		return q.Price
	}
	return q.CNYPerGram()
}
func ValidRealtime(q GoldQuote, now time.Time, native bool) bool {
	price := RealtimePrice(q, native)
	return !q.AsOf.IsZero() && q.Price > 0 && price > 0 && !math.IsNaN(price) && !math.IsInf(price, 0) && !q.AsOf.After(now.Add(5*time.Second)) && now.Sub(q.AsOf) <= (120+time.Duration(q.SourceDelaySeconds))*time.Second
}
func SampleTime(q GoldQuote, now time.Time) time.Time {
	if q.SourceDelaySeconds > 0 {
		return q.AsOf
	}
	return now
}
