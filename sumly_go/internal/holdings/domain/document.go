package domain

import (
	"math"
	"regexp"
	"strings"
	"unicode/utf8"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const MaxBytes = 4 * 1024 * 1024
const DefaultBook = "默认账本"

type Document struct {
	SchemaVersion int
	Books         []string
	Records       []Record
}
type Snapshot struct {
	Revision int64
	Document Document
}
type Record struct {
	ID                    string
	Grams                 float64
	UnitPriceCNY          float64
	Timestamp             float64
	Note                  string
	CreatedAt             float64
	Brand                 string
	BookName              string
	Disposition           string
	DisposedAt            *float64
	DisposalAmount        float64
	PurchaseID            *string
	ExtraFee              float64
	PurchaseChannel       string
	Counterparty          string
	AssetType             string
	Purity                float64
	LaborFee              float64
	PurchaseTotalOverride *float64
	RecoveryDeduction     float64
	RecoveryDiscount      float64
	RecoveryFixedFee      float64
	Alerts                []Alert
}
type Alert struct {
	ID        string
	Kind      string
	Threshold float64
	Enabled   bool
	Basis     string
}

func EmptyDocument() Document {
	return Document{SchemaVersion: 1, Books: []string{DefaultBook}, Records: []Record{}}
}
func invalid() error { return sharederror.New(sharederror.KindValidation, "持仓文档无效") }

var uuidPattern = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func finite(v float64) bool      { return !math.IsNaN(v) && !math.IsInf(v, 0) }
func nonnegative(v float64) bool { return finite(v) && v >= 0 }
func date(v float64) bool        { return finite(v) && v >= -62135596800000 && v <= 253402300799999 }
func text(v string, max int) bool {
	return utf8.ValidString(v) && utf8.RuneCountInString(v) <= max && !strings.ContainsAny(v, "\x00")
}
func (d Document) Validate() error {
	if d.SchemaVersion != 1 || d.Books == nil || len(d.Books) == 0 || len(d.Books) > 100 || d.Records == nil || len(d.Records) > 1000 {
		return invalid()
	}
	books := map[string]bool{}
	for _, b := range d.Books {
		if !text(b, 100) || strings.TrimSpace(b) == "" || books[b] {
			return invalid()
		}
		books[b] = true
	}
	ids := map[string]bool{}
	for _, r := range d.Records {
		id := strings.ToLower(r.ID)
		if !uuidPattern.MatchString(r.ID) || ids[id] {
			return invalid()
		}
		ids[id] = true
		if !finite(r.Grams) || r.Grams <= 0 || !nonnegative(r.UnitPriceCNY) || !date(r.Timestamp) || !date(r.CreatedAt) || !books[r.BookName] {
			return invalid()
		}
		if r.UnitPriceCNY == 0 && (r.PurchaseTotalOverride == nil || *r.PurchaseTotalOverride <= 0) {
			return invalid()
		}
		if r.Disposition != "holding" && r.Disposition != "sold" && r.Disposition != "gift" {
			return invalid()
		}
		if r.DisposedAt != nil && (!date(*r.DisposedAt) || *r.DisposedAt < r.Timestamp) {
			return invalid()
		}
		if r.Disposition != "holding" && r.DisposedAt == nil {
			return invalid()
		}
		if !text(r.Note, 2000) {
			return invalid()
		}
		for _, v := range []string{r.Brand, r.PurchaseChannel, r.Counterparty, r.AssetType} {
			if !text(v, 200) {
				return invalid()
			}
		}
		if r.PurchaseID != nil && !uuidPattern.MatchString(*r.PurchaseID) {
			return invalid()
		}
		for _, v := range []float64{r.DisposalAmount, r.ExtraFee, r.LaborFee, r.RecoveryDeduction, r.RecoveryFixedFee} {
			if !nonnegative(v) {
				return invalid()
			}
		}
		if r.PurchaseTotalOverride != nil && !nonnegative(*r.PurchaseTotalOverride) {
			return invalid()
		}
		if !finite(r.Purity) || r.Purity <= 0 || r.Purity > 1 || !nonnegative(r.RecoveryDiscount) || r.RecoveryDiscount >= 1 {
			return invalid()
		}
		if r.Alerts == nil || len(r.Alerts) > 4 {
			return invalid()
		}
		alertIDs := map[string]bool{}
		for _, a := range r.Alerts {
			aid := strings.ToLower(a.ID)
			if !uuidPattern.MatchString(a.ID) || alertIDs[aid] || !nonnegative(a.Threshold) || (a.Basis != "domestic" && a.Basis != "international") {
				return invalid()
			}
			alertIDs[aid] = true
			switch a.Kind {
			case "breakEven", "returnPercent", "profitAmount", "price":
			default:
				return invalid()
			}
		}
	}
	return nil
}
