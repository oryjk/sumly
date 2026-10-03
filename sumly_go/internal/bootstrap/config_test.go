package bootstrap

import "testing"

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
