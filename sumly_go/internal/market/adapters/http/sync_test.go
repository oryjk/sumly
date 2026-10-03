package markethttp

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/gin-gonic/gin"
)

type syncStub struct{}

func (syncStub) SyncHistory(_ context.Context, series domain.HistorySeries, cursor string) (domain.HistorySync, error) {
	return domain.HistorySync{Series: series.ID, Unit: "USD/troy_oz", Cursor: "epoch:xauusd:1", Reset: cursor == "", Points: []domain.HistoryChange{}}, nil
}
func TestSyncRouteValidatesSeriesAndPreservesEmptyDelta(t *testing.T) {
	r := gin.New()
	NewSyncHandler(application.NewHistorySync(syncStub{}, nil)).RegisterPublicRoutes(r.Group("/api/v1/app"))
	for _, tc := range []struct {
		query  string
		status int
	}{{"?series=xauusd&cursor=epoch:xauusd:1", 200}, {"?series=oops", 400}} {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/sync"+tc.query, nil))
		if w.Code != tc.status {
			t.Fatal(w.Code, w.Body.String())
		}
		if w.Code == 200 && !strings.Contains(w.Body.String(), `"points":[]`) {
			t.Fatal(w.Body.String())
		}
	}
}
