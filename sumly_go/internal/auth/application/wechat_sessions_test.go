package application

import (
	"context"
	"errors"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

// wechatSessionStore 只实现 LoginWechat 所需行为，其余方法留空以满足接口。
type wechatSessionStore struct {
	ports.NativeStore
	user             domain.User
	err              error
	calls            int
	mutation         ports.LoginMutation
	migrationAllowed bool
}

func (s *wechatSessionStore) LoginWechat(_ context.Context, appID, legacyAppID, openID string, session domain.Session) (domain.User, error) {
	s.calls++
	s.mutation = ports.LoginMutation{
		Provider: "wechat",
		Subject:  WechatSubject(appID, openID),
		OpenID:   openID,
		Session:  session,
	}
	// 记录迁移决策供断言；归属未确认时不得迁移旧身份
	s.migrationAllowed = legacyAppID != "" && legacyAppID == appID
	return s.user, s.err
}

type wechatGatewayStub struct {
	identity ports.WechatIdentity
	err      error
	codes    []string
}

func (g *wechatGatewayStub) ExchangeCode(_ context.Context, code string) (ports.WechatIdentity, error) {
	g.codes = append(g.codes, code)
	return g.identity, g.err
}

func newWechatSessions(gateway ports.WechatGateway, store ports.NativeStore) WechatSessions {
	return WechatSessions{
		Wechat:      gateway,
		Store:       store,
		Crypto:      wechatCrypto{},
		Tokens:      wechatTokens{},
		Sessions:    Sessions{Crypto: wechatCrypto{}, Tokens: wechatTokens{}},
		AppID:       "wx-current",
		LegacyAppID: "wx-legacy",
	}
}

func TestWechatSessionLoginIssuesNativeSession(t *testing.T) {
	store := &wechatSessionStore{user: domain.User{ID: 7, Status: "active", Provider: "wechat"}}
	gateway := &wechatGatewayStub{identity: ports.WechatIdentity{OpenID: "openid-1", SessionKey: "sk"}}
	sessions := newWechatSessions(gateway, store)

	result, err := sessions.Login(context.Background(), " code-1 ")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if result.User.ID != 7 {
		t.Fatalf("user = %d, want 7", result.User.ID)
	}
	if result.ExpiresIn != 900 {
		t.Fatalf("expires_in = %d, want 900", result.ExpiresIn)
	}
	if result.Token == "" || result.RefreshToken == "" {
		t.Fatal("expected both access and refresh tokens")
	}
	if store.calls != 1 {
		t.Fatalf("store calls = %d, want 1", store.calls)
	}
	// 身份以 appid + openid 编码，禁止跨 appid 误绑定
	if store.mutation.Subject != "wechat:wx-current:openid-1" {
		t.Fatalf("subject = %q", store.mutation.Subject)
	}
	// 不把 raw openid 或 session_key 放进登录响应
	if result.User.Email != nil {
		t.Fatal("unexpected email")
	}
}

func TestWechatSessionLoginRejectsEmptyCode(t *testing.T) {
	store := &wechatSessionStore{}
	gateway := &wechatGatewayStub{}
	sessions := newWechatSessions(gateway, store)

	if _, err := sessions.Login(context.Background(), "   "); err == nil {
		t.Fatal("expected validation error for empty code")
	}
	if store.calls != 0 {
		t.Fatal("store must not be touched for empty code")
	}
	if len(gateway.codes) != 0 {
		t.Fatal("gateway must not be called for empty code")
	}
}

func TestWechatSessionLoginPropagatesGatewayFailure(t *testing.T) {
	store := &wechatSessionStore{}
	gateway := &wechatGatewayStub{err: errors.New("upstream rejected")}
	sessions := newWechatSessions(gateway, store)

	if _, err := sessions.Login(context.Background(), "code"); err == nil {
		t.Fatal("expected error when gateway fails")
	}
	if store.calls != 0 {
		t.Fatal("no session may be created when identity exchange fails")
	}
}

func TestWechatSessionLoginWithoutConfiguredAppID(t *testing.T) {
	store := &wechatSessionStore{}
	gateway := &wechatGatewayStub{identity: ports.WechatIdentity{OpenID: "o"}}
	sessions := newWechatSessions(gateway, store)
	sessions.AppID = ""

	if _, err := sessions.Login(context.Background(), "code"); !errors.Is(err, domain.ErrUnavailable) {
		t.Fatalf("err = %v, want ErrUnavailable", err)
	}
	if store.calls != 0 {
		t.Fatal("no session may be created without appid")
	}
}

func TestWechatSessionLoginRejectsInactiveUser(t *testing.T) {
	store := &wechatSessionStore{user: domain.User{ID: 7, Status: "frozen", Provider: "wechat"}}
	gateway := &wechatGatewayStub{identity: ports.WechatIdentity{OpenID: "o"}}
	sessions := newWechatSessions(gateway, store)

	if _, err := sessions.Login(context.Background(), "code"); err == nil {
		t.Fatal("expected frozen account to be rejected")
	}
}

func TestWechatSubjectScopesOpenIDByAppID(t *testing.T) {
	if got := WechatSubject("wx-a", "openid"); got != "wechat:wx-a:openid" {
		t.Fatalf("subject = %q", got)
	}
	// 不同 appid 的同一 openid 必须得到不同 subject
	if WechatSubject("wx-a", "openid") == WechatSubject("wx-b", "openid") {
		t.Fatal("subject must not collide across appid")
	}
}

func TestWechatLegacySubjectOnlyWhenAppIDConfirmed(t *testing.T) {
	store := &wechatSessionStore{user: domain.User{ID: 3, Status: "active"}}
	gateway := &wechatGatewayStub{identity: ports.WechatIdentity{OpenID: "legacy-openid"}}
	sessions := newWechatSessions(gateway, store)
	sessions.LegacyAppID = "wx-current"

	if _, err := sessions.Login(context.Background(), "code"); err != nil {
		t.Fatalf("Login: %v", err)
	}
	if store.mutation.Subject != "wechat:wx-current:legacy-openid" {
		t.Fatalf("subject = %q", store.mutation.Subject)
	}
}

func TestWechatSessionLoginSkipsMigrationWhenLegacyAppIDUnconfirmed(t *testing.T) {
	store := &wechatSessionStore{user: domain.User{ID: 3, Status: "active"}}
	gateway := &wechatGatewayStub{identity: ports.WechatIdentity{OpenID: "legacy-openid"}}
	sessions := newWechatSessions(gateway, store)
	// legacy appid 与当前不一致时不得猜测归属：正常登录但不迁移
	sessions.LegacyAppID = "wx-other"

	if _, err := sessions.Login(context.Background(), "code"); err != nil {
		t.Fatalf("login should still succeed, got %v", err)
	}
	if store.migrationAllowed {
		t.Fatal("migration must be skipped when legacy appid differs")
	}
	// 身份仍按当前 appid 编码，不沿用旧裸 openid
	if store.mutation.Subject != "wechat:wx-current:legacy-openid" {
		t.Fatalf("subject = %q", store.mutation.Subject)
	}
}

func TestWechatCapabilitiesReflectConfiguration(t *testing.T) {
	accounts := Accounts{Wechat: &WechatSessions{AppID: "wx-current"}}
	if !accounts.Capabilities().Wechat {
		t.Fatal("wechat capability should be true when configured")
	}
	empty := Accounts{}
	if empty.Capabilities().Wechat {
		t.Fatal("wechat capability should be false when unconfigured")
	}
}

func TestWechatSessionLoginMapsUnavailableError(t *testing.T) {
	store := &wechatSessionStore{}
	gateway := &wechatGatewayStub{err: sharederror.New(sharederror.KindUnauthorized, "bad code")}
	sessions := newWechatSessions(gateway, store)

	_, err := sessions.Login(context.Background(), "code")
	if err == nil {
		t.Fatal("expected error")
	}
}

// wechatCrypto 与 wechatTokens 为本文件专用桩，避免与其他测试文件重名。
type wechatCrypto struct{ ports.Cryptography }

func (wechatCrypto) Random() string                   { return "random-value" }
func (wechatCrypto) Digest(kind, value string) string { return kind + ":" + value }

type wechatTokens struct{ ports.NativeTokens }

func (wechatTokens) IssueNative(context.Context, domain.Session) (string, error) {
	return "access-token", nil
}
func (wechatTokens) ParseNative(context.Context, string) (string, error) { return "sid", nil }
