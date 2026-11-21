import Foundation

/// 当前黄金形态专属的场景快捷微调项（只微调对应形态的纯度、工费、渠道与回收/赎回参数，不改动用户已填克重、单价或备注）。
struct HoldingAssetSubPreset: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let assetType: GoldAssetType
    let title: String
    let subtitle: String
    let symbol: String
    let purityText: String
    let laborPerGram: Bool
    let laborText: String
    let deductionText: String
    let discountText: String
    let fixedFeeText: String
    let suggestedBrand: String?
    let suggestedChannel: String?

    /// 将当前形态专属快捷微调写入草稿，保留已填克重、裸金单价、总价模式下的实付总价与备注。
    func apply(to draft: inout HoldingDraft) {
        draft.assetType = assetType
        draft.purityText = purityText
        draft.laborPerGram = laborPerGram
        draft.laborText = laborText
        draft.deductionText = deductionText
        draft.discountText = discountText
        draft.fixedFeeText = fixedFeeText
        if let suggestedBrand {
            draft.brand = suggestedBrand
        }
        if let suggestedChannel {
            draft.channel = suggestedChannel
        }
        if draft.costMode == .unit {
            draft.syncCalculatedTotal()
        }
    }
}

/// 记录旧持仓或当前草稿中是否包含某形态默认隐藏字段的有效数据，防止编辑旧记录时丢失或无法修改。
struct HoldingAssetFormLegacyPresence: Equatable, Sendable {
    var hasLabor: Bool
    var hasBrand: Bool
    var hasPerGramDeduction: Bool
    var hasCustomPurity: Bool

    static let none = HoldingAssetFormLegacyPresence(
        hasLabor: false,
        hasBrand: false,
        hasPerGramDeduction: false,
        hasCustomPurity: false
    )

    init(
        hasLabor: Bool = false,
        hasBrand: Bool = false,
        hasPerGramDeduction: Bool = false,
        hasCustomPurity: Bool = false
    ) {
        self.hasLabor = hasLabor
        self.hasBrand = hasBrand
        self.hasPerGramDeduction = hasPerGramDeduction
        self.hasCustomPurity = hasCustomPurity
    }

    init(draft: HoldingDraft) {
        let labor = Double(draft.laborText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let deduction = Double(draft.deductionText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let purityTrimmed = draft.purityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let purity = Double(purityTrimmed) ?? 99.99

        self.hasLabor = labor.isFinite && labor > 0
        self.hasBrand = !draft.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.hasPerGramDeduction = deduction.isFinite && deduction > 0
        self.hasCustomPurity = !purityTrimmed.isEmpty && abs(purity - 99.99) > 0.001
    }

    init(record: HoldingRecord) {
        self.hasLabor = record.laborFee.isFinite && record.laborFee > 0
        self.hasBrand = !record.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.hasPerGramDeduction = record.recoveryDeduction.isFinite && record.recoveryDeduction > 0
        self.hasCustomPurity = abs(record.purity * 100 - 99.99) > 0.001
    }

    func union(_ other: HoldingAssetFormLegacyPresence) -> HoldingAssetFormLegacyPresence {
        HoldingAssetFormLegacyPresence(
            hasLabor: hasLabor || other.hasLabor,
            hasBrand: hasBrand || other.hasBrand,
            hasPerGramDeduction: hasPerGramDeduction || other.hasPerGramDeduction,
            hasCustomPurity: hasCustomPurity || other.hasCustomPurity
        )
    }
}

/// 记账页「补充细节」随所选黄金形态动态联动的纯配置模型。
struct HoldingAssetFormProfile: Equatable, Sendable {
    let assetType: GoldAssetType
    let drawerSubtitle: String
    let subPresets: [HoldingAssetSubPreset]
    let purityPresets: [String]

    // 字段可见性
    let showsPurity: Bool
    let showsLabor: Bool
    let showsOtherCost: Bool
    let showsBrand: Bool
    let showsChannel: Bool
    let showsPerGramDeduction: Bool
    let showsDiscountRate: Bool
    let showsFixedFee: Bool

    // 分区与输入框文案
    let parameterSectionTitle: String
    let laborModeTitle: String
    let laborPerGramOptionLabel: String
    let laborTotalOptionLabel: String
    let laborPerGramFieldTitle: String
    let laborTotalFieldTitle: String
    let otherCostFieldTitle: String

    let metadataSectionTitle: String
    let brandFieldTitle: String
    let brandPlaceholder: String
    let suggestedBrands: [String]
    let channelFieldTitle: String
    let channelPlaceholder: String
    let suggestedChannels: [String]

    let recoverySectionTitle: String
    let recoverySectionHint: String
    let deductionFieldTitle: String
    let discountFieldTitle: String
    let fixedFeeFieldTitle: String

    let notePlaceholder: String

    /// 合并用户最近使用标签与形态建议标签（去重并保持最近使用优先）。
    static func mergedTags(recent: [String], suggested: [String], limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in recent + suggested {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
            if result.count >= limit { break }
        }
        return result
    }

    /// 按黄金形态与旧记录/当前草稿内容生成完整的表单联动规格。
    static func profile(
        for assetType: GoldAssetType,
        draft: HoldingDraft? = nil,
        legacy: HoldingAssetFormLegacyPresence = .none
    ) -> HoldingAssetFormProfile {
        let effectiveLegacy = draft.map { legacy.union(HoldingAssetFormLegacyPresence(draft: $0)) } ?? legacy

        switch assetType {
        case .accumulation:
            return HoldingAssetFormProfile(
                assetType: .accumulation,
                drawerSubtitle: "平台渠道、赎回费率、日期、账本、备注",
                subPresets: [
                    HoldingAssetSubPreset(
                        id: "accumulation.bank",
                        assetType: .accumulation,
                        title: "银行积存金",
                        subtitle: "0工费 · 赎回0.5%",
                        symbol: "building.columns",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "0",
                        deductionText: "",
                        discountText: "0.5",
                        fixedFeeText: "",
                        suggestedBrand: nil,
                        suggestedChannel: "工商银行"
                    ),
                    HoldingAssetSubPreset(
                        id: "accumulation.alipay",
                        assetType: .accumulation,
                        title: "支付宝黄金",
                        subtitle: "0工费 · 免赎回费",
                        symbol: "creditcard",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "0",
                        deductionText: "",
                        discountText: "0",
                        fixedFeeText: "",
                        suggestedBrand: nil,
                        suggestedChannel: "支付宝"
                    )
                ],
                purityPresets: ["99.99", "99.9"],
                showsPurity: effectiveLegacy.hasCustomPurity,
                showsLabor: effectiveLegacy.hasLabor,
                showsOtherCost: true,
                showsBrand: effectiveLegacy.hasBrand,
                showsChannel: true,
                showsPerGramDeduction: effectiveLegacy.hasPerGramDeduction,
                showsDiscountRate: true,
                showsFixedFee: true,
                parameterSectionTitle: (effectiveLegacy.hasLabor || effectiveLegacy.hasCustomPurity) ? "持仓参数（含历史字段）" : "持仓费用",
                laborModeTitle: "工费方式",
                laborPerGramOptionLabel: "按克",
                laborTotalOptionLabel: "总额",
                laborPerGramFieldTitle: "工费",
                laborTotalFieldTitle: "工费总额",
                otherCostFieldTitle: "其他费用",
                metadataSectionTitle: "平台渠道与账本",
                brandFieldTitle: "品牌 / 名称",
                brandPlaceholder: "历史记录品牌（可选）",
                suggestedBrands: [],
                channelFieldTitle: "银行 / 平台",
                channelPlaceholder: "如 工商银行 / 招商银行 / 支付宝",
                suggestedChannels: ["工商银行", "招商银行", "支付宝", "建设银行", "民生银行"],
                recoverySectionTitle: "赎回费用规则",
                recoverySectionHint: "以当前参考金价为基准；留空或为 0 时按无赎回费用估算，请以对应银行或平台实际卖出规则为准。",
                deductionFieldTitle: "每克回收扣减",
                discountFieldTitle: "赎回费率",
                fixedFeeFieldTitle: "固定卖出费",
                notePlaceholder: "记录积存计划、免手续费期限等（可选）"
            )

        case .bean:
            return HoldingAssetFormProfile(
                assetType: .bean,
                drawerSubtitle: "品牌/金店、工费、纯度、回购扣减、日期、账本、备注",
                subPresets: [
                    HoldingAssetSubPreset(
                        id: "bean.shuibei",
                        assetType: .bean,
                        title: "水贝低工费金豆",
                        subtitle: "99.99% · 工费¥5/g",
                        symbol: "sparkles",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "5",
                        deductionText: "3",
                        discountText: "",
                        fixedFeeText: "",
                        suggestedBrand: "水贝",
                        suggestedChannel: nil
                    ),
                    HoldingAssetSubPreset(
                        id: "bean.brand",
                        assetType: .bean,
                        title: "品牌金豆",
                        subtitle: "99.99% · 工费¥15/g",
                        symbol: "crown",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "15",
                        deductionText: "8",
                        discountText: "",
                        fixedFeeText: "",
                        suggestedBrand: nil,
                        suggestedChannel: nil
                    )
                ],
                purityPresets: ["99.99", "99.9"],
                showsPurity: true,
                showsLabor: true,
                showsOtherCost: true,
                showsBrand: true,
                showsChannel: true,
                showsPerGramDeduction: true,
                showsDiscountRate: true,
                showsFixedFee: true,
                parameterSectionTitle: "纯度与工费",
                laborModeTitle: "工费方式",
                laborPerGramOptionLabel: "按克",
                laborTotalOptionLabel: "总额",
                laborPerGramFieldTitle: "工费",
                laborTotalFieldTitle: "工费总额",
                otherCostFieldTitle: "其他费用",
                metadataSectionTitle: "品牌渠道与账本",
                brandFieldTitle: "品牌 / 金店",
                brandPlaceholder: "品牌 / 金店（如 水贝 / 菜百 / 周大福）",
                suggestedBrands: ["水贝", "菜百", "周大福", "周生生"],
                channelFieldTitle: "购买渠道",
                channelPlaceholder: "如 线下金店 / 水贝档口 / 电商旗舰店",
                suggestedChannels: ["水贝", "线下金店", "京东自营", "天猫旗舰店"],
                recoverySectionTitle: "回购扣减规则",
                recoverySectionHint: "以当前参考金价为基准；金豆回购通常以每克扣减为主，比例折价与固定费可按需填写。",
                deductionFieldTitle: "每克回购扣减",
                discountFieldTitle: "比例折价",
                fixedFeeFieldTitle: "固定卖出费",
                notePlaceholder: "记录攒豆瓶编号、克重规格等（可选）"
            )

        case .bar:
            return HoldingAssetFormProfile(
                assetType: .bar,
                drawerSubtitle: "发行银行/品牌、加工费、纯度、回购扣减、日期、账本、备注",
                subPresets: [
                    HoldingAssetSubPreset(
                        id: "bar.bank",
                        assetType: .bar,
                        title: "银行投资金条",
                        subtitle: "99.99% · 加工¥10/g",
                        symbol: "building.columns",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "10",
                        deductionText: "3",
                        discountText: "",
                        fixedFeeText: "",
                        suggestedBrand: nil,
                        suggestedChannel: nil
                    ),
                    HoldingAssetSubPreset(
                        id: "bar.craft",
                        assetType: .bar,
                        title: "工艺金条",
                        subtitle: "99.99% · 加工¥25/g",
                        symbol: "rectangle.stack.fill",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "25",
                        deductionText: "10",
                        discountText: "",
                        fixedFeeText: "",
                        suggestedBrand: nil,
                        suggestedChannel: nil
                    )
                ],
                purityPresets: ["99.99", "99.9"],
                showsPurity: true,
                showsLabor: true,
                showsOtherCost: true,
                showsBrand: true,
                showsChannel: true,
                showsPerGramDeduction: true,
                showsDiscountRate: true,
                showsFixedFee: true,
                parameterSectionTitle: "纯度与加工费",
                laborModeTitle: "加工 / 溢价方式",
                laborPerGramOptionLabel: "按克",
                laborTotalOptionLabel: "总额",
                laborPerGramFieldTitle: "加工 / 溢价费",
                laborTotalFieldTitle: "加工 / 溢价总额",
                otherCostFieldTitle: "其他费用",
                metadataSectionTitle: "发行机构与账本",
                brandFieldTitle: "发行银行 / 品牌",
                brandPlaceholder: "发行银行 / 品牌（如 工商银行 / 建设银行 / 中钞）",
                suggestedBrands: ["工商银行", "建设银行", "中钞", "中国黄金"],
                channelFieldTitle: "购买渠道",
                channelPlaceholder: "如 手机银行 / 银行网点 / 官方旗舰店",
                suggestedChannels: ["银行网点", "手机银行", "京东自营", "线下金店"],
                recoverySectionTitle: "银行/金店回购规则",
                recoverySectionHint: "以当前参考金价为基准；请按发行银行或金店实际回购价差填写，留空则暂不计入。",
                deductionFieldTitle: "每克回购扣减",
                discountFieldTitle: "比例折价",
                fixedFeeFieldTitle: "固定卖出费",
                notePlaceholder: "记录金条编号、证书及存放位置（可选）"
            )

        case .jewelry:
            return HoldingAssetFormProfile(
                assetType: .jewelry,
                drawerSubtitle: "金饰品牌、工艺工费、纯度、回收折价、日期、账本、备注",
                subPresets: [
                    HoldingAssetSubPreset(
                        id: "jewelry.brand",
                        assetType: .jewelry,
                        title: "品牌金饰",
                        subtitle: "99.9% · 工费¥60/g",
                        symbol: "sparkles",
                        purityText: "99.9",
                        laborPerGram: true,
                        laborText: "60",
                        deductionText: "15",
                        discountText: "",
                        fixedFeeText: "",
                        suggestedBrand: nil,
                        suggestedChannel: nil
                    ),
                    HoldingAssetSubPreset(
                        id: "jewelry.shuibei",
                        assetType: .jewelry,
                        title: "水贝金饰",
                        subtitle: "99.99% · 工费¥15/g",
                        symbol: "diamond",
                        purityText: "99.99",
                        laborPerGram: true,
                        laborText: "15",
                        deductionText: "5",
                        discountText: "",
                        fixedFeeText: "",
                        suggestedBrand: "水贝",
                        suggestedChannel: nil
                    )
                ],
                purityPresets: ["99.99", "99.9", "91.6", "75"],
                showsPurity: true,
                showsLabor: true,
                showsOtherCost: true,
                showsBrand: true,
                showsChannel: true,
                showsPerGramDeduction: true,
                showsDiscountRate: true,
                showsFixedFee: true,
                parameterSectionTitle: "纯度与工艺工费",
                laborModeTitle: "工艺工费方式",
                laborPerGramOptionLabel: "按克",
                laborTotalOptionLabel: "一口价",
                laborPerGramFieldTitle: "工艺工费",
                laborTotalFieldTitle: "工艺工费（一口价）",
                otherCostFieldTitle: "其他费用",
                metadataSectionTitle: "金饰品牌与账本",
                brandFieldTitle: "金饰品牌",
                brandPlaceholder: "金饰品牌（如 周大福 / 老凤祥 / 周生生 / 水贝）",
                suggestedBrands: ["周大福", "老凤祥", "周生生", "水贝"],
                channelFieldTitle: "购买渠道",
                channelPlaceholder: "如 专柜门店 / 水贝 / 官方旗舰店",
                suggestedChannels: ["专柜门店", "水贝", "天猫旗舰店", "京东自营"],
                recoverySectionTitle: "金饰回收折价规则",
                recoverySectionHint: "以当前参考金价为基准；金饰回收常涉及每克扣减、比例折价或固定检测费，留空则暂不计入。",
                deductionFieldTitle: "每克回收扣减",
                discountFieldTitle: "比例折价",
                fixedFeeFieldTitle: "固定卖出费",
                notePlaceholder: "记录款式、一口价凭证、佩戴场景等（可选）"
            )

        case .other:
            return HoldingAssetFormProfile(
                assetType: .other,
                drawerSubtitle: "纯度、品牌、渠道、工费、回收规则、日期、账本、备注",
                subPresets: [],
                purityPresets: ["99.99", "99.9", "91.6", "75"],
                showsPurity: true,
                showsLabor: true,
                showsOtherCost: true,
                showsBrand: true,
                showsChannel: true,
                showsPerGramDeduction: true,
                showsDiscountRate: true,
                showsFixedFee: true,
                parameterSectionTitle: "纯度与费用参数",
                laborModeTitle: "工费方式",
                laborPerGramOptionLabel: "按克",
                laborTotalOptionLabel: "总额",
                laborPerGramFieldTitle: "工费",
                laborTotalFieldTitle: "工费总额",
                otherCostFieldTitle: "其他费用",
                metadataSectionTitle: "品牌渠道与账本",
                brandFieldTitle: "品牌 / 名称",
                brandPlaceholder: "品牌 / 名称（可选）",
                suggestedBrands: [],
                channelFieldTitle: "购买渠道",
                channelPlaceholder: "购买渠道（可选）",
                suggestedChannels: [],
                recoverySectionTitle: "回收规则",
                recoverySectionHint: "以当前参考金价为基准；留空或全部为 0 时，尚未计入回收费用。",
                deductionFieldTitle: "每克回收扣减",
                discountFieldTitle: "比例折价",
                fixedFeeFieldTitle: "固定卖出费",
                notePlaceholder: "备注（可选）"
            )
        }
    }
}
