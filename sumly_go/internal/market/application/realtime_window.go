package application

import (
	"context"
	"errors"
	"math"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

const (
	minFrozenSecondPoints = 12
	minFrozenSecondSpan   = 10 * time.Minute
	// 同交易时段内零成交分钟的顺延上限；严格小于上金所午休(120m)/日夜盘休市(270m)，
	// 确保只延续同盘口最后真实成交价，绝不跨休市空档拼接。
	maxMinuteCarryGap = 60 * time.Minute
)

// GetGoldRealtime 停更时将窗口固定在上游最后报价时间，不能随墙上时钟消失。
// 五秒历史缺失或覆盖不足时回退到真实分钟记录，通过返回的间隔明确区分；不回填采样库。
func (s *GoldQuery) GetGoldRealtime(ctx context.Context) ([]domain.RealtimePoint, int, error) {
	points, err := s.store.LoadRealtime(ctx)
	if err != nil {
		return nil, 5, err
	}
	points = append([]domain.RealtimePoint(nil), points...)
	quote, err := s.GetGoldQuote(ctx)
	if err != nil {
		if !errors.Is(err, errQuoteUnavailable) {
			return nil, 5, err
		}
		if len(points) == 0 {
			return nil, 5, err
		}
		last := points[len(points)-1]
		return frozenWindow(points, domain.RealtimePoint{Time: last.SourceTime, SourceTime: last.SourceTime, Price: last.Price}), 5, nil
	}
	now := s.now()
	if domain.ValidRealtime(quote, now, s.native) && len(points) > 1 {
		return points, 5, nil
	}
	price := domain.RealtimePrice(quote, s.native)
	if quote.AsOf.IsZero() || quote.AsOf.After(now.Add(domain.MaxClockSkew)) || price <= 0 || math.IsNaN(price) || math.IsInf(price, 0) {
		return points, 5, nil
	}
	asOf := domain.ClampSourceTime(quote.AsOf, now)
	end := domain.RealtimePoint{Time: asOf, SourceTime: asOf, Price: price}
	// 并发请求返回的旧报价不能让已采集的窗口倒退。
	if len(points) > 0 && points[len(points)-1].SourceTime.After(end.Time) {
		last := points[len(points)-1]
		end = domain.RealtimePoint{Time: last.SourceTime, SourceTime: last.SourceTime, Price: last.Price}
	}
	frozen := frozenWindow(points, end)
	if hasSufficientFrozenSeconds(frozen) {
		return frozen, 5, nil
	}
	minutes, minuteErr := s.GetGoldIntraday(ctx)
	if minuteErr != nil {
		if !errors.Is(minuteErr, errIntradayUnavailable) {
			return nil, 5, minuteErr
		}
		return frozen, 5, nil
	}
	recovered := make([]domain.RealtimePoint, 0, len(minutes))
	for _, p := range minutes {
		price := p.Price
		if !s.native {
			price = p.Price / domain.GramsPerTroyOunce * quote.USDCNY
		}
		if price > 0 && !math.IsNaN(price) && !math.IsInf(price, 0) {
			recovered = append(recovered, domain.RealtimePoint{Time: p.Time, SourceTime: p.Time, Price: price})
		}
	}
	recoveredWindow := recoveredMinuteWindow(recovered, end)
	if preferRecoveredMinutes(frozen, recoveredWindow) {
		return recoveredWindow, 60, nil
	}
	return frozen, 5, nil
}

// recoveredMinuteWindow 在 20 分钟收盘回退窗口内展开 1 分钟分时点。
// 上金所夜盘尾段等低流动性时段若部分分钟无成交（上游仅返回有成交的 K 线），
// 在同盘口间隔不超过 maxMinuteCarryGap 时沿用上一笔真实成交价顺延补齐无成交分钟，
// 同时保留 SourceTime 为原始真实成交时间，不伪造波动、也不跨越休市空档。
func recoveredMinuteWindow(points []domain.RealtimePoint, end domain.RealtimePoint) []domain.RealtimePoint {
	cutoff := end.Time.Add(-RealtimeWindow)
	var carry *domain.RealtimePoint
	actual := make([]domain.RealtimePoint, 0, len(points))
	for _, p := range points {
		if !p.Time.Before(end.Time) {
			break
		}
		if !p.Time.After(cutoff) {
			candidate := p
			carry = &candidate
			continue
		}
		actual = append(actual, p)
	}

	result := make([]domain.RealtimePoint, 0, int(RealtimeWindow/time.Minute)+1)
	appendCarried := func(until time.Time) {
		if len(result) == 0 {
			return
		}
		last := result[len(result)-1]
		for next := last.Time.Add(time.Minute); next.Before(until); next = next.Add(time.Minute) {
			if next.Sub(last.SourceTime) > maxMinuteCarryGap {
				break
			}
			result = append(result, domain.RealtimePoint{
				Time:       next,
				SourceTime: last.SourceTime,
				Price:      last.Price,
			})
		}
	}

	if carry != nil && cutoff.Sub(carry.Time) <= maxMinuteCarryGap {
		result = append(result, domain.RealtimePoint{
			Time:       cutoff,
			SourceTime: carry.SourceTime,
			Price:      carry.Price,
		})
	}
	for _, p := range actual {
		appendCarried(p.Time)
		if len(result) > 0 && result[len(result)-1].Time.Equal(p.Time) {
			result[len(result)-1] = p
			continue
		}
		result = append(result, p)
	}
	appendCarried(end.Time)
	return append(result, end)
}

func realtimeSpan(points []domain.RealtimePoint) time.Duration {
	if len(points) < 2 {
		return 0
	}
	return points[len(points)-1].Time.Sub(points[0].Time)
}

func hasSufficientFrozenSeconds(points []domain.RealtimePoint) bool {
	return len(points) >= minFrozenSecondPoints && realtimeSpan(points) >= minFrozenSecondSpan
}

func preferRecoveredMinutes(frozen, recovered []domain.RealtimePoint) bool {
	if len(recovered) <= 1 {
		return false
	}
	if realtimeSpan(recovered) > realtimeSpan(frozen) {
		return true
	}
	return len(frozen) <= 2 && len(recovered) > len(frozen)
}

func frozenWindow(points []domain.RealtimePoint, end domain.RealtimePoint) []domain.RealtimePoint {
	cutoff := end.Time.Add(-RealtimeWindow)
	result := make([]domain.RealtimePoint, 0, len(points)+1)
	for _, p := range points {
		if !p.Time.Before(cutoff) && p.Time.Before(end.Time) {
			result = append(result, p)
		}
	}
	return append(result, end)
}
