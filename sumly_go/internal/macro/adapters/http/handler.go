package macrohttp

import (
	"context"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	"github.com/gin-gonic/gin"
)

// QueryUseCase is strictly read-only; HTTP handlers never trigger external fetches or DB writes.
type QueryUseCase interface {
	GetTemperature(ctx context.Context) (domain.TemperatureSnapshot, error)
	GetTemperatureHistory(ctx context.Context, rawRange string) (domain.Range, []domain.TemperatureDailyPoint, error)
	GetTreasuryDashboard(ctx context.Context, rawRange string) (domain.TreasuryDashboard, error)
	ListIndicators(ctx context.Context, section string) ([]domain.SectionWithIndicators, error)
	GetIndicatorDetail(ctx context.Context, seriesID, rawRange string) (domain.IndicatorDetail, error)
	GetGoldCot(ctx context.Context, rawRange string) (domain.CotDashboard, error)
	GetSyncStatus(ctx context.Context) (domain.SyncStatusOverview, error)
}

type Handler struct {
	query QueryUseCase
}

func NewHandler(query QueryUseCase) *Handler {
	return &Handler{query: query}
}

func (h *Handler) RegisterPublicRoutes(group *gin.RouterGroup) {
	macro := group.Group("/macro")
	macro.GET("/temperature", h.Temperature)
	macro.GET("/temperature/history", h.TemperatureHistory)
	macro.GET("/treasury", h.Treasury)
	macro.GET("/indicators", h.Indicators)
	macro.GET("/indicators/:series_id", h.IndicatorDetail)
	macro.GET("/cot/gold", h.GoldCot)
	macro.GET("/sync/status", h.SyncStatus)
}

type TemperatureResponse struct {
	AsOf            string                         `json:"as_of"`
	ModelVersion    string                         `json:"model_version"`
	Degraded        bool                           `json:"degraded"`
	MissingFactors  []string                       `json:"missing_factors"`
	Score           float64                        `json:"score"`
	Level           string                         `json:"level"`
	LevelLabel      string                         `json:"level_label"`
	Change1D        *float64                       `json:"change_1d"`
	Change5D        *float64                       `json:"change_5d"`
	VolatilityAlert bool                           `json:"volatility_alert"`
	VolatilityNote  string                         `json:"volatility_note"`
	MacroRegime     MacroRegimeResponse            `json:"macro_regime"`
	ActionGuide     ActionGuideResponse            `json:"action_guide"`
	Dimensions      []TemperatureDimensionResponse `json:"dimensions"`
}

type MacroRegimeResponse struct {
	Score   float64 `json:"score"`
	Regime  string  `json:"regime"`
	Label   string  `json:"label"`
	Summary string  `json:"summary"`
}

type ActionGuideResponse struct {
	Signal              string   `json:"signal"`
	Title               string   `json:"title"`
	Summary             string   `json:"summary"`
	DCAMultiplier       float64  `json:"dca_multiplier"`
	DCALabel            string   `json:"dca_label"`
	MA200DeviationPct   *float64 `json:"ma200_deviation_pct"`
	MA200Note           string   `json:"ma200_note"`
	DomesticPremiumPct  *float64 `json:"domestic_premium_pct"`
	DomesticPremiumNote string   `json:"domestic_premium_note"`
	Disclaimer          string   `json:"disclaimer"`
}

type TemperatureDimensionResponse struct {
	Key       string             `json:"key"`
	Name      string             `json:"name"`
	Weight    float64            `json:"weight"`
	Score     float64            `json:"score"`
	Available bool               `json:"available"`
	Status    string             `json:"status"`
	Summary   string             `json:"summary"`
	Metrics   map[string]float64 `json:"metrics"`
}

type TemperatureHistoryPointResponse struct {
	Date         string   `json:"date"`
	Score        float64  `json:"score"`
	Level        string   `json:"level"`
	GoldPriceUSD *float64 `json:"gold_price_usd"`
}

type TemperatureHistoryResponse struct {
	Range        string                            `json:"range"`
	ModelVersion string                            `json:"model_version"`
	Points       []TemperatureHistoryPointResponse `json:"points"`
}

type DateValuePointResponse struct {
	Date  string  `json:"date"`
	Value float64 `json:"value"`
}

type IndicatorSummaryResponse struct {
	SeriesID     string    `json:"series_id"`
	NameZh       string    `json:"name_zh"`
	Section      string    `json:"section"`
	Unit         string    `json:"unit"`
	Frequency    string    `json:"frequency"`
	Source       string    `json:"source"`
	GoldRelation string    `json:"gold_relation"`
	PlainNote    string    `json:"plain_note"`
	LatestDate   *string   `json:"latest_date"`
	LatestValue  *float64  `json:"latest_value"`
	Change5D     *float64  `json:"change_5d"`
	Change20D    *float64  `json:"change_20d"`
	Change3M     *float64  `json:"change_3m"`
	ChangeYoY    *float64  `json:"change_yoy"`
	Percentile3Y *float64  `json:"percentile_3y"`
	Sparkline    []float64 `json:"sparkline"`
}

type TreasurySummaryResponse struct {
	TotalDebtTrillionUSD  *float64 `json:"total_debt_trillion_usd"`
	DebtChangeYoYTrillion *float64 `json:"debt_change_yoy_trillion"`
	DebtToGDPPct          *float64 `json:"debt_to_gdp_pct"`
	InterestToRevenuePct  *float64 `json:"interest_to_revenue_pct"`
	FiscalStressScore     *float64 `json:"fiscal_stress_score"`
	Yield10YNominalPct    *float64 `json:"yield_10y_nominal_pct"`
	Yield2YNominalPct     *float64 `json:"yield_2y_nominal_pct"`
	Spread10Y2YPct        *float64 `json:"spread_10y_2y_pct"`
	Yield10YRealPct       *float64 `json:"yield_10y_real_pct"`
	Breakeven10YPct       *float64 `json:"breakeven_10y_pct"`
	TLTPrice              *float64 `json:"tlt_price"`
	GoldImpactNote        string   `json:"gold_impact_note"`
}

type TreasuryResponse struct {
	AsOf               string                     `json:"as_of"`
	Summary            TreasurySummaryResponse    `json:"summary"`
	Cards              []IndicatorSummaryResponse `json:"cards"`
	DebtSeries         []DateValuePointResponse   `json:"debt_series"`
	RealYieldSeries    []DateValuePointResponse   `json:"real_yield_series"`
	NominalYieldSeries []DateValuePointResponse   `json:"nominal_yield_series"`
}

type SectionIndicatorsResponse struct {
	ID          string                     `json:"id"`
	NameZh      string                     `json:"name_zh"`
	Description string                     `json:"description"`
	Indicators  []IndicatorSummaryResponse `json:"indicators"`
}

type IndicatorsListResponse struct {
	Sections []SectionIndicatorsResponse `json:"sections"`
}

type PercentileResponse struct {
	Window           string  `json:"window"`
	Percentile       float64 `json:"percentile"`
	ObservationCount int     `json:"observation_count"`
}

type IndicatorDetailResponse struct {
	SeriesID     string                   `json:"series_id"`
	NameZh       string                   `json:"name_zh"`
	Section      string                   `json:"section"`
	Unit         string                   `json:"unit"`
	Frequency    string                   `json:"frequency"`
	Source       string                   `json:"source"`
	GoldRelation string                   `json:"gold_relation"`
	PlainNote    string                   `json:"plain_note"`
	LatestDate   *string                  `json:"latest_date"`
	LatestValue  *float64                 `json:"latest_value"`
	Change5D     *float64                 `json:"change_5d"`
	Change20D    *float64                 `json:"change_20d"`
	Change3M     *float64                 `json:"change_3m"`
	ChangeYoY    *float64                 `json:"change_yoy"`
	Percentile3Y *float64                 `json:"percentile_3y"`
	Range        string                   `json:"range"`
	Percentiles  []PercentileResponse     `json:"percentiles"`
	LastSyncedAt *string                  `json:"last_synced_at"`
	SyncStatus   string                   `json:"sync_status"`
	Observations []DateValuePointResponse `json:"observations"`
}

type CotPointResponse struct {
	Date          string   `json:"date"`
	MMLong        float64  `json:"mm_long"`
	MMShort       float64  `json:"mm_short"`
	MMNet         float64  `json:"mm_net"`
	SwapLong      float64  `json:"swap_long"`
	SwapShort     float64  `json:"swap_short"`
	SwapNet       float64  `json:"swap_net"`
	OpenInterest  float64  `json:"open_interest"`
	MMNetRatioPct *float64 `json:"mm_net_ratio_pct"`
}

type GoldCotResponse struct {
	SeriesID string             `json:"series_id"`
	Range    string             `json:"range"`
	Latest   *CotPointResponse  `json:"latest"`
	Points   []CotPointResponse `json:"points"`
}

type SyncStateResponse struct {
	SeriesID      string  `json:"series_id"`
	Source        string  `json:"source"`
	Status        string  `json:"status"`
	LastSyncedAt  *string `json:"last_synced_at"`
	LastSuccessAt *string `json:"last_success_at"`
	LastError     string  `json:"last_error"`
	RowCount      int     `json:"row_count"`
	LatestObsDate *string `json:"latest_obs_date"`
}

type SyncStatusResponse struct {
	TotalSeries  int                 `json:"total_series"`
	OKCount      int                 `json:"ok_count"`
	ErrorCount   int                 `json:"error_count"`
	SkippedCount int                 `json:"skipped_count"`
	PendingCount int                 `json:"pending_count"`
	LastSyncedAt *string             `json:"last_synced_at"`
	States       []SyncStateResponse `json:"states"`
}

func (h *Handler) Temperature(c *gin.Context) {
	snap, err := h.query.GetTemperature(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	missing := snap.MissingFactors
	if missing == nil {
		missing = []string{}
	}
	dims := make([]TemperatureDimensionResponse, 0, len(snap.Dimensions))
	for _, d := range snap.Dimensions {
		metrics := d.Metrics
		if metrics == nil {
			metrics = map[string]float64{}
		}
		dims = append(dims, TemperatureDimensionResponse{
			Key:       d.Key,
			Name:      d.Name,
			Weight:    d.Weight,
			Score:     d.Score,
			Available: d.Available,
			Status:    d.Status,
			Summary:   d.Summary,
			Metrics:   metrics,
		})
	}
	sharedhttpapi.WriteSuccess(c, TemperatureResponse{
		AsOf:            snap.AsOf,
		ModelVersion:    snap.ModelVersion,
		Degraded:        snap.Degraded,
		MissingFactors:  missing,
		Score:           snap.Score,
		Level:           snap.Level,
		LevelLabel:      snap.LevelLabel,
		Change1D:        snap.Change1D,
		Change5D:        snap.Change5D,
		VolatilityAlert: snap.VolatilityAlert,
		VolatilityNote:  snap.VolatilityNote,
		MacroRegime: MacroRegimeResponse{
			Score:   snap.MacroRegime.Score,
			Regime:  snap.MacroRegime.Regime,
			Label:   snap.MacroRegime.Label,
			Summary: snap.MacroRegime.Summary,
		},
		ActionGuide: ActionGuideResponse{
			Signal:              snap.ActionGuide.Signal,
			Title:               snap.ActionGuide.Title,
			Summary:             snap.ActionGuide.Summary,
			DCAMultiplier:       snap.ActionGuide.DCAMultiplier,
			DCALabel:            snap.ActionGuide.DCALabel,
			MA200DeviationPct:   snap.ActionGuide.MA200DeviationPct,
			MA200Note:           snap.ActionGuide.MA200Note,
			DomesticPremiumPct:  snap.ActionGuide.DomesticPremiumPct,
			DomesticPremiumNote: snap.ActionGuide.DomesticPremiumNote,
			Disclaimer:          snap.ActionGuide.Disclaimer,
		},
		Dimensions: dims,
	})
}

func (h *Handler) TemperatureHistory(c *gin.Context) {
	rng, points, err := h.query.GetTemperatureHistory(c.Request.Context(), c.Query("range"))
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	out := make([]TemperatureHistoryPointResponse, 0, len(points))
	for _, pt := range points {
		out = append(out, TemperatureHistoryPointResponse{
			Date:         domain.FormatDate(pt.Date),
			Score:        pt.Score,
			Level:        pt.Level,
			GoldPriceUSD: pt.GoldPriceUSD,
		})
	}
	sharedhttpapi.WriteSuccess(c, TemperatureHistoryResponse{
		Range:        string(rng),
		ModelVersion: domain.ModelVersionV1,
		Points:       out,
	})
}

func (h *Handler) Treasury(c *gin.Context) {
	dash, err := h.query.GetTreasuryDashboard(c.Request.Context(), c.Query("range"))
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	cards := make([]IndicatorSummaryResponse, 0, len(dash.Cards))
	for _, card := range dash.Cards {
		cards = append(cards, toIndicatorSummaryDTO(card))
	}
	sharedhttpapi.WriteSuccess(c, TreasuryResponse{
		AsOf: dash.AsOf,
		Summary: TreasurySummaryResponse{
			TotalDebtTrillionUSD:  dash.Summary.TotalDebtTrillionUSD,
			DebtChangeYoYTrillion: dash.Summary.DebtChangeYoYTrillion,
			DebtToGDPPct:          dash.Summary.DebtToGDPPct,
			InterestToRevenuePct:  dash.Summary.InterestToRevenuePct,
			FiscalStressScore:     dash.Summary.FiscalStressScore,
			Yield10YNominalPct:    dash.Summary.Yield10YNominalPct,
			Yield2YNominalPct:     dash.Summary.Yield2YNominalPct,
			Spread10Y2YPct:        dash.Summary.Spread10Y2YPct,
			Yield10YRealPct:       dash.Summary.Yield10YRealPct,
			Breakeven10YPct:       dash.Summary.Breakeven10YPct,
			TLTPrice:              dash.Summary.TLTPrice,
			GoldImpactNote:        dash.Summary.GoldImpactNote,
		},
		Cards:              cards,
		DebtSeries:         toDateValuePoints(dash.DebtSeries),
		RealYieldSeries:    toDateValuePoints(dash.RealYieldSeries),
		NominalYieldSeries: toDateValuePoints(dash.NominalYieldSeries),
	})
}

func (h *Handler) Indicators(c *gin.Context) {
	sections, err := h.query.ListIndicators(c.Request.Context(), c.Query("section"))
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	out := make([]SectionIndicatorsResponse, 0, len(sections))
	for _, sec := range sections {
		cards := make([]IndicatorSummaryResponse, 0, len(sec.Indicators))
		for _, item := range sec.Indicators {
			cards = append(cards, toIndicatorSummaryDTO(item))
		}
		out = append(out, SectionIndicatorsResponse{
			ID:          sec.Section.ID,
			NameZh:      sec.Section.NameZh,
			Description: sec.Section.Description,
			Indicators:  cards,
		})
	}
	sharedhttpapi.WriteSuccess(c, IndicatorsListResponse{Sections: out})
}

func (h *Handler) IndicatorDetail(c *gin.Context) {
	detail, err := h.query.GetIndicatorDetail(c.Request.Context(), c.Param("series_id"), c.Query("range"))
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	summary := toIndicatorSummaryDTO(detail.Summary)
	percentiles := make([]PercentileResponse, 0, len(detail.Percentiles))
	for _, p := range detail.Percentiles {
		percentiles = append(percentiles, PercentileResponse{
			Window:           p.Window,
			Percentile:       p.Percentile,
			ObservationCount: p.ObservationCount,
		})
	}
	sharedhttpapi.WriteSuccess(c, IndicatorDetailResponse{
		SeriesID:     summary.SeriesID,
		NameZh:       summary.NameZh,
		Section:      summary.Section,
		Unit:         summary.Unit,
		Frequency:    summary.Frequency,
		Source:       summary.Source,
		GoldRelation: summary.GoldRelation,
		PlainNote:    summary.PlainNote,
		LatestDate:   summary.LatestDate,
		LatestValue:  summary.LatestValue,
		Change5D:     summary.Change5D,
		Change20D:    summary.Change20D,
		Change3M:     summary.Change3M,
		ChangeYoY:    summary.ChangeYoY,
		Percentile3Y: summary.Percentile3Y,
		Range:        string(detail.Range),
		Percentiles:  percentiles,
		LastSyncedAt: formatRFC3339Ptr(detail.LastSyncedAt),
		SyncStatus:   detail.SyncStatus,
		Observations: toDateValuePoints(detail.Observations),
	})
}

func (h *Handler) GoldCot(c *gin.Context) {
	cot, err := h.query.GetGoldCot(c.Request.Context(), c.Query("range"))
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	var latest *CotPointResponse
	if cot.Latest != nil {
		dto := toCotPointDTO(*cot.Latest)
		latest = &dto
	}
	points := make([]CotPointResponse, 0, len(cot.Points))
	for _, pt := range cot.Points {
		points = append(points, toCotPointDTO(pt))
	}
	sharedhttpapi.WriteSuccess(c, GoldCotResponse{
		SeriesID: cot.SeriesID,
		Range:    string(cot.Range),
		Latest:   latest,
		Points:   points,
	})
}

func (h *Handler) SyncStatus(c *gin.Context) {
	status, err := h.query.GetSyncStatus(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	states := make([]SyncStateResponse, 0, len(status.States))
	for _, st := range status.States {
		states = append(states, SyncStateResponse{
			SeriesID:      st.SeriesID,
			Source:        st.Source,
			Status:        st.Status,
			LastSyncedAt:  formatRFC3339Ptr(st.LastSyncedAt),
			LastSuccessAt: formatRFC3339Ptr(st.LastSuccessAt),
			LastError:     st.LastError,
			RowCount:      st.RowCount,
			LatestObsDate: formatDatePtr(st.LatestObsDate),
		})
	}
	sharedhttpapi.WriteSuccess(c, SyncStatusResponse{
		TotalSeries:  status.TotalSeries,
		OKCount:      status.OKCount,
		ErrorCount:   status.ErrorCount,
		SkippedCount: status.SkippedCount,
		PendingCount: status.PendingCount,
		LastSyncedAt: formatRFC3339Ptr(status.LastSyncedAt),
		States:       states,
	})
}

func toIndicatorSummaryDTO(s domain.IndicatorSummary) IndicatorSummaryResponse {
	spark := s.Sparkline
	if spark == nil {
		spark = []float64{}
	}
	return IndicatorSummaryResponse{
		SeriesID:     s.Meta.SeriesID,
		NameZh:       s.Meta.NameZh,
		Section:      s.Meta.Section,
		Unit:         s.Meta.Unit,
		Frequency:    s.Meta.Frequency,
		Source:       s.Meta.Source,
		GoldRelation: s.Meta.GoldRelation,
		PlainNote:    s.Meta.PlainNote,
		LatestDate:   formatDatePtr(s.LatestDate),
		LatestValue:  s.LatestValue,
		Change5D:     s.Changes.Change5D,
		Change20D:    s.Changes.Change20D,
		Change3M:     s.Changes.Change3M,
		ChangeYoY:    s.Changes.ChangeYoY,
		Percentile3Y: s.Percentile3Y,
		Sparkline:    spark,
	}
}

func toDateValuePoints(obs []domain.Observation) []DateValuePointResponse {
	out := make([]DateValuePointResponse, 0, len(obs))
	for _, o := range obs {
		out = append(out, DateValuePointResponse{
			Date:  domain.FormatDate(o.Date),
			Value: o.Value,
		})
	}
	return out
}

func toCotPointDTO(c domain.CotObservation) CotPointResponse {
	return CotPointResponse{
		Date:          domain.FormatDate(c.Date),
		MMLong:        c.MMLong,
		MMShort:       c.MMShort,
		MMNet:         c.MMNet,
		SwapLong:      c.SwapLong,
		SwapShort:     c.SwapShort,
		SwapNet:       c.SwapNet,
		OpenInterest:  c.OpenInterest,
		MMNetRatioPct: c.MMNetRatioPct(),
	}
}

func formatDatePtr(t *time.Time) *string {
	if t == nil || t.IsZero() {
		return nil
	}
	s := domain.FormatDate(*t)
	return &s
}

func formatRFC3339Ptr(t *time.Time) *string {
	if t == nil || t.IsZero() {
		return nil
	}
	s := t.UTC().Format(time.RFC3339)
	return &s
}
