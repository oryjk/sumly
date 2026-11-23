package bootstrap

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	appconfighttp "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/adapters/http"
	appconfigpassword "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/adapters/password"
	appconfigpostgres "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/adapters/postgres"
	appconfigapplication "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	authpostgres "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/wechat"
	authapplication "gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	feedbackfeishu "gitee.com/oryjk/sumly/sumly_go/internal/feedback/adapters/feishu"
	feedbackhttp "gitee.com/oryjk/sumly/sumly_go/internal/feedback/adapters/http"
	feedbackminio "gitee.com/oryjk/sumly/sumly_go/internal/feedback/adapters/minio"
	feedbackpostgres "gitee.com/oryjk/sumly/sumly_go/internal/feedback/adapters/postgres"
	feedbackapplication "gitee.com/oryjk/sumly/sumly_go/internal/feedback/application"
	holdingshttp "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/http"
	holdingspostgres "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/postgres"
	holdingsapplication "gitee.com/oryjk/sumly/sumly_go/internal/holdings/application"
	macrobitcoin "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/bitcoin"
	macrocftc "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/cftc"
	macrofred "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/fred"
	macrohttp "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/http"
	macroimf "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/imf"
	macropostgres "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/postgres"
	macroseedcsv "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/seedcsv"
	macrospdr "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/spdr"
	macrotreasury "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/treasury"
	macroyahoo "gitee.com/oryjk/sumly/sumly_go/internal/macro/adapters/yahoo"
	macroapplication "gitee.com/oryjk/sumly/sumly_go/internal/macro/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/feed"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/historical"
	markethttp "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/jijinhao"
	marketpostgres "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/sge"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/sina"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/yahoo"
	marketapplication "gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	notificationhttp "gitee.com/oryjk/sumly/sumly_go/internal/notifications/adapters/http"
	notificationpostgres "gitee.com/oryjk/sumly/sumly_go/internal/notifications/adapters/postgres"
	notificationwechat "gitee.com/oryjk/sumly/sumly_go/internal/notifications/adapters/wechat"
	notificationapp "gitee.com/oryjk/sumly/sumly_go/internal/notifications/application"
	userhttp "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/http"
	userpostgres "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/postgres"
	userapplication "gitee.com/oryjk/sumly/sumly_go/internal/user/application"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	jwtTTL         = 24 * time.Hour
	wechatEndpoint = "https://api.weixin.qq.com/sns/jscode2session"
)

type Dependencies struct {
	Holdings        *holdingshttp.Handler
	NativeAuth      *authhttp.NativeHandler
	TrustedProxies  []string
	GoldInstruments *markethttp.InstrumentsHandler
	AuthMiddleware  *authhttp.Middleware
	UserAuth        *authhttp.Handler
	AppUsers        *userhttp.AppHandler
	ActiveUsers     authhttp.ActiveUserChecker
	GoldMarket      *markethttp.Handler
	GoldSync        *markethttp.SyncHandler
	GoldHistory     *markethttp.HistoryHandler
	Notifications   *notificationhttp.Handler
	Macro           *macrohttp.Handler
	AppConfig       *appconfighttp.Handler
	Feedback        *feedbackhttp.Handler
	AdminStaticDir  string
}

func BuildDependencies(ctx context.Context, config Config) (Dependencies, func(), error) {
	pool, err := pgxpool.New(ctx, config.DatabaseURL)
	if err != nil {
		return Dependencies{}, nil, fmt.Errorf("open PostgreSQL pool: %w", err)
	}
	closePool := func() { pool.Close() }
	if err := pool.Ping(ctx); err != nil {
		closePool()
		return Dependencies{}, nil, fmt.Errorf("ping PostgreSQL: %w", err)
	}

	tokens, err := jwt.NewService(config.JWTSecret, jwtTTL)
	if err != nil {
		closePool()
		return Dependencies{}, nil, fmt.Errorf("create JWT service: %w", err)
	}
	nativeHandler, authMiddleware, err := buildNative(config, pool, tokens)
	if err != nil {
		closePool()
		return Dependencies{}, nil, err
	}

	userRepository := userpostgres.NewRepository(pool)
	appUserService := userapplication.NewAppService(userRepository)
	appUserHandler := userhttp.NewAppHandler(appUserService)
	wechatClient := wechat.NewClient(&http.Client{Timeout: 10 * time.Second}, wechatEndpoint, config.WechatAppID, config.WechatAppSecret)
	wechatLogin := authapplication.NewWechatLogin(wechatClient, userRepository, tokens)
	var devLogin authhttp.DevLoginUseCase
	if config.DevLoginEnabled {
		// 纵深防御：dev 登录允许任意 identifier 直接换取 JWT，启用必须在日志中可见。
		slog.Warn("dev login endpoint is enabled (DEV_LOGIN_ENABLED=true); never enable in production")
		login := authapplication.NewDevLogin(userRepository, tokens)
		devLogin = login
	}
	userAuthHandler := authhttp.NewHandler(wechatLogin, devLogin)

	sinaClient := sina.NewClient(&http.Client{Timeout: 10 * time.Second})
	goldReader := marketpostgres.NewReader(pool)
	goldQuery := marketapplication.NewGoldQuery(goldReader)
	goldWriter := marketpostgres.NewWriter(pool)
	goldCollector := marketapplication.NewGoldCollector(sinaClient, goldWriter)
	goldMarketHandler := markethttp.NewHandler(goldQuery)

	annual, err := historical.AnnualGold()
	if err != nil {
		closePool()
		return Dependencies{}, nil, err
	}
	if err := goldWriter.SeedAnnual(ctx, annual); err != nil {
		closePool()
		return Dependencies{}, nil, fmt.Errorf("seed annual history: %w", err)
	}
	historyHandler := markethttp.NewHistoryHandler(marketapplication.NewStoredGoldHistory(goldQuery, goldReader))

	domesticQuote := sina.NewInstrumentClient(sinaClient, "gds_AU9999", "AU9999", "CNY")
	londonSource := sina.NewInstrumentClient(sinaClient, "hf_XAU", "XAUUSD", "USD")
	domesticSource := feed.Source{
		Quote:    domesticQuote,
		Daily:    &sge.Client{HTTP: &http.Client{Timeout: 20 * time.Second}},
		Intraday: jijinhao.NewClient(&http.Client{Timeout: 10 * time.Second}, "JO_71"),
	}
	comexSource := &yahoo.Client{HTTP: &http.Client{Timeout: 10 * time.Second}, Symbol: "GCZ26.CMX", FX: londonSource}
	markets := []marketapplication.InstrumentMarket{
		{Instrument: domain.Instrument{ID: "comex-gold", Name: "纽约黄金期货", Symbol: "GCZ26.CMX", Kind: "future", Currency: "USD", Unit: "USD/troy_oz", QuoteSource: "yahoo", DailySource: "yahoo", Exchange: "COMEX", Contract: "GCZ26", DelaySeconds: 1800}, Service: marketapplication.NewNativeGoldQuery(marketpostgres.NewNativeReader(pool, "GCZ26.CMX"))},
		{Instrument: domain.Instrument{ID: "au9999", Name: "国内黄金", Symbol: "AU9999", Kind: "spot", Currency: "CNY", Unit: "CNY/g", QuoteSource: "sina", DailySource: "sge", Exchange: "SGE"}, Service: marketapplication.NewNativeGoldQuery(marketpostgres.NewNativeReader(pool, "AU9999"))},
		{Instrument: domain.Instrument{ID: "xauusd", Name: "伦敦现货黄金", Symbol: "XAUUSD", Kind: "spot", Currency: "USD", Unit: "USD/troy_oz", QuoteSource: "sina", DailySource: "sina"}, Service: marketapplication.NewNativeGoldQuery(marketpostgres.NewNativeReader(pool, "XAUUSD"))},
	}
	instruments := marketapplication.NewInstruments(markets)
	instrumentsHandler := markethttp.NewInstrumentsHandler(instruments)
	collectors := []*marketapplication.GoldCollector{
		goldCollector,
		marketapplication.NewNativeGoldCollector(comexSource, marketpostgres.NewNativeWriter(pool, "GCZ26.CMX")),
		marketapplication.NewNativeGoldCollector(domesticSource, marketpostgres.NewNativeWriter(pool, "AU9999")),
		marketapplication.NewNativeGoldCollector(londonSource, marketpostgres.NewNativeWriter(pool, "XAUUSD")),
	}

	samplerCtx, stopSampler := context.WithCancel(ctx)
	var workers sync.WaitGroup
	if config.Native.Enabled {
		workers.Add(1)
		go func() {
			defer workers.Done()
			ticker := time.NewTicker(time.Hour)
			defer ticker.Stop()
			for {
				select {
				case <-samplerCtx.Done():
					return
				case <-ticker.C:
					cleanupCtx, cancel := context.WithTimeout(samplerCtx, 30*time.Second)
					if err := authpostgres.NewNativeStore(pool).Cleanup(cleanupCtx); err != nil {
						slog.Warn("native auth cleanup failed")
					}
					cancel()
				}
			}
		}()
	}

	for _, collector := range collectors {
		workers.Add(3)
		go func() { defer workers.Done(); collector.CollectRealtime(samplerCtx) }()
		go func() { defer workers.Done(); collector.CollectDaily(samplerCtx) }()
		go func() { defer workers.Done(); collector.CollectIntraday(samplerCtx) }()
	}

	macroReader := macropostgres.NewReader(pool)
	macroWriter := macropostgres.NewWriter(pool)
	macroQuery := macroapplication.NewMacroQuery(macroReader)
	macroHandler := macrohttp.NewHandlerWithOptions(macroQuery, macrohttp.HandlerOptions{
		OfficialAccountName: config.MacroOfficialAccountName,
		OfficialAccountNote: config.MacroOfficialAccountNote,
		InternalToken:       config.MacroInternalToken,
	})
	if config.MacroSyncEnabled {
		seedCSV := macroseedcsv.New()
		macroSyncer := macroapplication.NewMacroSyncer(macroReader, macroWriter, macroapplication.SyncSources{
			Treasury: macrotreasury.New(nil),
			FRED:     macrofred.New(nil, config.FREDAPIKey),
			Yahoo:    macroyahoo.New(nil),
			SPDR:     macrospdr.New(nil),
			CFTC:     macrocftc.New(nil),
			Bitcoin:  macrobitcoin.New(nil),
			IMF:      macroimf.New(nil, seedCSV),
			SeedCSV:  seedCSV,
		})
		workers.Add(1)
		go func() {
			defer workers.Done()
			macroSyncer.RunScheduler(samplerCtx, 6*time.Hour)
		}()
	}

	closeAll := func() { stopSampler(); workers.Wait(); closePool() }

	// 持仓提醒订阅消息：模板 ID 与字段全部来自配置，缺失时能力检测报不可用，
	// 不会用假模板顶替。路由仍注册，让前端能明确知道「不可用」而非静默失败。
	notificationCredentials, err := credentials.New(config.JWTSecret)
	if err != nil {
		closeAll()
		return Dependencies{}, nil, fmt.Errorf("create notification credentials: %w", err)
	}
	notificationHandler := notificationhttp.NewHandler(notificationapp.HoldingAlerts{
		Store:  notificationpostgres.NewStore(pool),
		Quotes: marketQuoteReader{reader: goldReader},
		Holdings: holdingsReader{
			repository: holdingspostgres.NewRepository(pool),
		},
		Wechat: notificationwechat.New(nil, config.WechatAppID, config.WechatAppSecret),
		Crypto: notificationCredentials,
		Template: notificationapp.TemplateConfig{
			TemplateID: config.HoldingNotificationTemplateID,
			Fields: map[string]string{
				"price":     config.HoldingNotificationFieldPrice,
				"kind":      config.HoldingNotificationFieldKind,
				"threshold": config.HoldingNotificationFieldTarget,
			},
		},
	})

	adminAuthService := appconfigapplication.NewAdminAuthService(
		appconfigpostgres.NewAdminAuthRepository(pool),
		appconfigpassword.NewBcryptHasher(),
		config.AdminAPIToken,
	)
	if config.AdminBootstrapPassword != "" {
		if err := adminAuthService.EnsureBootstrapAdmin(ctx, config.AdminBootstrapUsername, config.AdminBootstrapPassword); err != nil {
			closeAll()
			return Dependencies{}, nil, fmt.Errorf("ensure bootstrap admin: %w", err)
		}
	}

	appConfigHandler := appconfighttp.NewHandler(
		appconfigapplication.NewService(appconfigpostgres.NewRepository(pool)),
		appconfighttp.HandlerOptions{
			AdminAuth:   adminAuthService,
			AdminToken:  config.AdminAPIToken,
			CORSOrigins: config.AdminCORSOrigins,
		},
	)

	feedbackStorage := feedbackminio.NewClient(feedbackminio.Config{
		Endpoint:  config.FeedbackMinIOEndpoint,
		AccessKey: config.FeedbackMinIOAccessKey,
		SecretKey: config.FeedbackMinIOSecretKey,
		Bucket:    config.FeedbackMinIOBucket,
		Region:    config.FeedbackMinIORegion,
	})
	feedbackNotifier := feedbackfeishu.NewNotifier(config.FeishuFeedbackWebhookURL, nil)
	feedbackService := feedbackapplication.NewService(
		feedbackpostgres.NewRepository(pool),
		feedbackStorage,
		feedbackNotifier,
		feedbackapplication.ServiceOptions{
			MinIOPublicURLPrefix: config.FeedbackMinIOPublicURLPrefix,
			PublicBaseURL:        config.FeedbackPublicBaseURL,
		},
	)
	feedbackHandler := feedbackhttp.NewHandler(feedbackService, feedbackhttp.HandlerOptions{
		Tokens: &authMiddleware,
	})

	return Dependencies{
		Holdings:        holdingshttp.NewHandler(holdingsapplication.NewService(holdingspostgres.NewRepository(pool))),
		NativeAuth:      nativeHandler,
		TrustedProxies:  config.Native.TrustedProxies,
		GoldInstruments: instrumentsHandler,
		AuthMiddleware:  &authMiddleware,
		UserAuth:        userAuthHandler,
		AppUsers:        appUserHandler,
		ActiveUsers:     appUserService,
		GoldMarket:      goldMarketHandler,
		GoldSync:        markethttp.NewSyncHandler(marketapplication.NewHistorySync(goldReader, instruments.Catalog())),
		GoldHistory:     historyHandler,
		Notifications:   notificationHandler,
		Macro:           macroHandler,
		AppConfig:       appConfigHandler,
		Feedback:        feedbackHandler,
		AdminStaticDir:  config.AdminStaticDir,
	}, closeAll, nil
}
