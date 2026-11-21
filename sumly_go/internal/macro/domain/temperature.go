package domain

import (
	"fmt"
	"math"
	"sort"
	"strings"
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

const (
	DefaultDisclaimer          = "数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。"
	DefaultOfficialAccountNote = "每日宏观数据复盘与模型方法论笔记同步更新于微信公众号"
)

type GuideHelpLevel struct {
	Range       string
	Level       string
	Label       string
	Description string
}

type GuideHelp struct {
	Title               string
	Methodology         string
	Levels              []GuideHelpLevel
	OfficialAccountName string
	OfficialAccountNote string
}

func BuildGuideHelp(officialAccountName, officialAccountNote string) GuideHelp {
	name := strings.TrimSpace(officialAccountName)
	note := strings.TrimSpace(officialAccountNote)
	if name != "" && note == "" {
		note = DefaultOfficialAccountNote
	}
	return GuideHelp{
		Title:       "黄金温度计说明",
		Methodology: "黄金温度计综合趋势偏离、机构持仓拥挤度、国内溢价、资金流与跨品种强弱、实际利率与美元短期共振共 5 个维度，基于近 3 年滚动历史分位加权合成（0°~100°），仅客观刻画市场冷热与拥挤程度，不构成投资建议。",
		Levels: []GuideHelpLevel{
			{
				Range:       "0° ~ 20°",
				Level:       LevelFreezing,
				Label:       "极冷区间",
				Description: "情绪与交易热度处于近 3 年低位，市场关注度低迷",
			},
			{
				Range:       "20° ~ 40°",
				Level:       LevelCool,
				Label:       "偏冷区间",
				Description: "交易拥挤度较低，市场情绪尚未过热",
			},
			{
				Range:       "40° ~ 60°",
				Level:       LevelNeutral,
				Label:       "中性区间",
				Description: "多空力量相对均衡，市场热度处于常态",
			},
			{
				Range:       "60° ~ 80°",
				Level:       LevelWarm,
				Label:       "偏热区间",
				Description: "资金关注度升温，交投活跃度偏高",
			},
			{
				Range:       "80° ~ 100°",
				Level:       LevelHot,
				Label:       "极热区间",
				Description: "短期偏离与多头拥挤度处于高位，历史波动往往放大",
			},
		},
		OfficialAccountName: name,
		OfficialAccountNote: note,
	}
}

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
		return LevelFreezing, LabelForLevel(LevelFreezing)
	case score < 40:
		return LevelCool, LabelForLevel(LevelCool)
	case score < 60:
		return LevelNeutral, LabelForLevel(LevelNeutral)
	case score < 80:
		return LevelWarm, LabelForLevel(LevelWarm)
	default:
		return LevelHot, LabelForLevel(LevelHot)
	}
}

func LabelForLevel(level string) string {
	switch level {
	case LevelFreezing:
		return "极冷区间"
	case LevelCool:
		return "偏冷区间"
	case LevelNeutral:
		return "中性区间"
	case LevelWarm:
		return "偏热区间"
	case LevelHot:
		return "极热区间"
	default:
		return "中性区间"
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
		Summary: "长期宏观指标尚未同步完成，暂按中性区间统计。",
	}
	guide := BuildActionGuide(regime, LevelNeutral, 50, nil, nil, false)
	return TemperatureSnapshot{
		AsOf:            "",
		ModelVersion:    ModelVersionV1,
		Degraded:        true,
		MissingFactors:  missing,
		Score:           50,
		Level:           LevelNeutral,
		LevelLabel:      LabelForLevel(LevelNeutral),
		VolatilityAlert: false,
		VolatilityNote:  "波动率指标尚未同步，暂无法评估当前市场波动水平。",
		MacroRegime:     regime,
		ActionGuide:     guide,
		Dimensions:      dims,
	}
}

// SanitizePublicTemperatureSnapshot ensures even legacy persisted snapshots strictly
// present objective, non-advisory public copy without mutating stored metrics.
func SanitizePublicTemperatureSnapshot(snap TemperatureSnapshot) TemperatureSnapshot {
	if snap.MissingFactors == nil {
		snap.MissingFactors = []string{}
	}
	if snap.Dimensions == nil {
		snap.Dimensions = []TemperatureDimension{}
	} else {
		dims := make([]TemperatureDimension, len(snap.Dimensions))
		for i, d := range snap.Dimensions {
			if d.Metrics == nil {
				d.Metrics = map[string]float64{}
			}
			dims[i] = d
		}
		snap.Dimensions = dims
	}

	level := snap.Level
	if level == "" {
		level, _ = LevelForScore(snap.Score)
		snap.Level = level
	}
	snap.LevelLabel = LabelForLevel(level)

	if snap.AsOf == "" {
		snap.MacroRegime = MacroRegime{
			Score:   50,
			Regime:  RegimeNeutral,
			Label:   "宏观中性",
			Summary: "长期宏观指标尚未同步完成，暂按中性区间统计。",
		}
	} else {
		snap.MacroRegime = DescribeMacroRegime(snap.MacroRegime.Regime, snap.MacroRegime.Score)
	}

	snap.VolatilityNote = sanitizePublicVolatilityNote(snap.VolatilityNote, snap.VolatilityAlert, snap.AsOf == "")
	snap.ActionGuide = BuildActionGuide(
		snap.MacroRegime,
		snap.Level,
		snap.Score,
		snap.ActionGuide.MA200DeviationPct,
		snap.ActionGuide.DomesticPremiumPct,
		snap.VolatilityAlert,
	)
	return snap
}

func sanitizePublicVolatilityNote(note string, alert, coldStart bool) string {
	trimmed := strings.TrimSpace(note)
	if coldStart && trimmed == "" {
		return "波动率指标尚未同步，暂无法评估当前市场波动水平。"
	}
	if trimmed == "" || containsLegacyAdvisoryHint(trimmed) {
		if alert {
			return "黄金隐含波动率处于近 3 年高位，历史同期短期振幅往往放大。"
		}
		if coldStart {
			return "波动率指标尚未同步，暂无法评估当前市场波动水平。"
		}
		return "黄金隐含波动率整体处于常态波动区间。"
	}
	return trimmed
}

func containsLegacyAdvisoryHint(s string) bool {
	for _, token := range []string{"建议", "仓位", "分批", "定投", "追高", "止盈", "建仓", "加仓", "减仓", "加配", "减配", "适合", "划算", "黄金坑", "防守", "试探"} {
		if strings.Contains(s, token) {
			return true
		}
	}
	return false
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
			volNote := "黄金隐含波动率处于常态区间，暂无高波动提示。"
			if !math.IsNaN(gvzPct[i]) {
				if gvzPct[i] > 85.0 {
					volAlert = true
					volNote = fmt.Sprintf("黄金隐含波动率（GVZ=%.1f）处于近 3 年 %.0f%% 高位，历史同期短期振幅往往放大。", gvzVal[i], gvzPct[i])
				} else {
					volNote = fmt.Sprintf("黄金隐含波动率（GVZ=%.1f）处于近 3 年 %.0f%% 分位，整体波动处于常态区间。", gvzVal[i], gvzPct[i])
				}
			} else if gvzOK[i] {
				volNote = fmt.Sprintf("当前黄金隐含波动率 GVZ=%.1f，历史样本积累中，暂未触发高波动提示。", gvzVal[i])
			} else {
				volNote = "暂缺黄金隐含波动率（GVZ）观测数据，暂无法统计波动分位。"
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
			guide := BuildActionGuide(regime, level, totalScore, devPtr, shPtr, volAlert)

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
		empty.ActionGuide = BuildActionGuide(empty.MacroRegime, empty.Level, empty.Score, nil, nil, false)
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
			Summary: "长期宏观指标数据不足，暂按中性区间统计。",
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
		return DescribeMacroRegime(RegimeTailwind, score)
	case score >= 40:
		return DescribeMacroRegime(RegimeNeutral, score)
	default:
		return DescribeMacroRegime(RegimeHeadwind, score)
	}
}

func DescribeMacroRegime(regime string, score float64) MacroRegime {
	switch regime {
	case RegimeTailwind:
		return MacroRegime{
			Score:   score,
			Regime:  RegimeTailwind,
			Label:   "长期宏观偏暖",
			Summary: "美债规模、财政压力与央行购金等长期宏观指标整体偏强，反映中长期基本面背景偏暖。",
		}
	case RegimeHeadwind:
		return MacroRegime{
			Score:   score,
			Regime:  RegimeHeadwind,
			Label:   "长期宏观偏弱",
			Summary: "实际利率水平相对偏高且财政与外储端驱动偏弱，长期宏观背景整体偏弱。",
		}
	default:
		return MacroRegime{
			Score:   score,
			Regime:  RegimeNeutral,
			Label:   "宏观中性",
			Summary: "实际利率水平与美债规模、央行购金等长期宏观指标力量相对均衡，整体处于中性区间。",
		}
	}
}

func BuildActionGuide(
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
	regimeKind := regime.Regime
	if regimeKind != RegimeTailwind && regimeKind != RegimeHeadwind {
		regimeKind = RegimeNeutral
	}
	headwind := regimeKind == RegimeHeadwind

	switch level {
	case LevelFreezing:
		if headwind {
			rule = guideRule{
				signal:     "accumulate",
				title:      "极冷区间 · 宏观偏弱",
				summary:    "五维市场热度处于近 3 年极低分位，同时实际利率与财政端等长期宏观指标偏弱，整体呈现“宏观偏弱、短线极冷”特征。",
				multiplier: 1.2,
				dcaLabel:   "近3年极低分位",
			}
		} else if regimeKind == RegimeTailwind {
			rule = guideRule{
				signal:     "strong_accumulate",
				title:      "极冷区间 · 宏观偏暖",
				summary:    "五维市场热度处于近 3 年极低分位，同时美债与央行购金等长期宏观指标偏强，整体呈现“宏观偏暖、短线极冷”特征。",
				multiplier: 1.5,
				dcaLabel:   "近3年极低分位",
			}
		} else {
			rule = guideRule{
				signal:     "strong_accumulate",
				title:      "极冷区间 · 热度处于低位",
				summary:    "五维市场热度处于近 3 年极低分位，市场交易活跃度低迷，长期宏观指标整体处于中性区间。",
				multiplier: 1.5,
				dcaLabel:   "近3年极低分位",
			}
		}
	case LevelCool:
		if headwind {
			rule = guideRule{
				signal:     "hold_dca",
				title:      "偏冷区间 · 宏观偏弱",
				summary:    "五维市场热度处于近 3 年偏低分位，交易拥挤度较低，同时实际利率等长期宏观指标整体偏弱。",
				multiplier: 1.0,
				dcaLabel:   "拥挤度较低",
			}
		} else if regimeKind == RegimeTailwind {
			rule = guideRule{
				signal:     "accumulate",
				title:      "偏冷区间 · 宏观偏暖",
				summary:    "五维市场热度处于近 3 年偏低分位，同时美债与央行购金等长期宏观指标偏强，整体呈现“宏观偏暖、短线偏冷”特征。",
				multiplier: 1.2,
				dcaLabel:   "拥挤度较低",
			}
		} else {
			rule = guideRule{
				signal:     "accumulate",
				title:      "偏冷区间 · 拥挤度较低",
				summary:    "五维市场热度处于近 3 年偏低分位，交易拥挤度较低，长期宏观指标整体处于中性区间。",
				multiplier: 1.2,
				dcaLabel:   "拥挤度较低",
			}
		}
	case LevelNeutral:
		if headwind {
			rule = guideRule{
				signal:     "cautious",
				title:      "中性区间 · 宏观偏弱",
				summary:    "五维市场热度处于近 3 年中位区间，多空力量相对均衡，但实际利率等长期宏观指标整体偏弱。",
				multiplier: 0.5,
				dcaLabel:   "热度均衡",
			}
		} else if regimeKind == RegimeTailwind {
			rule = guideRule{
				signal:     "hold_dca",
				title:      "中性区间 · 宏观偏暖",
				summary:    "五维市场热度处于近 3 年中位区间，多空力量相对均衡，同时美债与央行购金等长期宏观指标偏强。",
				multiplier: 1.0,
				dcaLabel:   "热度均衡",
			}
		} else {
			rule = guideRule{
				signal:     "hold_dca",
				title:      "中性区间 · 多空相对均衡",
				summary:    "五维市场热度处于近 3 年中位区间，多空力量相对均衡，长期宏观指标亦处于中性常态。",
				multiplier: 1.0,
				dcaLabel:   "热度均衡",
			}
		}
	case LevelWarm:
		if headwind {
			rule = guideRule{
				signal:     "pause_take_profit",
				title:      "偏热区间 · 宏观偏弱",
				summary:    "五维市场热度处于近 3 年偏高分位，短期交投偏热，但长期宏观指标整体偏弱，短长周期出现背离特征。",
				multiplier: 0.0,
				dcaLabel:   "关注度偏高",
			}
		} else if regimeKind == RegimeTailwind {
			rule = guideRule{
				signal:     "cautious",
				title:      "偏热区间 · 宏观偏暖",
				summary:    "五维市场热度处于近 3 年偏高分位，资金关注度与交投活跃度升温，长期宏观指标同时偏强。",
				multiplier: 0.5,
				dcaLabel:   "关注度偏高",
			}
		} else {
			rule = guideRule{
				signal:     "cautious",
				title:      "偏热区间 · 关注度升温",
				summary:    "五维市场热度处于近 3 年偏高分位，资金关注度与交投活跃度升温，长期宏观指标整体处于中性区间。",
				multiplier: 0.5,
				dcaLabel:   "关注度偏高",
			}
		}
	default: // LevelHot
		if headwind {
			rule = guideRule{
				signal:     "pause_take_profit",
				title:      "极热区间 · 宏观偏弱",
				summary:    fmt.Sprintf("当前黄金温度为 %.1f°，五维热度与多头拥挤度处于近 3 年高位区间，且长期宏观指标偏弱，历史同期短期振幅往往放大。", score),
				multiplier: 0.0,
				dcaLabel:   "拥挤度偏高",
			}
		} else if regimeKind == RegimeTailwind {
			rule = guideRule{
				signal:     "pause_take_profit",
				title:      "极热区间 · 宏观偏暖",
				summary:    fmt.Sprintf("当前黄金温度为 %.1f°，五维热度与多头拥挤度处于近 3 年高位区间，同时长期宏观指标偏强，历史同期短期波动往往放大。", score),
				multiplier: 0.0,
				dcaLabel:   "拥挤度偏高",
			}
		} else {
			rule = guideRule{
				signal:     "pause_take_profit",
				title:      "极热区间 · 交易高度拥挤",
				summary:    fmt.Sprintf("当前黄金温度为 %.1f°，五维热度与多头拥挤度处于近 3 年高位区间，长期宏观指标处于中性，历史同期短期波动往往放大。", score),
				multiplier: 0.0,
				dcaLabel:   "拥挤度偏高",
			}
		}
	}

	if volAlert {
		rule.summary += " 当前隐含波动率处于近 3 年高位，市场短期振幅较常态明显扩大。"
	}

	ma200Note := "暂缺足够历史数据计算 200 日均线偏离度。"
	if ma200DevPct != nil {
		d := *ma200DevPct
		switch {
		case d < 0:
			ma200Note = fmt.Sprintf("低于 200 日均线 %.1f%%，处于年线下方。", math.Abs(d))
		case d <= 10:
			ma200Note = fmt.Sprintf("高于 200 日均线 %.1f%%，处于年线上方温和区间。", d)
		case d <= 20:
			ma200Note = fmt.Sprintf("高于 200 日均线 %.1f%%，较年线正向偏离幅度偏高。", d)
		default:
			ma200Note = fmt.Sprintf("高于 200 日均线 %.1f%%，显著高于年线均值水平。", d)
		}
	}

	premNote := "暂缺上海金相对国际折算价的溢价统计数据。"
	if domesticPremiumPct != nil {
		p := *domesticPremiumPct
		switch {
		case p < 0:
			premNote = fmt.Sprintf("国内金价较国际折算价折价 %+.2f%%。", p)
		case p <= 1.5:
			premNote = fmt.Sprintf("国内金价较国际折算价溢价 %+.2f%%，处于常态价差区间。", p)
		default:
			premNote = fmt.Sprintf("国内金价较国际折算价溢价 %+.2f%%，处于偏高溢价区间。", p)
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
