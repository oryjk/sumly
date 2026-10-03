package holdingshttp

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestDocumentJSONContractRoundTrip(t *testing.T) {
	raw := []byte(`{"schemaVersion":1,"books":["默认账本"],"records":[{"id":"ABCDEF01-2345-6789-ABCD-0123456789AB","grams":2,"unitPriceCNY":700,"timestamp":1700000000000.25,"note":"记录 <>&","createdAt":1700000000000.5,"brand":"品牌","bookName":"默认账本","disposition":"sold","disposedAt":1700000001000.75,"disposalAmount":1500,"purchaseID":"ABCDEF02-2345-6789-ABCD-0123456789AB","extraFee":3,"purchaseChannel":"门店","counterparty":"对方","assetType":"金条","purity":0.999,"laborFee":4,"purchaseTotalOverride":1400,"recoveryDeduction":0.01,"recoveryDiscount":0.02,"recoveryFixedFee":5,"alerts":[{"id":"ABCDEF03-2345-6789-ABCD-0123456789AB","kind":"price","threshold":900,"enabled":true,"basis":"domestic"}]}]}`)
	var dto documentDTO
	if err := json.Unmarshal(raw, &dto); err != nil {
		t.Fatal(err)
	}
	d := dto.toDomain()
	if err := d.Validate(); err != nil {
		t.Fatal(err)
	}
	got, err := json.Marshal(documentFromDomain(d))
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
