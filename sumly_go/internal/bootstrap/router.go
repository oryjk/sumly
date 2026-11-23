package bootstrap

import (
	"net/http"

	appconfighttp "gitee.com/oryjk/sumly/sumly_go/internal/appconfig/adapters/http"
	feedbackhttp "gitee.com/oryjk/sumly/sumly_go/internal/feedback/adapters/http"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

func NewRouter(dependencies Dependencies) *gin.Engine {
	router := gin.New()
	if err := router.SetTrustedProxies(dependencies.TrustedProxies); err != nil {
		panic("invalid trusted proxy configuration")
	}
	router.Use(gin.Logger(), gin.Recovery())
	router.Use(localDevelopmentCORS())
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, sharedhttp.Success(gin.H{"status": "ok"}))
	})
	registerOpenAPI(router)

	v1 := router.Group("/api/v1")
	app := v1.Group("/app")
	if dependencies.NativeAuth != nil {
		dependencies.NativeAuth.RegisterRoutes(app)
	}
	if dependencies.UserAuth != nil {
		dependencies.UserAuth.RegisterPublicRoutes(app)
	}
	if dependencies.GoldInstruments != nil {
		dependencies.GoldInstruments.RegisterPublicRoutes(app)
	}
	if dependencies.GoldSync != nil {
		dependencies.GoldSync.RegisterPublicRoutes(app)
	}
	if dependencies.GoldHistory != nil {
		dependencies.GoldHistory.RegisterPublicRoutes(app)
	}
	if dependencies.GoldMarket != nil {
		dependencies.GoldMarket.RegisterPublicRoutes(app)
	}
	if dependencies.Macro != nil {
		dependencies.Macro.RegisterPublicRoutes(app)
		dependencies.Macro.RegisterInternalRoutes(v1.Group("/internal"))
	}
	admin := v1.Group("/admin")
	if dependencies.AppConfig != nil {
		dependencies.AppConfig.RegisterPublicRoutes(app)
		dependencies.AppConfig.RegisterAdminRoutes(admin)
	}
	if dependencies.Feedback != nil {
		dependencies.Feedback.RegisterAppRoutes(app)
		var adminCfg feedbackhttp.AdminRouteConfig
		if dependencies.AppConfig != nil {
			adminCfg = feedbackhttp.AdminRouteConfig{
				AuthMiddleware:         dependencies.AppConfig.AdminAuthMiddleware(),
				RequirePasswordChanged: dependencies.AppConfig.RequirePasswordChangedMiddleware(),
				OperatorFromContext:    appconfighttp.AdminUsernameFromContext,
			}
		}
		dependencies.Feedback.RegisterAdminRoutes(admin, adminCfg)
	}
	if dependencies.Notifications != nil {
		dependencies.Notifications.RegisterRoutes(app)
	}
	if dependencies.AuthMiddleware != nil {
		userRoutes := app.Group("")
		userRoutes.Use(dependencies.AuthMiddleware.RequireUser())
		if dependencies.ActiveUsers != nil {
			userRoutes.Use(dependencies.AuthMiddleware.RequireActiveUser(dependencies.ActiveUsers))
		}
		if dependencies.Holdings != nil {
			dependencies.Holdings.RegisterAppRoutes(userRoutes)
		}
		if dependencies.AppUsers != nil {
			dependencies.AppUsers.RegisterAppRoutes(userRoutes)
		}
	}
	if dependencies.AdminStaticDir != "" {
		appconfighttp.RegisterStaticRoutes(router, dependencies.AdminStaticDir)
	}
	return router
}
