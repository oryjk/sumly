import Foundation
import SwiftData

/// 一条黄金持仓记录：买入克数、买入单价（元/克）与持有时点。
/// `timestamp` 是用户指定的精确时间点（补录历史时可为过去时间），
/// 后续画持仓走势 / 收益曲线时按它对齐历史行情。
@Model
final class HoldingRecord {
    @Attribute(.unique) var id: UUID
    var grams: Double
    /// 购入单价，元/克。
    var unitPriceCNY: Double
    /// 持有时间点（用户指定）。
    var timestamp: Date
    var note: String
    var createdAt: Date
    // 新字段有默认值，旧持仓通过 SwiftData 轻量迁移保留。
    var brand: String = ""
    var bookName: String = "默认账本"
    var disposition: String = "holding"
    var disposedAt: Date?
    var disposalAmount: Double = 0
    var purchaseID: UUID?
    var extraFee: Double = 0
    var purchaseChannel: String = ""
    var counterparty: String = ""

    var assetType: String = "其他"
    /// 旧记录未记纯度，以100%继续估算；新表单默认99.99%。
    var purity: Double = 1
    var laborFee: Double = 0
    var purchaseTotalOverride: Double?
    var recoveryDeduction: Double = 0
    var recoveryDiscount: Double = 0
    var recoveryFixedFee: Double = 0
    /// 黄金当前实际保管人 / 持有人（空字符串代表自己持有）。
    var holder: String = ""
    var alertsJSON: String = "[]"

    var holdingHolder: HoldingHolder? { HoldingHolder.parse(holder) }

    var totalPurchaseCost: Double { purchaseTotalOverride ?? (grams * unitPriceCNY + laborFee + extraFee) }
    var returnInput: GoldReturnInput {
        .init(grams: grams, purity: purity, unitPrice: unitPriceCNY, laborFee: laborFee, otherCost: extraFee,
              totalCostOverride: purchaseTotalOverride,
              rule: .init(perGramDeduction: recoveryDeduction, discountRate: recoveryDiscount, fixedFee: recoveryFixedFee))
    }
    static func localizedBookName(_ stored: String) -> String {
        stored == "默认账本" ? L10n.tr("默认账本") : stored
    }

    var displayName: String {
        if !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return brand }
        let type = assetType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type.isEmpty || type == "其他" { return L10n.tr("黄金记录") }
        return GoldAssetType(rawValue: type)?.displayName ?? type
    }

    init(
        grams: Double,
        unitPriceCNY: Double,
        timestamp: Date,
        note: String = "",
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.grams = grams
        self.unitPriceCNY = unitPriceCNY
        self.timestamp = timestamp
        self.note = note
        self.createdAt = createdAt
    }
}
