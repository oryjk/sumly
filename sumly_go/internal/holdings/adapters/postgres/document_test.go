package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

func TestDocumentJSONContractRoundTrip(t *testing.T) {
	raw := []byte(`{"schemaVersion":1,"books":["默认账本"],"records":[{"id":"ABCDEF01-2345-6789-ABCD-0123456789AB","grams":2,"unitPriceCNY":700,"timestamp":1700000000000.25,"note":"记录 <>&","createdAt":1700000000000.5,"brand":"品牌","bookName":"默认账本","disposition":"sold","disposedAt":1700000001000.75,"disposalAmount":1500,"purchaseID":"ABCDEF02-2345-6789-ABCD-0123456789AB","extraFee":3,"purchaseChannel":"门店","counterparty":"对方","assetType":"金条","purity":0.999,"laborFee":4,"purchaseTotalOverride":1400,"recoveryDeduction":0.01,"recoveryDiscount":0.02,"recoveryFixedFee":5,"alerts":[{"id":"ABCDEF03-2345-6789-ABCD-0123456789AB","kind":"price","threshold":900,"enabled":true,"basis":"domestic"}]}]}`)
	snap, err := decode(7, raw)
	if err != nil {
		t.Fatal(err)
	}
	if err := snap.Document.Validate(); err != nil {
		t.Fatal(err)
	}
	got, err := encodeDocument(snap.Document)
	if err != nil {
		t.Fatal(err)
	}
	var want, actual any
	if err := json.Unmarshal(raw, &want); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(got, &actual); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(want, actual) {
		t.Fatalf("JSON contract changed: %s", got)
	}
}

func TestRepositoryRejectsSnapshotThatWouldExceedResponseLimit(t *testing.T) {
	repo := NewRepository(nil)
	d := domain.EmptyDocument()
	for i := 0; i < 1000; i++ {
		d.Records = append(d.Records, domain.Record{ID: fmt.Sprintf("%08x-2345-6789-abcd-0123456789ab", i), Grams: 1, UnitPriceCNY: 700, Timestamp: 1700000000000, CreatedAt: 1700000000000, Note: strings.Repeat("金", 2000), BookName: "默认账本", Disposition: "holding", AssetType: "金", Purity: 1, Alerts: []domain.Alert{}})
	}
	if _, e := repo.Put(context.Background(), 42, 0, d); !errors.Is(e, errs.ErrValidation) {
		t.Fatal("oversize response persisted", e)
	}
}

func TestRepositoryRejectsJSONEscapingExpansionBeforePersistence(t *testing.T) {
	repo := NewRepository(nil)
	d := domain.EmptyDocument()
	// Raw unescaped HTTP text fits the limit, but escaping '<' in responses expands sixfold.
	for i := 0; i < 400; i++ {
		d.Records = append(d.Records, domain.Record{ID: fmt.Sprintf("%08x-2345-6789-abcd-0123456789ab", i), Grams: 1, UnitPriceCNY: 700, Timestamp: 1700000000000.25, CreatedAt: 1700000000000.5, Note: strings.Repeat("<", 2000), BookName: "默认账本", Disposition: "holding", Purity: 1, Alerts: []domain.Alert{}})
	}
	if err := d.Validate(); err != nil {
		t.Fatal("valid domain document", err)
	}
	raw, err := encodeDocument(d)
	if err != nil {
		t.Fatal(err)
	}
	if len(strings.ReplaceAll(string(raw), `\u003c`, "<")) >= domain.MaxBytes {
		t.Fatal("fixture already exceeds raw request limit")
	}
	if _, err := repo.Put(context.Background(), 42, 0, d); !errors.Is(err, errs.ErrValidation) {
		t.Fatal("escaping expansion reached database", err)
	}
}
