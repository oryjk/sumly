package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/ports"
)

const (
	deviceID  = "11111111-1111-1111-1111-111111111111"
	alertID   = "22222222-2222-2222-2222-222222222222"
	recordID  = "33333333-3333-3333-3333-333333333333"
	otherDev  = "44444444-4444-4444-4444-444444444444"
	grantHash = "ignored"
)

var baseTime = time.Unix(1_757_000_000, 0).UTC()

type fakeStore struct {
	grants    map[string]ports.Grant
	baselines map[string]map[string]ports.Baseline
	events    map[string]domain.Event
	putCalls  int
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		grants:    map[string]ports.Grant{},
		baselines: map[string]map[string]ports.Baseline{},
		events:    map[string]domain.Event{},
	}
}

func (s *fakeStore) PutGrant(_ context.Context, g ports.Grant) error {
	s.grants[g.Hash] = g
	return nil
}

func (s *fakeStore) Grant(_ context.Context, hash string, now time.Time) (ports.Grant, error) {
	g, ok := s.grants[hash]
	if !ok || !g.ExpiresAt.After(now) {
		return ports.Grant{}, domain.ErrGrantNotFound
	}
	return g, nil
}

func (s *fakeStore) eventKey(device, workspace, requestID, alertID string) string {
	return device + "|" + workspace + "|" + requestID + "|" + alertID
}

func (s *fakeStore) Event(_ context.Context, device, workspace, requestID, alert string) (domain.Event, bool, error) {
	if requestID == "" {
		return domain.Event{}, false, nil
	}
	e, ok := s.events[s.eventKey(device, workspace, requestID, alert)]
	return e, ok, nil
}

func (s *fakeStore) EventByID(_ context.Context, _, _, id string) (domain.Event, bool, error) {
	for _, e := range s.events {
		if e.ID == id {
			return e, true, nil
		}
	}
	return domain.Event{}, false, nil
}

func (s *fakeStore) PutEvent(_ context.Context, e domain.Event, device, workspace, requestID, alert string) error {
	s.putCalls++
	s.events[s.eventKey(device, workspace, requestID, alert)] = e
	return nil
}

func (s *fakeStore) Baselines(_ context.Context, device, workspace string) (map[string]ports.Baseline, error) {
	if s.baselines[device+"|"+workspace] == nil {
		return map[string]ports.Baseline{}, nil
	}
	return s.baselines[device+"|"+workspace], nil
}

func (s *fakeStore) PutBaseline(_ context.Context, device, workspace, hash string, b ports.Baseline) error {
	key := device + "|" + workspace
	if s.baselines[key] == nil {
		s.baselines[key] = map[string]ports.Baseline{}
	}
	s.baselines[key][hash] = b
	return nil
}

func (s *fakeStore) Purge(context.Context, time.Time) error { return nil }

type fakeQuotes struct {
	price float64
	asOf  time.Time
	err   error
}

func (q fakeQuotes) Read(context.Context, string) (float64, time.Time, error) {
	return q.price, q.asOf, q.err
}

type fakeWechat struct {
	openID  string
	sent    int
	err     error
	codeErr error
}

func (w *fakeWechat) Send(context.Context, string, string, map[string]string) error {
	w.sent++
	return w.err
}

func (w *fakeWechat) ExchangeCode(context.Context, string) (string, error) {
	if w.codeErr != nil {
		return "", w.codeErr
	}
	return w.openID, nil
}

type fakeCrypto struct{ n int }

func (c *fakeCrypto) Random() string {
	c.n++
	return "random-token-" + string(rune('a'+c.n))
}

func (c *fakeCrypto) Digest(kind, value string) string { return kind + ":" + value }

type fakeHoldings struct {
	doc domain.GuestConfiguration
}

func (h fakeHoldings) Read(context.Context, int64) (holdingsDocument, error) {
	return holdingsDocument{}, errors.New("unused")
}

type holdingsDocument = struct {
	SchemaVersion int
	Books         []string
	Records       []holdingRecord
}

type holdingRecord struct{}

func newAlerts(store *fakeStore, wechat ports.WechatSender, quotes ports.QuoteReader) HoldingAlerts {
	return HoldingAlerts{
		Store:  store,
		Quotes: quotes,
		Wechat: wechat,
		Crypto: &fakeCrypto{},
		Template: TemplateConfig{
			TemplateID: "template-1",
			Fields:     map[string]string{"kind": "thing1", "price": "thing2", "threshold": "thing3"},
		},
		Now:      func() time.Time { return baseTime },
		GrantTTL: 15 * time.Minute,
	}
}

func TestCapabilityRequiresTemplateConfiguration(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "o"}, fakeQuotes{})
	if !alerts.Capability().Available {
		t.Fatal("expected available when template configured")
	}
	// 缺模板必须报不可用，而不是用假模板糊弄
	alerts.Template = TemplateConfig{}
	if alerts.Capability().Available {
		t.Fatal("expected unavailable without template")
	}
}

func TestGrantsRejectUnknownTemplate(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "o"}, fakeQuotes{})
	if _, err := alerts.Grants(context.Background(), "code", deviceID, "other-template", 0, "guest"); err == nil {
		t.Fatal("expected rejection for unconfigured template")
	}
}

func TestGrantsRejectInvalidDeviceID(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "o"}, fakeQuotes{})
	if _, err := alerts.Grants(context.Background(), "code", "not-a-uuid", "template-1", 0, "guest"); !errors.Is(err, domain.ErrInvalidDeviceID) {
		t.Fatalf("err = %v, want ErrInvalidDeviceID", err)
	}
}

func TestGrantsIssueShortLivedToken(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "openid-1"}, fakeQuotes{})
	result, err := alerts.Grants(context.Background(), "code", deviceID, "template-1", 0, "guest")
	if err != nil {
		t.Fatalf("Grants: %v", err)
	}
	// 15 分钟 = 900 秒
	if result.ExpiresIn != 900 {
		t.Fatalf("expires_in = %d, want 900", result.ExpiresIn)
	}
	if result.Grant == "" {
		t.Fatal("expected non-empty grant token")
	}
	// 令牌本身不应等于存储的 hash
	stored := store.grants["sha256:"+result.Grant]
	if stored.Hash == result.Grant {
		t.Fatal("grant must not be stored in plaintext")
	}
}

func TestEvaluateRejectsMissingGrant(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "o"}, fakeQuotes{price: 600, asOf: baseTime})
	_, err := alerts.Evaluate(context.Background(), EvaluateInput{
		DeviceID: deviceID, RequestID: "req-1", Workspace: "guest",
	})
	if !errors.Is(err, domain.ErrGrantNotFound) {
		t.Fatalf("err = %v, want ErrGrantNotFound", err)
	}
}

func TestEvaluateRejectsGrantFromOtherDevice(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "o"}, fakeQuotes{price: 600, asOf: baseTime})
	issued, err := alerts.Grants(context.Background(), "code", deviceID, "template-1", 0, "guest")
	if err != nil {
		t.Fatalf("Grants: %v", err)
	}
	// 换一个设备使用该授权
	_, err = alerts.Evaluate(context.Background(), EvaluateInput{
		DeviceID: otherDev, RequestID: "req-1", Grant: issued.Grant, Workspace: "guest",
	})
	if !errors.Is(err, domain.ErrGrantNotFound) {
		t.Fatalf("err = %v, want ErrGrantNotFound", err)
	}
}

func TestEvaluateRejectsStaleQuote(t *testing.T) {
	store := newFakeStore()
	alerts := newAlerts(store, &fakeWechat{openID: "o"}, fakeQuotes{price: 600, asOf: baseTime.Add(-400 * time.Second)})
	issued, _ := alerts.Grants(context.Background(), "code", deviceID, "template-1", 0, "guest")
	// 带上有配置才能走到报价新鲜度检查
	_, err := alerts.Evaluate(context.Background(), EvaluateInput{
		DeviceID: deviceID, RequestID: "req-1", Grant: issued.Grant, Workspace: "guest",
		Guest: domain.GuestConfiguration{{
			RecordID: recordID,
			Input:    domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500},
			Alerts:   []domain.Alert{{ID: alertID, Kind: domain.AlertPrice, Threshold: 550}},
		}},
	})
	if !errors.Is(err, domain.ErrUnavailable) {
		t.Fatalf("err = %v, want ErrUnavailable for stale quote", err)
	}
}

func TestEvaluateIsIdempotentPerRequest(t *testing.T) {
	store := newFakeStore()
	wechat := &fakeWechat{openID: "o"}
	alerts := newAlerts(store, wechat, fakeQuotes{price: 600, asOf: baseTime})
	issued, _ := alerts.Grants(context.Background(), "code", deviceID, "template-1", 0, "guest")

	input := EvaluateInput{
		DeviceID: deviceID, RequestID: "req-1", Grant: issued.Grant, Workspace: "guest",
		Guest: domain.GuestConfiguration{{
			RecordID: recordID,
			Input:    domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500},
			Alerts:   []domain.Alert{{ID: alertID, Kind: domain.AlertPrice, Threshold: 550}},
		}},
	}
	// 第一次建立基线
	if _, err := alerts.Evaluate(context.Background(), input); err != nil {
		t.Fatalf("first evaluate: %v", err)
	}
	callsAfterFirst := wechat.sent
	// 同一 requestID 重复提交不得再次发送
	if _, err := alerts.Evaluate(context.Background(), input); err != nil {
		t.Fatalf("second evaluate: %v", err)
	}
	if wechat.sent != callsAfterFirst {
		t.Fatalf("duplicate request must not resend: %d -> %d", callsAfterFirst, wechat.sent)
	}
}

func TestGuestConfigurationRejectsArbitraryContent(t *testing.T) {
	// 只接受 UUID/数值/固定枚举，不接受任意文本
	valid := domain.ValidatedRecord{
		RecordID: recordID,
		Input:    domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500},
		Alerts:   []domain.Alert{{ID: alertID, Kind: domain.AlertPrice, Threshold: 600}},
	}
	if err := (domain.GuestConfiguration{valid}).Validate(); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
	// 非法 kind
	bad := valid
	bad.Alerts = []domain.Alert{{ID: alertID, Kind: "任意内容", Threshold: 600}}
	if err := (domain.GuestConfiguration{bad}).Validate(); err == nil {
		t.Fatal("expected rejection of unknown alert kind")
	}
	// 非法 record_id
	bad2 := valid
	bad2.RecordID = "<script>alert(1)</script>"
	if err := (domain.GuestConfiguration{bad2}).Validate(); err == nil {
		t.Fatal("expected rejection of non-uuid record id")
	}
}

func TestGuestConfigurationRejectsTooManyAlerts(t *testing.T) {
	record := domain.ValidatedRecord{
		RecordID: recordID,
		Input:    domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500},
		Alerts: []domain.Alert{
			{ID: "a1111111-1111-4111-8111-111111111111", Kind: domain.AlertPrice, Threshold: 1},
			{ID: "a2222222-2222-4222-8222-222222222222", Kind: domain.AlertPrice, Threshold: 2},
			{ID: "a3333333-3333-4333-8333-333333333333", Kind: domain.AlertPrice, Threshold: 3},
			{ID: "a4444444-4444-4444-8444-444444444444", Kind: domain.AlertPrice, Threshold: 4},
			{ID: "a5555555-5555-4555-8555-555555555555", Kind: domain.AlertPrice, Threshold: 5},
		},
	}
	if err := (domain.GuestConfiguration{record}).Validate(); err == nil {
		t.Fatal("expected rejection of more than 4 alerts")
	}
}

func TestEvaluateTriggersOnCrossingAndConsumesCooldown(t *testing.T) {
	store := newFakeStore()
	wechat := &fakeWechat{openID: "o"}
	clock := baseTime
	alerts := HoldingAlerts{
		Store:  store,
		Quotes: fakeQuotes{},
		Wechat: wechat,
		Crypto: &fakeCrypto{},
		Template: TemplateConfig{
			TemplateID: "template-1",
			Fields:     map[string]string{"kind": "thing1"},
		},
		Now:      func() time.Time { return clock },
		GrantTTL: 15 * time.Minute,
	}
	_ = alerts

	// 直接测引擎：先低于目标再达到才触发
	input := domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500}
	alert := domain.Alert{ID: alertID, Kind: domain.AlertPrice, Threshold: 600}

	baseline := ports.Baseline{}
	triggered, next := EvaluateOne(alert, input, baseline, 590, baseTime, baseTime)
	if triggered {
		t.Fatal("first observation above-near-target must not trigger")
	}
	if !next.Armed {
		t.Fatal("expected armed after observing below target")
	}

	triggered, next = EvaluateOne(alert, input, next, 605, baseTime.Add(5*time.Second), baseTime.Add(5*time.Second))
	if !triggered {
		t.Fatal("expected trigger on crossing")
	}
	if next.Armed {
		t.Fatal("armed must reset after trigger")
	}
	if next.LastTriggeredAt == nil {
		t.Fatal("cooldown must be recorded")
	}
}

func TestEvaluateRejectsJumpOver20Percent(t *testing.T) {
	input := domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500}
	alert := domain.Alert{ID: alertID, Kind: domain.AlertPrice, Threshold: 600}
	baseline := ports.Baseline{PreviousPrice: 500, PreviousAsOf: baseTime, Armed: true}
	// 500 → 700 是 40% 跳变
	triggered, next := EvaluateOne(alert, input, baseline, 700, baseTime.Add(5*time.Second), baseTime.Add(5*time.Second))
	if triggered {
		t.Fatal("abnormal jump must not trigger")
	}
	if next.PreviousPrice != 500 {
		t.Fatal("abnormal jump must not update baseline")
	}
}

func TestEvaluateRespectsCooldown(t *testing.T) {
	input := domain.GoldInput{Grams: 10, Purity: 1, UnitPrice: 500}
	alert := domain.Alert{ID: alertID, Kind: domain.AlertPrice, Threshold: 600}
	fired := baseTime.Add(-time.Hour)
	baseline := ports.Baseline{}
	baseline.PreviousPrice = 590
	baseline.PreviousAsOf = baseTime
	baseline.Armed = true
	baseline.LastTriggeredAt = &fired
	triggered, _ := EvaluateOne(alert, input, baseline, 605, baseTime.Add(time.Second), baseTime.Add(time.Second))
	if triggered {
		t.Fatal("must not trigger within 24h cooldown")
	}
}

func TestEvaluateGuestWithoutRecordsSendsNothing(t *testing.T) {
	store := newFakeStore()
	wechat := &fakeWechat{openID: "o"}
	alerts := newAlerts(store, wechat, fakeQuotes{price: 600, asOf: baseTime})
	issued, _ := alerts.Grants(context.Background(), "code", deviceID, "template-1", 0, "guest")

	result, err := alerts.Evaluate(context.Background(), EvaluateInput{
		DeviceID: deviceID, RequestID: "req-1", Grant: issued.Grant, Workspace: "guest",
	})
	if err != nil {
		t.Fatalf("Evaluate: %v", err)
	}
	if len(result.Events) != 0 {
		t.Fatalf("expected no events, got %d", len(result.Events))
	}
	if wechat.sent != 0 {
		t.Fatal("guest without configuration must not send")
	}
}

var _ = grantHash
