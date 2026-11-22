package bootstrap

import (
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net"
	"os"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/providers"
	wechatclient "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/wechat"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NativeConfig struct {
	Enabled               bool
	Apple                 providers.AppleConfig
	AppleEmailLinkEnabled bool
	GoogleClientID        string
	SMS                   providers.SMS
	SMTP                  providers.SMTP
	TrustedProxies        []string
	ChanlunEndpoint       string
	ChanlunSecret         string
}

func loadNativeConfig(environment AppEnvironment) (NativeConfig, error) {
	c := NativeConfig{Enabled: os.Getenv("NATIVE_AUTH_ENABLED") == "true"}
	if raw := strings.TrimSpace(os.Getenv("TRUSTED_PROXY_CIDRS")); raw != "" {
		for _, cidr := range strings.Split(raw, ",") {
			cidr = strings.TrimSpace(cidr)
			if _, _, e := net.ParseCIDR(cidr); e != nil {
				return c, fmt.Errorf("invalid TRUSTED_PROXY_CIDRS")
			}
			c.TrustedProxies = append(c.TrustedProxies, cidr)
		}
	}
	if !c.Enabled {
		return c, nil
	}
	c.ChanlunEndpoint = os.Getenv("CHANLUN_TICKET_URL")
	c.ChanlunSecret = os.Getenv("CHANLUN_BRIDGE_SECRET")
	c.Apple = providers.AppleConfig{ClientID: os.Getenv("APPLE_CLIENT_ID"), TeamID: os.Getenv("APPLE_TEAM_ID"), KeyID: os.Getenv("APPLE_KEY_ID")}
	c.GoogleClientID = os.Getenv("GOOGLE_OAUTH_CLIENT_ID")
	c.AppleEmailLinkEnabled = os.Getenv("APPLE_EMAIL_LINK_ENABLED") == "true"
	privateKeyPath := os.Getenv("APPLE_PRIVATE_KEY_FILE")
	if path := os.Getenv("APPLE_TEST_CLIENT_SECRET_FILE"); path != "" {
		if environment != EnvironmentTest {
			return c, fmt.Errorf("APPLE_TEST_CLIENT_SECRET_FILE requires APP_ENV=test")
		}
		if privateKeyPath != "" {
			return c, fmt.Errorf("APPLE_TEST_CLIENT_SECRET_FILE cannot be combined with APPLE_PRIVATE_KEY_FILE")
		}
		secret, e := os.ReadFile(path)
		if e != nil {
			return c, fmt.Errorf("cannot read APPLE_TEST_CLIENT_SECRET_FILE")
		}
		c.Apple.TestClientSecret = strings.TrimSpace(string(secret))
		if c.Apple.TestClientSecret == "" {
			return c, fmt.Errorf("APPLE_TEST_CLIENT_SECRET_FILE is empty")
		}
	}
	if path := privateKeyPath; path != "" {
		b, e := os.ReadFile(path)
		if e != nil {
			return c, fmt.Errorf("cannot read APPLE_PRIVATE_KEY_FILE")
		}
		p, _ := pem.Decode(b)
		if p == nil {
			return c, fmt.Errorf("invalid Apple private key")
		}
		k, e := x509.ParsePKCS8PrivateKey(p.Bytes)
		if e != nil {
			return c, fmt.Errorf("invalid Apple PKCS8 private key")
		}
		key, ok := k.(*ecdsa.PrivateKey)
		if !ok || key.Curve.Params().Name != "P-256" {
			return c, fmt.Errorf("Apple key must be ES256")
		}
		c.Apple.PrivateKey = key
	}
	c.SMS = providers.SMS{AccessKeyID: os.Getenv("ALIYUN_ACCESS_KEY_ID"), AccessKeySecret: os.Getenv("ALIYUN_ACCESS_KEY_SECRET"), SignName: os.Getenv("ALIYUN_SMS_SIGN_NAME"), TemplateCode: os.Getenv("ALIYUN_SMS_TEMPLATE_CODE")}
	c.SMTP = providers.SMTP{Host: os.Getenv("SMTP_HOST"), Port: os.Getenv("SMTP_PORT"), Username: os.Getenv("SMTP_USERNAME"), Password: os.Getenv("SMTP_PASSWORD"), From: os.Getenv("SMTP_FROM"), Mode: os.Getenv("SMTP_TLS_MODE")}
	return c, nil
}
func buildNative(config Config, pool *pgxpool.Pool, tokens *jwt.Service) (*authhttp.NativeHandler, authhttp.Middleware, error) {
	middleware := authhttp.NewMiddleware(tokens)
	if !config.Native.Enabled {
		return authhttp.NewNativeHandler(application.Accounts{}, application.Sessions{}, nil), middleware, nil
	}
	crypto, e := credentials.New(config.JWTSecret)
	if e != nil {
		return nil, middleware, e
	}
	store := postgres.NewNativeStore(pool)
	apple := providers.NewApple(config.Native.Apple, nil, crypto)
	google := providers.NewGoogle(config.Native.GoogleClientID, nil, crypto)
	codes := application.Codes{Store: store, Crypto: crypto, Phone: config.Native.SMS, Email: config.Native.SMTP}
	sessions := application.Sessions{Store: store, Crypto: crypto, Tokens: tokens, Apple: apple}
	dummy, e := crypto.HashPassword(crypto.Random())
	if e != nil {
		return nil, middleware, e
	}
	// 微信统一会话：与旧 /auth/wechat/login 共用身份解析，但签发可刷新的会话。
	// LegacyAppID 只有在明确确认归属时才允许迁移旧裸 openid 身份。
	var wechat *application.WechatSessions
	if config.WechatAppID != "" {
		gateway := wechatclient.NewClient(nil, wechatEndpoint, config.WechatAppID, config.WechatAppSecret)
		wechat = &application.WechatSessions{
			Wechat:      gateway,
			Store:       store,
			Crypto:      crypto,
			Tokens:      tokens,
			Sessions:    sessions,
			AppID:       config.WechatAppID,
			LegacyAppID: config.WechatLegacyAppID,
		}
	}
	accounts := application.Accounts{
		Store: store, Crypto: crypto, Codes: codes, Sessions: sessions,
		Apple: apple, AppleEmailLinkEnabled: config.Native.AppleEmailLinkEnabled,
		Google: google, Links: store, Wechat: wechat, DummyHash: dummy,
	}
	handler := authhttp.NewNativeHandler(accounts, sessions, wechat)
	if config.AppEnvironment != EnvironmentProduction && (config.Native.ChanlunEndpoint != "" || config.Native.ChanlunSecret != "") {
		bridge, err := providers.NewChanlunBridge(config.Native.ChanlunEndpoint, config.Native.ChanlunSecret)
		if err != nil {
			return nil, middleware, err
		}
		handler.EnableChanlunBridge(bridge)
	}
	return handler, authhttp.NewMiddleware(jwt.LiveTokens{Service: tokens, Store: store}), nil
}
