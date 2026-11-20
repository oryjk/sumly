package spdr

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"net/http"
	"path"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/httpclient"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

const DefaultEndpoint = "https://api.spdrgoldshares.com/api/v1/historical-archive?product=gld&exchange=NYSE&lang=en"

type Client struct {
	HTTP     *http.Client
	Endpoint string
}

var _ ports.SPDRSource = (*Client)(nil)

func New(httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = httpclient.New(60 * time.Second)
	}
	return &Client{HTTP: httpClient, Endpoint: DefaultEndpoint}
}

func (c *Client) FetchGLDTonnes(ctx context.Context) ([]domain.Observation, error) {
	endpoint := strings.TrimSpace(c.Endpoint)
	if endpoint == "" {
		endpoint = DefaultEndpoint
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = httpclient.New(60 * time.Second)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("create SPDR request: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,*/*")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("SPDR request failed: %w", err)
	}
	body, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		return nil, fmt.Errorf("read SPDR response: %w", readErr)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("SPDR API status %d", resp.StatusCode)
	}
	return ParseXLSX(body)
}

type xlsxWorkbook struct {
	Sheets []struct {
		Name  string `xml:"name,attr"`
		RelID string `xml:"id,attr"`
	} `xml:"sheets>sheet"`
}

type xlsxRelationships struct {
	Relationships []struct {
		ID     string `xml:"Id,attr"`
		Target string `xml:"Target,attr"`
	} `xml:"Relationship"`
}

type xlsxSharedStrings struct {
	Items []struct {
		T string `xml:"t"`
		R []struct {
			T string `xml:"t"`
		} `xml:"r"`
	} `xml:"si"`
}

type xlsxWorksheet struct {
	Rows []struct {
		Cells []struct {
			Ref    string `xml:"r,attr"`
			Type   string `xml:"t,attr"`
			Value  string `xml:"v"`
			Inline struct {
				T string `xml:"t"`
			} `xml:"is"`
		} `xml:"c"`
	} `xml:"sheetData>row"`
}

// ParseXLSX parses SPDR Gold Trust historical archive XLSX using only the Go standard library.
func ParseXLSX(raw []byte) ([]domain.Observation, error) {
	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return nil, fmt.Errorf("open SPDR XLSX zip: %w", err)
	}
	files := make(map[string]*zip.File, len(zr.File))
	for _, f := range zr.File {
		files[strings.TrimPrefix(path.Clean(f.Name), "/")] = f
	}

	sharedStrings, err := loadSharedStrings(files)
	if err != nil {
		return nil, err
	}

	sheetPath, err := resolveTargetSheetPath(files)
	if err != nil {
		return nil, err
	}
	sheetBytes, err := readZipEntry(files, sheetPath)
	if err != nil {
		return nil, fmt.Errorf("read worksheet %s: %w", sheetPath, err)
	}

	var ws xlsxWorksheet
	if err := xml.Unmarshal(sheetBytes, &ws); err != nil {
		return nil, fmt.Errorf("parse worksheet XML: %w", err)
	}

	rows := make([]map[int]string, 0, len(ws.Rows))
	for _, row := range ws.Rows {
		cells := make(map[int]string, len(row.Cells))
		for idx, c := range row.Cells {
			col := parseColumnIndex(c.Ref)
			if col < 0 {
				col = idx
			}
			val := extractCellString(c.Type, c.Value, c.Inline.T, sharedStrings)
			cells[col] = val
		}
		rows = append(rows, cells)
	}

	headerRow := -1
	dateCol := -1
	tonnesCol := -1
	limit := len(rows)
	if limit > 15 {
		limit = 15
	}
	for r := 0; r < limit; r++ {
		dCol := -1
		tCol := -1
		for col, text := range rows[r] {
			lower := strings.ToLower(strings.TrimSpace(text))
			if lower == "date" || strings.Contains(lower, "date") {
				if dCol < 0 || lower == "date" {
					dCol = col
				}
			}
			if strings.Contains(lower, "tonnes") && strings.Contains(lower, "gold") {
				tCol = col
			}
		}
		if dCol >= 0 && tCol >= 0 {
			headerRow = r
			dateCol = dCol
			tonnesCol = tCol
			break
		}
	}
	if headerRow < 0 || dateCol < 0 || tonnesCol < 0 {
		return nil, fmt.Errorf("SPDR XLSX missing Date or Tonnes of Gold columns")
	}

	out := make([]domain.Observation, 0, len(rows))
	for r := headerRow + 1; r < len(rows); r++ {
		dateRaw := strings.TrimSpace(rows[r][dateCol])
		tonnesRaw := strings.TrimSpace(rows[r][tonnesCol])
		if dateRaw == "" || tonnesRaw == "" {
			continue
		}
		dt, ok := parseSPDRDate(dateRaw)
		if !ok {
			continue
		}
		cleaned := strings.ReplaceAll(tonnesRaw, ",", "")
		val, err := strconv.ParseFloat(cleaned, 64)
		if err != nil || !domain.IsFinite(val) || val <= 0 {
			continue
		}
		out = append(out, domain.Observation{Date: dt, Value: domain.RoundTo(val, 2)})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("SPDR XLSX parsed zero valid tonnes observations")
	}
	return domain.SanitizeObservations(out), nil
}

func loadSharedStrings(files map[string]*zip.File) ([]string, error) {
	data, err := readZipEntry(files, "xl/sharedStrings.xml")
	if err != nil {
		return nil, nil
	}
	var ss xlsxSharedStrings
	if err := xml.Unmarshal(data, &ss); err != nil {
		return nil, fmt.Errorf("parse sharedStrings.xml: %w", err)
	}
	out := make([]string, 0, len(ss.Items))
	for _, item := range ss.Items {
		if len(item.R) > 0 {
			var b strings.Builder
			for _, run := range item.R {
				b.WriteString(run.T)
			}
			out = append(out, b.String())
		} else {
			out = append(out, item.T)
		}
	}
	return out, nil
}

func resolveTargetSheetPath(files map[string]*zip.File) (string, error) {
	wbBytes, err := readZipEntry(files, "xl/workbook.xml")
	if err != nil {
		if _, ok := files["xl/worksheets/sheet1.xml"]; ok {
			return "xl/worksheets/sheet1.xml", nil
		}
		return "", fmt.Errorf("missing xl/workbook.xml: %w", err)
	}
	var wb xlsxWorkbook
	if err := xml.Unmarshal(wbBytes, &wb); err != nil {
		return "", fmt.Errorf("parse workbook.xml: %w", err)
	}
	if len(wb.Sheets) == 0 {
		return "", fmt.Errorf("workbook has no sheets")
	}

	targetIdx := len(wb.Sheets) - 1
	for i, s := range wb.Sheets {
		lower := strings.ToLower(s.Name)
		if strings.Contains(lower, "historical") || strings.Contains(lower, "archive") {
			targetIdx = i
			break
		}
	}
	targetSheet := wb.Sheets[targetIdx]

	relsBytes, err := readZipEntry(files, "xl/_rels/workbook.xml.rels")
	if err == nil {
		var rels xlsxRelationships
		if xml.Unmarshal(relsBytes, &rels) == nil {
			for _, r := range rels.Relationships {
				if r.ID == targetSheet.RelID {
					target := strings.TrimPrefix(r.Target, "/")
					if !strings.HasPrefix(target, "xl/") {
						target = path.Clean("xl/" + target)
					}
					if _, ok := files[target]; ok {
						return target, nil
					}
				}
			}
		}
	}

	fallback := fmt.Sprintf("xl/worksheets/sheet%d.xml", targetIdx+1)
	if _, ok := files[fallback]; ok {
		return fallback, nil
	}
	return "", fmt.Errorf("cannot locate worksheet XML for sheet %q", targetSheet.Name)
}

func readZipEntry(files map[string]*zip.File, name string) ([]byte, error) {
	f, ok := files[name]
	if !ok {
		return nil, fmt.Errorf("zip entry %s not found", name)
	}
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	return io.ReadAll(rc)
}

func extractCellString(cellType, value, inline string, sharedStrings []string) string {
	switch cellType {
	case "s":
		idx, err := strconv.Atoi(strings.TrimSpace(value))
		if err == nil && idx >= 0 && idx < len(sharedStrings) {
			return sharedStrings[idx]
		}
		return ""
	case "inlineStr":
		return inline
	default:
		return value
	}
}

func parseColumnIndex(cellRef string) int {
	cellRef = strings.TrimSpace(cellRef)
	if cellRef == "" {
		return -1
	}
	col := 0
	found := false
	for i := 0; i < len(cellRef); i++ {
		ch := cellRef[i]
		if ch >= 'A' && ch <= 'Z' {
			col = col*26 + int(ch-'A'+1)
			found = true
		} else if ch >= 'a' && ch <= 'z' {
			col = col*26 + int(ch-'a'+1)
			found = true
		} else {
			break
		}
	}
	if !found {
		return -1
	}
	return col - 1
}

func parseSPDRDate(raw string) (time.Time, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, false
	}
	if serial, err := strconv.ParseFloat(raw, 64); err == nil && serial > 20000 && serial < 100000 {
		// Excel serial date (1899-12-30 accounts for the 1900 leap year bug).
		days := int(math.Floor(serial))
		return time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC).AddDate(0, 0, days), true
	}
	layouts := []string{
		"2006-01-02",
		"01/02/2006",
		"1/2/2006",
		"02-Jan-2006",
		"2-Jan-2006",
		"Jan 2, 2006",
		"January 2, 2006",
	}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, raw); err == nil {
			return domain.NormalizeDate(t), true
		}
	}
	return time.Time{}, false
}
