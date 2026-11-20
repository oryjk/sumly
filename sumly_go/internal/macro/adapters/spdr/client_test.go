package spdr

import (
	"archive/zip"
	"bytes"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
)

func buildTestSPDRXLSX(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	entries := map[string]string{
		"xl/workbook.xml": `<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Disclaimer" sheetId="1" r:id="rId1"/>
    <sheet name="Historical Archive" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>`,
		"xl/_rels/workbook.xml.rels": `<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Target="worksheets/sheet2.xml"/>
</Relationships>`,
		"xl/sharedStrings.xml": `<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Date</t></si>
  <si><t>GLD Close</t></si>
  <si><t>Tonnes of Gold in the Trust</t></si>
  <si><t>02-Jan-2026</t></si>
  <si><t>912.45</t></si>
</sst>`,
		"xl/worksheets/sheet1.xml": `<worksheet><sheetData><row><c r="A1"><v>Disclaimer</v></c></row></sheetData></worksheet>`,
		"xl/worksheets/sheet2.xml": `<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>
    <row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2"><v>250.10</v></c><c r="C2" t="s"><v>4</v></c></row>
    <row r="3"><c r="A3"><v>46025</v></c><c r="B3"><v>252.00</v></c><c r="C3"><v>915.80</v></c></row>
  </sheetData>
</worksheet>`,
	}
	for name, content := range entries {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestParseSPDRXLSXExtractsTonnesAndDates(t *testing.T) {
	raw := buildTestSPDRXLSX(t)
	obs, err := ParseXLSX(raw)
	if err != nil {
		t.Fatalf("ParseXLSX failed: %v", err)
	}
	if len(obs) != 2 {
		t.Fatalf("expected 2 observations, got %d", len(obs))
	}
	if domain.FormatDate(obs[0].Date) != "2026-01-02" || obs[0].Value != 912.45 {
		t.Fatalf("unexpected obs[0]: %+v", obs[0])
	}
	// Excel serial 46025 => 2026-01-03
	if domain.FormatDate(obs[1].Date) != "2026-01-03" || obs[1].Value != 915.80 {
		t.Fatalf("unexpected obs[1]: %+v", obs[1])
	}
}
