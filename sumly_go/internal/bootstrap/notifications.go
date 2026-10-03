package bootstrap

import (
	"context"
	"time"

	holdingspostgres "gitee.com/oryjk/sumly/sumly_go/internal/holdings/adapters/postgres"
	holdingsdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	marketpostgres "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	marketdomain "gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	notificationdomain "gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
)

// marketQuoteReader 把行情读端口适配到通知模块。
// 只读取已持久化的最新报价，不回源采集、不写库——通知不能拖动行情采集。
type marketQuoteReader struct {
	reader *marketpostgres.Reader
}

// Read 返回指定口径的最新有效报价与其时间。
// 国际口径按 USD/oz × 汇率换算为元/克；国内直接是元/克。
func (m marketQuoteReader) Read(ctx context.Context, basis string) (float64, time.Time, error) {
	quote, found, err := m.reader.LoadQuote(ctx)
	if err != nil {
		return 0, time.Time{}, err
	}
	if !found {
		return 0, time.Time{}, notificationdomain.ErrUnavailable
	}
	// 国内口径直接用元/克；国际口径按汇率折算（与行情服务同口径）
	price := quote.CNYPerGram()
	if basis != "domestic" {
		price = (quote.Price * quote.USDCNY) / marketdomain.GramsPerTroyOunce
	}
	if price <= 0 {
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
