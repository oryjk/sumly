package postgres

import (
	"encoding/json"

	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
)

// Adapter-owned JSON schema; domain models do not define serialization.
type storedDocument struct {
	SchemaVersion int            `json:"schemaVersion"`
	Books         []string       `json:"books"`
	Records       []storedRecord `json:"records"`
}
type storedSnapshot struct {
	Revision int64          `json:"revision"`
	Document storedDocument `json:"document"`
}
type storedRecord struct {
	ID                    string        `json:"id"`
	Grams                 float64       `json:"grams"`
	UnitPriceCNY          float64       `json:"unitPriceCNY"`
	Timestamp             float64       `json:"timestamp"`
	Note                  string        `json:"note"`
	CreatedAt             float64       `json:"createdAt"`
	Brand                 string        `json:"brand"`
	BookName              string        `json:"bookName"`
	Disposition           string        `json:"disposition"`
	DisposedAt            *float64      `json:"disposedAt,omitempty"`
	DisposalAmount        float64       `json:"disposalAmount"`
	PurchaseID            *string       `json:"purchaseID,omitempty"`
	ExtraFee              float64       `json:"extraFee"`
	PurchaseChannel       string        `json:"purchaseChannel"`
	Counterparty          string        `json:"counterparty"`
	AssetType             string        `json:"assetType"`
	Purity                float64       `json:"purity"`
	LaborFee              float64       `json:"laborFee"`
	PurchaseTotalOverride *float64      `json:"purchaseTotalOverride,omitempty"`
	RecoveryDeduction     float64       `json:"recoveryDeduction"`
	RecoveryDiscount      float64       `json:"recoveryDiscount"`
	RecoveryFixedFee      float64       `json:"recoveryFixedFee"`
	Alerts                []storedAlert `json:"alerts"`
}
type storedAlert struct {
	ID        string  `json:"id"`
	Kind      string  `json:"kind"`
	Threshold float64 `json:"threshold"`
	Enabled   bool    `json:"enabled"`
	Basis     string  `json:"basis"`
}

func storedDocumentFromDomain(d domain.Document) storedDocument {
	var records []storedRecord
	if d.Records != nil {
		records = make([]storedRecord, len(d.Records))
		for i, r := range d.Records {
			records[i] = storedRecordFromDomain(r)
		}
	}
	return storedDocument{SchemaVersion: d.SchemaVersion, Books: d.Books, Records: records}
}
func (d storedDocument) toDomain() domain.Document {
	var records []domain.Record
	if d.Records != nil {
		records = make([]domain.Record, len(d.Records))
		for i, r := range d.Records {
			records[i] = r.toDomain()
		}
	}
	return domain.Document{SchemaVersion: d.SchemaVersion, Books: d.Books, Records: records}
}
func storedRecordFromDomain(r domain.Record) storedRecord {
	var alerts []storedAlert
	if r.Alerts != nil {
		alerts = make([]storedAlert, len(r.Alerts))
		for i, a := range r.Alerts {
			alerts[i] = storedAlert(a)
		}
	}
	return storedRecord{
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
func (r storedRecord) toDomain() domain.Record {
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

func encodeDocument(d domain.Document) ([]byte, error) {
	return json.Marshal(storedDocumentFromDomain(d))
}
func snapshotSize(rev int64, d domain.Document) (int, error) {
	b, err := json.Marshal(storedSnapshot{Revision: rev, Document: storedDocumentFromDomain(d)})
	return len(b), err
}
