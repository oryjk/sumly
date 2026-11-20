package domain

import (
	"fmt"
	"math"
	"sort"
	"strings"
	"time"
)

const (
	ModelVersionV1   = "v1"
	GramsPerTroyOz   = 31.1035
	OuncesPerTonne   = 32150.747
	RollingWindow3Y  = 756
	MinRollingPoints = 20
)

type Range string

const (
	Range1Y  Range = "1y"
	Range3Y  Range = "3y"
	Range5Y  Range = "5y"
	Range10Y Range = "10y"
	RangeAll Range = "all"
)

type Observation struct {
	Date  time.Time
	Value float64
}

type CotObservation struct {
	Date         time.Time
	MMLong       float64
	MMShort      float64
	MMNet        float64
	SwapLong     float64
	SwapShort    float64
	SwapNet      float64
	OpenInterest float64
}

func (c CotObservation) MMNetRatioPct() *float64 {
	if !IsFinite(c.OpenInterest) || c.OpenInterest <= 0 || !IsFinite(c.MMNet) {
		return nil
	}
	v := RoundTo(c.MMNet/c.OpenInterest*100.0, 2)
	return &v
}

type SeriesMeta struct {
	SeriesID     string
	NameZh       string
	Section      string
	Unit         string
	Frequency    string
	Source       string
	GoldRelation string
	PlainNote    string
	DisplayOrder int
}

type SectionMeta struct {
	ID           string
	NameZh       string
	Description  string
	DisplayOrder int
}

type SyncState struct {
	SeriesID      string
	Source        string
	Status        string
	LastSyncedAt  *time.Time
	LastSuccessAt *time.Time
	LastError     string
	RowCount      int
	LatestObsDate *time.Time
}

type ChangeMetrics struct {
	Change5D  *float64
	Change20D *float64
	Change3M  *float64
	ChangeYoY *float64
}

type PercentilePoint struct {
	Window           string
	Percentile       float64
	ObservationCount int
}

type IndicatorSummary struct {
	Meta         SeriesMeta
	LatestDate   *time.Time
	LatestValue  *float64
	Changes      ChangeMetrics
	Percentile3Y *float64
	Sparkline    []float64
}

type IndicatorDetail struct {
	Summary      IndicatorSummary
	Range        Range
	Percentiles  []PercentilePoint
	LastSyncedAt *time.Time
	SyncStatus   string
	Observations []Observation
}

type SectionWithIndicators struct {
	Section    SectionMeta
	Indicators []IndicatorSummary
}

type TreasurySummary struct {
	TotalDebtTrillionUSD  *float64
	DebtChangeYoYTrillion *float64
	DebtToGDPPct          *float64
	InterestToRevenuePct  *float64
	FiscalStressScore     *float64
	Yield10YNominalPct    *float64
	Yield2YNominalPct     *float64
	Spread10Y2YPct        *float64
	Yield10YRealPct       *float64
	Breakeven10YPct       *float64
	TLTPrice              *float64
	GoldImpactNote        string
}

type TreasuryDashboard struct {
	AsOf               string
	Summary            TreasurySummary
	Cards              []IndicatorSummary
	DebtSeries         []Observation
	RealYieldSeries    []Observation
	NominalYieldSeries []Observation
}

type CotDashboard struct {
	SeriesID string
	Range    Range
	Latest   *CotObservation
	Points   []CotObservation
}

type SyncStatusOverview struct {
	TotalSeries  int
	OKCount      int
	ErrorCount   int
	SkippedCount int
	PendingCount int
	LastSyncedAt *time.Time
	States       []SyncState
}

func NormalizeDate(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func ParseDate(s string) (time.Time, error) {
	s = strings.TrimSpace(s)
	if len(s) >= 10 {
		if t, err := time.Parse("2006-01-02", s[:10]); err == nil {
			return NormalizeDate(t), nil
		}
	}
	return time.Time{}, fmt.Errorf("invalid date %q", s)
}

func FormatDate(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return NormalizeDate(t).Format("2006-01-02")
}

func IsFinite(v float64) bool {
	return !math.IsNaN(v) && !math.IsInf(v, 0)
}

func RoundTo(v float64, decimals int) float64 {
	if !IsFinite(v) {
		return 0
	}
	pow := math.Pow(10, float64(decimals))
	return math.Round(v*pow) / pow
}

func ParseRange(raw string, defaultRange Range, allow10Y bool) (Range, bool) {
	v := strings.ToLower(strings.TrimSpace(raw))
	if v == "" {
		return defaultRange, true
	}
	switch Range(v) {
	case Range1Y, Range3Y, Range5Y, RangeAll:
		return Range(v), true
	case Range10Y:
		if allow10Y {
			return Range10Y, true
		}
		return "", false
	default:
		return "", false
	}
}

func RangeStartDate(latest time.Time, r Range) *time.Time {
	if latest.IsZero() || r == RangeAll {
		return nil
	}
	latest = NormalizeDate(latest)
	var start time.Time
	switch r {
	case Range1Y:
		start = latest.AddDate(-1, 0, 0)
	case Range3Y:
		start = latest.AddDate(-3, 0, 0)
	case Range5Y:
		start = latest.AddDate(-5, 0, 0)
	case Range10Y:
		start = latest.AddDate(-10, 0, 0)
	default:
		return nil
	}
	return &start
}

func FilterObservationsByRange(obs []Observation, r Range) []Observation {
	clean := SanitizeObservations(obs)
	if len(clean) == 0 || r == RangeAll {
		return clean
	}
	start := RangeStartDate(clean[len(clean)-1].Date, r)
	if start == nil {
		return clean
	}
	out := make([]Observation, 0, len(clean))
	for _, item := range clean {
		if !item.Date.Before(*start) {
			out = append(out, item)
		}
	}
	return out
}

func FilterCotByRange(obs []CotObservation, r Range) []CotObservation {
	clean := SanitizeCotObservations(obs)
	if len(clean) == 0 || r == RangeAll {
		return clean
	}
	start := RangeStartDate(clean[len(clean)-1].Date, r)
	if start == nil {
		return clean
	}
	out := make([]CotObservation, 0, len(clean))
	for _, item := range clean {
		if !item.Date.Before(*start) {
			out = append(out, item)
		}
	}
	return out
}

// SanitizeObservations drops non-finite values, normalizes dates, deduplicates by date (last wins), and sorts ascending.
func SanitizeObservations(in []Observation) []Observation {
	if len(in) == 0 {
		return []Observation{}
	}
	byDate := make(map[string]Observation, len(in))
	for _, o := range in {
		if o.Date.IsZero() || !IsFinite(o.Value) {
			continue
		}
		d := NormalizeDate(o.Date)
		byDate[d.Format("2006-01-02")] = Observation{Date: d, Value: o.Value}
	}
	out := make([]Observation, 0, len(byDate))
	for _, o := range byDate {
		out = append(out, o)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date.Before(out[j].Date) })
	return out
}

func SanitizeCotObservations(in []CotObservation) []CotObservation {
	if len(in) == 0 {
		return []CotObservation{}
	}
	byDate := make(map[string]CotObservation, len(in))
	for _, o := range in {
		if o.Date.IsZero() ||
			!IsFinite(o.MMLong) || !IsFinite(o.MMShort) || !IsFinite(o.MMNet) ||
			!IsFinite(o.SwapLong) || !IsFinite(o.SwapShort) || !IsFinite(o.SwapNet) ||
			!IsFinite(o.OpenInterest) {
			continue
		}
		d := NormalizeDate(o.Date)
		o.Date = d
		byDate[d.Format("2006-01-02")] = o
	}
	out := make([]CotObservation, 0, len(byDate))
	for _, o := range byDate {
		out = append(out, o)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date.Before(out[j].Date) })
	return out
}

func ValueOnOrBefore(sorted []Observation, target time.Time) (float64, bool) {
	if len(sorted) == 0 {
		return 0, false
	}
	target = NormalizeDate(target)
	idx := sort.Search(len(sorted), func(i int) bool {
		return sorted[i].Date.After(target)
	})
	if idx == 0 {
		return 0, false
	}
	return sorted[idx-1].Value, true
}

func CalculateChanges(obs []Observation) ChangeMetrics {
	sorted := SanitizeObservations(obs)
	if len(sorted) < 2 {
		return ChangeMetrics{}
	}
	latest := sorted[len(sorted)-1]
	diffAt := func(days int) *float64 {
		target := latest.Date.AddDate(0, 0, -days)
		base, ok := ValueOnOrBefore(sorted, target)
		if !ok {
			return nil
		}
		diff := RoundTo(latest.Value-base, 4)
		return &diff
	}
	return ChangeMetrics{
		Change5D:  diffAt(5),
		Change20D: diffAt(20),
		Change3M:  diffAt(90),
		ChangeYoY: diffAt(365),
	}
}

// MidrankPercentile computes the midrank percentile (0-100) of current inside window.
func MidrankPercentile(window []float64, current float64) float64 {
	if len(window) == 0 || !IsFinite(current) {
		return 50
	}
	below := 0
	equal := 0
	valid := 0
	for _, v := range window {
		if !IsFinite(v) {
			continue
		}
		valid++
		if v < current {
			below++
		} else if v == current {
			equal++
		}
	}
	if valid == 0 {
		return 50
	}
	pct := (float64(below) + 0.5*float64(equal)) / float64(valid) * 100.0
	if pct < 0 {
		return 0
	}
	if pct > 100 {
		return 100
	}
	return RoundTo(pct, 1)
}

func CalculatePercentiles(obs []Observation) []PercentilePoint {
	sorted := SanitizeObservations(obs)
	if len(sorted) == 0 {
		return []PercentilePoint{}
	}
	latest := sorted[len(sorted)-1]
	windows := []struct {
		label string
		rng   Range
	}{
		{"1y", Range1Y},
		{"3y", Range3Y},
		{"5y", Range5Y},
		{"10y", Range10Y},
		{"all", RangeAll},
	}
	out := make([]PercentilePoint, 0, len(windows))
	for _, w := range windows {
		slice := FilterObservationsByRange(sorted, w.rng)
		if len(slice) < 2 && w.rng != RangeAll {
			continue
		}
		vals := make([]float64, 0, len(slice))
		for _, item := range slice {
			vals = append(vals, item.Value)
		}
		out = append(out, PercentilePoint{
			Window:           w.label,
			Percentile:       MidrankPercentile(vals, latest.Value),
			ObservationCount: len(vals),
		})
	}
	return out
}

func Percentile3Y(obs []Observation) *float64 {
	sorted := SanitizeObservations(obs)
	if len(sorted) < 2 {
		return nil
	}
	slice := FilterObservationsByRange(sorted, Range3Y)
	if len(slice) < 2 {
		slice = sorted
	}
	vals := make([]float64, 0, len(slice))
	for _, item := range slice {
		vals = append(vals, item.Value)
	}
	p := MidrankPercentile(vals, sorted[len(sorted)-1].Value)
	return &p
}

func Sparkline(obs []Observation, maxPoints int) []float64 {
	sorted := SanitizeObservations(obs)
	if len(sorted) == 0 || maxPoints <= 0 {
		return []float64{}
	}
	start := 0
	if len(sorted) > maxPoints {
		start = len(sorted) - maxPoints
	}
	out := make([]float64, 0, len(sorted)-start)
	for _, item := range sorted[start:] {
		out = append(out, RoundTo(item.Value, 4))
	}
	return out
}

func BuildIndicatorSummary(meta SeriesMeta, obs []Observation) IndicatorSummary {
	sorted := SanitizeObservations(obs)
	summary := IndicatorSummary{
		Meta:      meta,
		Sparkline: Sparkline(sorted, 30),
	}
	if len(sorted) == 0 {
		return summary
	}
	latest := sorted[len(sorted)-1]
	d := latest.Date
	v := RoundTo(latest.Value, 4)
	summary.LatestDate = &d
	summary.LatestValue = &v
	summary.Changes = CalculateChanges(sorted)
	summary.Percentile3Y = Percentile3Y(sorted)
	return summary
}
