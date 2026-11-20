package domain

import (
	"fmt"
	"math"
	"sort"
	"time"
)

const (
	LevelFreezing = "freezing"
	LevelCool     = "cool"
	LevelNeutral  = "neutral"
	LevelWarm     = "warm"
	LevelHot      = "hot"

	RegimeTailwind = "tailwind"
	RegimeNeutral  = "neutral"
	RegimeHeadwind = "headwind"

	DimTrendMomentum   = "trend_momentum"
	DimPositioning     = "positioning"
	DimDomesticPremium = "domestic_premium"
	DimFlowCrossAsset  = "flow_cross_asset"
	DimMacroPulse      = "macro_pulse"
)

const DefaultDisclaimer = "以上数据与黄金温度模型基于公开宏观及市场历史分位自动计算，仅供学习与参考，不构成任何投资建议。"

type TemperatureDimension struct {
	Key       string
	Name      string
	Weight    float64
	Score     float64
	Available bool
	Status    string
	Summary   string
	Metrics   map[string]float64
}

type MacroRegime struct {
	Score   float64
	Regime  string
	Label   string
	Summary string
}

type ActionGuide struct {
	Signal              string
	Title               string
	Summary             string
	DCAMultiplier       float64
	DCALabel            string
	MA200DeviationPct   *float64
	MA200Note           string
	DomesticPremiumPct  *float64
	DomesticPremiumNote string
	Disclaimer          string
}

type TemperatureSnapshot struct {
	AsOf            string
	ModelVersion    string
	Degraded        bool
	MissingFactors  []string
	Score           float64
	Level           string
	LevelLabel      string
	Change1D        *float64
	Change5D        *float64
	VolatilityAlert bool
	VolatilityNote  string
	MacroRegime     MacroRegime
	ActionGuide     ActionGuide
	Dimensions      []TemperatureDimension
}

type TemperatureDailyPoint struct {
	Date           time.Time
	Score          float64
	Level          string
	Degraded       bool
	MissingFactors []string
	GoldPriceUSD   *float64
	Snapshot       *TemperatureSnapshot
}

type TemperatureInputs struct {
	Gold            []Observation
	Silver          []Observation
	GoldSilverRatio []Observation
	Cot             []CotObservation
	ShanghaiPremium []Observation
	GLDTonnes       []Observation
	GLDPrice        []Observation
	DFII10          []Observation
	DTWEXBGS        []Observation
	GVZCLS          []Observation
	DebtToGDP       []Observation
	FiscalStress    []Observation
	CBGoldNet       []Observation
	USDReserveShare []Observation
}

type dimensionSpec struct {
	key    string
	name   string
	weight float64
}

var temperatureDimensions = []dimensionSpec{
	{key: DimTrendMomentum, name: "趋势与动量", weight: 0.30},
	{key: DimPositioning, name: "交易拥挤度", weight: 0.25},
	{key: DimDomesticPremium, name: "国内溢价热度", weight: 0.15},
	{key: DimFlowCrossAsset, name: "资金与跨资产", weight: 0.15},
	{key: DimMacroPulse, name: "短期宏观脉冲", weight: 0.15},
}

func LevelForScore(score float64) (string, string) {
	switch {
	case score < 20:
		return LevelFreezing, "极冷低迷"
	case score < 40:
		return LevelCool, "偏冷蓄势"
	case score < 60:
		return LevelNeutral, "温和中性"
	case score < 80:
		return LevelWarm, "偏热活跃"
	default:
		return LevelHot, "极度火热"
	}
}

func EmptyTemperatureSnapshot() TemperatureSnapshot {
	dims := make([]TemperatureDimension, 0, len(temperatureDimensions))
	missing := make([]string, 0, len(temperatureDimensions))
	for _, spec := range temperatureDimensions {
		missing = append(missing, spec.key)
		dims = append(dims, TemperatureDimension{
			Key:       spec.key,
			Name:      spec.name,
			Weight:    spec.weight,
			Score:     50,
			Available: false,
			Status:    "unavailable",
			Summary:   "暂无足够历史数据，等待后台同步完成",
			Metrics:   map[string]float64{},
		})
	}
	regime := MacroRegime{
		Score:   50,
		Regime:  RegimeNeutral,
		Label:   "宏观中性",
		Summary: "长期宏观指标尚未同步完成，暂按中性底座处理。",
	}
	guide := buildActionGuide(regime, LevelNeutral, 50, nil, nil, false)
	return TemperatureSnapshot{
		AsOf:            "",
		ModelVersion:    ModelVersionV1,
		Degraded:        true,
		MissingFactors:  missing,
		Score:           50,
		Level:           LevelNeutral,
		LevelLabel:      "温和中性",
		VolatilityAlert: false,
		VolatilityNote:  "波动率指标尚未同步，暂无法评估极端波动风险。",
		MacroRegime:     regime,
		ActionGuide:     guide,
		Dimensions:      dims,
	}
}

// ComputeTemperature computes the latest snapshot and daily historical temperature series.
func ComputeTemperature(inputs TemperatureInputs) (TemperatureSnapshot, []TemperatureDailyPoint) {
	gold := SanitizeObservations(inputs.Gold)
	if len(gold) == 0 {
		return EmptyTemperatureSnapshot(), []TemperatureDailyPoint{}
	}

	silver := SanitizeObservations(inputs.Silver)
	gsRatio := SanitizeObservations(inputs.GoldSilverRatio)
	if len(gsRatio) == 0 && len(silver) > 0 {
		gsRatio = CalcRatio(gold, silver)
	}
	cot := SanitizeCotObservations(inputs.Cot)
	shPremium := SanitizeObservations(inputs.ShanghaiPremium)
	gld := SanitizeObservations(inputs.GLDTonnes)
	gldPrice := SanitizeObservations(inputs.GLDPrice)
	dfii10 := SanitizeObservations(inputs.DFII10)
	dtwex := SanitizeObservations(inputs.DTWEXBGS)
	gvz := SanitizeObservations(inputs.GVZCLS)
	debtGDP := SanitizeObservations(inputs.DebtToGDP)
	fiscalStress := SanitizeObservations(inputs.FiscalStress)
	cbGoldNet := SanitizeObservations(inputs.CBGoldNet)
	usdReserve := SanitizeObservations(inputs.USDReserveShare)

	// Precompute trend & momentum arrays aligned with gold dates.
	n := len(gold)
	ma20 := computeRollingMean(gold, 20)
	ma60 := computeRollingMean(gold, 60)
	ma200 := computeRollingMean(gold, 200)
	rsi14 := computeRSI14(gold)

	dev200 := make([]float64, n)
	hasDev200 := make([]bool, n)
	for i := 0; i < n; i++ {
		if !math.IsNaN(ma200[i]) && ma200[i] > 0 {
			dev := (gold[i].Value - ma200[i]) / ma200[i] * 100.0
			if IsFinite(dev) {
				dev200[i] = dev
				hasDev200[i] = true
			}
		}
	}
	dev200Pct := rollingPercentilesSparse(dev200, hasDev200, RollingWindow3Y, MinRollingPoints)

	// Precompute COT mm_net / open_interest aligned to gold trading days via forward fill.
	cotRatioSeries := make([]Observation, 0, len(cot))
	cotByDate := make([]CotObservation, 0, len(cot))
	for _, c := range cot {
		if c.OpenInterest > 0 {
			cotRatioSeries = append(cotRatioSeries, Observation{Date: c.Date, Value: c.MMNet / c.OpenInterest * 100.0})
			cotByDate = append(cotByDate, c)
		}
	}
	cotAlignedVal := make([]float64, n)
	cotAlignedOK := make([]bool, n)
	cotAlignedObs := make([]*CotObservation, n)
	for i, g := range gold {
		idx := searchLastOnOrBeforeCot(cotByDate, g.Date)
		if idx >= 0 {
			// Avoid stale forward-fill older than 45 days.
			if g.Date.Sub(cotByDate[idx].Date) <= 45*24*time.Hour {
				cotAlignedVal[i] = cotRatioSeries[idx].Value
				cotAlignedOK[i] = true
				cCopy := cotByDate[idx]
				cotAlignedObs[i] = &cCopy
			}
		}
	}
	cotPct := rollingPercentilesSparse(cotAlignedVal, cotAlignedOK, RollingWindow3Y, MinRollingPoints)

	// Precompute Shanghai Premium rolling percentile aligned to gold dates (forward fill up to 10 days).
	shVal, shOK := alignSeries(gold, shPremium, 10)
	shPct := rollingPercentilesSparse(shVal, shOK, RollingWindow3Y, MinRollingPoints)

	// Precompute Flow (GLD tonnes preferred, fallback to GLD_PRICE) 20-trading-day pct change.
	flowSeries := gld
	usedGLDPriceFallback := false
	if len(flowSeries) < 21+MinRollingPoints && len(gldPrice) > len(flowSeries) {
		flowSeries = gldPrice
		usedGLDPriceFallback = true
	}
	gldROC20Series := computePctChange(flowSeries, 20)
	gldROCVal, gldROCOK := alignSeries(gold, gldROC20Series, 10)
	gldROCPct := rollingPercentilesSparse(gldROCVal, gldROCOK, RollingWindow3Y, MinRollingPoints)

	// Precompute Gold/Silver ratio 60-trading-day change (inverse percentile).
	gsChg60Series := computeDiff(gsRatio, 60)
	gsVal, gsOK := alignSeries(gold, gsRatio, 10)
	gsChgVal, gsChgOK := alignSeries(gold, gsChg60Series, 10)
	gsChgPct := rollingPercentilesSparse(gsChgVal, gsChgOK, RollingWindow3Y, MinRollingPoints)

	// Precompute Macro pulse: DFII10 20d change (inverse) & DTWEXBGS 20d change (inverse).
	dfiiChg20Series := computeDiff(dfii10, 20)
	dfiiChgVal, dfiiChgOK := alignSeries(gold, dfiiChg20Series, 10)
	dfiiChgPct := rollingPercentilesSparse(dfiiChgVal, dfiiChgOK, RollingWindow3Y, MinRollingPoints)

	dtwexChg20Series := computeDiff(dtwex, 20)
	dtwexChgVal, dtwexChgOK := alignSeries(gold, dtwexChg20Series, 10)
	dtwexChgPct := rollingPercentilesSparse(dtwexChgVal, dtwexChgOK, RollingWindow3Y, MinRollingPoints)

	// Precompute GVZ rolling percentile for volatility safety valve.
	gvzVal, gvzOK := alignSeries(gold, gvz, 10)
	gvzPct := rollingPercentilesSparse(gvzVal, gvzOK, RollingWindow3Y, MinRollingPoints)

	history := make([]TemperatureDailyPoint, 0, n)
	for i := 0; i < n; i++ {
		g := gold[i]
		dims := make([]TemperatureDimension, 0, len(temperatureDimensions))

		// 1. trend_momentum
		{
			metrics := map[string]float64{"gold_price_usd": RoundTo(g.Value, 2)}
			if !math.IsNaN(ma20[i]) {
				metrics["ma20"] = RoundTo(ma20[i], 2)
			}
			if !math.IsNaN(ma60[i]) {
				metrics["ma60"] = RoundTo(ma60[i], 2)
			}
			if !math.IsNaN(ma200[i]) {
				metrics["ma200"] = RoundTo(ma200[i], 2)
			}
			if hasDev200[i] {
				metrics["ma200_deviation_pct"] = RoundTo(dev200[i], 2)
			}
			if !math.IsNaN(rsi14[i]) {
				metrics["rsi_14"] = RoundTo(rsi14[i], 1)
			}
			hasDev := !math.IsNaN(dev200Pct[i])
			hasRSI := !math.IsNaN(rsi14[i])
			var score float64
			avail := false
			switch {
			case hasDev && hasRSI:
				score = 0.70*dev200Pct[i] + 0.30*rsi14[i]
				avail = true
			case hasDev:
				score = dev200Pct[i]
				avail = true
			case hasRSI:
				score = rsi14[i]
				avail = true
			}
			dims = append(dims, buildDimension(temperatureDimensions[0], score, avail, metrics))
		}

		// 2. positioning
		{
			metrics := map[string]float64{}
			avail := !math.IsNaN(cotPct[i])
			score := 50.0
			if cotAlignedObs[i] != nil {
				metrics["mm_net"] = RoundTo(cotAlignedObs[i].MMNet, 0)
				metrics["open_interest"] = RoundTo(cotAlignedObs[i].OpenInterest, 0)
				metrics["mm_net_ratio_pct"] = RoundTo(cotAlignedVal[i], 2)
			}
			if avail {
				score = cotPct[i]
			}
			dims = append(dims, buildDimension(temperatureDimensions[1], score, avail, metrics))
		}

		// 3. domestic_premium
		{
			metrics := map[string]float64{}
			avail := !math.IsNaN(shPct[i])
			score := 50.0
			if shOK[i] {
				metrics["shanghai_premium_pct"] = RoundTo(shVal[i], 2)
			}
			if avail {
				score = shPct[i]
			}
			dims = append(dims, buildDimension(temperatureDimensions[2], score, avail, metrics))
		}

		// 4. flow_cross_asset
		{
			metrics := map[string]float64{}
			if gldROCOK[i] {
				metrics["gld_20d_change_pct"] = RoundTo(gldROCVal[i], 2)
			}
			if gsOK[i] {
				metrics["gold_silver_ratio"] = RoundTo(gsVal[i], 2)
			}
			if gsChgOK[i] {
				metrics["gold_silver_60d_change"] = RoundTo(gsChgVal[i], 2)
			}
			if usedGLDPriceFallback {
				metrics["gld_fallback_price"] = 1
			}
			hasGLD := !math.IsNaN(gldROCPct[i])
			hasGS := !math.IsNaN(gsChgPct[i])
			var score float64
			avail := false
			switch {
			case hasGLD && hasGS:
				score = 0.50*gldROCPct[i] + 0.50*(100.0-gsChgPct[i])
				avail = true
			case hasGLD:
				score = gldROCPct[i]
				avail = true
			case hasGS:
				score = 100.0 - gsChgPct[i]
				avail = true
			}
			dims = append(dims, buildDimension(temperatureDimensions[3], score, avail, metrics))
		}

		// 5. macro_pulse
		{
			metrics := map[string]float64{}
			if dfiiChgOK[i] {
				metrics["dfii10_20d_change"] = RoundTo(dfiiChgVal[i], 3)
			}
			if dtwexChgOK[i] {
				metrics["dtwexbgs_20d_change"] = RoundTo(dtwexChgVal[i], 2)
			}
			hasDFII := !math.IsNaN(dfiiChgPct[i])
			hasDTWEX := !math.IsNaN(dtwexChgPct[i])
			var score float64
			avail := false
			switch {
			case hasDFII && hasDTWEX:
				score = 0.50*(100.0-dfiiChgPct[i]) + 0.50*(100.0-dtwexChgPct[i])
				avail = true
			case hasDFII:
				score = 100.0 - dfiiChgPct[i]
				avail = true
			case hasDTWEX:
				score = 100.0 - dtwexChgPct[i]
				avail = true
			}
			dims = append(dims, buildDimension(temperatureDimensions[4], score, avail, metrics))
		}

		totalScore, missing, degraded := combineDimensions(dims)
		if len(missing) == len(dims) {
			// Skip earliest rows where no dimension has enough history yet.
			continue
		}
		level, levelLabel := LevelForScore(totalScore)
		price := RoundTo(g.Value, 2)

		var snap *TemperatureSnapshot
		if i == n-1 {
			volAlert := false
			volNote := "黄金隐含波动率处于常态区间，暂无极端波动预警。"
			if !math.IsNaN(gvzPct[i]) {
				if gvzPct[i] > 85.0 {
					volAlert = true
					volNote = fmt.Sprintf("黄金隐含波动率（GVZ=%.1f）处于近 3 年 %.0f%% 极端高位，短期剧烈震荡风险上升，建议控制单笔仓位、拉长分批节奏。", gvzVal[i], gvzPct[i])
				} else {
					volNote = fmt.Sprintf("黄金隐含波动率（GVZ=%.1f）处于近 3 年 %.0f%% 分位，波动在可控区间内。", gvzVal[i], gvzPct[i])
				}
			} else if gvzOK[i] {
				volNote = fmt.Sprintf("当前 GVZ=%.1f，历史样本积累中，暂未触发极端波动预警。", gvzVal[i])
			} else {
				volNote = "暂缺 GVZ 波动率数据，请结合仓位控制短期波动风险。"
			}

			regime := computeMacroRegime(g.Date, debtGDP, fiscalStress, cbGoldNet, usdReserve, dfii10)
			var devPtr *float64
			if hasDev200[i] {
				v := RoundTo(dev200[i], 2)
				devPtr = &v
			}
			var shPtr *float64
			if shOK[i] {
				v := RoundTo(shVal[i], 2)
				shPtr = &v
			}
			guide := buildActionGuide(regime, level, totalScore, devPtr, shPtr, volAlert)

			s := TemperatureSnapshot{
				AsOf:            FormatDate(g.Date),
				ModelVersion:    ModelVersionV1,
				Degraded:        degraded,
				MissingFactors:  missing,
				Score:           totalScore,
				Level:           level,
				LevelLabel:      levelLabel,
				VolatilityAlert: volAlert,
				VolatilityNote:  volNote,
				MacroRegime:     regime,
				ActionGuide:     guide,
				Dimensions:      dims,
			}
			snap = &s
		}

		history = append(history, TemperatureDailyPoint{
			Date:           g.Date,
			Score:          totalScore,
			Level:          level,
			Degraded:       degraded,
			MissingFactors: missing,
			GoldPriceUSD:   &price,
			Snapshot:       snap,
		})
	}

	if len(history) == 0 {
		// Gold exists but too short to compute even RSI(14); return degraded latest snapshot on latest gold date.
		empty := EmptyTemperatureSnapshot()
		empty.AsOf = FormatDate(gold[n-1].Date)
		empty.MacroRegime = computeMacroRegime(gold[n-1].Date, debtGDP, fiscalStress, cbGoldNet, usdReserve, dfii10)
		empty.ActionGuide = buildActionGuide(empty.MacroRegime, empty.Level, empty.Score, nil, nil, false)
		return empty, []TemperatureDailyPoint{}
	}

	latestIdx := len(history) - 1
	latestPoint := &history[latestIdx]
	var latest TemperatureSnapshot
	if latestPoint.Snapshot != nil {
		latest = *latestPoint.Snapshot
	} else {
		// In case the very last gold point was skipped (shouldn't happen if earlier points succeeded), build from latestPoint.
		latest = EmptyTemperatureSnapshot()
		latest.AsOf = FormatDate(latestPoint.Date)
		latest.Score = latestPoint.Score
		latest.Level, latest.LevelLabel = LevelForScore(latestPoint.Score)
		latest.Degraded = latestPoint.Degraded
		latest.MissingFactors = latestPoint.MissingFactors
	}

	if latestIdx >= 1 {
		c1 := RoundTo(history[latestIdx].Score-history[latestIdx-1].Score, 1)
		latest.Change1D = &c1
	}
	if latestIdx >= 5 {
		c5 := RoundTo(history[latestIdx].Score-history[latestIdx-5].Score, 1)
		latest.Change5D = &c5
	}
	latestCopy := latest
	history[latestIdx].Snapshot = &latestCopy

	return latest, history
}

func buildDimension(spec dimensionSpec, score float64, available bool, metrics map[string]float64) TemperatureDimension {
	if metrics == nil {
		metrics = map[string]float64{}
	}
	if !available || !IsFinite(score) {
		return TemperatureDimension{
			Key:       spec.key,
			Name:      spec.name,
			Weight:    spec.weight,
			Score:     50,
			Available: false,
			Status:    "unavailable",
			Summary:   "该维度历史样本不足或暂未同步，已自动降级并按其余维度重分配权重",
			Metrics:   metrics,
		}
	}
	clamped := RoundTo(math.Max(0, math.Min(100, score)), 1)
	lvl, label := LevelForScore(clamped)
	return TemperatureDimension{
		Key:       spec.key,
		Name:      spec.name,
		Weight:    spec.weight,
		Score:     clamped,
		Available: true,
		Status:    lvl,
		Summary:   dimensionSummary(spec.key, clamped, label, metrics),
		Metrics:   metrics,
	}
}

func dimensionSummary(key string, score float64, label string, metrics map[string]float64) string {
	switch key {
	case DimTrendMomentum:
		if dev, ok := metrics["ma200_deviation_pct"]; ok {
			return fmt.Sprintf("金价较 200 日年线偏离 %+.1f%%，动量读数 %.1f（%s）", dev, score, label)
		}
		return fmt.Sprintf("短中期价格动量读数 %.1f（%s）", score, label)
	case DimPositioning:
		if ratio, ok := metrics["mm_net_ratio_pct"]; ok {
			return fmt.Sprintf("CFTC 管理基金净多头占总持仓 %.1f%%，拥挤度 %.1f（%s）", ratio, score, label)
		}
		return fmt.Sprintf("期货持仓拥挤度读数 %.1f（%s）", score, label)
	case DimDomesticPremium:
		if prem, ok := metrics["shanghai_premium_pct"]; ok {
			return fmt.Sprintf("上海金相对国际折算价溢价 %+.2f%%，热度 %.1f（%s）", prem, score, label)
		}
		return fmt.Sprintf("国内现货溢价热度 %.1f（%s）", score, label)
	case DimFlowCrossAsset:
		return fmt.Sprintf("黄金 ETF 资金流与金银比扩散综合读数 %.1f（%s）", score, label)
	case DimMacroPulse:
		return fmt.Sprintf("实际利率与美元 20 日脉冲综合读数 %.1f（%s）", score, label)
	default:
		return fmt.Sprintf("维度读数 %.1f（%s）", score, label)
	}
}

func combineDimensions(dims []TemperatureDimension) (float64, []string, bool) {
	weightSum := 0.0
	weightedScore := 0.0
	missing := make([]string, 0)
	for _, d := range dims {
		if d.Available && IsFinite(d.Score) {
			weightSum += d.Weight
			weightedScore += d.Weight * d.Score
		} else {
			missing = append(missing, d.Key)
		}
	}
	if weightSum <= 0 {
		return 50.0, missing, true
	}
	score := RoundTo(math.Max(0, math.Min(100, weightedScore/weightSum)), 1)
	return score, missing, len(missing) > 0
}

func computeMacroRegime(
	asOf time.Time,
	debtGDP, fiscalStress, cbGoldNet, usdReserve, dfii10 []Observation,
) MacroRegime {
	type pillar struct {
		weight float64
		score  float64
		ok     bool
	}
	pillars := make([]pillar, 0, 5)

	// 1. Debt/GDP (higher => stronger gold tailwind)
	if v, ok := ValueOnOrBefore(debtGDP, asOf); ok {
		s := linearClamp(v, 50, 140, 15, 95)
		pillars = append(pillars, pillar{weight: 0.20, score: s, ok: true})
	}
	// 2. Fiscal stress (already 0-100)
	if v, ok := ValueOnOrBefore(fiscalStress, asOf); ok {
		s := math.Max(0, math.Min(100, v))
		pillars = append(pillars, pillar{weight: 0.25, score: s, ok: true})
	}
	// 3. Central bank net gold buying (tons/year)
	if v, ok := ValueOnOrBefore(cbGoldNet, asOf); ok {
		s := linearClamp(v, 100, 1100, 15, 95)
		pillars = append(pillars, pillar{weight: 0.20, score: s, ok: true})
	}
	// 4. USD reserve share level + 3y trend (lower & falling => stronger gold tailwind)
	if v, ok := ValueOnOrBefore(usdReserve, asOf); ok {
		levelScore := linearClamp(72-v, 0, 18, 15, 85)
		trendAdj := 0.0
		if prev, okPrev := ValueOnOrBefore(usdReserve, asOf.AddDate(-3, 0, 0)); okPrev {
			// Dropping 2 percentage points over 3y adds +10
			trendAdj = math.Max(-15, math.Min(15, (prev-v)*5.0))
		}
		s := math.Max(0, math.Min(100, levelScore+trendAdj))
		pillars = append(pillars, pillar{weight: 0.15, score: s, ok: true})
	}
	// 5. 10Y real yield level (lower => stronger gold tailwind)
	if v, ok := ValueOnOrBefore(dfii10, asOf); ok {
		// -1% -> 95, 0% -> 80, 1% -> 62, 2% -> 42, 3% -> 20
		s := linearClamp(3.2-v, 0, 4.2, 15, 95)
		pillars = append(pillars, pillar{weight: 0.20, score: s, ok: true})
	}

	if len(pillars) == 0 {
		return MacroRegime{
			Score:   50,
			Regime:  RegimeNeutral,
			Label:   "宏观中性",
			Summary: "长期宏观指标数据不足，暂按中性底座评估。",
		}
	}

	wSum := 0.0
	sSum := 0.0
	for _, p := range pillars {
		wSum += p.weight
		sSum += p.weight * p.score
	}
	score := RoundTo(sSum/wSum, 1)

	switch {
	case score >= 60:
		return MacroRegime{
			Score:   score,
			Regime:  RegimeTailwind,
			Label:   "长期宏观顺风",
			Summary: "美债扩张与财政压力偏高、央行购金或去美元化趋势提供长期支撑，黄金具备较强中长期配置底座。",
		}
	case score >= 40:
		return MacroRegime{
			Score:   score,
			Regime:  RegimeNeutral,
			Label:   "宏观中性",
			Summary: "高实际利率压制与债务/央行购金支撑相互拉锯，黄金长逻辑中性偏震荡，更宜重节奏轻追涨。",
		}
	default:
		return MacroRegime{
			Score:   score,
			Regime:  RegimeHeadwind,
			Label:   "长期宏观逆风",
			Summary: "实际利率偏高且财政/去美元化驱动偏弱，黄金长期顺风不足，建议降低定投系数并严控追高。",
		}
	}
}

func buildActionGuide(
	regime MacroRegime,
	level string,
	score float64,
	ma200DevPct *float64,
	domesticPremiumPct *float64,
	volAlert bool,
) ActionGuide {
	type guideRule struct {
		signal     string
		title      string
		summary    string
		multiplier float64
		dcaLabel   string
	}

	var rule guideRule
	headwind := regime.Regime == RegimeHeadwind

	switch level {
	case LevelFreezing:
		if headwind {
			rule = guideRule{
				signal:     "accumulate",
				title:      "冰点分批试探",
				summary:    "市场情绪极冷但长期宏观偏逆风，可小幅提高定投系数分批低吸，不宜一次性重仓。",
				multiplier: 1.2,
				dcaLabel:   "适度加配 1.2x",
			}
		} else {
			rule = guideRule{
				signal:     "strong_accumulate",
				title:      "极冷区间 · 黄金击球区",
				summary:    "短期情绪极度低迷而宏观底座稳健，历史上赔率较优，适合提高定投系数积极分批收集筹码。",
				multiplier: 1.5,
				dcaLabel:   "加速定投 1.5x",
			}
		}
	case LevelCool:
		if headwind {
			rule = guideRule{
				signal:     "hold_dca",
				title:      "偏冷蓄势 · 常规分批",
				summary:    "黄金温度偏低具备一定安全边际，但宏观顺风偏弱，维持标准定投节奏即可。",
				multiplier: 1.0,
				dcaLabel:   "标准定投 1.0x",
			}
		} else {
			rule = guideRule{
				signal:     "accumulate",
				title:      "偏冷蓄势 · 逢低加配",
				summary:    "市场情绪尚未拥挤且长期宏观偏暖，适合略高于常规的节奏稳步定投或逢回调加仓。",
				multiplier: 1.2,
				dcaLabel:   "偏冷加配 1.2x",
			}
		}
	case LevelNeutral:
		if headwind {
			rule = guideRule{
				signal:     "cautious",
				title:      "温度中性 · 逆风减配",
				summary:    "市场冷热适中但宏观底座偏逆风，建议下调定投系数，耐心等待更有性价比的回踩。",
				multiplier: 0.5,
				dcaLabel:   "逆风减半 0.5x",
			}
		} else {
			rule = guideRule{
				signal:     "hold_dca",
				title:      "温和中性 · 保持定投",
				summary:    "当前市场既不恐慌也不狂热，按原计划标准节奏定投持有，避免频繁择时折腾。",
				multiplier: 1.0,
				dcaLabel:   "标准定投 1.0x",
			}
		}
	case LevelWarm:
		if headwind {
			rule = guideRule{
				signal:     "pause_take_profit",
				title:      "偏热叠加逆风 · 暂停追高",
				summary:    "短期温度偏热且长期宏观支撑不足，建议暂停新增定投，盈利仓位可考虑分批落袋。",
				multiplier: 0.0,
				dcaLabel:   "暂停定投 0.0x",
			}
		} else {
			rule = guideRule{
				signal:     "cautious",
				title:      "偏热活跃 · 减半定投勿追高",
				summary:    "金价与交易情绪已偏热，虽有长期宏观顺风，仍建议将定投减半，切忌情绪化大额追涨。",
				multiplier: 0.5,
				dcaLabel:   "偏热减半 0.5x",
			}
		}
	default: // LevelHot
		rule = guideRule{
			signal:     "pause_take_profit",
			title:      "极度火热 · 暂停定投防回撤",
			summary:    fmt.Sprintf("当前黄金温度高达 %.1f°，市场交易高度拥挤，短期回撤风险显著上升；建议暂停新增定投，偏重仓位可分批止盈再平衡。", score),
			multiplier: 0.0,
			dcaLabel:   "过热暂停 0.0x",
		}
	}

	if volAlert && rule.multiplier > 0 {
		rule.summary += " 当前波动率处于高位预警区，请拉长分批间隔并控制单笔金额。"
	}

	ma200Note := "暂缺足够历史数据计算 200 日年线偏离度。"
	if ma200DevPct != nil {
		d := *ma200DevPct
		switch {
		case d < 0:
			ma200Note = fmt.Sprintf("当前金价低于 200 日年线 %.1f%%，处于年线下方，长期安全垫较厚。", math.Abs(d))
		case d <= 10:
			ma200Note = fmt.Sprintf("当前金价高于年线 %.1f%%，处于温和健康的多头区间。", d)
		case d <= 20:
			ma200Note = fmt.Sprintf("当前金价高于年线 %.1f%%，偏离度偏高，追高性价比下降。", d)
		default:
			ma200Note = fmt.Sprintf("当前金价高于年线 %.1f%%，显著远离年线，谨防均值回归式回踩。", d)
		}
	}

	premNote := "暂缺上海金溢价数据，购金时建议留意品牌工费与盘面价差。"
	if domesticPremiumPct != nil {
		p := *domesticPremiumPct
		switch {
		case p < 0:
			premNote = fmt.Sprintf("国内金价较国际折算价折价 %.2f%%，当前国内买金性价比偏高。", math.Abs(p))
		case p <= 1.5:
			premNote = fmt.Sprintf("国内溢价率 %+.2f%%，处于正常合理区间。", p)
		default:
			premNote = fmt.Sprintf("国内溢价率 %+.2f%% 偏高，存在额外溢价成本，非刚需可分批等待价差收敛。", p)
		}
	}

	return ActionGuide{
		Signal:              rule.signal,
		Title:               rule.title,
		Summary:             rule.summary,
		DCAMultiplier:       rule.multiplier,
		DCALabel:            rule.dcaLabel,
		MA200DeviationPct:   ma200DevPct,
		MA200Note:           ma200Note,
		DomesticPremiumPct:  domesticPremiumPct,
		DomesticPremiumNote: premNote,
		Disclaimer:          DefaultDisclaimer,
	}
}

func linearClamp(x, x0, x1, y0, y1 float64) float64 {
	if x1 == x0 {
		return (y0 + y1) / 2
	}
	t := (x - x0) / (x1 - x0)
	if t < 0 {
		t = 0
	}
	if t > 1 {
		t = 1
	}
	return y0 + t*(y1-y0)
}

func computeRollingMean(obs []Observation, window int) []float64 {
	n := len(obs)
	out := make([]float64, n)
	sum := 0.0
	for i := 0; i < n; i++ {
		sum += obs[i].Value
		if i >= window {
			sum -= obs[i-window].Value
		}
		if i >= window-1 {
			out[i] = sum / float64(window)
		} else {
			out[i] = math.NaN()
		}
	}
	return out
}

// computeRSI14 computes Wilder's 14-period RSI (0-100).
func computeRSI14(obs []Observation) []float64 {
	const period = 14
	n := len(obs)
	out := make([]float64, n)
	for i := range out {
		out[i] = math.NaN()
	}
	if n <= period {
		return out
	}
	var sumGain, sumLoss float64
	for i := 1; i <= period; i++ {
		diff := obs[i].Value - obs[i-1].Value
		if diff > 0 {
			sumGain += diff
		} else {
			sumLoss -= diff
		}
	}
	avgGain := sumGain / period
	avgLoss := sumLoss / period
	out[period] = rsiFromAverages(avgGain, avgLoss)
	for i := period + 1; i < n; i++ {
		diff := obs[i].Value - obs[i-1].Value
		gain, loss := 0.0, 0.0
		if diff > 0 {
			gain = diff
		} else {
			loss = -diff
		}
		avgGain = (avgGain*(period-1) + gain) / period
		avgLoss = (avgLoss*(period-1) + loss) / period
		out[i] = rsiFromAverages(avgGain, avgLoss)
	}
	return out
}

func rsiFromAverages(avgGain, avgLoss float64) float64 {
	if avgGain == 0 && avgLoss == 0 {
		return 50.0
	}
	if avgLoss == 0 {
		return 100.0
	}
	rs := avgGain / avgLoss
	return 100.0 - 100.0/(1.0+rs)
}

func rollingPercentilesSparse(values []float64, valid []bool, window, minPoints int) []float64 {
	n := len(values)
	out := make([]float64, n)
	for i := range out {
		out[i] = math.NaN()
	}
	validIndices := make([]int, 0, n)
	for i := 0; i < n; i++ {
		if !valid[i] || !IsFinite(values[i]) {
			continue
		}
		validIndices = append(validIndices, i)
		startIdx := i - window + 1
		if startIdx < 0 {
			startIdx = 0
		}
		// Find first entry in validIndices >= startIdx
		pos := sort.SearchInts(validIndices, startIdx)
		active := validIndices[pos:]
		if len(active) < minPoints {
			continue
		}
		cur := values[i]
		below := 0
		equal := 0
		for _, idx := range active {
			v := values[idx]
			if v < cur {
				below++
			} else if v == cur {
				equal++
			}
		}
		pct := (float64(below) + 0.5*float64(equal)) / float64(len(active)) * 100.0
		out[i] = math.Max(0, math.Min(100, pct))
	}
	return out
}

func alignSeries(anchor []Observation, series []Observation, maxStaleDays int) ([]float64, []bool) {
	n := len(anchor)
	vals := make([]float64, n)
	ok := make([]bool, n)
	if len(series) == 0 {
		return vals, ok
	}
	maxAge := time.Duration(maxStaleDays) * 24 * time.Hour
	j := 0
	for i, a := range anchor {
		for j+1 < len(series) && !series[j+1].Date.After(a.Date) {
			j++
		}
		if !series[j].Date.After(a.Date) && a.Date.Sub(series[j].Date) <= maxAge {
			vals[i] = series[j].Value
			ok[i] = true
		}
	}
	return vals, ok
}

func searchLastOnOrBeforeCot(cot []CotObservation, target time.Time) int {
	if len(cot) == 0 {
		return -1
	}
	idx := sort.Search(len(cot), func(i int) bool {
		return cot[i].Date.After(target)
	})
	return idx - 1
}

func computePctChange(obs []Observation, lookback int) []Observation {
	if len(obs) <= lookback {
		return []Observation{}
	}
	out := make([]Observation, 0, len(obs)-lookback)
	for i := lookback; i < len(obs); i++ {
		prev := obs[i-lookback].Value
		if prev <= 0 {
			continue
		}
		chg := (obs[i].Value/prev - 1.0) * 100.0
		if IsFinite(chg) {
			out = append(out, Observation{Date: obs[i].Date, Value: chg})
		}
	}
	return out
}

func computeDiff(obs []Observation, lookback int) []Observation {
	if len(obs) <= lookback {
		return []Observation{}
	}
	out := make([]Observation, 0, len(obs)-lookback)
	for i := lookback; i < len(obs); i++ {
		diff := obs[i].Value - obs[i-lookback].Value
		if IsFinite(diff) {
			out = append(out, Observation{Date: obs[i].Date, Value: diff})
		}
	}
	return out
}
