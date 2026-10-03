package markethttp

import (
	"context"
	"errors"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	shared "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	"github.com/gin-gonic/gin"
)

type HistorySyncUseCase interface {
	Sync(context.Context, string, string) (domain.HistorySync, error)
}
type SyncHandler struct{ query HistorySyncUseCase }

func NewSyncHandler(query HistorySyncUseCase) *SyncHandler { return &SyncHandler{query: query} }
func (h *SyncHandler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.GET("/market/gold/sync", func(c *gin.Context) {
		series := c.DefaultQuery("series", "xauusd")
		cursor := c.Query("cursor")
		result, err := h.query.Sync(c.Request.Context(), series, cursor)
		if errors.Is(err, domain.ErrInvalidSyncQuery) {
			c.JSON(400, gin.H{"code": 400, "message": "invalid market sync query", "data": nil})
			return
		}
		if err != nil {
			shared.WriteError(c, err)
			return
		}
		c.Header("Cache-Control", "no-store")
		shared.WriteSuccess(c, result)
	})
}
