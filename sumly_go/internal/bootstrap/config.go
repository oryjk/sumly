package bootstrap

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/appconfig/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/shared/configenv"
)

const (
	defaultDBPoolMaxConns          int32 = 25
	defaultDBPoolMinConns          int32 = 4
	defaultDBPoolMaxConnLifetime         = 30 * time.Minute
	defaultDBPoolMaxConnIdleTime         = 5 * time.Minute
	defaultDBPoolHealthCheckPeriod       = 30 * time.Second
)

// DBPoolConfig 控制 pgxpool 连接池容量与健康检查参数，可通过环境变量覆盖。
type DBPoolConfig struct {
	MaxConns           int32
	MinConns           int32
	MaxConnLifetime    time.Duration
	MaxConnIdleTime    time.Duration
	HealthCheckPeriod  time.Duration
	minConnsConfigured bool
}

func defaultDBPoolConfig() DBPoolConfig {
	return DBPoolConfig{
		MaxConns:          defaultDBPoolMaxConns,
		MinConns:          defaultDBPoolMinConns,
		MaxConnLifetime:   defaultDBPoolMaxConnLifetime,
		MaxConnIdleTime:   defaultDBPoolMaxConnIdleTime,
		HealthCheckPeriod: defaultDBPoolHealthCheckPeriod,
	}
}

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
	DBPool          DBPoolConfig
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
	// MACRO_OFFICIAL_ACCOUNT_NAME / MACRO_OFFICIAL_ACCOUNT_NOTE 可选，用于温度计说明弹窗中的克制公众号信息；
	// MACRO_INTERNAL_TOKEN 可选，仅用于内部只读策略映射接口鉴权（留空时关闭该内部接口，绝不记录到日志）。
	FREDAPIKey               string
	MacroSyncEnabled         bool
	MacroOfficialAccountName string
	MacroOfficialAccountNote string
	MacroInternalToken       string
	// 远程应用配置与管理后台：
	// ADMIN_BOOTSTRAP_USERNAME（默认 "admin"）与 ADMIN_BOOTSTRAP_PASSWORD（可选）用于首次启动种入初始管理员账号，绝不覆盖已修改密码、绝不记录日志；
	// ADMIN_API_TOKEN 可选，用作自动化脚本兜底令牌（绝不记录日志）；
	// ADMIN_CORS_ORIGINS 留空时默认允许 http://localhost:5173,http://127.0.0.1:5173,https://oryjk.cn；
	// ADMIN_STATIC_DIR 可选，非空且目录存在时挂载 /admin 静态管理后台 SPA。
	AdminBootstrapUsername string
	AdminBootstrapPassword string
	AdminAPIToken          string
	AdminCORSOrigins       []string
	AdminStaticDir         string
	// 用户反馈模块：MinIO S3 对象存储与飞书卡片通知均可选（留空不影响服务启动，绝不记录密钥或 Webhook URL）。
	FeedbackMinIOEndpoint        string
	FeedbackMinIOAccessKey       string
	FeedbackMinIOSecretKey       string
	FeedbackMinIOBucket          string
	FeedbackMinIORegion          string
	FeedbackMinIOPublicURLPrefix string
	FeedbackPublicBaseURL        string
	FeishuFeedbackWebhookURL     string
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
		MacroOfficialAccountName:       strings.TrimSpace(os.Getenv("MACRO_OFFICIAL_ACCOUNT_NAME")),
		MacroOfficialAccountNote:       strings.TrimSpace(os.Getenv("MACRO_OFFICIAL_ACCOUNT_NOTE")),
		MacroInternalToken:             strings.TrimSpace(os.Getenv("MACRO_INTERNAL_TOKEN")),
		AdminBootstrapUsername:         parseAdminBootstrapUsername(os.Getenv("ADMIN_BOOTSTRAP_USERNAME")),
		AdminBootstrapPassword:         os.Getenv("ADMIN_BOOTSTRAP_PASSWORD"),
		AdminAPIToken:                  strings.TrimSpace(os.Getenv("ADMIN_API_TOKEN")),
		AdminCORSOrigins:               parseAdminCORSOrigins(os.Getenv("ADMIN_CORS_ORIGINS")),
		AdminStaticDir:                 strings.TrimSpace(os.Getenv("ADMIN_STATIC_DIR")),
		FeedbackMinIOEndpoint:          strings.TrimSpace(os.Getenv("FEEDBACK_MINIO_ENDPOINT")),
		FeedbackMinIOAccessKey:         strings.TrimSpace(os.Getenv("FEEDBACK_MINIO_ACCESS_KEY")),
		FeedbackMinIOSecretKey:         strings.TrimSpace(os.Getenv("FEEDBACK_MINIO_SECRET_KEY")),
		FeedbackMinIOBucket:            envOrDefaultTrimmed("FEEDBACK_MINIO_BUCKET", "sumly"),
		FeedbackMinIORegion:            envOrDefaultTrimmed("FEEDBACK_MINIO_REGION", "us-east-1"),
		FeedbackMinIOPublicURLPrefix:   strings.TrimSpace(os.Getenv("FEEDBACK_MINIO_PUBLIC_URL_PREFIX")),
		FeedbackPublicBaseURL:          strings.TrimSpace(os.Getenv("FEEDBACK_PUBLIC_BASE_URL")),
		FeishuFeedbackWebhookURL:       strings.TrimSpace(os.Getenv("FEISHU_FEEDBACK_WEBHOOK_URL")),
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
	config.DBPool, err = loadDBPoolConfig()
	if err != nil {
		return Config{}, err
	}
	config.Native, err = loadNativeConfig(config.AppEnvironment)
	if err != nil {
		return Config{}, err
	}
	return config, nil
}

func loadDBPoolConfig() (DBPoolConfig, error) {
	cfg := defaultDBPoolConfig()

	if raw := strings.TrimSpace(os.Getenv("DB_POOL_MAX_CONNS")); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || v <= 0 {
			return DBPoolConfig{}, fmt.Errorf("invalid DB_POOL_MAX_CONNS")
		}
		cfg.MaxConns = int32(v)
	}
	if raw := strings.TrimSpace(os.Getenv("DB_POOL_MIN_CONNS")); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || v < 0 {
			return DBPoolConfig{}, fmt.Errorf("invalid DB_POOL_MIN_CONNS")
		}
		cfg.MinConns = int32(v)
		cfg.minConnsConfigured = true
	}
	if cfg.minConnsConfigured {
		if cfg.MinConns > cfg.MaxConns {
			return DBPoolConfig{}, fmt.Errorf("DB_POOL_MIN_CONNS (%d) cannot exceed DB_POOL_MAX_CONNS (%d)", cfg.MinConns, cfg.MaxConns)
		}
	} else if cfg.MinConns > cfg.MaxConns {
		cfg.MinConns = cfg.MaxConns
	}
	if raw := strings.TrimSpace(os.Getenv("DB_POOL_MAX_CONN_LIFETIME")); raw != "" {
		d, err := time.ParseDuration(raw)
		if err != nil || d <= 0 {
			return DBPoolConfig{}, fmt.Errorf("invalid DB_POOL_MAX_CONN_LIFETIME")
		}
		cfg.MaxConnLifetime = d
	}
	if raw := strings.TrimSpace(os.Getenv("DB_POOL_MAX_CONN_IDLE_TIME")); raw != "" {
		d, err := time.ParseDuration(raw)
		if err != nil || d <= 0 {
			return DBPoolConfig{}, fmt.Errorf("invalid DB_POOL_MAX_CONN_IDLE_TIME")
		}
		cfg.MaxConnIdleTime = d
	}
	if raw := strings.TrimSpace(os.Getenv("DB_POOL_HEALTH_CHECK_PERIOD")); raw != "" {
		d, err := time.ParseDuration(raw)
		if err != nil || d <= 0 {
			return DBPoolConfig{}, fmt.Errorf("invalid DB_POOL_HEALTH_CHECK_PERIOD")
		}
		cfg.HealthCheckPeriod = d
	}
	return cfg, nil
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

func envOrDefaultTrimmed(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func parseAdminBootstrapUsername(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return domain.DefaultBootstrapAdminUsername
	}
	return trimmed
}

func parseAdminCORSOrigins(raw string) []string {
	var origins []string
	for _, part := range strings.Split(raw, ",") {
		trimmed := strings.TrimRight(strings.TrimSpace(part), "/")
		if trimmed != "" {
			origins = append(origins, trimmed)
		}
	}
	if len(origins) == 0 {
		return []string{
			"http://localhost:5173",
			"http://127.0.0.1:5173",
			"https://oryjk.cn",
		}
	}
	return origins
}
