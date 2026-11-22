package bootstrap

import (
	"net/http"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
)

func localDevelopmentCORS() gin.HandlerFunc {
	return func(c *gin.Context) {
		// /api/v1/admin/* 由管理后台专属 CORS 中间件统一处理（含 ADMIN_CORS_ORIGINS 与 X-Admin-Token）。
		if c.Request.URL.Path == "/api/v1/admin" || strings.HasPrefix(c.Request.URL.Path, "/api/v1/admin/") {
			c.Next()
			return
		}
		origin := c.GetHeader("Origin")
		if isLocalDevelopmentOrigin(origin) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Methods", "GET,POST,PATCH,PUT,DELETE,OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Authorization,Content-Type")
			c.Header("Access-Control-Allow-Credentials", "true")
			c.Header("Vary", "Origin")
		}

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func isLocalDevelopmentOrigin(origin string) bool {
	origin = strings.TrimSpace(origin)
	if origin == "" {
		return false
	}
	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme != "http" {
		return false
	}
	if parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
		return false
	}
	return parsed.Hostname() == "localhost" || parsed.Hostname() == "127.0.0.1"
}
