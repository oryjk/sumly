package authhttp

import (
	"context"
	"net/http"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

type ChanlunHandler struct{ sessions application.ChanlunSessions }

func NewChanlunHandler(identity application.ChanlunIdentity, tickets ports.ChanlunTicketIssuer) *ChanlunHandler {
	return &ChanlunHandler{sessions: application.ChanlunSessions{Identity: identity, Tickets: tickets}}
}

func (h *ChanlunHandler) RegisterRoutes(group *gin.RouterGroup) {
	group.POST("/auth/chanlun/session", h.issue)
}

func (h *ChanlunHandler) issue(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	token, ok := bearerToken(c.GetHeader("Authorization"))
	if !ok {
		nativeError(c, domain.ErrCredentials)
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()
	code, err := h.sessions.Issue(ctx, token)
	if err != nil {
		nativeError(c, err)
		return
	}
	c.JSON(http.StatusOK, sharedhttp.Success(gin.H{"code": code}))
}
