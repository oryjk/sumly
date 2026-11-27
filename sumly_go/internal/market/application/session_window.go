package application

import (
	"context"
	"errors"
	"math"
	"sort"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

const (
	sgeSessionDuration  = 6*time.Hour + 30*time.Minute
	sgeDaySpanDuration  = 17*time.Hour + 30*time.Minute // 09:00 ~ 次日 02:30
	sgeCloseAnchorGrace = 5 * time.Minute
)

var (
	shanghaiZone = loadShanghaiZone()
	newYorkZone  = loadNewYorkZone()
)

func loadShanghaiZone() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}

func loadNewYorkZone() *time.Location {
	if loc, err := time.LoadLocation("America/New_York"); err == nil {
		return loc
	}
	return time.FixedZone("EST", -5*3600)
}

// GetGoldRealtimeWindow 按 mode 返回默认 20 分钟滚动窗、最近交易时段分时或完整当日分时窗口。
// mode 为空或 20m 时完全复用 GetGoldRealtime，保持老版本客户端 100% 向后兼容。
func (s *GoldQuery) GetGoldRealtimeWindow(ctx context.Context, mode domain.RealtimeWindowMode) (domain.GoldWindow, error) {
	return s.getGoldRealtimeWindow(ctx, mode, false)
}

func (s *GoldQuery) getGoldRealtimeWindowForInstrument(ctx context.Context, instrument domain.Instrument, mode domain.RealtimeWindowMode) (domain.GoldWindow, error) {
	return s.getGoldRealtimeWindow(ctx, mode, isDomesticSGEInstrument(instrument))
}

func (s *GoldQuery) getGoldRealtimeWindow(ctx context.Context, mode domain.RealtimeWindowMode, forceDomestic bool) (domain.GoldWindow, error) {
	if mode != domain.RealtimeWindowModeSession && mode != domain.RealtimeWindowModeDay {
		return s.getDefaultRealtimeWindow(ctx)
	}
	return s.getSessionRealtimeWindow(ctx, mode, forceDomestic)
}

func (s *GoldQuery) getDefaultRealtimeWindow(ctx context.Context) (domain.GoldWindow, error) {
	points, interval, err := s.GetGoldRealtime(ctx)
	if err != nil {
		return domain.GoldWindow{}, err
	}
	window := domain.GoldWindow{
		Points:          points,
		IntervalSeconds: interval,
		WindowSeconds:   int(RealtimeWindow.Seconds()),
	}
	if len(points) > 0 {
		window.End = points[len(points)-1].Time
		window.Start = window.End.Add(-RealtimeWindow)
	}
	return window, nil
}

func (s *GoldQuery) getSessionRealtimeWindow(ctx context.Context, mode domain.RealtimeWindowMode, forceDomestic bool) (domain.GoldWindow, error) {
	rawPoints, err := s.store.LoadRealtime(ctx)
	if err != nil {
		return domain.GoldWindow{}, err
	}
	rawPoints = append([]domain.RealtimePoint(nil), rawPoints...)

	quote, quoteErr := s.GetGoldQuote(ctx)
	hasQuote := true
	if quoteErr != nil {
		if !errors.Is(quoteErr, errQuoteUnavailable) {
			return domain.GoldWindow{}, quoteErr
		}
		hasQuote = false
	}

	rawMinutes, minuteErr := s.GetGoldIntraday(ctx)
	hasMinutes := true
	if minuteErr != nil {
		if !errors.Is(minuteErr, errIntradayUnavailable) {
			return domain.GoldWindow{}, minuteErr
		}
		hasMinutes = false
	}

	now := s.now()
	live := hasQuote && domain.ValidRealtime(quote, now, s.native)
	var quotePoint *domain.RealtimePoint
	if hasQuote {
		price := domain.RealtimePrice(quote, s.native)
		if !quote.AsOf.IsZero() && !quote.AsOf.After(now.Add(domain.MaxClockSkew)) && price > 0 && !math.IsNaN(price) && !math.IsInf(price, 0) {
			asOf := domain.ClampSourceTime(quote.AsOf, now)
			quotePoint = &domain.RealtimePoint{Time: asOf, SourceTime: asOf, Price: price}
		}
	}

	realtime := normalizeRealtimeSamples(rawPoints, live)
	var minutes []domain.RealtimePoint
	if hasMinutes {
		minutes = convertSessionMinutes(rawMinutes, quote, hasQuote, s.native)
	}

	domestic := forceDomestic || (s.native && hasQuote && isDomesticSGEQuote(quote))
	if domestic {
		if mode == domain.RealtimeWindowModeDay {
			if window, ok := buildDomesticSGEDayWindow(minutes, realtime, quotePoint, live); ok {
				return window, nil
			}
		} else {
			if window, ok := buildDomesticSGESessionWindow(minutes, realtime, quotePoint, live); ok {
				return window, nil
			}
		}
	} else {
		if mode == domain.RealtimeWindowModeDay {
			if window, ok := buildInternationalDayWindow(minutes, realtime, quotePoint, live); ok {
				return window, nil
			}
		} else {
			if window, ok := buildInternationalSessionWindow(minutes, realtime, quotePoint, live); ok {
				return window, nil
			}
		}
	}

	return buildSessionSecondFallback(rawPoints, minutes, realtime, quotePoint, domestic, live, hasQuote, quoteErr)
}

func isDomesticSGEInstrument(i domain.Instrument) bool {
	return strings.EqualFold(i.Exchange, "SGE") ||
		strings.EqualFold(i.Symbol, "AU9999") ||
		strings.EqualFold(i.Currency, "CNY")
}

func isDomesticSGEQuote(q domain.GoldQuote) bool {
	return strings.EqualFold(q.Symbol, "AU9999") || strings.EqualFold(q.Currency, "CNY")
}

// domesticSGESessionStart 根据北京时间最新点判断所属上金所交易时段起点：
//   - 夜盘（20:00 ~ 23:59 或次日 00:00 ~ 08:59）：对应夜盘开盘 20:00（00:00~08:59 为前一日 20:00）
//   - 日盘（09:00 ~ 19:59）：当日 09:00
func domesticSGESessionStart(end time.Time) time.Time {
	bj := end.In(shanghaiZone)
	y, m, d := bj.Date()
	hour := bj.Hour()
	switch {
	case hour >= 20:
		return time.Date(y, m, d, 20, 0, 0, 0, shanghaiZone)
	case hour < 9:
		prev := bj.AddDate(0, 0, -1)
		py, pm, pd := prev.Date()
		return time.Date(py, pm, pd, 20, 0, 0, 0, shanghaiZone)
	default:
		return time.Date(y, m, d, 9, 0, 0, 0, shanghaiZone)
	}
}

// domesticSGEDayStart 将国内上金所当日的日盘（09:00~15:30）与当晚夜盘（20:00~次日 02:30）归为同一连续自然日：
//   - 北京时间 09:00 ~ 23:59：当日 09:00
//   - 北京时间 00:00 ~ 08:59：前一日 09:00
func domesticSGEDayStart(end time.Time) time.Time {
	bj := end.In(shanghaiZone)
	if bj.Hour() < 9 {
		prev := bj.AddDate(0, 0, -1)
		return time.Date(prev.Year(), prev.Month(), prev.Day(), 9, 0, 0, 0, shanghaiZone)
	}
	return time.Date(bj.Year(), bj.Month(), bj.Day(), 9, 0, 0, 0, shanghaiZone)
}

// internationalDayStart 按美东 18:00 交易日切换点计算国际伦敦金当日开盘时刻（自动适配美国夏/冬令时）。
func internationalDayStart(end time.Time) time.Time {
	ny := end.In(newYorkZone)
	if ny.Hour() < 18 {
		prev := ny.AddDate(0, 0, -1)
		return time.Date(prev.Year(), prev.Month(), prev.Day(), 18, 0, 0, 0, newYorkZone).In(shanghaiZone)
	}
	return time.Date(ny.Year(), ny.Month(), ny.Day(), 18, 0, 0, 0, newYorkZone).In(shanghaiZone)
}

func clampWindowSeconds(seconds int) int {
	if seconds < domain.MinRealtimeWindowSeconds {
		return domain.MinRealtimeWindowSeconds
	}
	if seconds > domain.MaxRealtimeWindowSeconds {
		return domain.MaxRealtimeWindowSeconds
	}
	return seconds
}

func convertSessionMinutes(raw []domain.IntradayPoint, quote domain.GoldQuote, hasQuote, native bool) []domain.RealtimePoint {
	if len(raw) == 0 {
		return nil
	}
	if !native && (!hasQuote || quote.USDCNY <= 0 || math.IsNaN(quote.USDCNY) || math.IsInf(quote.USDCNY, 0)) {
		return nil
	}
	out := make([]domain.RealtimePoint, 0, len(raw))
	for _, p := range raw {
		if p.Time.IsZero() {
			continue
		}
		price := p.Price
		if !native {
			price = p.Price / domain.GramsPerTroyOunce * quote.USDCNY
		}
		if price <= 0 || math.IsNaN(price) || math.IsInf(price, 0) {
			continue
		}
		out = append(out, domain.RealtimePoint{Time: p.Time, SourceTime: p.Time, Price: price})
	}
	return sortAndDeduplicateRealtime(out)
}

func normalizeRealtimeSamples(raw []domain.RealtimePoint, live bool) []domain.RealtimePoint {
	if len(raw) == 0 {
		return nil
	}
	out := make([]domain.RealtimePoint, 0, len(raw))
	for _, p := range raw {
		if p.Price <= 0 || math.IsNaN(p.Price) || math.IsInf(p.Price, 0) {
			continue
		}
		if live {
			if p.Time.IsZero() {
				continue
			}
			src := p.SourceTime
			if src.IsZero() {
				src = p.Time
			}
			out = append(out, domain.RealtimePoint{Time: p.Time, SourceTime: src, Price: p.Price})
			continue
		}
		ts := p.SourceTime
		if ts.IsZero() {
			ts = p.Time
		}
		if ts.IsZero() {
			continue
		}
		out = append(out, domain.RealtimePoint{Time: ts, SourceTime: ts, Price: p.Price})
	}
	return sortAndDeduplicateRealtime(out)
}

func sortAndDeduplicateRealtime(points []domain.RealtimePoint) []domain.RealtimePoint {
	if len(points) <= 1 {
		return points
	}
	sort.SliceStable(points, func(i, j int) bool {
		return points[i].Time.Before(points[j].Time)
	})
	dedup := points[:0]
	for _, p := range points {
		if len(dedup) > 0 && dedup[len(dedup)-1].Time.Equal(p.Time) {
			dedup[len(dedup)-1] = p
			continue
		}
		dedup = append(dedup, p)
	}
	return dedup
}

func latestTailCandidate(realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint) *domain.RealtimePoint {
	var best *domain.RealtimePoint
	if quotePoint != nil {
		cp := *quotePoint
		best = &cp
	}
	if len(realtime) > 0 {
		lastRT := realtime[len(realtime)-1]
		if best == nil || lastRT.Time.After(best.Time) {
			cp := lastRT
			best = &cp
		}
	}
	return best
}

func appendNewerRealtimeTail(base, realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint, maxTime time.Time) []domain.RealtimePoint {
	if len(base) == 0 {
		return base
	}
	result := append([]domain.RealtimePoint(nil), base...)
	lastTime := result[len(result)-1].Time
	lastMinBucket := lastTime.Truncate(time.Minute)

	var bucketed []domain.RealtimePoint
	var sameBucketLatest *domain.RealtimePoint
	for _, p := range realtime {
		if !p.Time.After(lastTime) || p.Time.After(maxTime) {
			continue
		}
		bucket := p.Time.Truncate(time.Minute)
		if !bucket.After(lastMinBucket) {
			candidate := p
			sameBucketLatest = &candidate
			continue
		}
		if len(bucketed) > 0 && bucketed[len(bucketed)-1].Time.Truncate(time.Minute).Equal(bucket) {
			bucketed[len(bucketed)-1] = p
		} else {
			bucketed = append(bucketed, p)
		}
	}
	if len(bucketed) > 0 {
		result = append(result, bucketed...)
	} else if sameBucketLatest != nil {
		result = append(result, *sameBucketLatest)
	}

	if quotePoint != nil && !quotePoint.Time.After(maxTime) {
		last := result[len(result)-1]
		if quotePoint.Time.After(last.Time) {
			if len(result) > len(base) && quotePoint.Time.Truncate(time.Minute).Equal(last.Time.Truncate(time.Minute)) {
				result[len(result)-1] = *quotePoint
			} else {
				result = append(result, *quotePoint)
			}
		} else if quotePoint.Time.Equal(last.Time) {
			result[len(result)-1] = *quotePoint
		}
	}
	return result
}

func buildDomesticSGESessionWindow(minutes, realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint, live bool) (domain.GoldWindow, bool) {
	if len(minutes) == 0 {
		return domain.GoldWindow{}, false
	}
	lastMin := minutes[len(minutes)-1]
	tail := latestTailCandidate(realtime, quotePoint)

	end := lastMin.Time
	mergeTail := false
	if tail != nil && tail.Time.After(lastMin.Time) {
		minSessionStart := domesticSGESessionStart(lastMin.Time)
		tailSessionStart := domesticSGESessionStart(tail.Time)
		if tailSessionStart.Equal(minSessionStart) {
			sessionClose := minSessionStart.Add(sgeSessionDuration)
			if live ||
				tail.Time.Sub(lastMin.Time) <= maxMinuteCarryGap ||
				!tail.Time.After(sessionClose.Add(sgeCloseAnchorGrace)) {
				end = tail.Time
				mergeTail = true
			}
		} else if tailSessionStart.After(minSessionStart) {
			// 已进入新交易时段但分钟快照仍在旧时段：不跨休市拼接，降级回新时段 5 秒样本。
			return domain.GoldWindow{}, false
		}
	}

	sessionStart := domesticSGESessionStart(end)
	sliced := make([]domain.RealtimePoint, 0, len(minutes)+2)
	for _, p := range minutes {
		if !p.Time.Before(sessionStart) && !p.Time.After(end) {
			sliced = append(sliced, p)
		}
	}
	if len(sliced) == 0 {
		return domain.GoldWindow{}, false
	}

	if mergeTail {
		sliced = appendNewerRealtimeTail(sliced, realtime, quotePoint, end)
	} else if quotePoint != nil && quotePoint.Time.Equal(sliced[len(sliced)-1].Time) {
		sliced[len(sliced)-1] = *quotePoint
	}

	actualEnd := sliced[len(sliced)-1].Time
	windowSeconds := clampWindowSeconds(int(actualEnd.Sub(sessionStart).Seconds()))
	return domain.GoldWindow{
		Points:          sliced,
		IntervalSeconds: 60,
		WindowSeconds:   windowSeconds,
		Start:           sessionStart,
		End:             actualEnd,
	}, true
}

func buildInternationalSessionWindow(minutes, realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint, live bool) (domain.GoldWindow, bool) {
	if len(minutes) == 0 {
		return domain.GoldWindow{}, false
	}
	lastMin := minutes[len(minutes)-1]
	tail := latestTailCandidate(realtime, quotePoint)

	combined := minutes
	if tail != nil && tail.Time.After(lastMin.Time) {
		if tail.Time.Sub(lastMin.Time) > domain.SessionGapThreshold {
			// 跨越超过 2 小时的停盘跳空进入新时段：不跨停盘拼接，降级回新时段 5 秒样本。
			return domain.GoldWindow{}, false
		}
		combined = appendNewerRealtimeTail(minutes, realtime, quotePoint, tail.Time)
	} else if quotePoint != nil && quotePoint.Time.Equal(lastMin.Time) {
		combined = append([]domain.RealtimePoint(nil), minutes...)
		combined[len(combined)-1] = *quotePoint
	}

	end := combined[len(combined)-1].Time
	cutoff := end.Add(-domain.InternationalSessionSpan)
	sliced := make([]domain.RealtimePoint, 0, len(combined))
	for _, p := range combined {
		if !p.Time.Before(cutoff) && !p.Time.After(end) {
			sliced = append(sliced, p)
		}
	}
	if len(sliced) == 0 {
		return domain.GoldWindow{}, false
	}

	cutIdx := 0
	for i := 1; i < len(sliced); i++ {
		if sliced[i].Time.Sub(sliced[i-1].Time) > domain.SessionGapThreshold {
			cutIdx = i
		}
	}
	sliced = sliced[cutIdx:]

	start := sliced[0].Time
	actualEnd := sliced[len(sliced)-1].Time
	windowSeconds := clampWindowSeconds(int(actualEnd.Sub(start).Seconds()))
	return domain.GoldWindow{
		Points:          sliced,
		IntervalSeconds: 60,
		WindowSeconds:   windowSeconds,
		Start:           start,
		End:             actualEnd,
	}, true
}

func buildDomesticSGEDayWindow(minutes, realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint, live bool) (domain.GoldWindow, bool) {
	if len(minutes) == 0 {
		return domain.GoldWindow{}, false
	}
	lastMin := minutes[len(minutes)-1]
	tail := latestTailCandidate(realtime, quotePoint)

	end := lastMin.Time
	mergeTail := false
	if tail != nil && tail.Time.After(lastMin.Time) {
		minDayStart := domesticSGEDayStart(lastMin.Time)
		tailDayStart := domesticSGEDayStart(tail.Time)
		if tailDayStart.Equal(minDayStart) {
			dayClose := minDayStart.Add(sgeDaySpanDuration)
			if live ||
				tail.Time.Sub(lastMin.Time) <= maxMinuteCarryGap ||
				!tail.Time.After(dayClose.Add(sgeCloseAnchorGrace)) {
				end = tail.Time
				mergeTail = true
			}
		} else if tailDayStart.After(minDayStart) {
			return domain.GoldWindow{}, false
		}
	}

	dayStart := domesticSGEDayStart(end)
	sliced := make([]domain.RealtimePoint, 0, len(minutes)+2)
	for _, p := range minutes {
		if !p.Time.Before(dayStart) && !p.Time.After(end) {
			sliced = append(sliced, p)
		}
	}
	if len(sliced) == 0 {
		return domain.GoldWindow{}, false
	}

	if mergeTail {
		sliced = appendNewerRealtimeTail(sliced, realtime, quotePoint, end)
	} else if quotePoint != nil && quotePoint.Time.Equal(sliced[len(sliced)-1].Time) {
		sliced[len(sliced)-1] = *quotePoint
	}

	actualEnd := sliced[len(sliced)-1].Time
	windowSeconds := clampWindowSeconds(int(actualEnd.Sub(dayStart).Seconds()))
	return domain.GoldWindow{
		Points:          sliced,
		IntervalSeconds: 60,
		WindowSeconds:   windowSeconds,
		Start:           dayStart,
		End:             actualEnd,
	}, true
}

func buildInternationalDayWindow(minutes, realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint, live bool) (domain.GoldWindow, bool) {
	if len(minutes) == 0 {
		return domain.GoldWindow{}, false
	}
	lastMin := minutes[len(minutes)-1]
	tail := latestTailCandidate(realtime, quotePoint)

	combined := minutes
	if tail != nil && tail.Time.After(lastMin.Time) {
		if tail.Time.Sub(lastMin.Time) > domain.SessionGapThreshold {
			return domain.GoldWindow{}, false
		}
		combined = appendNewerRealtimeTail(minutes, realtime, quotePoint, tail.Time)
	} else if quotePoint != nil && quotePoint.Time.Equal(lastMin.Time) {
		combined = append([]domain.RealtimePoint(nil), minutes...)
		combined[len(combined)-1] = *quotePoint
	}

	end := combined[len(combined)-1].Time
	cutoff := internationalDayStart(end)
	minCutoff := end.Add(-domain.InternationalDaySpan)
	if minCutoff.After(cutoff) {
		cutoff = minCutoff
	}

	sliced := make([]domain.RealtimePoint, 0, len(combined))
	for _, p := range combined {
		if !p.Time.Before(cutoff) && !p.Time.After(end) {
			sliced = append(sliced, p)
		}
	}
	if len(sliced) == 0 {
		return domain.GoldWindow{}, false
	}

	cutIdx := 0
	for i := 1; i < len(sliced); i++ {
		if sliced[i].Time.Sub(sliced[i-1].Time) > domain.SessionGapThreshold {
			cutIdx = i
		}
	}
	sliced = sliced[cutIdx:]

	start := sliced[0].Time
	actualEnd := sliced[len(sliced)-1].Time
	windowSeconds := clampWindowSeconds(int(actualEnd.Sub(start).Seconds()))
	return domain.GoldWindow{
		Points:          sliced,
		IntervalSeconds: 60,
		WindowSeconds:   windowSeconds,
		Start:           start,
		End:             actualEnd,
	}, true
}

func buildSessionSecondFallback(rawPoints, minutes, realtime []domain.RealtimePoint, quotePoint *domain.RealtimePoint, domestic, live, hasQuote bool, quoteErr error) (domain.GoldWindow, error) {
	if !hasQuote && len(rawPoints) == 0 {
		return domain.GoldWindow{}, quoteErr
	}

	tail := latestTailCandidate(realtime, quotePoint)
	if tail == nil {
		if len(rawPoints) == 0 {
			return domain.GoldWindow{
				Points:          []domain.RealtimePoint{},
				IntervalSeconds: 5,
				WindowSeconds:   domain.MinRealtimeWindowSeconds,
			}, nil
		}
		last := rawPoints[len(rawPoints)-1]
		end := domain.RealtimePoint{Time: last.SourceTime, SourceTime: last.SourceTime, Price: last.Price}
		if end.Time.IsZero() {
			end = last
		}
		pts := frozenWindow(rawPoints, end)
		return domain.GoldWindow{
			Points:          pts,
			IntervalSeconds: 5,
			WindowSeconds:   domain.MinRealtimeWindowSeconds,
			Start:           end.Time.Add(-RealtimeWindow),
			End:             end.Time,
		}, nil
	}

	// 过滤掉旧交易时段的 5 秒样本，避免在刚开盘分钟线尚未落地时跨休市拼接。
	candidates := rawPoints
	if domestic {
		sessionStart := domesticSGESessionStart(tail.Time)
		filtered := make([]domain.RealtimePoint, 0, len(rawPoints))
		for _, p := range rawPoints {
			if !p.Time.Before(sessionStart) {
				filtered = append(filtered, p)
			}
		}
		candidates = filtered
	} else if len(minutes) > 0 {
		lastMinTime := minutes[len(minutes)-1].Time
		if tail.Time.Sub(lastMinTime) > domain.SessionGapThreshold {
			filtered := make([]domain.RealtimePoint, 0, len(rawPoints))
			for _, p := range rawPoints {
				if p.Time.After(lastMinTime) && tail.Time.Sub(p.Time) <= domain.SessionGapThreshold {
					filtered = append(filtered, p)
				}
			}
			candidates = filtered
		}
	}

	var points []domain.RealtimePoint
	if live && len(candidates) > 1 {
		points = append([]domain.RealtimePoint(nil), candidates...)
		if tail.Time.After(points[len(points)-1].Time) {
			points = append(points, *tail)
		}
	} else {
		points = frozenWindow(candidates, *tail)
	}

	end := points[len(points)-1].Time
	start := end.Add(-RealtimeWindow)
	if len(points) > 0 && points[0].Time.Before(start) {
		start = points[0].Time
	}
	windowSeconds := clampWindowSeconds(int(end.Sub(start).Seconds()))
	return domain.GoldWindow{
		Points:          points,
		IntervalSeconds: 5,
		WindowSeconds:   windowSeconds,
		Start:           start,
		End:             end,
	}, nil
}
