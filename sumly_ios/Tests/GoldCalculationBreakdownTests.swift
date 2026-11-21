import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Sumly

@Suite("GoldCalculationBreakdown 拆解模型与格式化")
struct GoldCalculationBreakdownTests {

    @Test("亏损单笔：复现截图案例（50g 99.99% 裸金 1907.61 工费 10000 当前价 755.01）")
    func lossCaseMatchesScreenshotExample() throws {
        let input = GoldReturnInput(
            grams: 50,
            purity: 0.9999,
            unitPrice: 1907.61,
            laborFee: 10000,
            otherCost: 0
        )
        let breakdown = try #require(
            GoldCalculationBreakdown.make(inputs: [input], title: "古法金手镯", referencePrice: 755.01)
        )

        #expect(!breakdown.isSummary)
        #expect(breakdown.recordCount == 1)
        #expect(abs(breakdown.rawGoldCost - 95380.50) < 0.001)
        #expect(abs(breakdown.feesCost - 10000.00) < 0.001)
        #expect(abs(breakdown.totalCost - 105380.50) < 0.001)
        #expect(abs(breakdown.effectiveGrams - 49.995) < 0.0001)

        let proceeds = try #require(breakdown.proceeds)
        let profit = try #require(breakdown.profit)
        #expect(abs(proceeds - 37746.72495) < 0.01)
        #expect(abs(profit - (-67633.77505)) < 0.01)
        #expect(breakdown.profitState == .loss)

        // 保本价与每克摊薄
        #expect(abs(breakdown.baseUnitPrice - 1907.61) < 0.01)
        #expect(abs(breakdown.breakEvenPrice - 2107.82) < 0.01)
        #expect(abs(breakdown.breakEvenDilution - 200.21) < 0.01)
        #expect(abs((breakdown.distanceFromBreakEven ?? 0) - (-1352.81)) < 0.01)

        // 柱图纵轴严格共用比例尺，左柱包含裸金 + 工费两段
        #expect(abs(breakdown.barMaxValue - 105380.50) < 0.01)
        #expect(breakdown.costSegments.map(\.kind) == [.rawGold, .fees])

        // 99.99% 纯度损耗约 3.78 元 > 0.01，显示损耗段
        #expect(breakdown.hasVisibleLoss)
        #expect(abs((breakdown.totalLoss ?? 0) - 3.77505) < 0.01)

        // 回收规则默认全 0（UI 去噪合并为单行）
        #expect(breakdown.allDefaultRecoveryRules)
        #expect(!breakdown.someCustomRecoveryRules)

        // 规范格式化与大白话校验
        #expect(GoldCalculationFormatter.currency(breakdown.totalCost) == "¥105,380.50")
        #expect(GoldCalculationFormatter.currency(breakdown.proceeds) == "¥37,746.72")
        #expect(GoldCalculationFormatter.currency(breakdown.profit, signed: true) == "-¥67,633.78")
        #expect(GoldCalculationFormatter.unitPrice(breakdown.breakEvenPrice) == "¥2,107.82/g")
        #expect(GoldCalculationFormatter.unitPrice(breakdown.breakEvenDilution, signed: true) == "+¥200.21/g")
        #expect(breakdown.outcomeBadgeText(hidden: false) == "浮亏 -¥67,633.78")
        #expect(breakdown.breakEvenDistanceBadgeText(hidden: false) == "还需涨 ¥1,352.81/g 回本")

        let summary = breakdown.barSummaryText(hidden: false)
        #expect(summary.contains("¥105,380.50"))
        #expect(summary.contains("¥10,000.00"))
        #expect(summary.contains("¥755.01/g"))
        #expect(summary.contains("¥37,746.72"))
        #expect(summary.contains("-¥67,633.78"))
        #expect(!summary.contains("¥-"))
    }

    @Test("盈利单笔：含纯度与回收扣减/折价/固定费，验证损耗段与浮盈")
    func profitCaseWithFullRecoveryFeesAndLossSegment() throws {
        let input = GoldReturnInput(
            grams: 10,
            purity: 0.99,
            unitPrice: 700,
            laborFee: 300,
            otherCost: 50,
            rule: .init(perGramDeduction: 10, discountRate: 0.02, fixedFee: 20)
        )
        let breakdown = try #require(
            GoldCalculationBreakdown.make(inputs: [input], title: "投资金条", referencePrice: 900)
        )

        #expect(breakdown.profitState == .profit)
        #expect(abs(breakdown.rawGoldCost - 7000) < 0.001)
        #expect(abs(breakdown.feesCost - 350) < 0.001)
        #expect(abs(breakdown.totalCost - 7350) < 0.001)

        // nominal = 9000, bookValue = 8910 (purityLoss = 90)
        // recoveryUnitPrice = (900 - 10) * 0.98 = 872.20
        // proceeds = 872.20 * 9.9 - 20 = 8614.78 (recoveryLoss = 295.22, totalLoss = 385.22)
        #expect(abs((breakdown.recoveryUnitPrice ?? 0) - 872.20) < 0.001)
        #expect(abs((breakdown.proceeds ?? 0) - 8614.78) < 0.001)
        #expect(abs((breakdown.purityLoss ?? 0) - 90.00) < 0.001)
        #expect(abs((breakdown.recoveryLoss ?? 0) - 295.22) < 0.001)
        #expect(abs((breakdown.totalLoss ?? 0) - 385.22) < 0.001)
        #expect(breakdown.hasVisibleLoss)
        #expect(abs((breakdown.profit ?? 0) - 1264.78) < 0.001)

        // 右柱总额 = proceeds + totalLoss = 9000 > totalCost (7350)
        #expect(abs(breakdown.barMaxValue - 9000.0) < 0.01)
        #expect(abs(breakdown.rulerMaxPrice - 900.0) < 0.01)

        #expect(!breakdown.allDefaultRecoveryRules)
        #expect(breakdown.someCustomRecoveryRules)
        #expect(breakdown.outcomeBadgeText(hidden: false) == "浮盈 +¥1,264.78")
        #expect(breakdown.breakEvenDistanceBadgeText(hidden: false).hasPrefix("已超保本线 ¥"))

        let legendKinds = breakdown.legendEntries(hidden: false).map(\.kind)
        #expect(legendKinds == [.rawGold, .fees, .proceeds, .loss, .profitGain])
    }

    @Test("手动总价覆写：整柱显示手动总投入，不重复叠加工费")
    func manualTotalCostOverrideShowsSingleSegment() throws {
        let input = GoldReturnInput(
            grams: 20,
            purity: 0.999,
            unitPrice: 780,
            laborFee: 500,
            otherCost: 100,
            totalCostOverride: 16500
        )
        let breakdown = try #require(
            GoldCalculationBreakdown.make(inputs: [input], title: "一口价饰品", referencePrice: 800)
        )

        #expect(breakdown.isManualTotalOnly)
        #expect(breakdown.hasManualTotalCost)
        #expect(breakdown.rawGoldCost == 0)
        #expect(breakdown.feesCost == 0)
        #expect(breakdown.manualTotalCost == 16500)
        #expect(breakdown.totalCost == 16500)
        #expect(breakdown.costSegments.map(\.kind) == [.manualTotal])
        #expect(breakdown.costSegments.first?.share == 1)

        // 买入均价应为 16500 / 20 = 825，而不是被覆写的 780
        #expect(abs(breakdown.baseUnitPrice - 825.0) < 0.001)
        #expect(breakdown.baseUnitPriceLabel.contains("手动总价"))
        #expect(breakdown.barSummaryText(hidden: false).contains("手动总价"))
    }

    @Test("多笔汇总计算与单笔 scope 切换")
    func multiRecordSummaryAndScopeSwitching() throws {
        let first = GoldCalculationItem(
            id: "a",
            title: "银行金条",
            input: GoldReturnInput(grams: 10, purity: 1.0, unitPrice: 700, laborFee: 100)
        )
        let second = GoldCalculationItem(
            id: "b",
            title: "周大福手镯",
            input: GoldReturnInput(
                grams: 20,
                purity: 0.999,
                unitPrice: 750,
                laborFee: 1200,
                rule: .init(perGramDeduction: 10, discountRate: 0.01, fixedFee: 30)
            )
        )

        let summary = try #require(
            GoldCalculationBreakdown.make(items: [first, second], scope: .summary, referencePrice: 820)
        )
        let expectedAgg = try #require(
            GoldReturnCalculator.aggregate([first.input, second.input], referencePrice: 820)
        )

        #expect(summary.isSummary)
        #expect(summary.recordCount == 2)
        #expect(summary.singleInput == nil)
        #expect(abs(summary.totalGrams - 30) < 0.0001)
        #expect(abs(summary.totalCost - expectedAgg.totalCost) < 0.001)
        #expect(abs((summary.proceeds ?? 0) - (expectedAgg.proceeds ?? 0)) < 0.001)
        #expect(abs((summary.profit ?? 0) - (expectedAgg.profit ?? 0)) < 0.001)
        #expect(abs(summary.breakEvenPrice - (expectedAgg.breakEvenPrice ?? 0)) < 0.001)
        #expect(abs(summary.rawGoldCost - (10 * 700 + 20 * 750)) < 0.001)
        #expect(abs(summary.feesCost - 1300) < 0.001)
        #expect(!summary.allDefaultRecoveryRules)
        #expect(summary.someCustomRecoveryRules)

        // 切换到单笔 scope
        let singleFirst = try #require(
            GoldCalculationBreakdown.make(items: [first, second], scope: .item("a"), referencePrice: 820)
        )
        #expect(!singleFirst.isSummary)
        #expect(singleFirst.recordCount == 1)
        #expect(singleFirst.title == "银行金条")
        #expect(abs(singleFirst.totalCost - 7100) < 0.001)
        #expect(singleFirst.allDefaultRecoveryRules)
        #expect(!singleFirst.hasVisibleLoss)
    }

    @Test("隐私脱敏 hideAmounts == true 与负号/千分位格式化")
    func privacyMaskingAndCurrencyFormatting() throws {
        // 规范负号在 ¥ 前 + 千分位，绝不出现 ¥-
        #expect(GoldCalculationFormatter.currency(-67633.775, signed: true) == "-¥67,633.78")
        #expect(GoldCalculationFormatter.currency(-67633.775, signed: false) == "-¥67,633.78")
        #expect(GoldCalculationFormatter.currency(1234.5, signed: true) == "+¥1,234.50")
        #expect(GoldCalculationFormatter.currency(105380.5, signed: false) == "¥105,380.50")
        #expect(GoldCalculationFormatter.currency(-0.001, signed: true) == "¥0.00")
        #expect(GoldCalculationFormatter.currency(0, signed: true) == "¥0.00")
        #expect(GoldCalculationFormatter.currency(nil) == "—")
        #expect(GoldCalculationFormatter.currency(-67633.78, signed: true, hidden: true) == "••••")
        #expect(GoldCalculationFormatter.unitPrice(2107.82, hidden: true) == "••••")
        #expect(GoldCalculationFormatter.grams(50, hidden: true) == "••••")
        #expect(GoldCalculationFormatter.percent(-64.18, signed: true, hidden: true) == "••••")
        #expect(GoldCalculationFormatter.sharePercent(0.905, hidden: true) == "••••")

        // 隐私模式下所有展示文案不泄露任何真实数字
        let input = GoldReturnInput(grams: 50, purity: 0.9999, unitPrice: 1907.61, laborFee: 10000)
        let breakdown = try #require(
            GoldCalculationBreakdown.make(inputs: [input], title: "私密持仓", referencePrice: 755.01)
        )

        let maskedStrings = [
            breakdown.outcomeBadgeText(hidden: true),
            breakdown.barSummaryText(hidden: true),
            breakdown.breakEvenDistanceBadgeText(hidden: true),
            breakdown.breakEvenExplanationText(hidden: true)
        ] + breakdown.legendEntries(hidden: true).flatMap { [$0.amountText, $0.shareText ?? ""] }

        for text in maskedStrings {
            #expect(!text.contains("105"))
            #expect(!text.contains("67,633"))
            #expect(!text.contains("37,746"))
            #expect(!text.contains("1,907"))
            #expect(!text.contains("2,107"))
            #expect(!text.contains("755"))
            #expect(!text.contains("10,000"))
            #expect(!text.contains("200"))
        }
        #expect(breakdown.outcomeBadgeText(hidden: true) == "••••")
        #expect(breakdown.breakEvenDistanceBadgeText(hidden: true) == "••••")
        #expect(breakdown.legendEntries(hidden: true).allSatisfy { $0.amountText == "••••" && $0.shareText == nil })
        #expect(!breakdown.legendEntries(hidden: true).contains { $0.title == "浮亏" || $0.title == "浮盈" })
    }

    @Test("无参考金价（quote == nil 或无效报价）降级状态")
    func noQuoteGracefulDegradation() throws {
        let input = GoldReturnInput(grams: 50, purity: 0.9999, unitPrice: 1907.61, laborFee: 10000)

        for invalidPrice: Double? in [nil, 0, -10, .nan, .infinity] {
            let breakdown = try #require(
                GoldCalculationBreakdown.make(inputs: [input], title: "手镯", referencePrice: invalidPrice)
            )
            #expect(breakdown.referencePrice == nil)
            #expect(breakdown.proceeds == nil)
            #expect(breakdown.profit == nil)
            #expect(breakdown.profitPercent == nil)
            #expect(breakdown.totalLoss == nil)
            #expect(!breakdown.hasVisibleLoss)
            #expect(breakdown.profitState == .noQuote)

            // 无行情时仍能完整展示投入构成与真实保本金价
            #expect(abs(breakdown.totalCost - 105380.50) < 0.01)
            #expect(abs(breakdown.breakEvenPrice - 2107.82) < 0.01)
            #expect(abs(breakdown.barMaxValue - 105380.50) < 0.01)
            #expect(breakdown.costSegments.map(\.kind) == [.rawGold, .fees])
            #expect(breakdown.outcomeBadgeText(hidden: false) == "待获取金价")
            #expect(breakdown.breakEvenDistanceBadgeText(hidden: false) == "获取参考金价后显示")
            #expect(breakdown.barSummaryText(hidden: false).contains("获取参考金价后"))

            // 无行情时图例只显示投入构成，不包含预计到手/浮盈/浮亏
            #expect(breakdown.legendEntries(hidden: false).map(\.kind) == [.rawGold, .fees])
        }
    }

    @MainActor
    @Test("渲染「怎么算的？」可视化 Sheet 关键状态供目视核查")
    func renderCalculationSheetStatesForVisualReview() async throws {
        let now = Date(timeIntervalSince1970: 1_795_180_000)
        let lossRecord = HoldingRecord(grams: 50, unitPriceCNY: 1907.61, timestamp: now)
        lossRecord.brand = "古法金手镯"
        lossRecord.purity = 0.9999
        lossRecord.laborFee = 10000

        let profitRecord = HoldingRecord(grams: 10, unitPriceCNY: 700, timestamp: now)
        profitRecord.brand = "银行投资金条"
        profitRecord.purity = 0.99
        profitRecord.laborFee = 300
        profitRecord.extraFee = 50
        profitRecord.recoveryDeduction = 10
        profitRecord.recoveryDiscount = 0.02
        profitRecord.recoveryFixedFee = 20

        let lossQuote = GoldQuote(
            symbol: "AU9999", price: 3300, open: 3290, high: 3320, low: 3280,
            prevClose: 3295, usdCNY: 7.20, cnyPerGram: 755.01, asOf: .now
        )
        let profitQuote = GoldQuote(
            symbol: "AU9999", price: 3900, open: 3890, high: 3920, low: 3880,
            prevClose: 3895, usdCNY: 7.20, cnyPerGram: 900.00, asOf: .now
        )

        let fixtures: [(String, [HoldingRecord], GoldQuote?, GoldMarketBasis, Bool)] = [
            ("calc-loss", [lossRecord], lossQuote, .domestic, false),
            ("calc-profit", [profitRecord], profitQuote, .domestic, false),
            ("calc-multi", [lossRecord, profitRecord], lossQuote, .international, false),
            ("calc-hidden", [lossRecord], lossQuote, .domestic, true),
            ("calc-no-quote", [lossRecord], nil, .domestic, false)
        ]

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-calc-ui-review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, records, quote, basis, hidden) in fixtures {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 1320)
            let view = GoldCalculationSheet(records: records, quote: quote, basis: basis, hideAmounts: hidden)
                .preferredColorScheme(.dark)
                .tint(GoldTheme.gold)
            let controller = UIHostingController(rootView: view)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = directory.appendingPathComponent(name + ".png")
            let data = try #require(image.pngData())
            try data.write(to: path)
            print("CALC_RENDER_ARTIFACT: \(path.path)")
            window.isHidden = true
        }
        previous?.makeKey()
    }
}
