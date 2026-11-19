package main

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/providers"
	"github.com/gin-gonic/gin"
)

func main() {
	identity, err := providers.NewNativeSessionClient(os.Getenv("SUMLY_NATIVE_ME_URL"))
	if err != nil {
		slog.Error("configure Sumly session validation", "error", err)
		os.Exit(1)
	}
	tickets, err := providers.NewChanlunBridge(os.Getenv("CHANLUN_TICKET_URL"), os.Getenv("CHANLUN_BRIDGE_SECRET"))
	if err != nil {
		slog.Error("configure Chanlun ticket minting", "error", err)
		os.Exit(1)
	}
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()
	_ = router.SetTrustedProxies(nil)
	router.Use(gin.Recovery())
	router.GET("/health", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	authhttp.NewChanlunHandler(identity, tickets).RegisterRoutes(router.Group("/api/v1/app"))
	server := &http.Server{
		Addr:              ":18191",
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      12 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	slog.Info("starting Chanlun bridge", "address", server.Addr)
	if err := server.ListenAndServe(); err != nil {
		slog.Error("Chanlun bridge stopped", "error", err)
		os.Exit(1)
	}
}
