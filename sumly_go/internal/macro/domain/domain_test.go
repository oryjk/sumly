package domain

import (
	"math"
	"strings"
	"testing"
	"time"
)

func d(y int, m time.Month, day int) time.Time {
	return time.Date(y, m, day, 0, 0, 0, 0, time.UTC)
}

func TestSanitizeObservationsHandlesUnsortedNaNInfAndDupes(t *testing.T) {
	in := []Observation{
		{Date: d(2025, 1, 3), Value: 103},
		{Date: d(2025, 1, 1), Value: math.NaN()},
		{Date: d(2025, 1, 2), Value: math.Inf(1)},
		{Date: d(2025, 1, 1), Value: 100},
		{Date: d(2025, 1, 3), Value: 105},
	}
	got := SanitizeObservations(in)
	if len(got) != 2 {
		t.Fatalf("expected 2 valid observations, got %d", len(got))
	}
	if FormatDate(got[0].Date) != "2025-01-01" || got[0].Value != 100 {
		t.Fatalf("unexpected first obs: %+v", got[0])
	}
	if FormatDate(got[1].Date) != "2025-01-03" || got[1].Value != 105 {
		t.Fatalf("unexpected second obs: %+v", got[1])
	}
}

func TestDerivedFormulas(t *testing.T) {
	t.Run("PCE_YOY", func(t *testing.T) {
		series := make([]Observation, 0, 14)
		for i := 0; i < 14; i++ {
			dt := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC).AddDate(0, i, 0)
			val := 100.0 + float64(i)
			series = append(series, Observation{Date: dt, Value: val})
		}
		yoy := CalcPCEYoY(series)
		if len(yoy) != 2 {
			t.Fatalf("expected 2 YoY points, got %d", len(yoy))
		}
		if yoy[0].Value != 12.0 {
			t.Fatalf("expected 12.0%%, got %.2f", yoy[0].Value)
		}
	})

	t.Run("INTEREST_RATIO and FISCAL_STRESS", func(t *testing.T) {
		ir := CalcInterestRatio(
			[]Observation{{Date: d(2024, 1, 1), Value: 900000}},
			[]Observation{{Date: d(2024, 1, 1), Value: 4500000}},
		)
		if len(ir) != 1 || ir[0].Value != 20.0 {
			t.Fatalf("unexpected interest ratio: %+v", ir)
		}
		fs := CalcFiscalStress(
			ir,
			[]Observation{{Date: d(2024, 1, 1), Value: -6.5}},
			[]Observation{{Date: d(2024, 1, 1), Value: 122.0}},
		)
		if len(fs) != 1 {
			t.Fatalf("expected 1 fiscal stress point, got %d", len(fs))
		}
		// IR=20 => scoreIR=75, m=2 => eff=100, total=150 => w=(2/3, 30/150=0.2, 20/150=0.1333)
		// def=6.5 => scoreDef=50 + 1.5/2*20 = 65
		// debt=122 => scoreDebt=75 + 2/30*17 = 76.1333
		// score = 75*(2/3) + 65*0.2 + 76.1333*(2/15) = 50 + 13 + 10.1511 = 73.1511 => 73.2
		if fs[0].Value != 73.2 {
			t.Fatalf("expected fiscal stress 73.2, got %.1f", fs[0].Value)
		}
	})

	t.Run("GOLD_CNY and SHANGHAI_PREMIUM forward-fills FX", func(t *testing.T) {
		gold := []Observation{{Date: d(2026, 3, 24), Value: 3110.35}}
		fx := []Observation{{Date: d(2026, 3, 20), Value: 7.0}}
		sge := []Observation{{Date: d(2026, 3, 24), Value: 714.0}}
		cny := CalcGoldCNY(gold, fx)
		if len(cny) != 1 || cny[0].Value != 700.0 {
			t.Fatalf("expected 700.0 CNY/g, got %+v", cny)
		}
		prem := CalcShanghaiPremium(sge, gold, fx)
		if len(prem) != 1 || prem[0].Value != 2.0 {
			t.Fatalf("expected 2.0%% premium, got %+v", prem)
		}
	})

	t.Run("TREASURY_10Y_2Y_SPREAD, GOLD_SILVER_RATIO, GOLD_OIL_RATIO", func(t *testing.T) {
		sp := CalcTreasurySpread(
			[]Observation{{Date: d(2026, 1, 2), Value: 4.5}},
			[]Observation{{Date: d(2026, 1, 2), Value: 4.1}},
		)
		if len(sp) != 1 || sp[0].Value != 0.4 {
			t.Fatalf("unexpected spread: %+v", sp)
		}
		gs := CalcRatio(
			[]Observation{{Date: d(2026, 1, 2), Value: 3000}},
			[]Observation{{Date: d(2026, 1, 2), Value: 30}},
		)
		if len(gs) != 1 || gs[0].Value != 100 {
			t.Fatalf("unexpected ratio: %+v", gs)
		}
	})
}

func TestTemperatureEmptyAndDegradedAndFull(t *testing.T) {
	t.Run("empty inputs return degraded neutral snapshot", func(t *testing.T) {
		snap, hist := ComputeTemperature(TemperatureInputs{})
		if !snap.Degraded || snap.AsOf != "" || len(snap.MissingFactors) != 5 || len(hist) != 0 {
			t.Fatalf("unexpected empty snapshot: %+v, hist=%d", snap, len(hist))
		}
		if len(snap.Dimensions) != 5 {
			t.Fatalf("expected 5 dimensions, got %d", len(snap.Dimensions))
		}
	})

	t.Run("single factor missing renormalizes weights and marks degraded", func(t *testing.T) {
		// Build 300 days of gold with a flat base then accelerating breakout so MA200 deviation & RSI are hot (>85)
		gold := make([]Observation, 0, 300)
		start := d(2024, 1, 1)
		for i := 0; i < 300; i++ {
			price := 2000.0
			if i >= 200 {
				x := float64(i - 200)
				price = 2000.0 + x*x*0.15
			}
			gold = append(gold, Observation{
				Date:  start.AddDate(0, 0, i),
				Value: price,
			})
		}
		snap, hist := ComputeTemperature(TemperatureInputs{
			Gold: gold,
			// All other dimensions omitted -> degraded with 4 missing factors
			GVZCLS: func() []Observation {
				out := make([]Observation, 0, 300)
				for i := 0; i < 300; i++ {
					val := 15.0 + float64(i)*0.1
					out = append(out, Observation{Date: start.AddDate(0, 0, i), Value: val})
				}
				return out
			}(),
			FiscalStress: []Observation{{Date: d(2024, 1, 1), Value: 80}},
			CBGoldNet:    []Observation{{Date: d(2024, 1, 1), Value: 1045}},
			DebtToGDP:    []Observation{{Date: d(2024, 1, 1), Value: 125}},
		})
		if !snap.Degraded {
			t.Fatalf("expected degraded=true when 4 factors are missing")
		}
		if len(snap.MissingFactors) != 4 {
			t.Fatalf("expected 4 missing factors, got %v", snap.MissingFactors)
		}
		if snap.Score < 80 || snap.Level != LevelHot {
			t.Fatalf("expected hot score >=80 on monotonically rising gold, got %.1f (%s)", snap.Score, snap.Level)
		}
		if !snap.VolatilityAlert {
			t.Fatalf("expected volatility alert when GVZ is at 3y max")
		}
		if snap.MacroRegime.Regime != RegimeTailwind {
			t.Fatalf("expected tailwind macro regime, got %+v", snap.MacroRegime)
		}
		if snap.ActionGuide.DCAMultiplier != 0.0 {
			t.Fatalf("expected hot DCA multiplier 0.0, got %.1f", snap.ActionGuide.DCAMultiplier)
		}
		if snap.Change1D == nil || snap.Change5D == nil {
			t.Fatalf("expected change_1d and change_5d populated")
		}
		if len(hist) == 0 {
			t.Fatalf("expected non-empty temperature history")
		}
	})

	t.Run("all five dimensions freezing with headwind steps down DCA multiplier", func(t *testing.T) {
		n := 260
		start := d(2025, 1, 1)
		gold := make([]Observation, 0, n)
		silver := make([]Observation, 0, n)
		shPrem := make([]Observation, 0, n)
		gld := make([]Observation, 0, n)
		dfii := make([]Observation, 0, n)
		dtwex := make([]Observation, 0, n)
		cot := make([]CotObservation, 0, 40)

		for i := 0; i < n; i++ {
			dt := start.AddDate(0, 0, i)
			// Falling gold, falling faster on silver (gold/silver ratio rising => bearish), falling premium, falling GLD, rising real yields & USD
			g := 3000.0 - float64(i)*3.0
			s := 40.0 - float64(i)*0.11
			gold = append(gold, Observation{Date: dt, Value: g})
			silver = append(silver, Observation{Date: dt, Value: s})
			shPrem = append(shPrem, Observation{Date: dt, Value: 3.0 - float64(i)*0.02})
			gld = append(gld, Observation{Date: dt, Value: 1000.0 - float64(i)*0.5})
			dfii = append(dfii, Observation{Date: dt, Value: 0.5 + float64(i)*0.015})
			dtwex = append(dtwex, Observation{Date: dt, Value: 105.0 + float64(i)*0.1})
			if i%7 == 0 {
				mmNet := 200000.0 - float64(i)*700.0
				cot = append(cot, CotObservation{
					Date:         dt,
					MMLong:       250000 - float64(i)*500,
					MMShort:      50000 + float64(i)*200,
					MMNet:        mmNet,
					OpenInterest: 500000,
				})
			}
		}

		snap, _ := ComputeTemperature(TemperatureInputs{
			Gold:            gold,
			Silver:          silver,
			Cot:             cot,
			ShanghaiPremium: shPrem,
			GLDTonnes:       gld,
			DFII10:          dfii,
			DTWEXBGS:        dtwex,
			// Headwind macro inputs: low debt, low fiscal stress, low CB buying, high USD reserve, high real yield
			DebtToGDP:       []Observation{{Date: start, Value: 55}},
			FiscalStress:    []Observation{{Date: start, Value: 20}},
			CBGoldNet:       []Observation{{Date: start, Value: 120}},
			USDReserveShare: []Observation{{Date: start, Value: 70}},
		})
		if snap.Degraded || len(snap.MissingFactors) != 0 {
			t.Fatalf("expected non-degraded with all 5 dimensions, got degraded=%v missing=%v", snap.Degraded, snap.MissingFactors)
		}
		if snap.Level != LevelFreezing {
			t.Fatalf("expected freezing level, got %.1f (%s)", snap.Score, snap.Level)
		}
		if snap.MacroRegime.Regime != RegimeHeadwind {
			t.Fatalf("expected headwind regime, got %+v", snap.MacroRegime)
		}
		if snap.ActionGuide.DCAMultiplier != 1.2 {
			t.Fatalf("expected headwind freezing multiplier 1.2 (stepped down from 1.5), got %.1f", snap.ActionGuide.DCAMultiplier)
		}
	})
}

func TestLevelForScoreBoundaries(t *testing.T) {
	cases := []struct {
		score float64
		want  string
	}{
		{0, LevelFreezing},
		{19.9, LevelFreezing},
		{20.0, LevelCool},
		{39.9, LevelCool},
		{40.0, LevelNeutral},
		{59.9, LevelNeutral},
		{60.0, LevelWarm},
		{79.9, LevelWarm},
		{80.0, LevelHot},
		{100.0, LevelHot},
	}
	for _, tc := range cases {
		got, _ := LevelForScore(tc.score)
		if got != tc.want {
			t.Errorf("LevelForScore(%.1f) = %s, want %s", tc.score, got, tc.want)
		}
	}
}

var forbiddenAdvisoryWords = []string{
	"逢低加配", "建仓", "加仓", "减仓", "止盈", "追高", "定投",
	"适合", "建议", "划算", "黄金坑", "防守", "试探",
	"击球区", "落袋", "重仓", "低吸", "追涨", "加配", "减配",
	"减半", "暂停", "分批", "仓位", "性价比", "买金", "筹码",
	"择时", "满仓", "杀跌", "切忌", "谨防", "严控",
}

func assertNoForbiddenAdvisoryWords(t *testing.T, field, text string) {
	t.Helper()
	cleaned := strings.ReplaceAll(text, "不构成任何投资建议", "")
	cleaned = strings.ReplaceAll(cleaned, "不构成投资建议", "")
	for _, word := range forbiddenAdvisoryWords {
		if strings.Contains(cleaned, word) {
			t.Errorf("public field %s contains forbidden advisory word %q: %q", field, word, text)
		}
	}
}

func TestPublicTemperatureCopyContainsNoAdvisoryTerms(t *testing.T) {
	levels := []struct {
		level string
		score float64
	}{
		{LevelFreezing, 12.5},
		{LevelCool, 31.4},
		{LevelNeutral, 50.0},
		{LevelWarm, 72.8},
		{LevelHot, 89.3},
	}
	regimes := []struct {
		regime string
		score  float64
	}{
		{RegimeTailwind, 72.0},
		{RegimeNeutral, 50.0},
		{RegimeHeadwind, 28.0},
	}
	floatPtr := func(v float64) *float64 { return &v }
	ma200Cases := []*float64{nil, floatPtr(-17.2), floatPtr(4.5), floatPtr(15.6), floatPtr(26.8)}
	premCases := []*float64{nil, floatPtr(-0.42), floatPtr(0.75), floatPtr(2.40)}

	for _, lv := range levels {
		assertNoForbiddenAdvisoryWords(t, "level_label", LabelForLevel(lv.level))
		for _, rg := range regimes {
			regime := DescribeMacroRegime(rg.regime, rg.score)
			assertNoForbiddenAdvisoryWords(t, "macro_regime.label", regime.Label)
			assertNoForbiddenAdvisoryWords(t, "macro_regime.summary", regime.Summary)
			for _, volAlert := range []bool{false, true} {
				for _, ma := range ma200Cases {
					for _, prem := range premCases {
						guide := BuildActionGuide(regime, lv.level, lv.score, ma, prem, volAlert)
						assertNoForbiddenAdvisoryWords(t, "action_guide.title", guide.Title)
						assertNoForbiddenAdvisoryWords(t, "action_guide.summary", guide.Summary)
						assertNoForbiddenAdvisoryWords(t, "action_guide.dca_label", guide.DCALabel)
						assertNoForbiddenAdvisoryWords(t, "action_guide.ma200_note", guide.MA200Note)
						assertNoForbiddenAdvisoryWords(t, "action_guide.domestic_premium_note", guide.DomesticPremiumNote)
						assertNoForbiddenAdvisoryWords(t, "action_guide.disclaimer", guide.Disclaimer)
						if guide.Disclaimer != DefaultDisclaimer {
							t.Fatalf("unexpected disclaimer: %q", guide.Disclaimer)
						}
					}
				}
			}
		}
	}

	// Empty snapshot & computed snapshot volatility notes must also be free of advisory wording.
	empty := EmptyTemperatureSnapshot()
	assertNoForbiddenAdvisoryWords(t, "empty.volatility_note", empty.VolatilityNote)
	assertNoForbiddenAdvisoryWords(t, "empty.macro_regime.summary", empty.MacroRegime.Summary)
	assertNoForbiddenAdvisoryWords(t, "empty.action_guide.summary", empty.ActionGuide.Summary)

	help := BuildGuideHelp("测试号", "")
	assertNoForbiddenAdvisoryWords(t, "guide_help.title", help.Title)
	assertNoForbiddenAdvisoryWords(t, "guide_help.methodology", help.Methodology)
	assertNoForbiddenAdvisoryWords(t, "guide_help.official_account_note", help.OfficialAccountNote)
	for _, lv := range help.Levels {
		assertNoForbiddenAdvisoryWords(t, "guide_help.level.label", lv.Label)
		assertNoForbiddenAdvisoryWords(t, "guide_help.level.description", lv.Description)
	}
}

func TestSanitizePublicTemperatureSnapshotCleansLegacyAdvisoryCopy(t *testing.T) {
	dev := -17.2
	prem := -0.42
	legacy := TemperatureSnapshot{
		AsOf:            "2026-04-01",
		ModelVersion:    ModelVersionV1,
		Score:           32.5,
		Level:           LevelCool,
		LevelLabel:      "偏冷蓄势",
		VolatilityAlert: true,
		VolatilityNote:  "黄金隐含波动率（GVZ=28.7）处于近 3 年 91% 极端高位，建议控制单笔仓位、拉长分批节奏。",
		MacroRegime: MacroRegime{
			Score:   25.0,
			Regime:  RegimeHeadwind,
			Label:   "长期宏观逆风",
			Summary: "实际利率偏高且财政/去美元化驱动偏弱，建议降低定投系数并严控追高。",
		},
		ActionGuide: ActionGuide{
			Signal:              "hold_dca",
			Title:               "偏冷蓄势 · 逢低加配",
			Summary:             "适合稳步定投或逢回调加仓",
			DCAMultiplier:       1.0,
			DCALabel:            "标准定投 1.0x",
			MA200DeviationPct:   &dev,
			MA200Note:           "低于年线，长期安全垫较厚",
			DomesticPremiumPct:  &prem,
			DomesticPremiumNote: "当前国内买金性价比偏高",
			Disclaimer:          "旧免责声明",
		},
	}

	got := SanitizePublicTemperatureSnapshot(legacy)
	assertNoForbiddenAdvisoryWords(t, "sanitized.level_label", got.LevelLabel)
	assertNoForbiddenAdvisoryWords(t, "sanitized.volatility_note", got.VolatilityNote)
	assertNoForbiddenAdvisoryWords(t, "sanitized.macro_regime.label", got.MacroRegime.Label)
	assertNoForbiddenAdvisoryWords(t, "sanitized.macro_regime.summary", got.MacroRegime.Summary)
	assertNoForbiddenAdvisoryWords(t, "sanitized.action_guide.title", got.ActionGuide.Title)
	assertNoForbiddenAdvisoryWords(t, "sanitized.action_guide.summary", got.ActionGuide.Summary)
	assertNoForbiddenAdvisoryWords(t, "sanitized.action_guide.dca_label", got.ActionGuide.DCALabel)
	assertNoForbiddenAdvisoryWords(t, "sanitized.action_guide.ma200_note", got.ActionGuide.MA200Note)
	assertNoForbiddenAdvisoryWords(t, "sanitized.action_guide.domestic_premium_note", got.ActionGuide.DomesticPremiumNote)
	if got.ActionGuide.DCAMultiplier != 1.0 {
		t.Fatalf("expected DCAMultiplier preserved as 1.0, got %.1f", got.ActionGuide.DCAMultiplier)
	}
	if got.ActionGuide.MA200DeviationPct == nil || *got.ActionGuide.MA200DeviationPct != -17.2 {
		t.Fatalf("expected MA200DeviationPct preserved, got %v", got.ActionGuide.MA200DeviationPct)
	}
	if got.ActionGuide.DomesticPremiumPct == nil || *got.ActionGuide.DomesticPremiumPct != -0.42 {
		t.Fatalf("expected DomesticPremiumPct preserved, got %v", got.ActionGuide.DomesticPremiumPct)
	}
}

func TestBuildGuideHelpOfficialAccountOptions(t *testing.T) {
	t.Run("empty config leaves official account fields empty", func(t *testing.T) {
		h := BuildGuideHelp("", "")
		if h.Title != "黄金温度计说明" || len(h.Levels) != 5 {
			t.Fatalf("unexpected guide help: %+v", h)
		}
		if h.OfficialAccountName != "" || h.OfficialAccountNote != "" {
			t.Fatalf("expected empty official account fields, got name=%q note=%q", h.OfficialAccountName, h.OfficialAccountNote)
		}
	})

	t.Run("configured name without note uses restrained default note", func(t *testing.T) {
		h := BuildGuideHelp("  金市观察笔记  ", "   ")
		if h.OfficialAccountName != "金市观察笔记" {
			t.Fatalf("unexpected account name: %q", h.OfficialAccountName)
		}
		if h.OfficialAccountNote != DefaultOfficialAccountNote {
			t.Fatalf("expected default note %q, got %q", DefaultOfficialAccountNote, h.OfficialAccountNote)
		}
	})

	t.Run("configured name and custom note preserves custom note", func(t *testing.T) {
		h := BuildGuideHelp("金市观察笔记", "自定义公众号说明")
		if h.OfficialAccountName != "金市观察笔记" || h.OfficialAccountNote != "自定义公众号说明" {
			t.Fatalf("unexpected account fields: %+v", h)
		}
	})
}

func TestStrategyMappingAllCombinationsAndBriefGeneration(t *testing.T) {
	levels := []struct {
		level string
		score float64
	}{
		{LevelFreezing, 15.0},
		{LevelCool, 30.0},
		{LevelNeutral, 50.0},
		{LevelWarm, 70.0},
		{LevelHot, 88.5},
	}
	regimes := []string{RegimeTailwind, RegimeNeutral, RegimeHeadwind}

	for _, lv := range levels {
		for _, rg := range regimes {
			for _, volAlert := range []bool{false, true} {
				regime := DescribeMacroRegime(rg, 50)
				publicGuide := BuildActionGuide(regime, lv.level, lv.score, nil, nil, volAlert)
				fw := MapStrategyFramework(lv.level, rg, lv.score, volAlert)

				if fw.Signal != publicGuide.Signal {
					t.Errorf("(%s,%s) signal mismatch: fw=%q guide=%q", lv.level, rg, fw.Signal, publicGuide.Signal)
				}
				if fw.ReferencePaceMultiplier != publicGuide.DCAMultiplier {
					t.Errorf("(%s,%s) multiplier mismatch: fw=%.1f guide=%.1f", lv.level, rg, fw.ReferencePaceMultiplier, publicGuide.DCAMultiplier)
				}
				if fw.Title == "" || fw.HistoricalPerspective == "" || fw.ReferencePaceLabel == "" || fw.RiskNotice == "" {
					t.Errorf("(%s,%s) has empty framework fields: %+v", lv.level, rg, fw)
				}
				if !strings.Contains(fw.RiskNotice, "不构成任何投资建议") {
					t.Errorf("(%s,%s) risk notice missing disclaimer: %q", lv.level, rg, fw.RiskNotice)
				}
			}
		}
	}

	c1 := 1.8
	c5 := -2.3
	dev := 8.4
	prem := 0.65
	debt := 36.45
	debtYoY := 2.15
	debtGDP := 123.5
	fiscal := 78.2
	y10 := 4.42
	realY10 := 2.08
	be10 := 2.34

	snap := TemperatureSnapshot{
		AsOf:            "2026-04-10",
		ModelVersion:    ModelVersionV1,
		Degraded:        false,
		MissingFactors:  []string{},
		Score:           34.2,
		Level:           LevelCool,
		LevelLabel:      LabelForLevel(LevelCool),
		Change1D:        &c1,
		Change5D:        &c5,
		VolatilityAlert: true,
		VolatilityNote:  "黄金隐含波动率（GVZ=28.7）处于近 3 年 91% 高位，历史同期短期振幅往往放大。",
		MacroRegime:     DescribeMacroRegime(RegimeTailwind, 74.5),
		ActionGuide:     BuildActionGuide(DescribeMacroRegime(RegimeTailwind, 74.5), LevelCool, 34.2, &dev, &prem, true),
		Dimensions: []TemperatureDimension{
			{Key: DimTrendMomentum, Name: "趋势与动量", Weight: 0.30, Score: 42.0, Available: true, Status: LevelNeutral, Summary: "动量读数 42.0", Metrics: map[string]float64{"gold_price_usd": 2980.5, "ma200_deviation_pct": 8.4}},
			{Key: DimPositioning, Name: "交易拥挤度", Weight: 0.25, Score: 28.0, Available: true, Status: LevelCool, Summary: "拥挤度 28.0", Metrics: map[string]float64{"mm_net_ratio_pct": 21.5}},
			{Key: DimDomesticPremium, Name: "国内溢价热度", Weight: 0.15, Score: 35.0, Available: true, Status: LevelCool, Summary: "溢价热度 35.0", Metrics: map[string]float64{"shanghai_premium_pct": 0.65}},
			{Key: DimFlowCrossAsset, Name: "资金与跨资产", Weight: 0.15, Score: 31.0, Available: true, Status: LevelCool, Summary: "资金流读数 31.0", Metrics: map[string]float64{}},
			{Key: DimMacroPulse, Name: "短期宏观脉冲", Weight: 0.15, Score: 33.0, Available: true, Status: LevelCool, Summary: "宏观脉冲 33.0", Metrics: map[string]float64{}},
		},
	}

	brief := BuildStrategyBrief(StrategyBriefInput{
		Snapshot: snap,
		Treasury: &TreasurySummary{
			TotalDebtTrillionUSD:  &debt,
			DebtChangeYoYTrillion: &debtYoY,
			DebtToGDPPct:          &debtGDP,
			FiscalStressScore:     &fiscal,
			Yield10YNominalPct:    &y10,
			Yield10YRealPct:       &realY10,
			Breakeven10YPct:       &be10,
		},
		LatestCot: &CotObservation{
			Date:         d(2026, 4, 7),
			MMLong:       220000,
			MMShort:      50000,
			MMNet:        170000,
			OpenInterest: 500000,
		},
		OfficialAccountName: "测试宏观笔记",
	})

	for _, want := range []string{"测试宏观笔记", "2026-04-10", "34.2°", "36.45 万亿美元", "2.08%", "1.2x", "我个人的黄金量化观察框架", "不构成任何投资建议"} {
		if !strings.Contains(brief.OfficialAccountReply, want) {
			t.Errorf("OfficialAccountReply missing %q:\n%s", want, brief.OfficialAccountReply)
		}
	}
	for _, want := range []string{"# 测试宏观笔记", "## 1. 黄金温度与宏观底座", "## 2. 五维情绪分位拆解", "## 3. 美债与 CFTC COT 关键指标", "## 4. 我的个人观察框架记录", "趋势与动量", "170000", "34.00%", "1.2x", "个人观察框架"} {
		if !strings.Contains(brief.CommunityBrief, want) {
			t.Errorf("CommunityBrief missing %q:\n%s", want, brief.CommunityBrief)
		}
	}

	// Cold-start degraded snapshot should still render safely without panicking.
	coldBrief := BuildStrategyBrief(StrategyBriefInput{Snapshot: EmptyTemperatureSnapshot()})
	if coldBrief.OfficialAccountReply == "" || coldBrief.CommunityBrief == "" {
		t.Fatalf("expected non-empty cold-start templates")
	}
}
