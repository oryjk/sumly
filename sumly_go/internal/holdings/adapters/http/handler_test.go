package holdingshttp

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/gin-gonic/gin"
)

type repository struct {
	snap domain.Snapshot
	id   int64
}

func (r *repository) Get(_ context.Context, id int64) (domain.Snapshot, error) {
	r.id = id
	return r.snap, nil
}
func (r *repository) Put(_ context.Context, id, rev int64, d domain.Document) (domain.Snapshot, error) {
	r.id = id
	if rev != r.snap.Revision {
		return domain.Snapshot{}, errs.ErrConflict
	}
	r.snap = domain.Snapshot{Revision: rev + 1, Document: d}
	return r.snap, nil
}
func TestBoundedAuthenticatedStrictSnapshotProtocol(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := &repository{snap: domain.Snapshot{Document: domain.EmptyDocument()}}
	handler := NewHandler(application.NewService(r))
	tokens, e := jwt.NewService("01234567890123456789012345678901", time.Hour)
	if e != nil {
		t.Fatal(e)
	}
	middleware := authhttp.NewMiddleware(tokens)
	router := gin.New()
	group := router.Group("/api/v1/app", middleware.RequireUser())
	handler.RegisterAppRoutes(group)
	token, e := tokens.IssueUser(context.Background(), 42)
	if e != nil {
		t.Fatal(e)
	}
	request := func(method, body string, authorized bool) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, "/api/v1/app/holdings", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		if authorized {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		out := httptest.NewRecorder()
		router.ServeHTTP(out, req)
		return out
	}
	for _, method := range []string{"GET", "PUT"} {
		if got := request(method, "{}", false); got.Code != 401 {
			t.Fatal("unprotected holdings", got.Code)
		}
	}
	got := request("GET", "", true)
	if got.Code != 200 || r.id != 42 || !strings.Contains(got.Body.String(), `"revision":0`) || got.Header().Get("Cache-Control") != "no-store" {
		t.Fatal(got.Code, got.Body.String())
	}
	valid := `{"expectedRevision":0,"document":{"schemaVersion":1,"books":["默认账本"],"records":[]}}`
	got = request("PUT", valid, true)
	if got.Code != 200 || !strings.Contains(got.Body.String(), `"revision":1`) {
		t.Fatal(got.Code, got.Body.String())
	}
	if got = request("PUT", valid, true); got.Code != 409 {
		t.Fatal("stale overwrite", got.Code)
	}
	bad := []string{strings.Replace(valid, `"expectedRevision":0`, `"expectedRevision":0,"ExpectedRevision":0`, 1), `{}`, `{"document":{"schemaVersion":1,"books":["默认账本"],"records":[]}}`, strings.Replace(valid, `"records":[]`, `"records":null`, 1), valid + ` {}`, strings.Replace(valid, `"expectedRevision":0`, `"expectedRevision":null`, 1), strings.Replace(valid, `"expectedRevision":0`, `"expectedRevision":-1`, 1), strings.Replace(valid, `"expectedRevision":0`, `"expectedRevision":0,"userID":7`, 1)}
	for _, body := range bad {
		if got = request("PUT", body, true); got.Code != 422 {
			t.Fatalf("bad payload status=%d body=%s", got.Code, body)
		}
	}
	big := string(bytes.Repeat([]byte(" "), domain.MaxBytes+1))
	if got = request("PUT", big, true); got.Code != 413 {
		t.Fatal("unbounded request", got.Code)
	}
	record := domain.Record{ID: "ABCDEF01-2345-6789-ABCD-0123456789AB", Grams: 1, UnitPriceCNY: 700, Timestamp: 1700000000000.25, CreatedAt: 1700000000000.5, BookName: "默认账本", Disposition: "holding", AssetType: "旧类型", Purity: 1, Alerts: []domain.Alert{}}
	encoded, e := json.Marshal(map[string]any{"expectedRevision": 1, "document": documentFromDomain(domain.Document{SchemaVersion: 1, Books: []string{"默认账本"}, Records: []domain.Record{record}})})
	if e != nil {
		t.Fatal(e)
	}
	for _, body := range []string{strings.Replace(string(encoded), `"extraFee":0,`, ``, 1), strings.Replace(string(encoded), `"extraFee":0`, `"extraFee":null`, 1), strings.Replace(string(encoded), `"alerts":[]`, `"alerts":[{"id":"ABCDEF02-2345-6789-ABCD-0123456789AB","kind":"price","threshold":0,"enabled":null,"basis":"domestic"}]`, 1)} {
		if got = request("PUT", body, true); got.Code != 422 {
			t.Fatal("missing/null required record field accepted", got.Code, body)
		}
	}
	if got = request("PUT", string(encoded), true); got.Code != 200 || !strings.Contains(got.Body.String(), `1700000000000.25`) {
		t.Fatal("fractional date roundtrip", got.Code, got.Body.String())
	}
}
