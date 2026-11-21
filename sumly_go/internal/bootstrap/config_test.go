package bootstrap

import (
	"strings"
	"testing"
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
