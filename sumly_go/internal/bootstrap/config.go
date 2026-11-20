package bootstrap

import (
	"fmt"
	"os"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/shared/configenv"
)

type AppEnvironment string

const (
	EnvironmentDevelopment AppEnvironment = "development"
	EnvironmentTest        AppEnvironment = "test"
	EnvironmentProduction  AppEnvironment = "production"
)

type Config struct {
	Native          NativeConfig
	HTTPAddr        string
	DatabaseURL     string
	JWTSecret       string
	WechatAppID     string
	WechatAppSecret string
	// WechatLegacyAppID 为已确认归属的旧小程序 appid。
	// 仅当与 WechatAppID 相同时才允许把旧裸 openid 身份迁移到新身份；
	// 留空表示不迁移，避免猜测归属造成错误关联。
	WechatLegacyAppID string
	// 持仓提醒的微信订阅消息模板。TemplateID 与 Fields 必须由部署方按
	// 真实模板填写；缺失时能力检测返回不可用，不会用假模板顶替。
	HoldingNotificationTemplateID  string
	HoldingNotificationFieldPrice  string
	HoldingNotificationFieldKind   string
	HoldingNotificationFieldTarget string
	AppEnvironment                 AppEnvironment
	DevLoginEnabled                bool
	// Macro 宏观与黄金温度模块配置：FRED_API_KEY 可选（留空时跳过 FRED 并告警，不阻断服务启动）；
	// MACRO_SYNC_ENABLED 默认 true，设置为 false 时关闭后台同步 goroutine。
	FREDAPIKey       string
	MacroSyncEnabled bool
}

func LoadConfig() (Config, error) {
	configenv.Load()
	config := Config{
		HTTPAddr:        envOrDefault("HTTP_ADDR", ":18090"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		JWTSecret:       os.Getenv("JWT_SECRET"),
		WechatAppID:     os.Getenv("WECHAT_APP_ID"),
		WechatAppSecret: os.Getenv("WECHAT_APP_SECRET"),
		// 可选项：留空表示不迁移旧裸 openid 身份
		WechatLegacyAppID:              os.Getenv("WECHAT_LEGACY_APP_ID"),
		HoldingNotificationTemplateID:  os.Getenv("HOLDING_NOTIFICATION_TEMPLATE_ID"),
		HoldingNotificationFieldPrice:  os.Getenv("HOLDING_NOTIFICATION_FIELD_PRICE"),
		HoldingNotificationFieldKind:   os.Getenv("HOLDING_NOTIFICATION_FIELD_KIND"),
		HoldingNotificationFieldTarget: os.Getenv("HOLDING_NOTIFICATION_FIELD_TARGET"),
		AppEnvironment:                 parseAppEnvironment(os.Getenv("APP_ENV")),
		DevLoginEnabled:                os.Getenv("DEV_LOGIN_ENABLED") == "true",
		FREDAPIKey:                     strings.TrimSpace(os.Getenv("FRED_API_KEY")),
		MacroSyncEnabled:               !strings.EqualFold(strings.TrimSpace(os.Getenv("MACRO_SYNC_ENABLED")), "false"),
	}

	for name, value := range map[string]string{
		"DATABASE_URL":      config.DatabaseURL,
		"JWT_SECRET":        config.JWTSecret,
		"WECHAT_APP_ID":     config.WechatAppID,
		"WECHAT_APP_SECRET": config.WechatAppSecret,
	} {
		if value == "" {
			return Config{}, fmt.Errorf("%s is required", name)
		}
	}
	var err error
	config.Native, err = loadNativeConfig(config.AppEnvironment)
	if err != nil {
		return Config{}, err
	}
	return config, nil
}

func parseAppEnvironment(value string) AppEnvironment {
	switch AppEnvironment(strings.TrimSpace(value)) {
	case EnvironmentDevelopment:
		return EnvironmentDevelopment
	case EnvironmentTest:
		return EnvironmentTest
	case EnvironmentProduction:
		return EnvironmentProduction
	default:
		return EnvironmentProduction
	}
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
