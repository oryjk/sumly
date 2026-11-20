package domain

import (
	"math"
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
