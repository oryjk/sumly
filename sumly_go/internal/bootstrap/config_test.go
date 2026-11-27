package bootstrap

import (
	"strings"
	"testing"
	"time"
)

func TestLoadConfigRejectsAppleTestCredentialOutsideTest(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("NATIVE_AUTH_ENABLED", "true")
	t.Setenv("APPLE_TEST_CLIENT_SECRET_FILE", "test-credential")
	for _, environment := range []string{"production", "development", ""} {
		t.Setenv("APP_ENV", environment)
		if _, err := LoadConfig(); err == nil || !strings.Contains(err.Error(), "requires APP_ENV=test") {
			t.Fatalf("expected test credential rejection for %q, got %v", environment, err)
		}
	}
}

func TestLoadConfigParsesDevLoginEnabled(t *testing.T) {
	for _, test := range []struct {
		name     string
		value    string
		expected bool
	}{
		{name: "true 开启", value: "true", expected: true},
		{name: "false 关闭", value: "false", expected: false},
		{name: "缺省关闭", value: "", expected: false},
		{name: "其他值关闭", value: "1", expected: false},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("DATABASE_URL", "postgres://example")
			t.Setenv("JWT_SECRET", "secret")
			t.Setenv("WECHAT_APP_ID", "appid")
			t.Setenv("WECHAT_APP_SECRET", "appsecret")
			t.Setenv("DEV_LOGIN_ENABLED", test.value)

			config, err := LoadConfig()
			if err != nil {
				t.Fatalf("load config: %v", err)
			}
			if config.DevLoginEnabled != test.expected {
				t.Fatalf("expected DevLoginEnabled=%v, got %v", test.expected, config.DevLoginEnabled)
			}
		})
	}
}

// WECHAT_LEGACY_APP_ID 是可选的：留空表示不迁移旧裸 openid 身份，
// 而不是配置错误。误设为必填会让所有部署直接启动失败。
func TestLoadConfigTreatsWechatLegacyAppIDAsOptional(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("WECHAT_LEGACY_APP_ID", "")

	config, err := LoadConfig()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if config.WechatLegacyAppID != "" {
		t.Fatalf("expected empty legacy appid, got %q", config.WechatLegacyAppID)
	}
}

func TestLoadConfigKeepsConfirmedLegacyAppID(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("WECHAT_LEGACY_APP_ID", "appid")

	config, err := LoadConfig()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if config.WechatLegacyAppID != "appid" {
		t.Fatalf("legacy appid = %q", config.WechatLegacyAppID)
	}
}

func TestLoadConfigMacroDefaultsAndOverrides(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("FRED_API_KEY", "")
	t.Setenv("MACRO_SYNC_ENABLED", "")
	t.Setenv("MACRO_OFFICIAL_ACCOUNT_NAME", "")
	t.Setenv("MACRO_OFFICIAL_ACCOUNT_NOTE", "")
	t.Setenv("MACRO_INTERNAL_TOKEN", "")

	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.FREDAPIKey != "" || !cfg.MacroSyncEnabled || cfg.MacroOfficialAccountName != "" || cfg.MacroOfficialAccountNote != "" || cfg.MacroInternalToken != "" {
		t.Fatalf("expected optional empty macro defaults and MacroSyncEnabled=true, got %+v", cfg)
	}

	t.Setenv("FRED_API_KEY", "test-fred-key")
	t.Setenv("MACRO_SYNC_ENABLED", "false")
	t.Setenv("MACRO_OFFICIAL_ACCOUNT_NAME", "  黄金观察室  ")
	t.Setenv("MACRO_OFFICIAL_ACCOUNT_NOTE", "  自定义方法论注记  ")
	t.Setenv("MACRO_INTERNAL_TOKEN", "  internal-secret-token  ")
	cfg, err = LoadConfig()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.FREDAPIKey != "test-fred-key" || cfg.MacroSyncEnabled {
		t.Fatalf("expected FREDAPIKey=test-fred-key and MacroSyncEnabled=false, got %+v", cfg)
	}
	if cfg.MacroOfficialAccountName != "黄金观察室" || cfg.MacroOfficialAccountNote != "自定义方法论注记" || cfg.MacroInternalToken != "internal-secret-token" {
		t.Fatalf("unexpected macro compliance/internal config: %+v", cfg)
	}
}

func TestLoadConfigAdminDefaultsAndOverrides(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("ADMIN_BOOTSTRAP_USERNAME", "")
	t.Setenv("ADMIN_BOOTSTRAP_PASSWORD", "")
	t.Setenv("ADMIN_API_TOKEN", "")
	t.Setenv("ADMIN_CORS_ORIGINS", "")
	t.Setenv("ADMIN_STATIC_DIR", "")

	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.AdminBootstrapUsername != "admin" || cfg.AdminBootstrapPassword != "" {
		t.Fatalf("expected default bootstrap admin username='admin' and empty password, got user=%q pass=%q", cfg.AdminBootstrapUsername, cfg.AdminBootstrapPassword)
	}
	if cfg.AdminAPIToken != "" || cfg.AdminStaticDir != "" {
		t.Fatalf("expected empty optional admin defaults, got token=%q static=%q", cfg.AdminAPIToken, cfg.AdminStaticDir)
	}
	wantOrigins := []string{"http://localhost:5173", "http://127.0.0.1:5173", "https://oryjk.cn"}
	if len(cfg.AdminCORSOrigins) != len(wantOrigins) {
		t.Fatalf("default AdminCORSOrigins=%v want %v", cfg.AdminCORSOrigins, wantOrigins)
	}
	for i, origin := range wantOrigins {
		if cfg.AdminCORSOrigins[i] != origin {
			t.Fatalf("default AdminCORSOrigins[%d]=%q want %q", i, cfg.AdminCORSOrigins[i], origin)
		}
	}

	t.Setenv("ADMIN_BOOTSTRAP_USERNAME", "  superadmin  ")
	t.Setenv("ADMIN_BOOTSTRAP_PASSWORD", "BootstrapPass#2026")
	t.Setenv("ADMIN_API_TOKEN", "  admin-secret-xyz  ")
	t.Setenv("ADMIN_CORS_ORIGINS", " https://admin.oryjk.cn/ , http://localhost:3000 ")
	t.Setenv("ADMIN_STATIC_DIR", "  /var/www/sumly-admin  ")
	cfg, err = LoadConfig()
	if err != nil {
		t.Fatalf("load config overrides: %v", err)
	}
	if cfg.AdminBootstrapUsername != "superadmin" || cfg.AdminBootstrapPassword != "BootstrapPass#2026" {
		t.Fatalf("unexpected admin bootstrap overrides: user=%q pass=%q", cfg.AdminBootstrapUsername, cfg.AdminBootstrapPassword)
	}
	if cfg.AdminAPIToken != "admin-secret-xyz" || cfg.AdminStaticDir != "/var/www/sumly-admin" {
		t.Fatalf("unexpected admin overrides: token=%q static=%q", cfg.AdminAPIToken, cfg.AdminStaticDir)
	}
	if len(cfg.AdminCORSOrigins) != 2 || cfg.AdminCORSOrigins[0] != "https://admin.oryjk.cn" || cfg.AdminCORSOrigins[1] != "http://localhost:3000" {
		t.Fatalf("unexpected AdminCORSOrigins override: %v", cfg.AdminCORSOrigins)
	}
}

func TestLoadConfigFeedbackDefaultsAndOverrides(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("FEEDBACK_MINIO_ENDPOINT", "")
	t.Setenv("FEEDBACK_MINIO_ACCESS_KEY", "")
	t.Setenv("FEEDBACK_MINIO_SECRET_KEY", "")
	t.Setenv("FEEDBACK_MINIO_BUCKET", "")
	t.Setenv("FEEDBACK_MINIO_REGION", "")
	t.Setenv("FEEDBACK_MINIO_PUBLIC_URL_PREFIX", "")
	t.Setenv("FEEDBACK_PUBLIC_BASE_URL", "")
	t.Setenv("FEISHU_FEEDBACK_WEBHOOK_URL", "")

	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.FeedbackMinIOBucket != "sumly" || cfg.FeedbackMinIORegion != "us-east-1" {
		t.Fatalf("unexpected feedback defaults: bucket=%q region=%q", cfg.FeedbackMinIOBucket, cfg.FeedbackMinIORegion)
	}
	if cfg.FeedbackMinIOEndpoint != "" || cfg.FeishuFeedbackWebhookURL != "" {
		t.Fatalf("expected empty optional feedback config, got %+v", cfg)
	}

	t.Setenv("FEEDBACK_MINIO_ENDPOINT", "  https://minio.example.com/  ")
	t.Setenv("FEEDBACK_MINIO_ACCESS_KEY", "  ak-test ")
	t.Setenv("FEEDBACK_MINIO_SECRET_KEY", " sk-test ")
	t.Setenv("FEEDBACK_MINIO_BUCKET", " custom-bucket ")
	t.Setenv("FEEDBACK_MINIO_REGION", " ap-east-1 ")
	t.Setenv("FEEDBACK_MINIO_PUBLIC_URL_PREFIX", " https://cdn.example.com/sumly ")
	t.Setenv("FEEDBACK_PUBLIC_BASE_URL", " https://oryjk.cn/sumly ")
	t.Setenv("FEISHU_FEEDBACK_WEBHOOK_URL", " https://open.feishu.cn/open-apis/bot/v2/hook/test-only ")

	cfg, err = LoadConfig()
	if err != nil {
		t.Fatalf("load config overrides: %v", err)
	}
	if cfg.FeedbackMinIOEndpoint != "https://minio.example.com/" ||
		cfg.FeedbackMinIOAccessKey != "ak-test" ||
		cfg.FeedbackMinIOSecretKey != "sk-test" ||
		cfg.FeedbackMinIOBucket != "custom-bucket" ||
		cfg.FeedbackMinIORegion != "ap-east-1" ||
		cfg.FeedbackMinIOPublicURLPrefix != "https://cdn.example.com/sumly" ||
		cfg.FeedbackPublicBaseURL != "https://oryjk.cn/sumly" ||
		cfg.FeishuFeedbackWebhookURL != "https://open.feishu.cn/open-apis/bot/v2/hook/test-only" {
		t.Fatalf("unexpected feedback overrides: %+v", cfg)
	}
}

func TestLoadConfigDBPoolDefaultsAndOverrides(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://sumly:pass@localhost:5432/sumly?sslmode=disable")
	t.Setenv("JWT_SECRET", "secret")
	t.Setenv("WECHAT_APP_ID", "appid")
	t.Setenv("WECHAT_APP_SECRET", "appsecret")
	t.Setenv("DB_POOL_MAX_CONNS", "")
	t.Setenv("DB_POOL_MIN_CONNS", "")
	t.Setenv("DB_POOL_MAX_CONN_LIFETIME", "")
	t.Setenv("DB_POOL_MAX_CONN_IDLE_TIME", "")
	t.Setenv("DB_POOL_HEALTH_CHECK_PERIOD", "")

	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("load config defaults: %v", err)
	}
	if cfg.DBPool.MaxConns != 25 ||
		cfg.DBPool.MinConns != 4 ||
		cfg.DBPool.MaxConnLifetime != 30*time.Minute ||
		cfg.DBPool.MaxConnIdleTime != 5*time.Minute ||
		cfg.DBPool.HealthCheckPeriod != 30*time.Second {
		t.Fatalf("unexpected DBPool defaults: %+v", cfg.DBPool)
	}

	parsed, err := buildPoolConfig(cfg.DatabaseURL, cfg.DBPool)
	if err != nil {
		t.Fatalf("buildPoolConfig defaults: %v", err)
	}
	if parsed.MaxConns != 25 ||
		parsed.MinConns != 4 ||
		parsed.MaxConnLifetime != 30*time.Minute ||
		parsed.MaxConnIdleTime != 5*time.Minute ||
		parsed.HealthCheckPeriod != 30*time.Second {
		t.Fatalf("unexpected parsed pool config defaults: max=%d min=%d life=%v idle=%v hc=%v",
			parsed.MaxConns, parsed.MinConns, parsed.MaxConnLifetime, parsed.MaxConnIdleTime, parsed.HealthCheckPeriod)
	}

	t.Setenv("DB_POOL_MAX_CONNS", "40")
	t.Setenv("DB_POOL_MIN_CONNS", "0")
	t.Setenv("DB_POOL_MAX_CONN_LIFETIME", "45m")
	t.Setenv("DB_POOL_MAX_CONN_IDLE_TIME", "10m")
	t.Setenv("DB_POOL_HEALTH_CHECK_PERIOD", "15s")

	cfg, err = LoadConfig()
	if err != nil {
		t.Fatalf("load config overrides: %v", err)
	}
	parsed, err = buildPoolConfig(cfg.DatabaseURL, cfg.DBPool)
	if err != nil {
		t.Fatalf("buildPoolConfig overrides: %v", err)
	}
	if parsed.MaxConns != 40 ||
		parsed.MinConns != 0 ||
		parsed.MaxConnLifetime != 45*time.Minute ||
		parsed.MaxConnIdleTime != 10*time.Minute ||
		parsed.HealthCheckPeriod != 15*time.Second {
		t.Fatalf("unexpected parsed pool config overrides: max=%d min=%d life=%v idle=%v hc=%v",
			parsed.MaxConns, parsed.MinConns, parsed.MaxConnLifetime, parsed.MaxConnIdleTime, parsed.HealthCheckPeriod)
	}

	// 未显式指定 MinConns 且 MaxConns < 默认 MinConns 时自动夹紧
	t.Setenv("DB_POOL_MAX_CONNS", "2")
	t.Setenv("DB_POOL_MIN_CONNS", "")
	cfg, err = LoadConfig()
	if err != nil {
		t.Fatalf("load config small max conns: %v", err)
	}
	if cfg.DBPool.MaxConns != 2 || cfg.DBPool.MinConns != 2 {
		t.Fatalf("expected MinConns clamped to MaxConns=2, got %+v", cfg.DBPool)
	}

	// 显式指定 MinConns > MaxConns 时报错
	t.Setenv("DB_POOL_MIN_CONNS", "5")
	if _, err := LoadConfig(); err == nil || !strings.Contains(err.Error(), "DB_POOL_MIN_CONNS") {
		t.Fatalf("expected error when DB_POOL_MIN_CONNS > DB_POOL_MAX_CONNS, got %v", err)
	}

	// 非法 duration 报错
	t.Setenv("DB_POOL_MIN_CONNS", "1")
	t.Setenv("DB_POOL_MAX_CONN_LIFETIME", "not-a-duration")
	if _, err := LoadConfig(); err == nil || !strings.Contains(err.Error(), "DB_POOL_MAX_CONN_LIFETIME") {
		t.Fatalf("expected invalid DB_POOL_MAX_CONN_LIFETIME error, got %v", err)
	}
}
