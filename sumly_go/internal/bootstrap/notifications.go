package bootstrap

import (
	"context"
	"math"
	"strings"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	holdingspostgres "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/postgres"
	holdingsdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	marketdomain "gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	notificationdomain "gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	"github.com/gin-gonic/gin"
)

// quoteLoader 约束通知模块只依赖行情只读能力，不触发回源采集或写库。
type quoteLoader interface {
	LoadQuote(ctx context.Context) (marketdomain.GoldQuote, bool, error)
}

// marketQuoteReader 把国内（AU9999）与国际（XAUUSD）行情读端口适配到通知模块。
// 只读取已持久化的最新报价，不回源采集、不写库——通知不能拖动行情采集。
type marketQuoteReader struct {
	domestic      quoteLoader
	international quoteLoader
}

// Read 返回指定口径的最新有效报价（元/克）与其时间。
// 国内口径读取 AU9999（CNY/g）；国际口径读取 XAUUSD（USD/oz × 汇率换算为元/克）。
func (m marketQuoteReader) Read(ctx context.Context, basis string) (float64, time.Time, error) {
	var loader quoteLoader
	switch notificationdomain.QuoteBasis(strings.ToLower(strings.TrimSpace(basis))) {
	case notificationdomain.BasisDomestic:
		loader = m.domestic
	case notificationdomain.BasisInternational:
		loader = m.international
	default:
		return 0, time.Time{}, notificationdomain.ErrInvalid
	}
	if loader == nil {
		return 0, time.Time{}, notificationdomain.ErrUnavailable
	}
	quote, found, err := loader.LoadQuote(ctx)
	if err != nil {
		return 0, time.Time{}, err
	}
	if !found {
		return 0, time.Time{}, notificationdomain.ErrUnavailable
	}
	price := quote.CNYPerGram()
	if price <= 0 || math.IsNaN(price) || math.IsInf(price, 0) {
		return 0, time.Time{}, notificationdomain.ErrUnavailable
	}
	return price, quote.AsOf, nil
}

// holdingsReader 让通知模块重读账户已保存的持仓配置。
// 评估前必须重读，不能信任客户端提交的阈值。
type holdingsReader struct {
	repository *holdingspostgres.Repository
}

// Read 返回账户的持仓文档。
func (h holdingsReader) Read(ctx context.Context, userID int64) (holdingsdomain.Document, error) {
	snapshot, err := h.repository.Get(ctx, userID)
	if err != nil {
		return holdingsdomain.EmptyDocument(), err
	}
	return snapshot.Document, nil
}

type userTokenParser interface {
	Parse(ctx context.Context, rawToken string) (sharedauth.Actor, error)
}

// notificationActorUserID 提取已认证用户 ID：优先读 gin context 中的 actor，
// 未经必选鉴权中间件时尝试解析可选 Bearer JWT；访客模式或未登录/无效令牌一律返回 0。
func notificationActorUserID(tokens userTokenParser, activeUsers authhttp.ActiveUserChecker) func(*gin.Context) int64 {
	return func(c *gin.Context) int64 {
		if c == nil || c.Query("workspace") == "guest" {
			return 0
		}
		actor, ok := authhttp.ActorFromContext(c)
		if !ok {
			if tokens == nil {
				return 0
			}
			rawToken, hasBearer := parseBearerHeader(c.GetHeader("Authorization"))
			if !hasBearer {
				return 0
			}
			parsed, err := tokens.Parse(c.Request.Context(), rawToken)
			if err != nil {
				return 0
			}
			actor = parsed
		}
		if !actor.IsUser() || actor.ID <= 0 {
			return 0
		}
		if activeUsers != nil && activeUsers.EnsureActive(c.Request.Context(), actor.ID) != nil {
			return 0
		}
		return actor.ID
	}
}

func parseBearerHeader(header string) (string, bool) {
	prefix, token, ok := strings.Cut(strings.TrimSpace(header), " ")
	if !ok || !strings.EqualFold(prefix, "Bearer") || strings.TrimSpace(token) == "" {
		return "", false
	}
	return strings.TrimSpace(token), true
}
