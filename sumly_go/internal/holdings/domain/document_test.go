package domain

import (
	"math"
	"reflect"
	"strings"
	"testing"
)

func validRecord() Record {
	return Record{ID: "ABCDEF01-2345-6789-ABCD-0123456789AB", Grams: 2, UnitPriceCNY: 700, Timestamp: 1700000000000.25, CreatedAt: 1700000000000.5, BookName: "默认账本", Disposition: "holding", AssetType: "旧类型", Purity: 1, Alerts: []Alert{}}
}
func validDocument() Document {
	return Document{SchemaVersion: 1, Books: []string{"默认账本"}, Records: []Record{validRecord()}}
}
func TestDocumentValidation(t *testing.T) {
	tests := []struct {
		name   string
		change func(*Document)
	}{
		{"schema", func(d *Document) { d.SchemaVersion = 2 }},
		{"nil books", func(d *Document) { d.Books = nil }},
		{"nil records", func(d *Document) { d.Records = nil }},
		{"duplicate book", func(d *Document) { d.Books = append(d.Books, "默认账本") }},
		{"blank book", func(d *Document) { d.Books = []string{" "} }},
		{"long book", func(d *Document) { d.Books = []string{strings.Repeat("金", 101)} }},
		{"many books", func(d *Document) { d.Books = make([]string, 101) }},
		{"many records", func(d *Document) { d.Records = make([]Record, 1001) }},
		{"duplicate record case insensitive", func(d *Document) { r := d.Records[0]; r.ID = strings.ToLower(r.ID); d.Records = append(d.Records, r) }},
		{"bad uuid", func(d *Document) { d.Records[0].ID = "invalid" }},
		{"negative grams", func(d *Document) { d.Records[0].Grams = -1 }},
		{"zero grams", func(d *Document) { d.Records[0].Grams = 0 }},
		{"nan grams", func(d *Document) { d.Records[0].Grams = math.NaN() }},
		{"infinite cost", func(d *Document) { d.Records[0].ExtraFee = math.Inf(1) }},
		{"negative cost", func(d *Document) { d.Records[0].DisposalAmount = -1 }},
		{"zero price without total", func(d *Document) { d.Records[0].UnitPriceCNY = 0 }},
		{"purity zero", func(d *Document) { d.Records[0].Purity = 0 }},
		{"purity above one", func(d *Document) { d.Records[0].Purity = 1.1 }},
		{"discount one", func(d *Document) { d.Records[0].RecoveryDiscount = 1 }},
		{"date nan", func(d *Document) { d.Records[0].Timestamp = math.NaN() }},
		{"date huge", func(d *Document) { d.Records[0].CreatedAt = 1e100 }},
		{"unknown book", func(d *Document) { d.Records[0].BookName = "不存在" }},
		{"unknown disposition", func(d *Document) { d.Records[0].Disposition = "gifted" }},
		{"disposed date missing", func(d *Document) { d.Records[0].Disposition = "sold" }},
		{"long note", func(d *Document) { d.Records[0].Note = strings.Repeat("金", 2001) }},
		{"long brand", func(d *Document) { d.Records[0].Brand = strings.Repeat("金", 201) }},
		{"bad purchase uuid", func(d *Document) { v := "bad"; d.Records[0].PurchaseID = &v }},
		{"negative override", func(d *Document) { v := -1.; d.Records[0].PurchaseTotalOverride = &v }},
		{"nil alerts", func(d *Document) { d.Records[0].Alerts = nil }},
		{"many alerts", func(d *Document) { d.Records[0].Alerts = make([]Alert, 5) }},
		{"bad alert", func(d *Document) {
			d.Records[0].Alerts = []Alert{{ID: "abcdef02-2345-6789-abcd-0123456789ab", Kind: "bad", Basis: "domestic"}}
		}},
		{"bad alert uuid", func(d *Document) { d.Records[0].Alerts = []Alert{{ID: "bad", Kind: "price", Basis: "domestic"}} }},
		{"bad alert basis", func(d *Document) {
			d.Records[0].Alerts = []Alert{{ID: "abcdef02-2345-6789-abcd-0123456789ab", Kind: "price", Basis: "bad"}}
		}},
		{"duplicate alert uuid", func(d *Document) {
			d.Records[0].Alerts = []Alert{{ID: "abcdef02-2345-6789-abcd-0123456789ab", Kind: "price", Basis: "domestic"}, {ID: "ABCDEF02-2345-6789-ABCD-0123456789AB", Kind: "price", Basis: "domestic"}}
		}},
		{"negative threshold", func(d *Document) {
			d.Records[0].Alerts = []Alert{{ID: "abcdef02-2345-6789-abcd-0123456789ab", Kind: "price", Basis: "domestic", Threshold: -1}}
		}},
	}
	if err := validDocument().Validate(); err != nil {
		t.Fatal("valid legacy record", err)
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := validDocument()
			tt.change(&d)
			if d.Validate() == nil {
				t.Fatal("accepted invalid document")
			}
		})
	}
	d := validDocument()
	v := 1400.
	d.Records[0].UnitPriceCNY = 0
	d.Records[0].PurchaseTotalOverride = &v
	if err := d.Validate(); err != nil {
		t.Fatal(err)
	}
	d = validDocument()
	date := 1700000000001.
	d.Records[0].Disposition = "gift"
	d.Records[0].DisposedAt = &date
	if err := d.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestDomainModelsDoNotDefineJSONContract(t *testing.T) {
	for _, value := range []any{Document{}, Snapshot{}, Record{}, Alert{}} {
		typ := reflect.TypeOf(value)
		for i := 0; i < typ.NumField(); i++ {
			if tag := typ.Field(i).Tag.Get("json"); tag != "" {
				t.Errorf("domain %s.%s owns JSON contract %q", typ.Name(), typ.Field(i).Name, tag)
			}
		}
	}
}
