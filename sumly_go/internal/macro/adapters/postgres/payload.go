package postgres

import (
	"encoding/json"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

type temperaturePayloadDTO struct {
	AsOf            string                `json:"as_of"`
	ModelVersion    string                `json:"model_version"`
	Degraded        bool                  `json:"degraded"`
	MissingFactors  []string              `json:"missing_factors"`
	Score           float64               `json:"score"`
	Level           string                `json:"level"`
	LevelLabel      string                `json:"level_label"`
	Change1D        *float64              `json:"change_1d"`
	Change5D        *float64              `json:"change_5d"`
	VolatilityAlert bool                  `json:"volatility_alert"`
	VolatilityNote  string                `json:"volatility_note"`
	MacroRegime     macroRegimePayloadDTO `json:"macro_regime"`
	ActionGuide     actionGuidePayloadDTO `json:"action_guide"`
	Dimensions      []dimensionPayloadDTO `json:"dimensions"`
}

type macroRegimePayloadDTO struct {
	Score   float64 `json:"score"`
	Regime  string  `json:"regime"`
	Label   string  `json:"label"`
	Summary string  `json:"summary"`
}

type actionGuidePayloadDTO struct {
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

type dimensionPayloadDTO struct {
	Key       string             `json:"key"`
	Name      string             `json:"name"`
	Weight    float64            `json:"weight"`
	Score     float64            `json:"score"`
	Available bool               `json:"available"`
	Status    string             `json:"status"`
	Summary   string             `json:"summary"`
	Metrics   map[string]float64 `json:"metrics"`
}

func marshalSnapshotPayload(snap *domain.TemperatureSnapshot) ([]byte, error) {
	if snap == nil {
		return []byte("{}"), nil
	}
	missing := snap.MissingFactors
	if missing == nil {
		missing = []string{}
	}
	dims := make([]dimensionPayloadDTO, 0, len(snap.Dimensions))
	for _, d := range snap.Dimensions {
		m := d.Metrics
		if m == nil {
			m = map[string]float64{}
		}
		dims = append(dims, dimensionPayloadDTO{
			Key:       d.Key,
			Name:      d.Name,
			Weight:    d.Weight,
			Score:     d.Score,
			Available: d.Available,
			Status:    d.Status,
			Summary:   d.Summary,
			Metrics:   m,
		})
	}
	dto := temperaturePayloadDTO{
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
		MacroRegime: macroRegimePayloadDTO{
			Score:   snap.MacroRegime.Score,
			Regime:  snap.MacroRegime.Regime,
			Label:   snap.MacroRegime.Label,
			Summary: snap.MacroRegime.Summary,
		},
		ActionGuide: actionGuidePayloadDTO{
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
	}
	return json.Marshal(dto)
}

func unmarshalSnapshotPayload(raw []byte) *domain.TemperatureSnapshot {
	if len(raw) == 0 || string(raw) == "{}" {
		return nil
	}
	var dto temperaturePayloadDTO
	if err := json.Unmarshal(raw, &dto); err != nil {
		return nil
	}
	if dto.ModelVersion == "" && len(dto.Dimensions) == 0 {
		return nil
	}
	missing := dto.MissingFactors
	if missing == nil {
		missing = []string{}
	}
	dims := make([]domain.TemperatureDimension, 0, len(dto.Dimensions))
	for _, d := range dto.Dimensions {
		m := d.Metrics
		if m == nil {
			m = map[string]float64{}
		}
		dims = append(dims, domain.TemperatureDimension{
			Key:       d.Key,
			Name:      d.Name,
			Weight:    d.Weight,
			Score:     d.Score,
			Available: d.Available,
			Status:    d.Status,
			Summary:   d.Summary,
			Metrics:   m,
		})
	}
	return &domain.TemperatureSnapshot{
		AsOf:            dto.AsOf,
		ModelVersion:    dto.ModelVersion,
		Degraded:        dto.Degraded,
		MissingFactors:  missing,
		Score:           dto.Score,
		Level:           dto.Level,
		LevelLabel:      dto.LevelLabel,
		Change1D:        dto.Change1D,
		Change5D:        dto.Change5D,
		VolatilityAlert: dto.VolatilityAlert,
		VolatilityNote:  dto.VolatilityNote,
		MacroRegime: domain.MacroRegime{
			Score:   dto.MacroRegime.Score,
			Regime:  dto.MacroRegime.Regime,
			Label:   dto.MacroRegime.Label,
			Summary: dto.MacroRegime.Summary,
		},
		ActionGuide: domain.ActionGuide{
			Signal:              dto.ActionGuide.Signal,
			Title:               dto.ActionGuide.Title,
			Summary:             dto.ActionGuide.Summary,
			DCAMultiplier:       dto.ActionGuide.DCAMultiplier,
			DCALabel:            dto.ActionGuide.DCALabel,
			MA200DeviationPct:   dto.ActionGuide.MA200DeviationPct,
			MA200Note:           dto.ActionGuide.MA200Note,
			DomesticPremiumPct:  dto.ActionGuide.DomesticPremiumPct,
			DomesticPremiumNote: dto.ActionGuide.DomesticPremiumNote,
			Disclaimer:          dto.ActionGuide.Disclaimer,
		},
		Dimensions: dims,
	}
}
