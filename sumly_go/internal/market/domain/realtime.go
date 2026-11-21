package domain

import (
	"math"
	"time"
)

const RealtimeInterval = 5 * time.Second
const RealtimeWindow = 20 * time.Minute

// MaxClockSkew 允许上游报价时间相对服务器时钟的合理超前容差；
// 落在 (now, now+MaxClockSkew] 内会钳制为 now，超过则视为异常未来时间拒绝。
const MaxClockSkew = 90 * time.Second

func ClampSourceTime(sourceTime, now time.Time) time.Time {
	if sourceTime.After(now) && !sourceTime.After(now.Add(MaxClockSkew)) {
		return now
	}
	return sourceTime
}

func RealtimePrice(q GoldQuote, native bool) float64 {
	if native {
		return q.Price
	}
	return q.CNYPerGram()
}
func ValidRealtime(q GoldQuote, now time.Time, native bool) bool {
	price := RealtimePrice(q, native)
	return !q.AsOf.IsZero() && q.Price > 0 && price > 0 && !math.IsNaN(price) && !math.IsInf(price, 0) && !q.AsOf.After(now.Add(MaxClockSkew)) && now.Sub(q.AsOf) <= (120+time.Duration(q.SourceDelaySeconds))*time.Second
}
func SampleTime(q GoldQuote, now time.Time) time.Time {
	if q.SourceDelaySeconds > 0 {
		return ClampSourceTime(q.AsOf, now)
	}
	return now
}
