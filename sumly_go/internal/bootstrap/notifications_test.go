package bootstrap

import (
	"context"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	holdingsdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	marketdomain "gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	notificationhttp "gitee.com/oryjk/sumly/sumly_go/internal/notifications/adapters/http"
	notificationapp "gitee.com/oryjk/sumly/sumly_go/internal/notifications/application"
	notificationdomain "gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	notificationports "gitee.com/oryjk/sumly/sumly_go/internal/notifications/ports"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/gin-gonic/gin"
)

type stubQuoteLoader struct {
	quote marketdomain.GoldQuote
	found bool
	err   error
	calls int
}

func (s *stubQuoteLoader) LoadQuote(context.Context) (marketdomain.GoldQuote, bool, error) {
	s.calls++
	return s.quote, s.found, s.err
}

func TestMarketQuoteReaderSupportsDomesticAndInternationalBases(t *testing.T) {
	asOf := time.Unix(1_757_000_000, 0).UTC()
	domesticLoader := &stubQuoteLoader{
		found: true,
		quote: marketdomain.GoldQuote{
			Symbol:   "AU9999",
			Currency: "CNY",
			Price:    612.50,
			AsOf:     asOf,
		},
	}
	internationalLoader := &stubQuoteLoader{
		found: true,
		quote: marketdomain.GoldQuote{
			Symbol:   "XAUUSD",
			Currency: "USD",
			Price:    2600.0,
			USDCNY:   7.2,
			AsOf:     asOf.Add(time.Second),
		},
	}
	reader := marketQuoteReader{
		domestic:      domesticLoader,
		international: internationalLoader,
	}

	price, gotAsOf, err := reader.Read(context.Background(), "domestic")
	if err != nil {
		t.Fatalf("read domestic: %v", err)
	}
	if price != 612.50 || !gotAsOf.Equal(asOf) {
		t.Fatalf("domestic = (%v, %v), want (612.50, %v)", price, gotAsOf, asOf)
	}
	if domesticLoader.calls != 1 || internationalLoader.calls != 0 {
		t.Fatalf("unexpected loader calls: domestic=%d international=%d", domesticLoader.calls, internationalLoader.calls)
	}

	price, gotAsOf, err = reader.Read(context.Background(), "international")
	if err != nil {
		t.Fatalf("read international: %v", err)
	}
	wantIntl := 2600.0 / marketdomain.GramsPerTroyOunce * 7.2
	if math.Abs(price-wantIntl) > 1e-9 || !gotAsOf.Equal(asOf.Add(time.Second)) {
		t.Fatalf("international = (%v, %v), want (%v, %v)", price, gotAsOf, wantIntl, asOf.Add(time.Second))
	}
	if internationalLoader.calls != 1 {
		t.Fatalf("international calls = %d, want 1", internationalLoader.calls)
	}

	// 模板 ID 等非法口径必须拒绝，不得静默回退
	if _, _, err := reader.Read(context.Background(), "tmpl-wechat-123"); !errors.Is(err, notificationdomain.ErrInvalid) {
		t.Fatalf("unknown basis err = %v, want ErrInvalid", err)
	}
}

func TestMarketQuoteReaderHandlesMissingAndInvalidQuotes(t *testing.T) {
	asOf := time.Unix(1_757_000_000, 0).UTC()
	missing := marketQuoteReader{
		domestic:      &stubQuoteLoader{found: false},
		international: &stubQuoteLoader{found: true, quote: marketdomain.GoldQuote{Symbol: "XAUUSD", Currency: "USD", Price: 2600, USDCNY: 0, AsOf: asOf}},
	}
	if _, _, err := missing.Read(context.Background(), "domestic"); !errors.Is(err, notificationdomain.ErrUnavailable) {
		t.Fatalf("missing domestic err = %v, want ErrUnavailable", err)
	}
	if _, _, err := missing.Read(context.Background(), "international"); !errors.Is(err, notificationdomain.ErrUnavailable) {
		t.Fatalf("zero fx international err = %v, want ErrUnavailable", err)
	}
}

type stubNotificationStore struct {
	grants    map[string]notificationports.Grant
	baselines map[string]map[string]notificationports.Baseline
	events    map[string]notificationdomain.Event
}

func newStubNotificationStore() *stubNotificationStore {
	return &stubNotificationStore{
		grants:    map[string]notificationports.Grant{},
		baselines: map[string]map[string]notificationports.Baseline{},
		events:    map[string]notificationdomain.Event{},
	}
}

func (s *stubNotificationStore) PutGrant(_ context.Context, g notificationports.Grant) error {
	s.grants[g.Hash] = g
	return nil
}

func (s *stubNotificationStore) Grant(_ context.Context, hash string, now time.Time) (notificationports.Grant, error) {
	g, ok := s.grants[hash]
	if !ok || !g.ExpiresAt.After(now) {
		return notificationports.Grant{}, notificationdomain.ErrGrantNotFound
	}
	return g, nil
}

func (s *stubNotificationStore) Event(_ context.Context, deviceID, workspace, requestID, alertID string) (notificationdomain.Event, bool, error) {
	e, ok := s.events[deviceID+"|"+workspace+"|"+requestID+"|"+alertID]
	return e, ok, nil
}

func (s *stubNotificationStore) EventByID(_ context.Context, _, _, id string) (notificationdomain.Event, bool, error) {
	for _, e := range s.events {
		if e.ID == id {
			return e, true, nil
		}
	}
	return notificationdomain.Event{}, false, nil
}

func (s *stubNotificationStore) PutEvent(_ context.Context, e notificationdomain.Event, deviceID, workspace, requestID, alertID string) error {
	s.events[deviceID+"|"+workspace+"|"+requestID+"|"+alertID] = e
	return nil
}

func (s *stubNotificationStore) Baselines(_ context.Context, deviceID, workspace string) (map[string]notificationports.Baseline, error) {
	if s.baselines[deviceID+"|"+workspace] == nil {
		return map[string]notificationports.Baseline{}, nil
	}
	return s.baselines[deviceID+"|"+workspace], nil
}

func (s *stubNotificationStore) PutBaseline(_ context.Context, deviceID, workspace, hash string, b notificationports.Baseline) error {
	key := deviceID + "|" + workspace
	if s.baselines[key] == nil {
		s.baselines[key] = map[string]notificationports.Baseline{}
	}
	s.baselines[key][hash] = b
	return nil
}

func (s *stubNotificationStore) Purge(context.Context, time.Time) error { return nil }

type stubNotificationWechat struct {
	openID string
}

func (w stubNotificationWechat) Send(context.Context, string, string, map[string]string) error {
	return nil
}

func (w stubNotificationWechat) ExchangeCode(context.Context, string) (string, error) {
	return w.openID, nil
}

type stubNotificationCrypto struct{ n int }

func (c *stubNotificationCrypto) Random() string {
	c.n++
	return "grant-token-1234567890abcdef12345678"
}
func (c *stubNotificationCrypto) Digest(k, v string) string { return k + ":" + v }

type stubNotificationHoldings struct {
	lastUserID int64
	doc        holdingsdomain.Document
}

func (h *stubNotificationHoldings) Read(_ context.Context, userID int64) (holdingsdomain.Document, error) {
	h.lastUserID = userID
	return h.doc, nil
}

func TestNotificationActorUserIDExtractor(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	authMW := authhttp.NewMiddleware(tokens)
	userJWT, err := tokens.IssueUser(context.Background(), 88)
	if err != nil {
		t.Fatal(err)
	}
	adminJWT, err := tokens.IssueAdmin(context.Background(), 99, true)
	if err != nil {
		t.Fatal(err)
	}

	extractor := notificationActorUserID(&authMW, routerActiveUsers{})

	t.Run("extracts authenticated user from bearer header", func(t *testing.T) {
		rec := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(rec)
		c.Request = httptest.NewRequest(http.MethodPost, "/api/v1/app/notifications/holding/grants", nil)
		c.Request.Header.Set("Authorization", "Bearer "+userJWT)
		if got := extractor(c); got != 88 {
			t.Fatalf("ActorUserID = %d, want 88", got)
		}
	})

	t.Run("extracts authenticated user from gin context actor", func(t *testing.T) {
		rec := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(rec)
		c.Request = httptest.NewRequest(http.MethodPost, "/api/v1/app/notifications/holding/grants", nil)
		c.Set("authenticated_actor", sharedauth.Actor{Kind: sharedauth.ActorUser, ID: 55})
		if got := extractor(c); got != 55 {
			t.Fatalf("ActorUserID = %d, want 55", got)
		}
	})

	t.Run("returns 0 for guest workspace even with bearer token", func(t *testing.T) {
		rec := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(rec)
		c.Request = httptest.NewRequest(http.MethodPost, "/api/v1/app/notifications/holding/grants?workspace=guest", nil)
		c.Request.Header.Set("Authorization", "Bearer "+userJWT)
		if got := extractor(c); got != 0 {
			t.Fatalf("guest ActorUserID = %d, want 0", got)
		}
	})

	t.Run("returns 0 when unauthenticated or invalid or admin or frozen", func(t *testing.T) {
		for _, tc := range []struct {
			name   string
			header string
			active authhttp.ActiveUserChecker
		}{
			{name: "no header", active: routerActiveUsers{}},
			{name: "invalid bearer", header: "Bearer invalid.jwt.token", active: routerActiveUsers{}},
			{name: "admin token", header: "Bearer " + adminJWT, active: routerActiveUsers{}},
			{name: "frozen user", header: "Bearer " + userJWT, active: routerActiveUsers{err: sharederror.ErrUnauthorized}},
		} {
			t.Run(tc.name, func(t *testing.T) {
				rec := httptest.NewRecorder()
				c, _ := gin.CreateTestContext(rec)
				c.Request = httptest.NewRequest(http.MethodPost, "/api/v1/app/notifications/holding/grants", nil)
				if tc.header != "" {
					c.Request.Header.Set("Authorization", tc.header)
				}
				fn := notificationActorUserID(&authMW, tc.active)
				if got := fn(c); got != 0 {
					t.Fatalf("%s ActorUserID = %d, want 0", tc.name, got)
				}
			})
		}
	})
}

func TestNotificationGrantsAndEvaluateAccountModeReadsCloudHoldings(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	authMW := authhttp.NewMiddleware(tokens)
	userJWT, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatal(err)
	}

	now := time.Unix(1_757_000_000, 0).UTC()
	store := newStubNotificationStore()
	holdings := &stubNotificationHoldings{
		doc: holdingsdomain.Document{
			SchemaVersion: 1,
			Books:         []string{holdingsdomain.DefaultBook},
			Records: []holdingsdomain.Record{{
				ID:           "33333333-3333-3333-3333-333333333333",
				Grams:        10,
				Purity:       1,
				UnitPriceCNY: 500,
				Disposition:  "holding",
				Alerts: []holdingsdomain.Alert{{
					ID:        "22222222-2222-2222-2222-222222222222",
					Kind:      "price",
					Threshold: 600,
					Enabled:   true,
					Basis:     "domestic",
				}},
			}},
		},
	}
	domesticLoader := &stubQuoteLoader{
		found: true,
		quote: marketdomain.GoldQuote{Symbol: "AU9999", Currency: "CNY", Price: 590, AsOf: now},
	}
	handler := notificationhttp.NewHandler(notificationapp.HoldingAlerts{
		Store:    store,
		Quotes:   marketQuoteReader{domestic: domesticLoader},
		Holdings: holdings,
		Wechat:   stubNotificationWechat{openID: "openid-42"},
		Crypto:   &stubNotificationCrypto{},
		Template: notificationapp.TemplateConfig{
			TemplateID: "tmpl-real",
			Fields:     map[string]string{"kind": "thing1", "price": "thing2", "threshold": "thing3"},
		},
		Now:      func() time.Time { return now },
		GrantTTL: 15 * time.Minute,
	})
	handler.ActorUserID = notificationActorUserID(&authMW, routerActiveUsers{})

	router := NewRouter(Dependencies{
		AuthMiddleware: &authMW,
		Notifications:  handler,
	})

	grantReq := httptest.NewRequest(http.MethodPost, "/api/v1/app/notifications/holding/grants", strings.NewReader(`{"js_code":"wx-code","device_id":"11111111-1111-1111-1111-111111111111","template_id":"tmpl-real"}`))
	grantReq.Header.Set("Authorization", "Bearer "+userJWT)
	grantRec := httptest.NewRecorder()
	router.ServeHTTP(grantRec, grantReq)
	if grantRec.Code != http.StatusOK {
		t.Fatalf("grants status=%d body=%s", grantRec.Code, grantRec.Body.String())
	}

	var storedGrant notificationports.Grant
	for _, g := range store.grants {
		storedGrant = g
	}
	if storedGrant.UserID != 42 {
		t.Fatalf("stored grant user_id = %d, want 42", storedGrant.UserID)
	}

	evalReq := httptest.NewRequest(http.MethodPost, "/api/v1/app/notifications/holding/evaluate", strings.NewReader(`{"device_id":"11111111-1111-1111-1111-111111111111","request_id":"req-1"}`))
	evalReq.Header.Set(notificationhttp.GrantHeader, "grant-token-1234567890abcdef12345678")
	evalRec := httptest.NewRecorder()
	router.ServeHTTP(evalRec, evalReq)
	if evalRec.Code != http.StatusOK {
		t.Fatalf("evaluate status=%d body=%s", evalRec.Code, evalRec.Body.String())
	}
	if holdings.lastUserID != 42 {
		t.Fatalf("holdings read userID = %d, want 42", holdings.lastUserID)
	}
	if domesticLoader.calls != 1 {
		t.Fatalf("domestic loader calls = %d, want 1", domesticLoader.calls)
	}
}
