package domain

import (
	"fmt"
	"math"
	"strings"
)

const (
	PersonalFrameworkReplyDisclaimer = "注：以上为我个人的黄金量化观察框架与公开数据复盘记录，不构成任何投资建议。"
	PersonalFrameworkLongDisclaimer  = "以上内容仅为本人基于公开宏观与市场统计数据整理的个人观察框架复盘记录，不构成任何投资建议或买卖依据。"
)

// StrategyFramework maps objective temperature level & macro regime to the
// internal personal observation framework (strictly for protected internal IP workflows).
type StrategyFramework struct {
	Signal                  string
	Level                   string
	MacroRegime             string
	Title                   string
	HistoricalPerspective   string
	ReferencePaceMultiplier float64
	ReferencePaceLabel      string
	RiskNotice              string
}

type StrategyKeyMetrics struct {
	GoldPriceUSD          *float64
	MA200DeviationPct     *float64
	DomesticPremiumPct    *float64
	TotalDebtTrillionUSD  *float64
	DebtChangeYoYTrillion *float64
	DebtToGDPPct          *float64
	FiscalStressScore     *float64
	Yield10YNominalPct    *float64
	Yield10YRealPct       *float64
	Breakeven10YPct       *float64
	CotDate               string
	CotMMNet              *float64
	CotOpenInterest       *float64
	CotMMNetRatioPct      *float64
}

type StrategyBriefInput struct {
	Snapshot            TemperatureSnapshot
	Treasury            *TreasurySummary
	LatestCot           *CotObservation
	OfficialAccountName string
}

type StrategyBrief struct {
	AsOf                 string
	ModelVersion         string
	Degraded             bool
	Score                float64
	Level                string
	LevelLabel           string
	Change1D             *float64
	Change5D             *float64
	VolatilityAlert      bool
	VolatilityNote       string
	MacroRegime          MacroRegime
	Framework            StrategyFramework
	KeyMetrics           StrategyKeyMetrics
	OfficialAccountReply string
	CommunityBrief       string
}

// MapStrategyFramework preserves the complete signal & (level x macro_regime) mapping
// into the internal personal observation framework.
func MapStrategyFramework(level, regime string, score float64, volAlert bool) StrategyFramework {
	lvl := normalizeLevel(level, score)
	reg := normalizeRegime(regime)

	var fw StrategyFramework
	fw.Level = lvl
	fw.MacroRegime = reg

	switch lvl {
	case LevelFreezing:
		switch reg {
		case RegimeHeadwind:
			fw.Signal = "accumulate"
			fw.Title = "极冷区间 × 宏观偏弱 · 冰点分批试探观察"
			fw.HistoricalPerspective = "历史回测中，五维热度跌入极冷区间往往对应情绪冰点，但长期宏观底座偏弱时右侧启动更曲折；个人框架记录为温和放大定投节奏观察（1.2x），拉长观察周期。"
			fw.ReferencePaceMultiplier = 1.2
			fw.ReferencePaceLabel = "适度加配观察 1.2x"
		case RegimeTailwind:
			fw.Signal = "strong_accumulate"
			fw.Title = "极冷区间 × 宏观偏暖 · 黄金击球区观察"
			fw.HistoricalPerspective = "历史回测中，短期情绪极度低迷而美债与央行购金等长期宏观底座偏强时，中长期风险收益比通常处于较优区间；个人框架记录为加速定投节奏观察（1.5x）。"
			fw.ReferencePaceMultiplier = 1.5
			fw.ReferencePaceLabel = "加速定投观察 1.5x"
		default:
			fw.Signal = "strong_accumulate"
			fw.Title = "极冷区间 × 宏观中性 · 情绪冰点观察"
			fw.HistoricalPerspective = "历史回测中，五维热度处于近 3 年极低分位且长期宏观维持中性时，市场筹码拥挤度低；个人框架记录为高优先级分批观察（1.5x）。"
			fw.ReferencePaceMultiplier = 1.5
			fw.ReferencePaceLabel = "加速定投观察 1.5x"
		}
	case LevelCool:
		switch reg {
		case RegimeHeadwind:
			fw.Signal = "hold_dca"
			fw.Title = "偏冷区间 × 宏观偏弱 · 常规节奏观察"
			fw.HistoricalPerspective = "历史回测中，温度偏冷具备一定估值缓冲，但在宏观逆风阶段更易反复磨底；个人框架维持基准定投节奏观察（1.0x）。"
			fw.ReferencePaceMultiplier = 1.0
			fw.ReferencePaceLabel = "标准节奏观察 1.0x"
		case RegimeTailwind:
			fw.Signal = "accumulate"
			fw.Title = "偏冷区间 × 宏观偏暖 · 顺风偏冷观察"
			fw.HistoricalPerspective = "历史回测中，交易拥挤度较低叠加长期宏观偏暖属于典型的“宏观顺风、短线偏冷”组合；个人框架记录为小幅提升定投节奏观察（1.2x）。"
			fw.ReferencePaceMultiplier = 1.2
			fw.ReferencePaceLabel = "偏冷加配观察 1.2x"
		default:
			fw.Signal = "accumulate"
			fw.Title = "偏冷区间 × 宏观中性 · 低拥挤度观察"
			fw.HistoricalPerspective = "历史回测中，情绪与持仓拥挤度仍处偏低分位、宏观底座中性；个人框架记录为略高于基准的稳步节奏观察（1.2x）。"
			fw.ReferencePaceMultiplier = 1.2
			fw.ReferencePaceLabel = "偏冷加配观察 1.2x"
		}
	case LevelNeutral:
		switch reg {
		case RegimeHeadwind:
			fw.Signal = "cautious"
			fw.Title = "中性区间 × 宏观偏弱 · 逆风收敛观察"
			fw.HistoricalPerspective = "历史回测中，温度处于中位但长期宏观偏弱时，上行弹性受制于高实际利率；个人框架记录为下调节奏至半速观察（0.5x）。"
			fw.ReferencePaceMultiplier = 0.5
			fw.ReferencePaceLabel = "逆风减半观察 0.5x"
		case RegimeTailwind:
			fw.Signal = "hold_dca"
			fw.Title = "中性区间 × 宏观偏暖 · 顺风常态观察"
			fw.HistoricalPerspective = "历史回测中，短线多空相对均衡而长期宏观偏暖时，趋势延续性较好；个人框架按基准节奏（1.0x）跟踪，减少主观择时干扰。"
			fw.ReferencePaceMultiplier = 1.0
			fw.ReferencePaceLabel = "标准节奏观察 1.0x"
		default:
			fw.Signal = "hold_dca"
			fw.Title = "中性区间 × 宏观中性 · 均衡常态观察"
			fw.HistoricalPerspective = "历史回测中，五维热度与长期宏观均处于常态区间，既不恐慌也不拥挤；个人框架维持基准节奏观察（1.0x）。"
			fw.ReferencePaceMultiplier = 1.0
			fw.ReferencePaceLabel = "标准节奏观察 1.0x"
		}
	case LevelWarm:
		switch reg {
		case RegimeHeadwind:
			fw.Signal = "pause_take_profit"
			fw.Title = "偏热区间 × 宏观偏弱 · 背离暂停观察"
			fw.HistoricalPerspective = "历史回测中，短线热度偏高但长期宏观支撑偏弱属于短长周期背离，回撤风险上升；个人框架记录为暂停新增节奏观察（0.0x），重点留意波动回落。"
			fw.ReferencePaceMultiplier = 0.0
			fw.ReferencePaceLabel = "暂停新增观察 0.0x"
		case RegimeTailwind:
			fw.Signal = "cautious"
			fw.Title = "偏热区间 × 宏观偏暖 · 顺风降速观察"
			fw.HistoricalPerspective = "历史回测中，虽然长期宏观偏暖，但短期情绪与动量已进入偏热区间；个人框架记录为将新增节奏减半（0.5x），避免情绪化追涨。"
			fw.ReferencePaceMultiplier = 0.5
			fw.ReferencePaceLabel = "偏热减半观察 0.5x"
		default:
			fw.Signal = "cautious"
			fw.Title = "偏热区间 × 宏观中性 · 升温降速观察"
			fw.HistoricalPerspective = "历史回测中，资金关注度与交投活跃度升温而宏观底座中性，短期盈亏比趋于收敛；个人框架记录为降速至半速观察（0.5x）。"
			fw.ReferencePaceMultiplier = 0.5
			fw.ReferencePaceLabel = "偏热减半观察 0.5x"
		}
	default: // LevelHot
		fw.Signal = "pause_take_profit"
		fw.ReferencePaceMultiplier = 0.0
		fw.ReferencePaceLabel = "过热暂停观察 0.0x"
		switch reg {
		case RegimeHeadwind:
			fw.Title = "极热区间 × 宏观偏弱 · 极端拥挤防回撤观察"
			fw.HistoricalPerspective = fmt.Sprintf("当前温度 %.1f° 已进入极热区间且长期宏观偏弱，历史回测中该组合出现大幅均值回归回撤的概率显著升高；个人框架记录为暂停新增观察（0.0x）。", score)
		case RegimeTailwind:
			fw.Title = "极热区间 × 宏观偏暖 · 高位拥挤暂停观察"
			fw.HistoricalPerspective = fmt.Sprintf("当前温度 %.1f° 处于极热区间，即便长期宏观偏暖，短期多头高度拥挤仍易引发剧烈震荡；个人框架记录为暂停新增观察（0.0x），等待热度自然降温。", score)
		default:
			fw.Title = "极热区间 × 宏观中性 · 交易拥挤暂停观察"
			fw.HistoricalPerspective = fmt.Sprintf("当前温度 %.1f° 处于近 3 年高位区间，短期偏离与持仓拥挤度均偏高；个人框架记录为暂停新增观察（0.0x），观察情绪消化节奏。", score)
		}
	}

	riskParts := make([]string, 0, 2)
	if volAlert {
		riskParts = append(riskParts, "当前黄金隐含波动率（GVZ）处于近 3 年 85% 以上高位，历史同期短期振幅往往显著放大，个人框架需同步拉长观察间隔并防范流动性冲击。")
	} else {
		riskParts = append(riskParts, "当前隐含波动率未处于极端分位，但仍需关注美联储利率预期、美元指数及地缘事件引发的突发波动。")
	}
	riskParts = append(riskParts, PersonalFrameworkReplyDisclaimer)
	fw.RiskNotice = strings.Join(riskParts, " ")

	return fw
}

func BuildStrategyBrief(input StrategyBriefInput) StrategyBrief {
	snap := SanitizePublicTemperatureSnapshot(input.Snapshot)
	fw := MapStrategyFramework(snap.Level, snap.MacroRegime.Regime, snap.Score, snap.VolatilityAlert)
	metrics := extractStrategyKeyMetrics(snap, input.Treasury, input.LatestCot)

	brief := StrategyBrief{
		AsOf:            snap.AsOf,
		ModelVersion:    snap.ModelVersion,
		Degraded:        snap.Degraded,
		Score:           snap.Score,
		Level:           snap.Level,
		LevelLabel:      snap.LevelLabel,
		Change1D:        snap.Change1D,
		Change5D:        snap.Change5D,
		VolatilityAlert: snap.VolatilityAlert,
		VolatilityNote:  snap.VolatilityNote,
		MacroRegime:     snap.MacroRegime,
		Framework:       fw,
		KeyMetrics:      metrics,
	}
	brief.OfficialAccountReply = renderOfficialAccountReply(brief, input.Treasury, strings.TrimSpace(input.OfficialAccountName))
	brief.CommunityBrief = renderCommunityBrief(brief, snap, input.Treasury, input.LatestCot, strings.TrimSpace(input.OfficialAccountName))
	return brief
}

func extractStrategyKeyMetrics(snap TemperatureSnapshot, treasury *TreasurySummary, cot *CotObservation) StrategyKeyMetrics {
	m := StrategyKeyMetrics{
		MA200DeviationPct:  snap.ActionGuide.MA200DeviationPct,
		DomesticPremiumPct: snap.ActionGuide.DomesticPremiumPct,
	}
	for _, dim := range snap.Dimensions {
		if dim.Key == DimTrendMomentum {
			if p, ok := dim.Metrics["gold_price_usd"]; ok && IsFinite(p) {
				v := RoundTo(p, 2)
				m.GoldPriceUSD = &v
			}
			if m.MA200DeviationPct == nil {
				if dev, ok := dim.Metrics["ma200_deviation_pct"]; ok && IsFinite(dev) {
					v := RoundTo(dev, 2)
					m.MA200DeviationPct = &v
				}
			}
		}
		if dim.Key == DimDomesticPremium && m.DomesticPremiumPct == nil {
			if prem, ok := dim.Metrics["shanghai_premium_pct"]; ok && IsFinite(prem) {
				v := RoundTo(prem, 2)
				m.DomesticPremiumPct = &v
			}
		}
	}
	if treasury != nil {
		m.TotalDebtTrillionUSD = treasury.TotalDebtTrillionUSD
		m.DebtChangeYoYTrillion = treasury.DebtChangeYoYTrillion
		m.DebtToGDPPct = treasury.DebtToGDPPct
		m.FiscalStressScore = treasury.FiscalStressScore
		m.Yield10YNominalPct = treasury.Yield10YNominalPct
		m.Yield10YRealPct = treasury.Yield10YRealPct
		m.Breakeven10YPct = treasury.Breakeven10YPct
	}
	if cot != nil && !cot.Date.IsZero() {
		m.CotDate = FormatDate(cot.Date)
		mmNet := RoundTo(cot.MMNet, 0)
		oi := RoundTo(cot.OpenInterest, 0)
		m.CotMMNet = &mmNet
		m.CotOpenInterest = &oi
		m.CotMMNetRatioPct = cot.MMNetRatioPct()
	}
	return m
}

func renderOfficialAccountReply(brief StrategyBrief, treasury *TreasurySummary, accountName string) string {
	dateLabel := brief.AsOf
	if dateLabel == "" {
		dateLabel = "数据同步中"
	}

	var b strings.Builder
	if accountName != "" {
		fmt.Fprintf(&b, "【%s｜黄金温度复盘 %s】\n", accountName, dateLabel)
	} else {
		fmt.Fprintf(&b, "【黄金温度复盘 %s】\n", dateLabel)
	}

	tempLine := fmt.Sprintf("今日温度：%.1f°（%s）", brief.Score, brief.LevelLabel)
	if brief.Change1D != nil {
		tempLine += fmt.Sprintf("，较前日 %+.1f°", *brief.Change1D)
	}
	if brief.Degraded {
		tempLine += "（部分维度降级）"
	}
	b.WriteString(tempLine + "\n")
	fmt.Fprintf(&b, "宏观底座：%s（%.1f 分）\n", brief.MacroRegime.Label, brief.MacroRegime.Score)

	macroHighlights := make([]string, 0, 3)
	if brief.KeyMetrics.TotalDebtTrillionUSD != nil {
		macroHighlights = append(macroHighlights, fmt.Sprintf("美债 %.2f 万亿美元", *brief.KeyMetrics.TotalDebtTrillionUSD))
	}
	if brief.KeyMetrics.Yield10YRealPct != nil {
		macroHighlights = append(macroHighlights, fmt.Sprintf("10Y实际利率 %.2f%%", *brief.KeyMetrics.Yield10YRealPct))
	}
	if brief.KeyMetrics.Yield10YNominalPct != nil {
		macroHighlights = append(macroHighlights, fmt.Sprintf("10Y名义利率 %.2f%%", *brief.KeyMetrics.Yield10YNominalPct))
	}
	if len(macroHighlights) > 0 {
		fmt.Fprintf(&b, "美债与利率：%s\n", strings.Join(macroHighlights, "｜"))
	} else if treasury != nil && strings.TrimSpace(treasury.GoldImpactNote) != "" {
		fmt.Fprintf(&b, "美债与利率：%s\n", strings.TrimSpace(treasury.GoldImpactNote))
	}

	fmt.Fprintf(&b, "我的观察框架：%s（参考节奏系数 %.1fx，%s）\n", brief.Framework.Title, brief.Framework.ReferencePaceMultiplier, brief.Framework.ReferencePaceLabel)
	if brief.VolatilityAlert {
		fmt.Fprintf(&b, "波动提示：%s\n", brief.VolatilityNote)
	}
	b.WriteString(PersonalFrameworkReplyDisclaimer)
	return b.String()
}

func renderCommunityBrief(brief StrategyBrief, snap TemperatureSnapshot, treasury *TreasurySummary, cot *CotObservation, accountName string) string {
	dateLabel := brief.AsOf
	if dateLabel == "" {
		dateLabel = "待同步"
	}

	var b strings.Builder
	if accountName != "" {
		fmt.Fprintf(&b, "# %s 黄金宏观与温度复盘（%s）\n\n", accountName, dateLabel)
	} else {
		fmt.Fprintf(&b, "# 黄金宏观与温度每日复盘（%s）\n\n", dateLabel)
	}

	b.WriteString("## 1. 黄金温度与宏观底座\n")
	fmt.Fprintf(&b, "- **综合温度**：`%.1f°`（%s）", brief.Score, brief.LevelLabel)
	if brief.Change1D != nil {
		fmt.Fprintf(&b, "｜1D `%+.1f°`", *brief.Change1D)
	}
	if brief.Change5D != nil {
		fmt.Fprintf(&b, "｜5D `%+.1f°`", *brief.Change5D)
	}
	if brief.Degraded {
		b.WriteString("｜*降级模式*")
	}
	b.WriteString("\n")
	fmt.Fprintf(&b, "- **长期宏观底座**：%s（`%.1f` 分）—— %s\n", brief.MacroRegime.Label, brief.MacroRegime.Score, brief.MacroRegime.Summary)
	fmt.Fprintf(&b, "- **波动率状态**：%s\n", brief.VolatilityNote)
	if brief.KeyMetrics.GoldPriceUSD != nil {
		fmt.Fprintf(&b, "- **国际金价参考**：`$%.2f/oz`", *brief.KeyMetrics.GoldPriceUSD)
		if brief.KeyMetrics.MA200DeviationPct != nil {
			fmt.Fprintf(&b, "（较 200 日均线 `%+.2f%%`）", *brief.KeyMetrics.MA200DeviationPct)
		}
		b.WriteString("\n")
	} else if brief.KeyMetrics.MA200DeviationPct != nil {
		fmt.Fprintf(&b, "- **200 日均线偏离**：`%+.2f%%`（%s）\n", *brief.KeyMetrics.MA200DeviationPct, snap.ActionGuide.MA200Note)
	}
	if brief.KeyMetrics.DomesticPremiumPct != nil {
		fmt.Fprintf(&b, "- **国内溢价状态**：`%+.2f%%`（%s）\n", *brief.KeyMetrics.DomesticPremiumPct, snap.ActionGuide.DomesticPremiumNote)
	}

	b.WriteString("\n## 2. 五维情绪分位拆解\n")
	for _, dim := range snap.Dimensions {
		weightPct := math.Round(dim.Weight * 100)
		if dim.Available {
			fmt.Fprintf(&b, "- **%s**（权重 %.0f%%）：`%.1f°`（%s）—— %s\n", dim.Name, weightPct, dim.Score, LabelForLevel(dim.Status), dim.Summary)
		} else {
			fmt.Fprintf(&b, "- **%s**（权重 %.0f%%）：暂缺样本（已自动降级）\n", dim.Name, weightPct)
		}
	}

	b.WriteString("\n## 3. 美债与 CFTC COT 关键指标\n")
	hasMacroDetail := false
	if brief.KeyMetrics.TotalDebtTrillionUSD != nil {
		hasMacroDetail = true
		line := fmt.Sprintf("- **美国国债总规模**：`%.2f 万亿美元`", *brief.KeyMetrics.TotalDebtTrillionUSD)
		if brief.KeyMetrics.DebtChangeYoYTrillion != nil {
			line += fmt.Sprintf("（同比 `%+.2f 万亿`）", *brief.KeyMetrics.DebtChangeYoYTrillion)
		}
		if brief.KeyMetrics.DebtToGDPPct != nil {
			line += fmt.Sprintf("｜债务/GDP `%.2f%%`", *brief.KeyMetrics.DebtToGDPPct)
		}
		b.WriteString(line + "\n")
	}
	if brief.KeyMetrics.Yield10YRealPct != nil || brief.KeyMetrics.Yield10YNominalPct != nil || brief.KeyMetrics.FiscalStressScore != nil {
		hasMacroDetail = true
		parts := make([]string, 0, 4)
		if brief.KeyMetrics.Yield10YRealPct != nil {
			parts = append(parts, fmt.Sprintf("10Y 实际利率 `%.2f%%`", *brief.KeyMetrics.Yield10YRealPct))
		}
		if brief.KeyMetrics.Yield10YNominalPct != nil {
			parts = append(parts, fmt.Sprintf("10Y 名义利率 `%.2f%%`", *brief.KeyMetrics.Yield10YNominalPct))
		}
		if brief.KeyMetrics.Breakeven10YPct != nil {
			parts = append(parts, fmt.Sprintf("10Y 通胀预期 `%.2f%%`", *brief.KeyMetrics.Breakeven10YPct))
		}
		if brief.KeyMetrics.FiscalStressScore != nil {
			parts = append(parts, fmt.Sprintf("财政压力指数 `%.1f`", *brief.KeyMetrics.FiscalStressScore))
		}
		fmt.Fprintf(&b, "- **美债利率与财政**：%s\n", strings.Join(parts, "｜"))
	}
	if cot != nil && !cot.Date.IsZero() {
		hasMacroDetail = true
		cotLine := fmt.Sprintf("- **CFTC 黄金 COT（%s）**：管理基金净多头 `%.0f` 手｜总持仓 `%.0f` 手", FormatDate(cot.Date), cot.MMNet, cot.OpenInterest)
		if ratio := cot.MMNetRatioPct(); ratio != nil {
			cotLine += fmt.Sprintf("｜净多头占比 `%.2f%%`", *ratio)
		}
		b.WriteString(cotLine + "\n")
	}
	if !hasMacroDetail {
		if treasury != nil && strings.TrimSpace(treasury.GoldImpactNote) != "" {
			fmt.Fprintf(&b, "- %s\n", strings.TrimSpace(treasury.GoldImpactNote))
		} else {
			b.WriteString("- 美债与 CFTC COT 数据同步中，暂未生成关键指标明细。\n")
		}
	}

	b.WriteString("\n## 4. 我的个人观察框架记录\n")
	fmt.Fprintf(&b, "- **状态信号**：`%s`｜**观察框架**：%s\n", brief.Framework.Signal, brief.Framework.Title)
	fmt.Fprintf(&b, "- **定投节奏观察系数**：`%.1fx`（%s）\n", brief.Framework.ReferencePaceMultiplier, brief.Framework.ReferencePaceLabel)
	fmt.Fprintf(&b, "- **历史回测视角**：%s\n", brief.Framework.HistoricalPerspective)
	fmt.Fprintf(&b, "- **风险与观察要点**：%s\n", brief.Framework.RiskNotice)

	fmt.Fprintf(&b, "\n> %s\n", PersonalFrameworkLongDisclaimer)
	return b.String()
}

func normalizeLevel(level string, score float64) string {
	switch level {
	case LevelFreezing, LevelCool, LevelNeutral, LevelWarm, LevelHot:
		return level
	default:
		lvl, _ := LevelForScore(score)
		return lvl
	}
}

func normalizeRegime(regime string) string {
	switch regime {
	case RegimeTailwind, RegimeNeutral, RegimeHeadwind:
		return regime
	default:
		return RegimeNeutral
	}
}
