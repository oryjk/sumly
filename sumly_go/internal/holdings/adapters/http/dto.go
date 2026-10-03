package holdingshttp

import (
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
)

// Adapter-owned JSON schema; domain models do not define serialization.
type documentDTO struct {
	SchemaVersion int         `json:"schemaVersion"`
	Books         []string    `json:"books"`
	Records       []recordDTO `json:"records"`
}
type snapshotDTO struct {
	Revision int64       `json:"revision"`
	Document documentDTO `json:"document"`
}
type recordDTO struct {
	ID                    string     `json:"id"`
	Grams                 float64    `json:"grams"`
	UnitPriceCNY          float64    `json:"unitPriceCNY"`
	Timestamp             float64    `json:"timestamp"`
	Note                  string     `json:"note"`
	CreatedAt             float64    `json:"createdAt"`
	Brand                 string     `json:"brand"`
	BookName              string     `json:"bookName"`
	Disposition           string     `json:"disposition"`
	DisposedAt            *float64   `json:"disposedAt,omitempty"`
	DisposalAmount        float64    `json:"disposalAmount"`
	PurchaseID            *string    `json:"purchaseID,omitempty"`
	ExtraFee              float64    `json:"extraFee"`
	PurchaseChannel       string     `json:"purchaseChannel"`
	Counterparty          string     `json:"counterparty"`
	AssetType             string     `json:"assetType"`
	Purity                float64    `json:"purity"`
	LaborFee              float64    `json:"laborFee"`
	PurchaseTotalOverride *float64   `json:"purchaseTotalOverride,omitempty"`
	RecoveryDeduction     float64    `json:"recoveryDeduction"`
	RecoveryDiscount      float64    `json:"recoveryDiscount"`
	RecoveryFixedFee      float64    `json:"recoveryFixedFee"`
	Alerts                []alertDTO `json:"alerts"`
}
type alertDTO struct {
	ID        string  `json:"id"`
	Kind      string  `json:"kind"`
	Threshold float64 `json:"threshold"`
	Enabled   bool    `json:"enabled"`
	Basis     string  `json:"basis"`
}

func documentFromDomain(d domain.Document) documentDTO {
	var records []recordDTO
	if d.Records != nil {
		records = make([]recordDTO, len(d.Records))
		for i, r := range d.Records {
			records[i] = recordFromDomain(r)
		}
	}
	return documentDTO{SchemaVersion: d.SchemaVersion, Books: d.Books, Records: records}
}
func (d documentDTO) toDomain() domain.Document {
	var records []domain.Record
	if d.Records != nil {
		records = make([]domain.Record, len(d.Records))
		for i, r := range d.Records {
			records[i] = r.toDomain()
		}
	}
	return domain.Document{SchemaVersion: d.SchemaVersion, Books: d.Books, Records: records}
}
func recordFromDomain(r domain.Record) recordDTO {
	var alerts []alertDTO
	if r.Alerts != nil {
		alerts = make([]alertDTO, len(r.Alerts))
		for i, a := range r.Alerts {
			alerts[i] = alertDTO(a)
		}
	}
	return recordDTO{
		ID:                    r.ID,
		Grams:                 r.Grams,
		UnitPriceCNY:          r.UnitPriceCNY,
		Timestamp:             r.Timestamp,
		Note:                  r.Note,
		CreatedAt:             r.CreatedAt,
		Brand:                 r.Brand,
		BookName:              r.BookName,
		Disposition:           r.Disposition,
		DisposedAt:            r.DisposedAt,
		DisposalAmount:        r.DisposalAmount,
		PurchaseID:            r.PurchaseID,
		ExtraFee:              r.ExtraFee,
		PurchaseChannel:       r.PurchaseChannel,
		Counterparty:          r.Counterparty,
		AssetType:             r.AssetType,
		Purity:                r.Purity,
		LaborFee:              r.LaborFee,
		PurchaseTotalOverride: r.PurchaseTotalOverride,
		RecoveryDeduction:     r.RecoveryDeduction,
		RecoveryDiscount:      r.RecoveryDiscount,
		RecoveryFixedFee:      r.RecoveryFixedFee,
		Alerts:                alerts,
	}
}
func (r recordDTO) toDomain() domain.Record {
	var alerts []domain.Alert
	if r.Alerts != nil {
		alerts = make([]domain.Alert, len(r.Alerts))
		for i, a := range r.Alerts {
			alerts[i] = domain.Alert(a)
		}
	}
	return domain.Record{
		ID:                    r.ID,
		Grams:                 r.Grams,
		UnitPriceCNY:          r.UnitPriceCNY,
		Timestamp:             r.Timestamp,
		Note:                  r.Note,
		CreatedAt:             r.CreatedAt,
		Brand:                 r.Brand,
		BookName:              r.BookName,
		Disposition:           r.Disposition,
		DisposedAt:            r.DisposedAt,
		DisposalAmount:        r.DisposalAmount,
		PurchaseID:            r.PurchaseID,
		ExtraFee:              r.ExtraFee,
		PurchaseChannel:       r.PurchaseChannel,
		Counterparty:          r.Counterparty,
		AssetType:             r.AssetType,
		Purity:                r.Purity,
		LaborFee:              r.LaborFee,
		PurchaseTotalOverride: r.PurchaseTotalOverride,
		RecoveryDeduction:     r.RecoveryDeduction,
		RecoveryDiscount:      r.RecoveryDiscount,
		RecoveryFixedFee:      r.RecoveryFixedFee,
		Alerts:                alerts,
	}
}
