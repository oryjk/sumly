import Foundation

/// 宏观与黄金温度计模块的多语言兜底映射：
/// - 简体中文（`zh-Hans`）下优先原样保留服务端返回的中文内容，确保中文版 100% 原貌与既有单测兼容；
/// - 非中文语言（`en`/`es`/`fr`/`pt`/`ja`）下，基于稳定的 `seriesID`、板块 ID、维度键及枚举等级返回 `L10n.tr` / `L10n.fmt` 本地化文案，避免中英混杂。
/// - 全部端侧兜底文案严格遵守零投资建议合规红线，仅做客观宏观统计与历史分位描述。
enum MacroLocalization {
    static var isChinese: Bool {
        AppLanguage.resolvedLanguageCode == AppLanguage.zhHans.rawValue
    }

    /// 东亚计数习惯（万 = 10,000）仅适用于中文与日语；欧美语系使用千位（k）计数。
    static var usesTenThousandScale: Bool {
        let code = AppLanguage.resolvedLanguageCode
        return code == AppLanguage.zhHans.rawValue || code == AppLanguage.ja.rawValue
    }

    // MARK: - 1. 宏观板块（Section）名称与描述

    static func sectionName(id: String, fallback: String) -> String {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        switch id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "treasury_fiscal":
            return L10n.tr("美债与财政信用")
        case "opportunity_cost":
            return L10n.tr("利率与机会成本")
        case "dollar_liquidity":
            return L10n.tr("美元与流动性")
        case "inflation_growth":
            return L10n.tr("通胀与增长")
        case "official_market":
            return L10n.tr("贵金属与跨资产")
        case "risk_temperature":
            return L10n.tr("资金情绪与波动")
        default:
            return trimmed.isEmpty ? id : trimmed
        }
    }

    static func sectionDescription(id: String, fallback: String) -> String {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        switch id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "treasury_fiscal":
            return L10n.tr("美国国债规模、财政赤字、付息负担、联储资产负债表与央行购金等长期信用逻辑")
        case "opportunity_cost":
            return L10n.tr("实际收益率、名义美债收益率、期限利差与股债机会成本变化")
        case "dollar_liquidity":
            return L10n.tr("广义美元指数、人民币汇率与金融条件松紧对金价的影响")
        case "inflation_growth":
            return L10n.tr("核心 PCE、CPI 通胀粘性与制造业、就业周期")
        case "official_market":
            return L10n.tr("国际金价、人民币金价、上海金溢价、白银原油比价与金矿股指数")
        case "risk_temperature":
            return L10n.tr("黄金隐含波动率、SPDR ETF 持仓、CFTC 投机头寸、比特币与均线动量")
        default:
            return isChinese ? trimmed : ""
        }
    }

    // MARK: - 2. 宏观指标（Series）名称与客观说明

    static func indicatorName(seriesID: String, fallback: String) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmedFallback.isEmpty {
            return trimmedFallback
        }
        let normalizedID = seriesID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let mapped = localizedSeriesName(for: normalizedID) {
            return mapped
        }
        if !trimmedFallback.isEmpty && !containsCJK(trimmedFallback) {
            return trimmedFallback
        }
        return seriesID
    }

    static func indicatorPlainNote(seriesID: String, fallback: String) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmedFallback.isEmpty {
            return trimmedFallback
        }
        let normalizedID = seriesID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let mapped = localizedSeriesNote(for: normalizedID) {
            return mapped
        }
        if !trimmedFallback.isEmpty && !containsCJK(trimmedFallback) {
            return trimmedFallback
        }
        return ""
    }

    // MARK: - 3. 黄金温度五维因子名称与摘要

    static func dimensionName(_ dim: MacroTemperatureDimension) -> String {
        let trimmed = dim.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        return MacroPresentation.factorDisplayName(dim.key)
    }

    static func dimensionSummary(_ dim: MacroTemperatureDimension) -> String {
        let trimmed = dim.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        guard dim.available else {
            return L10n.tr("该维度历史样本不足或暂未同步，已自动降级并按其余维度重分配权重")
        }
        let clamped = MacroPresentation.clampedTemperatureScore(dim.score)
        let scoreText = String(format: "%.1f", clamped)
        let level = MacroTemperatureLevel(rawValue: dim.status.lowercased()) ?? MacroTemperatureLevel.from(score: clamped)
        let levelText = level.defaultLabel

        switch dim.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "trend_momentum":
            if let dev = dim.metrics["ma200_deviation_pct"] ?? dim.metrics["ma200_dev"], dev.isFinite {
                let sign = dev > 0 ? "+" : ""
                let devText = "\(sign)\(String(format: "%.1f", dev))%"
                return L10n.fmt("金价较 200 日年线偏离 %@，动量读数 %@（%@）", devText, scoreText, levelText)
            }
            return L10n.fmt("短中期价格动量读数 %@（%@）", scoreText, levelText)

        case "positioning":
            if let ratio = dim.metrics["mm_net_ratio_pct"], ratio.isFinite {
                let ratioText = "\(String(format: "%.1f", ratio))%"
                return L10n.fmt("CFTC 管理基金净多头占总持仓 %@，拥挤度 %@（%@）", ratioText, scoreText, levelText)
            }
            return L10n.fmt("期货持仓拥挤度读数 %@（%@）", scoreText, levelText)

        case "domestic_premium":
            if let prem = dim.metrics["shanghai_premium_pct"], prem.isFinite {
                let sign = prem > 0 ? "+" : ""
                let premText = "\(sign)\(String(format: "%.2f", prem))%"
                return L10n.fmt("上海金相对国际折算价溢价 %@，热度 %@（%@）", premText, scoreText, levelText)
            }
            return L10n.fmt("国内现货溢价热度 %@（%@）", scoreText, levelText)

        case "flow_cross_asset":
            return L10n.fmt("黄金 ETF 资金流与金银比扩散综合读数 %@（%@）", scoreText, levelText)

        case "macro_pulse":
            return L10n.fmt("实际利率与美元 20 日脉冲综合读数 %@（%@）", scoreText, levelText)

        default:
            return L10n.fmt("维度读数 %@（%@）", scoreText, levelText)
        }
    }

    // MARK: - 4. 温度等级、宏观背景与美债解读

    static func temperatureLevelLabel(level: MacroTemperatureLevel, fallback: String) -> String {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        return level.defaultLabel
    }

    static func macroRegimeLabel(regime: MacroRegimeKind, fallback: String) -> String {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        return regime.defaultLabel
    }

    static func macroRegimeSummary(regime: MacroRegimeKind, fallback: String) -> String {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        switch regime {
        case .tailwind:
            return L10n.tr("美债规模、财政压力与央行购金等长期宏观指标整体偏强，中长期基本面支撑较强。")
        case .neutral:
            return L10n.tr("实际利率水平与美债规模、央行购金等长期宏观指标力量相对均衡，整体处于中性背景。")
        case .headwind:
            return L10n.tr("实际利率水平相对偏高且财政与外储端驱动偏弱，中长期宏观支撑相对偏弱。")
        }
    }

    static func treasuryGoldImpactNote(for summary: MacroTreasurySummary) -> String {
        let trimmed = summary.goldImpactNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese {
            return trimmed
        }
        var parts: [String] = []
        if let debt = summary.totalDebtTrillionUSD, debt.isFinite {
            let debtText = MacroPresentation.formatTrillionUSD(debt)
            if let yoy = summary.debtChangeYoYTrillion, yoy.isFinite {
                let yoyText = MacroPresentation.formatTrillionUSD(yoy, signed: true)
                parts.append(L10n.fmt("美债总规模达 %@（同比 %@），债务持续扩张构成长期信用背景关注点", debtText, yoyText))
            } else {
                parts.append(L10n.fmt("美债总规模达 %@，债务规模处于高位", debtText))
            }
        }
        if let real = summary.yield10yRealPct, real.isFinite {
            let realText = MacroPresentation.formatPercent(real)
            if real >= 1.8 {
                parts.append(L10n.fmt("10Y 实际利率 %@ 处于偏高水平，持有无息黄金的利率成本偏高", realText))
            } else if real <= 0.8 {
                parts.append(L10n.fmt("10Y 实际利率 %@ 处于偏低水平，持有无息黄金的利率成本较低", realText))
            } else {
                parts.append(L10n.fmt("10Y 实际利率 %@ 处于温和区间", realText))
            }
        }
        if let stress = summary.fiscalStressScore, stress.isFinite {
            let stressText = String(format: "%.1f", stress)
            if stress >= 65 {
                parts.append(L10n.fmt("财政压力指数 %@ 处于偏高区间", stressText))
            } else {
                parts.append(L10n.fmt("财政压力指数 %@", stressText))
            }
        }
        if !parts.isEmpty {
            return parts.joined(separator: L10n.tr("；"))
        }
        if !trimmed.isEmpty {
            return L10n.tr("美债与利率数据正在同步中，同步完成后将自动生成宏观解读。")
        }
        return ""
    }

    static func guideLevelLabel(for item: MacroTemperatureGuideLevel) -> String {
        let trimmed = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        return item.level.defaultLabel
    }

    static func guideLevelDescription(for item: MacroTemperatureGuideLevel) -> String {
        let trimmed = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese && !trimmed.isEmpty {
            return trimmed
        }
        switch item.level {
        case .freezing:
            return L10n.tr("情绪与交易热度处于近 3 年低位，市场关注度低迷")
        case .cool:
            return L10n.tr("交易拥挤度较低，市场情绪尚未过热")
        case .neutral:
            return L10n.tr("多空力量相对均衡，市场热度处于常态")
        case .warm:
            return L10n.tr("资金关注度升温，交投活跃度偏高")
        case .hot:
            return L10n.tr("短期偏离与多头拥挤度处于高位，历史波动往往放大")
        }
    }

    // MARK: - 私有查表（覆盖全部 47 个服务端系列与常见别名）

    private static func localizedSeriesName(for normalizedID: String) -> String? {
        switch normalizedID {
        // 1. treasury_fiscal
        case "US_DEBT_DAILY":
            return L10n.tr("美国国债总规模（日频）")
        case "GFDEBTN":
            return L10n.tr("美国国债总规模（季频）")
        case "GFDEGDQ188S", "US_DEBT_GDP":
            return L10n.tr("联邦债务 / GDP")
        case "FYFSGDA188S", "US_DEFICIT_GDP":
            return L10n.tr("财政赤字 / GDP")
        case "FYOINT":
            return L10n.tr("联邦政府付息支出")
        case "FYFR":
            return L10n.tr("联邦政府财政收入")
        case "INTEREST_RATIO", "US_INTEREST_REV":
            return L10n.tr("付息支出占财政收入比")
        case "FISCAL_STRESS":
            return L10n.tr("美国财政压力指数")
        case "WALCL":
            return L10n.tr("美联储资产负债表总规模")
        case "CB_GOLD_NET", "CENTRAL_BANK_GOLD":
            return L10n.tr("全球央行净购金")
        case "USD_RESERVE_SHARE":
            return L10n.tr("美元全球外储占比")

        // 2. opportunity_cost
        case "DFII10":
            return L10n.tr("10Y TIPS 实际收益率")
        case "DFII5":
            return L10n.tr("5Y TIPS 实际收益率")
        case "DGS10":
            return L10n.tr("10年期美债名义收益率")
        case "DGS2":
            return L10n.tr("2年期美债名义收益率")
        case "TREASURY_10Y_2Y_SPREAD":
            return L10n.tr("美债 10Y-2Y 期限利差")
        case "T10YIE":
            return L10n.tr("10年盈亏平衡通胀率")
        case "FEDFUNDS":
            return L10n.tr("联邦基金有效利率")
        case "TLT":
            return L10n.tr("20+年期美国国债 ETF（TLT）")
        case "IEF":
            return L10n.tr("7-10年期美国国债 ETF（IEF）")
        case "SHV":
            return L10n.tr("短期美国国债 ETF（SHV）")
        case "SPY":
            return L10n.tr("标普500 ETF（SPY）")
        case "QQQ":
            return L10n.tr("纳斯达克100 ETF（QQQ）")

        // 3. dollar_liquidity
        case "DTWEXBGS":
            return L10n.tr("广义美元指数")
        case "DXY":
            return L10n.tr("美元指数（DXY）")
        case "DEXCHUS":
            return L10n.tr("美元兑人民币汇率")
        case "NFCI":
            return L10n.tr("芝加哥联储金融条件指数")

        // 4. inflation_growth
        case "PCE_YOY":
            return L10n.tr("核心 PCE 同比")
        case "PCEPILFE":
            return L10n.tr("核心 PCE 物价指数")
        case "CPIAUCSL":
            return L10n.tr("美国 CPI 消费者物价指数")
        case "IPMAN":
            return L10n.tr("美国制造业工业产出指数")
        case "UNRATE":
            return L10n.tr("美国失业率")

        // 5. official_market
        case "GOLDAMGBD228NLBM":
            return L10n.tr("国际黄金价格（COMEX）")
        case "GOLD_CNY":
            return L10n.tr("理论人民币金价")
        case "SHANGHAI_PREMIUM":
            return L10n.tr("上海金溢价率")
        case "SILVER":
            return L10n.tr("国际白银价格（COMEX）")
        case "GOLD_SILVER_RATIO":
            return L10n.tr("金银比（Gold/Silver）")
        case "OIL":
            return L10n.tr("WTI 原油价格")
        case "GOLD_OIL_RATIO":
            return L10n.tr("金油比（Gold/Oil）")
        case "XAU":
            return L10n.tr("费城金银矿业指数（XAU）")
        case "HUI":
            return L10n.tr("NYSE Arca 金矿指数（HUI）")

        // 6. risk_temperature
        case "GVZCLS":
            return L10n.tr("黄金隐含波动率（GVZ）")
        case "GLD", "SPDR_GOLD":
            return L10n.tr("SPDR 黄金 ETF 持仓（吨）")
        case "GLD_PRICE":
            return L10n.tr("SPDR 黄金 ETF 价格（GLD）")
        case "GOLD_COT", "CFTC_GOLD_NET":
            return L10n.tr("CFTC 黄金管理基金净多头")
        case "GOLD_MA":
            return L10n.tr("国际金价 200 日年线")
        case "BTC_USD":
            return L10n.tr("比特币价格")
        case "BTC_MCAP":
            return L10n.tr("比特币总市值")
        case "GOLD_BTC_RATIO":
            return L10n.tr("黄金/比特币比价")

        default:
            return nil
        }
    }

    private static func localizedSeriesNote(for normalizedID: String) -> String? {
        switch normalizedID {
        // 1. treasury_fiscal
        case "US_DEBT_DAILY":
            return L10n.tr("美国财政部每日公布的联邦公共债务总额，用于追踪长期债务扩张与主权信用变化。")
        case "GFDEBTN":
            return L10n.tr("FRED 季频联邦总债务，与日频美债口径统一为万亿美元，用于长周期趋势观察。")
        case "GFDEGDQ188S", "US_DEBT_GDP":
            return L10n.tr("美国联邦债务占名义 GDP 比重，反映债务体量与经济规模的相对变化。")
        case "FYFSGDA188S", "US_DEFICIT_GDP":
            return L10n.tr("美国联邦财政盈余/赤字占 GDP 比例（负值代表赤字），衡量年度财政收支缺口。")
        case "FYOINT":
            return L10n.tr("美国财政年度债务利息支出，用于衡量利率水平与债务规模叠加下的付息负担。")
        case "FYFR":
            return L10n.tr("美国联邦政府年度税收与财政总收入，用来衡量偿债与付息承载能力。")
        case "INTEREST_RATIO", "US_INTEREST_REV":
            return L10n.tr("利息支出占财政总收入的比例，用于衡量财政偿债负担与政策空间。")
        case "FISCAL_STRESS":
            return L10n.tr("综合付息占比、赤字率与债务率的非线性压力评分（0-100），分值越高代表财政压力越显著。")
        case "WALCL":
            return L10n.tr("美联储总资产规模（十亿美元），用于追踪货币扩张与缩表周期。")
        case "CB_GOLD_NET", "CENTRAL_BANK_GOLD":
            return L10n.tr("世界黄金协会统计的全球央行年度净购金量，反映官方储备多元化趋势。")
        case "USD_RESERVE_SHARE":
            return L10n.tr("IMF COFER 美元在全球已分配外汇储备中的份额，反映国际储备货币结构演变。")

        // 2. opportunity_cost
        case "DFII10":
            return L10n.tr("10 年期通胀保值国债隐含的实际利率，是衡量无息黄金持有成本的核心宏观指标。")
        case "DFII5":
            return L10n.tr("5 年期中期实际利率，对美联储货币政策路径预期更为敏感。")
        case "DGS10":
            return L10n.tr("美国 10 年期国债名义收益率，是全球金融资产定价的重要基准利率。")
        case "DGS2":
            return L10n.tr("2 年期短端美债收益率，紧密反映市场对美联储短期政策利率路径的预期。")
        case "TREASURY_10Y_2Y_SPREAD":
            return L10n.tr("10 年期与 2 年期美债收益率之差，用于观察收益率曲线倒挂与陡峭化周期。")
        case "T10YIE":
            return L10n.tr("债券市场隐含的未来 10 年平均通胀预期水平。")
        case "FEDFUNDS":
            return L10n.tr("美联储基准政策利率有效水平，反映美国货币政策松紧周期。")
        case "TLT":
            return L10n.tr("追踪 20 年以上长期美国国债价格的 ETF，反映长端利率波动方向。")
        case "IEF":
            return L10n.tr("追踪 7-10 年期中长期美国国债价格的 ETF，反映债市利率变动节奏。")
        case "SHV":
            return L10n.tr("短期美国国债类现金资产基准，用于对照无风险短端收益水平。")
        case "SPY":
            return L10n.tr("追踪标普 500 指数的美股代表 ETF，用于观察跨资产风险偏好变化。")
        case "QQQ":
            return L10n.tr("追踪纳斯达克 100 指数的美股科技代表 ETF，反映高久期权益资产情绪。")

        // 3. dollar_liquidity
        case "DTWEXBGS":
            return L10n.tr("美元兑一篮子贸易加权货币的广义汇率指数，反映美元整体强弱周期。")
        case "DXY":
            return L10n.tr("美元兑主要国际货币的汇率指数，衡量美元全球相对强弱。")
        case "DEXCHUS":
            return L10n.tr("美元兑人民币即期汇率，反映国际金价折算为人民币计价时的汇率影响。")
        case "NFCI":
            return L10n.tr("芝加哥联储金融条件指数；低于 0 表示金融环境相对宽松，高于 0 表示相对收紧。")

        // 4. inflation_growth
        case "PCE_YOY":
            return L10n.tr("剔除食品能源后的核心个人消费支出物价同比增速，是美联储核心通胀观测指标。")
        case "PCEPILFE":
            return L10n.tr("剔除食品能源后的美国个人消费支出物价绝对指数，用于计算核心 PCE 同比。")
        case "CPIAUCSL":
            return L10n.tr("美国城市居民消费物价总水平，长期衡量法币购买力变化速度。")
        case "IPMAN":
            return L10n.tr("美国制造业实体产出水平指标，用于衡量工业经济周期强弱。")
        case "UNRATE":
            return L10n.tr("美国官方月度失业率，反映劳动力市场松紧与货币政策背景。")

        // 5. official_market
        case "GOLDAMGBD228NLBM":
            return L10n.tr("以美元/盎司计价的国际黄金期货主力收盘价，是全球黄金定价基准。")
        case "GOLD_CNY":
            return L10n.tr("按国际金价与美元兑人民币汇率折算的每克理论人民币金价，用来对照国内盘面价差。")
        case "SHANGHAI_PREMIUM":
            return L10n.tr("国内金价相对国际折算价的溢价百分比，客观反映境内外现货供需价差状态。")
        case "SILVER":
            return L10n.tr("COMEX 国际白银价格，兼具贵金属与工业金属双重属性。")
        case "GOLD_SILVER_RATIO":
            return L10n.tr("1 盎司黄金可兑换的白银盎司数，用于衡量贵金属板块内部相对强弱。")
        case "OIL":
            return L10n.tr("WTI 原油期货基准价格，反映全球能源成本与通胀背景变化。")
        case "GOLD_OIL_RATIO":
            return L10n.tr("1 盎司黄金可兑换的原油桶数，用于观察跨大宗商品相对比价周期。")
        case "XAU":
            return L10n.tr("北美主流黄金白银矿企股指数，反映权益市场对贵金属矿企盈利的定价。")
        case "HUI":
            return L10n.tr("未做长期套保的纯金矿股指数，对金价趋势和市场风险偏好高度敏感。")

        // 6. risk_temperature
        case "GVZCLS":
            return L10n.tr("黄金期权市场隐含波动率指数，用于衡量黄金短期波动幅度所处历史分位。")
        case "GLD", "SPDR_GOLD":
            return L10n.tr("全球最大黄金 ETF 的实物黄金持有吨数，直接体现欧美机构资金流入流出。")
        case "GLD_PRICE":
            return L10n.tr("GLD 场内收盘价，并在 SPDR 实物持仓源异常时作为资金动量的兜底参考。")
        case "GOLD_COT", "CFTC_GOLD_NET":
            return L10n.tr("COMEX 黄金期货管理基金净多头合约数，用于衡量期货投机持仓拥挤度。")
        case "GOLD_MA":
            return L10n.tr("国际金价 200 交易日简单移动均线（年线），用于衡量中长期趋势偏离度。")
        case "BTC_USD":
            return L10n.tr("比特币美元价格，用于对照全球流动性风险偏好与替代资产走势。")
        case "BTC_MCAP":
            return L10n.tr("比特币流通总市值（十亿美元），便于与黄金总市值体量进行跨资产比较。")
        case "GOLD_BTC_RATIO":
            return L10n.tr("黄金与比特币价格比值，用于观察传统贵金属与数字资产的相对走势。")

        default:
            return nil
        }
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3000...0x303F).contains(scalar.value)
                || (0xFF00...0xFFEF).contains(scalar.value)
        }
    }
}
