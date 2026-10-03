package application

import (
	"strconv"
	"time"

	holdingsdomain "gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/notifications/ports"
)

// returnInput 是评估所需的最小区间口径，与小程序端 GoldReturnInput 同构。
type returnInput struct {
	Grams             float64
	Purity            float64
	UnitPrice         float64
	LaborFee          float64
	OtherCost         float64
	TotalCostOverride *float64
	PerGramDeduction  float64
	DiscountRate      float64
	FixedFee          float64
}

// totalCost 与小程序端一致：实付总额优先，不再叠加工费与其他费用。
func (r returnInput) totalCost() float64 {
	if r.TotalCostOverride != nil {
		return *r.TotalCostOverride
	}
	return r.Grams*r.UnitPrice + r.LaborFee + r.OtherCost
}

func (r returnInput) effectiveGrams() float64 { return r.Grams * r.Purity }

// referencePrice 是保本反推：使预计到手恰等于 target 所需的参考价。
// 提醒目标与保本共用这一个反函数。
func referencePrice(r returnInput, target float64) (float64, bool) {
	if target < 0 || r.Grams <= 0 {
		return 0, false
	}
	if target == 0 {
		return 0, true
	}
	weight := r.effectiveGrams()
	if weight <= 0 || r.DiscountRate >= 1 {
		return 0, false
	}
	price := (target+r.FixedFee)/(weight*(1-r.DiscountRate)) + r.PerGramDeduction
	if price < 0 || isNaNOrInf(price) {
		return 0, false
	}
	return price, true
}

// breakEven 是成本对应的保本价。
func breakEven(r returnInput) (float64, bool) {
	return referencePrice(r, r.totalCost())
}

func isNaNOrInf(value float64) bool {
	return value != value || value > 1.7976931348623157e308 || value < -1.7976931348623157e308
}

// EvaluateOne 判定单个提醒是否穿越，并返回下一份基线。
//
// 规则与小程序端 HoldingAlertEngine 严格一致：
// - 先低于目标才 armed，再达到目标才触发；
// - 报价有效期 300 秒，接受未来 60 秒（时钟偏差）；
// - 单次跳变超过 20% 视为数据异常，不更新基线也不触发；
// - 长断档后重置基线；
// - 24 小时冷却。
func EvaluateOne(
	alert domain.Alert,
	input domain.GoldInput,
	baseline ports.Baseline,
	price float64,
	asOf time.Time,
	now time.Time,
) (bool, ports.Baseline) {
	next := baseline

	age := now.Sub(asOf)
	if age > 300*time.Second || age < -60*time.Second {
		return false, next
	}
	if price <= 0 || isNaNOrInf(price) {
		return false, next
	}

	// 长断档后重置基线，避免用陈旧基线判断穿越
	if !baseline.PreviousAsOf.IsZero() && asOf.Sub(baseline.PreviousAsOf) > 300*time.Second {
		next = ports.Baseline{LastTriggeredAt: baseline.LastTriggeredAt}
	}

	// 异常跳变
	if next.PreviousPrice > 0 {
		ratio := price/next.PreviousPrice - 1
		if ratio < 0 {
			ratio = -ratio
		}
		if ratio > 0.2 {
			return false, next
		}
	}

	r := toReturnInput(input)
	var target float64
	switch alert.Kind {
	case domain.AlertBreakEven:
		value, ok := breakEven(r)
		if !ok {
			return false, next
		}
		target = value
	case domain.AlertPrice:
		target = alert.Threshold
	case domain.AlertProfitAmount:
		value, ok := referencePrice(r, r.totalCost()+alert.Threshold)
		if !ok {
			return false, next
		}
		target = value
	case domain.AlertReturnPct:
		cost := r.totalCost()
		if cost <= 0 {
			return false, next
		}
		value, ok := referencePrice(r, cost*(1+alert.Threshold/100))
		if !ok {
			return false, next
		}
		target = value
	default:
		return false, next
	}
	if target <= 0 || isNaNOrInf(target) {
		return false, next
	}

	wasArmed := next.Armed
	next.PreviousPrice = price
	next.PreviousAsOf = asOf

	tolerance := 0.01
	if target*0.001 > tolerance {
		tolerance = target * 0.001
	}
	if price < target-tolerance {
		next.Armed = true
	}
	if !wasArmed || price < target {
		return false, next
	}

	next.Armed = false
	if next.LastTriggeredAt != nil && now.Sub(*next.LastTriggeredAt) < 24*time.Hour {
		return false, next
	}
	triggeredAt := now
	next.LastTriggeredAt = &triggeredAt
	return true, next
}

// fromHoldingsDocument 把账户云文档转为待评估配置。
// 只有持有中的记录才有目标提醒，处置记录不参与。
func fromHoldingsDocument(doc holdingsdomain.Document) domain.GuestConfiguration {
	out := make(domain.GuestConfiguration, 0, len(doc.Records))
	for _, record := range doc.Records {
		if record.Disposition != "holding" || len(record.Alerts) == 0 {
			continue
		}
		purity := record.Purity
		if purity == 0 {
			purity = 1
		}
		alerts := make([]domain.Alert, 0, len(record.Alerts))
		for _, a := range record.Alerts {
			alerts = append(alerts, domain.Alert{ID: a.ID, Kind: domain.AlertKind(a.Kind), Threshold: a.Threshold})
		}
		out = append(out, domain.ValidatedRecord{
			RecordID: record.ID,
			Input: domain.GoldInput{
				Grams:             record.Grams,
				Purity:            purity,
				UnitPrice:         record.UnitPriceCNY,
				LaborFee:          record.LaborFee,
				OtherCost:         record.ExtraFee,
				TotalCostOverride: record.PurchaseTotalOverride,
				PerGramDeduction:  record.RecoveryDeduction,
				DiscountRate:      record.RecoveryDiscount,
				FixedFee:          record.RecoveryFixedFee,
			},
			Alerts: alerts,
		})
	}
	return out
}

func toReturnInput(input domain.GoldInput) returnInput {
	purity := input.Purity
	if purity == 0 {
		purity = 1
	}
	return returnInput{
		Grams:             input.Grams,
		Purity:            purity,
		UnitPrice:         input.UnitPrice,
		LaborFee:          input.LaborFee,
		OtherCost:         input.OtherCost,
		TotalCostOverride: input.TotalCostOverride,
		PerGramDeduction:  input.PerGramDeduction,
		DiscountRate:      input.DiscountRate,
		FixedFee:          input.FixedFee,
	}
}

func formatFloat(value float64) string {
	return strconv.FormatFloat(value, 'f', -1, 64)
}
