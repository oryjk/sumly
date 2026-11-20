package seedcsv

import (
	"bufio"
	"bytes"
	"embed"
	"fmt"
	"strconv"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/macro/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/macro/ports"
)

//go:embed data/*.csv
var embeddedCSV embed.FS

type Loader struct{}

var _ ports.SeedCSVSource = (*Loader)(nil)

func New() *Loader {
	return &Loader{}
}

func (l *Loader) LoadSeries(seriesID string) ([]domain.Observation, error) {
	var filename string
	switch seriesID {
	case domain.SeriesCBGoldNet:
		filename = "data/cb_gold_net.csv"
	case domain.SeriesUSDReserveShare:
		filename = "data/usd_reserve_share.csv"
	default:
		return nil, fmt.Errorf("no embedded seed CSV for series %s", seriesID)
	}
	raw, err := embeddedCSV.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("read embedded CSV %s: %w", filename, err)
	}
	return ParseCSV(raw)
}

func ParseCSV(raw []byte) ([]domain.Observation, error) {
	scanner := bufio.NewScanner(bytes.NewReader(raw))
	out := make([]domain.Observation, 0, 64)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(strings.ToLower(line), "date,") {
			continue
		}
		parts := strings.Split(line, ",")
		if len(parts) < 2 {
			continue
		}
		dt, err := domain.ParseDate(parts[0])
		if err != nil {
			continue
		}
		val, err := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		if err != nil || !domain.IsFinite(val) {
			continue
		}
		out = append(out, domain.Observation{Date: dt, Value: val})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return domain.SanitizeObservations(out), nil
}
