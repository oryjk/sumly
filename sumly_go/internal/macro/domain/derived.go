package domain

import (
	"math"
	"sort"
	"time"
)

// CalcPCEYoY computes core PCE year-over-year percentage change: (PCE[t] / PCE[t-12m] - 1) * 100.
func CalcPCEYoY(pceSeries []Observation) []Observation {
	clean := SanitizeObservations(pceSeries)
	if len(clean) < 13 {
		return []Observation{}
	}
	byDate := make(map[string]float64, len(clean))
	for _, obs := range clean {
		byDate[FormatDate(obs.Date)] = obs.Value
	}
	out := make([]Observation, 0, len(clean))
	for _, obs := range clean {
		prevDate := obs.Date.AddDate(-1, 0, 0)
		prevVal, ok := byDate[FormatDate(prevDate)]
		if !ok || prevVal <= 0 {
			continue
		}
		yoy := (obs.Value/prevVal - 1.0) * 100.0
		if IsFinite(yoy) {
			out = append(out, Observation{Date: obs.Date, Value: RoundTo(yoy, 2)})
		}
	}
	return out
}

// CalcInterestRatio computes FYOINT / FYFR * 100 on matching dates.
func CalcInterestRatio(interestSeries, revenueSeries []Observation) []Observation {
	ints := SanitizeObservations(interestSeries)
	revs := SanitizeObservations(revenueSeries)
	if len(ints) == 0 || len(revs) == 0 {
		return []Observation{}
	}
	revByDate := make(map[string]float64, len(revs))
	for _, r := range revs {
		if r.Value > 0 {
			revByDate[FormatDate(r.Date)] = r.Value
		}
	}
	out := make([]Observation, 0, len(ints))
	for _, in := range ints {
		if in.Value <= 0 {
			continue
		}
		rev, ok := revByDate[FormatDate(in.Date)]
		if !ok || rev <= 0 {
			continue
		}
		ratio := in.Value / rev * 100.0
		if IsFinite(ratio) {
			out = append(out, Observation{Date: in.Date, Value: RoundTo(ratio, 2)})
		}
	}
	return out
}

func scoreIR(v float64) float64 {
	if v < 0 {
		return 0
	}
	switch {
	case v <= 8.0:
		return v / 8.0 * 20.0
	case v <= 12.0:
		return 20.0 + (v-8.0)/4.0*20.0
	case v <= 15.0:
		return 40.0 + (v-12.0)/3.0*15.0
	case v <= 20.0:
		return 55.0 + (v-15.0)/5.0*20.0
	case v <= 25.0:
		return 75.0 + (v-20.0)/5.0*15.0
	default:
		return math.Min(90.0+(v-25.0)/10.0*10.0, 100.0)
	}
}

func scoreDef(v float64) float64 {
	if v < 0 {
		return 0
	}
	switch {
	case v <= 2.0:
		return v / 2.0 * 15.0
	case v <= 3.0:
		return 15.0 + (v-2.0)*15.0
	case v <= 5.0:
		return 30.0 + (v-3.0)/2.0*20.0
	case v <= 7.0:
		return 50.0 + (v-5.0)/2.0*20.0
	case v <= 10.0:
		return 70.0 + (v-7.0)/3.0*20.0
	default:
		return math.Min(90.0+(v-10.0)/5.0*10.0, 100.0)
	}
}

func scoreDebt(v float64) float64 {
	if v < 0 {
		return 0
	}
	switch {
	case v <= 40.0:
		return v / 40.0 * 15.0
	case v <= 60.0:
		return 15.0 + (v-40.0)/20.0*15.0
	case v <= 90.0:
		return 30.0 + (v-60.0)/30.0*20.0
	case v <= 100.0:
		return 50.0 + (v-90.0)/10.0*10.0
	case v <= 120.0:
		return 60.0 + (v-100.0)/20.0*15.0
	case v <= 150.0:
		return 75.0 + (v-120.0)/30.0*17.0
	default:
		return math.Min(92.0+(v-150.0)/50.0*8.0, 100.0)
	}
}

func fiscalStressWeights(irVal float64) (float64, float64, float64) {
	m := 1.0
	if irVal >= 25.0 {
		m = 3.0
	} else if irVal >= 15.0 {
		m = 2.0
	}
	eff := 50.0 * m
	total := eff + 30.0 + 20.0
	return eff / total, 30.0 / total, 20.0 / total
}

// CalcFiscalStress replicates gold-board-backend's non-linear weighted US fiscal stress index (0-100).
func CalcFiscalStress(interestRatioSeries, deficitGDPSeries, debtGDPSeries []Observation) []Observation {
	irByYear := make(map[int]float64)
	for _, obs := range SanitizeObservations(interestRatioSeries) {
		irByYear[obs.Date.Year()] = obs.Value
	}
	defByYear := make(map[int]float64)
	for _, obs := range SanitizeObservations(deficitGDPSeries) {
		defByYear[obs.Date.Year()] = math.Abs(obs.Value)
	}
	debtByYear := make(map[int]float64)
	for _, obs := range SanitizeObservations(debtGDPSeries) {
		debtByYear[obs.Date.Year()] = obs.Value
	}

	years := make([]int, 0, len(irByYear))
	for y := range irByYear {
		if _, okDef := defByYear[y]; okDef {
			if _, okDebt := debtByYear[y]; okDebt {
				years = append(years, y)
			}
		}
	}
	sort.Ints(years)

	out := make([]Observation, 0, len(years))
	for _, y := range years {
		ir := irByYear[y]
		def := defByYear[y]
		debt := debtByYear[y]
		wIR, wDef, wDebt := fiscalStressWeights(ir)
		score := scoreIR(ir)*wIR + scoreDef(def)*wDef + scoreDebt(debt)*wDebt
		if IsFinite(score) {
			out = append(out, Observation{
				Date:  time.Date(y, 1, 1, 0, 0, 0, 0, time.UTC),
				Value: RoundTo(score, 1),
			})
		}
	}
	return out
}

// CalcSMA computes a simple moving average over window observations.
func CalcSMA(series []Observation, window int) []Observation {
	clean := SanitizeObservations(series)
	if window <= 0 || len(clean) < window {
		return []Observation{}
	}
	out := make([]Observation, 0, len(clean)-window+1)
	sum := 0.0
	for i := 0; i < len(clean); i++ {
		sum += clean[i].Value
		if i >= window {
			sum -= clean[i-window].Value
		}
		if i >= window-1 {
			avg := sum / float64(window)
			if IsFinite(avg) {
				out = append(out, Observation{Date: clean[i].Date, Value: RoundTo(avg, 2)})
			}
		}
	}
	return out
}

// CalcGoldMA returns the 200-day simple moving average of gold price.
func CalcGoldMA(goldSeries []Observation) []Observation {
	return CalcSMA(goldSeries, 200)
}

// CalcGoldCNY computes theoretical international gold price in CNY/gram: Gold_USD * DEXCHUS / 31.1035.
func CalcGoldCNY(goldSeries, fxSeries []Observation) []Observation {
	gold := SanitizeObservations(goldSeries)
	fx := SanitizeObservations(fxSeries)
	if len(gold) == 0 || len(fx) == 0 {
		return []Observation{}
	}
	out := make([]Observation, 0, len(gold))
	for _, g := range gold {
		if g.Value <= 0 {
			continue
		}
		rate, ok := ValueOnOrBefore(fx, g.Date)
		if !ok || rate <= 0 {
			continue
		}
		cny := g.Value * rate / GramsPerTroyOz
		if IsFinite(cny) {
			out = append(out, Observation{Date: g.Date, Value: RoundTo(cny, 2)})
		}
	}
	return out
}

// CalcShanghaiPremium computes (SGE_CNY - Intl_CNY) / Intl_CNY * 100.
func CalcShanghaiPremium(sgeSeries, goldSeries, fxSeries []Observation) []Observation {
	sge := SanitizeObservations(sgeSeries)
	gold := SanitizeObservations(goldSeries)
	fx := SanitizeObservations(fxSeries)
	if len(sge) == 0 || len(gold) == 0 || len(fx) == 0 {
		return []Observation{}
	}
	goldByDate := make(map[string]float64, len(gold))
	for _, g := range gold {
		if g.Value > 0 {
			goldByDate[FormatDate(g.Date)] = g.Value
		}
	}
	out := make([]Observation, 0, len(sge))
	for _, s := range sge {
		if s.Value <= 0 {
			continue
		}
		goldUSD, ok := goldByDate[FormatDate(s.Date)]
		if !ok {
			continue
		}
		fxRate, ok := ValueOnOrBefore(fx, s.Date)
		if !ok || fxRate <= 0 {
			continue
		}
		intlCNY := goldUSD * fxRate / GramsPerTroyOz
		if intlCNY <= 0 {
			continue
		}
		premium := (s.Value - intlCNY) / intlCNY * 100.0
		if IsFinite(premium) {
			out = append(out, Observation{Date: s.Date, Value: RoundTo(premium, 2)})
		}
	}
	return out
}

// CalcTreasurySpread computes DGS10 - DGS2 on matching dates.
func CalcTreasurySpread(dgs10Series, dgs2Series []Observation) []Observation {
	s10 := SanitizeObservations(dgs10Series)
	s2 := SanitizeObservations(dgs2Series)
	if len(s10) == 0 || len(s2) == 0 {
		return []Observation{}
	}
	byDate2 := make(map[string]float64, len(s2))
	for _, o := range s2 {
		byDate2[FormatDate(o.Date)] = o.Value
	}
	out := make([]Observation, 0, len(s10))
	for _, o10 := range s10 {
		v2, ok := byDate2[FormatDate(o10.Date)]
		if !ok {
			continue
		}
		spread := o10.Value - v2
		if IsFinite(spread) {
			out = append(out, Observation{Date: o10.Date, Value: RoundTo(spread, 4)})
		}
	}
	return out
}

// CalcRatio computes numerator / denominator on matching dates where denominator > 0.
func CalcRatio(numeratorSeries, denominatorSeries []Observation) []Observation {
	num := SanitizeObservations(numeratorSeries)
	den := SanitizeObservations(denominatorSeries)
	if len(num) == 0 || len(den) == 0 {
		return []Observation{}
	}
	denByDate := make(map[string]float64, len(den))
	for _, o := range den {
		if o.Value > 0 {
			denByDate[FormatDate(o.Date)] = o.Value
		}
	}
	out := make([]Observation, 0, len(num))
	for _, n := range num {
		if n.Value <= 0 {
			continue
		}
		d, ok := denByDate[FormatDate(n.Date)]
		if !ok || d <= 0 {
			continue
		}
		ratio := n.Value / d
		if IsFinite(ratio) {
			out = append(out, Observation{Date: n.Date, Value: RoundTo(ratio, 2)})
		}
	}
	return out
}
