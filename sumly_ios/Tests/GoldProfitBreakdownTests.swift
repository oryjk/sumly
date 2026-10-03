import Foundation
import Testing
@testable import Sumly

@Test func offsettingRecordEffectsRemainAvailableForInspection() throws {
    let inputs = [GoldReturnInput(grams: 1, unitPrice: 800, laborFee: 10),
                  GoldReturnInput(grams: 1, unitPrice: 1000)]
    let breakdown = try #require(GoldProfitBreakdown.estimate(inputs, referencePrice: 900))
    #expect(breakdown.components.contains { $0.kind == .price && $0.cents == 0 })
    #expect(breakdown.profitCents == -1000)
    let price = try #require(breakdown.components.first { $0.kind == .price })
    #expect(price.contributions.map(\.recordIndex) == [0, 1])
    #expect(price.contributions.map(\.cents) == [10000, -10000])
}

@Test func recordContributionsReconcileEverySourceAcrossFractionalPortfolios() throws {
    let inputs = (0..<40).map { index in
        GoldReturnInput(grams: 1.2345 + Double(index) / 1000, purity: 0.9999,
            unitPrice: 812.34 + Double(index), laborFee: 12.345, otherCost: 0.005,
            rule: .init(perGramDeduction: 7.23, discountRate: 0.0123, fixedFee: 1.235))
    }
    let breakdown = try #require(GoldProfitBreakdown.estimate(inputs, referencePrice: 923.456))
    for component in breakdown.components {
        #expect(component.contributions.map(\.recordIndex) == Array(inputs.indices))
        #expect(component.contributions.reduce(Decimal(0)) { $0 + Decimal($1.cents) } == Decimal(component.cents))
    }
    #expect(breakdown.components.reduce(Decimal(0)) { $0 + Decimal($1.cents) } == Decimal(breakdown.profitCents))
}

@Test func manualCostContributionsStayAttachedToTheirOwnRecords() throws {
    let inputs = [GoldReturnInput(grams: 1, unitPrice: 800, laborFee: 10),
                  GoldReturnInput(grams: 1, unitPrice: 100, laborFee: 20, otherCost: 30, totalCostOverride: 950)]
    let breakdown = try #require(GoldProfitBreakdown.estimate(inputs, referencePrice: 900))
    for component in breakdown.components {
        #expect(component.contributions.map(\.recordIndex) == (component.kind == .unitemized ? [1] : [0]))
    }
    #expect(breakdown.amount(for: .unitemized) == -50)
    #expect(breakdown.amount(for: .labor) == -10)
}

@Test func recordContributionsRespectRecoveryFloorsAndActualSale() throws {
    let input = GoldReturnInput(grams: 1, unitPrice: 800,
        rule: .init(perGramDeduction: 5, discountRate: 0.2, fixedFee: 10000))
    let breakdown = try #require(GoldProfitBreakdown.estimate([input, input], referencePrice: 900))
    let fixed = try #require(breakdown.components.first { $0.kind == .fixed })
    #expect(fixed.contributions.map(\.cents) == [-71600, -71600])
    let sale = try #require(GoldProfitBreakdown.sale(totalCost: 8120, proceeds: 9000))
    #expect(sale.components[0].contributions.map(\.recordIndex) == [0])
    #expect(sale.components[0].contributions.map(\.cents) == [88000])
    let even = try #require(GoldProfitBreakdown.estimate([.init(grams: 1, unitPrice: 900)], referencePrice: 900))
    #expect(even.components[0].contributions.map(\.cents) == [0])
}

@Test func itemizedProfitShowsPricePurityAndEveryFee() throws {
    let input = GoldReturnInput(grams: 10, purity: 0.99, unitPrice: 800, laborFee: 100, otherCost: 20,
        rule: .init(perGramDeduction: 10, discountRate: 0.02, fixedFee: 20))
    let breakdown = try #require(GoldProfitBreakdown.estimate([input], referencePrice: 900))
    #expect(breakdown.amount(for: .price) == 1000)
    #expect(breakdown.amount(for: .purity) == -90)
    #expect(breakdown.amount(for: .labor) == -100)
    #expect(breakdown.amount(for: .other) == -20)
    #expect(breakdown.amount(for: .deduction) == -99)
    #expect(breakdown.amount(for: .discount) == -176.22)
    #expect(breakdown.amount(for: .fixed) == -20)
    #expect(breakdown.profitCents == 49478)
    #expect(breakdown.components.reduce(0) { $0 + $1.cents } == breakdown.profitCents)
}

@Test func manualTotalDoesNotInventCostAttributionOrCountFeesTwice() throws {
    let input = GoldReturnInput(grams: 10, unitPrice: 300, laborFee: 100, otherCost: 20, totalCostOverride: 8500)
    let breakdown = try #require(GoldProfitBreakdown.estimate([input], referencePrice: 900))
    #expect(breakdown.components.map(\.kind) == [.unitemized])
    #expect(breakdown.profitCents == 50000)
    #expect(breakdown.hasUnitemizedCost)
    #expect(breakdown.hasUnconfiguredRecovery)
}

@Test func clampedPayoutDoesNotDeductMoreThanRemainingGoldValue() throws {
    for rule in [GoldRecoveryRule(perGramDeduction: 1000, discountRate: 0.5, fixedFee: 500),
                 GoldRecoveryRule(perGramDeduction: 5, discountRate: 0.2, fixedFee: 10000)] {
        let breakdown = try #require(GoldProfitBreakdown.estimate([.init(grams: 1, unitPrice: 800, rule: rule)], referencePrice: 900))
        #expect(breakdown.profitCents == -80000)
        #expect(breakdown.components.reduce(0) { $0 + $1.cents } == -80000)
    }
}

@Test func mixedPortfolioAndFractionalAmountsReconcileToDisplayedProfit() throws {
    let inputs = [GoldReturnInput(grams: 1.2345, purity: 0.9999, unitPrice: 812.34, laborFee: 12.345,
                      rule: .init(perGramDeduction: 7.23, discountRate: 0.0123, fixedFee: 1.23)),
                  .init(grams: 2.3456, unitPrice: 700, totalCostOverride: 1900.123)]
    let breakdown = try #require(GoldProfitBreakdown.estimate(inputs, referencePrice: 923.456))
    let expected = try #require(GoldReturnCalculator.aggregate(inputs, referencePrice: 923.456)?.profit)
    #expect(breakdown.profitCents == Int64((expected * 100).rounded()))
    #expect(breakdown.components.reduce(0) { $0 + $1.cents } == breakdown.profitCents)
    #expect(breakdown.hasUnitemizedCost && breakdown.hasUnconfiguredRecovery)
}

@Test func missingOrInvalidQuoteDoesNotCreateZeroProfit() {
    for price: Double? in [nil, .nan, 0, .infinity] {
        #expect(GoldProfitBreakdown.estimate([.init(grams: 10, unitPrice: 800)], referencePrice: price) == nil)
    }
    #expect(GoldProfitBreakdown.estimate([], referencePrice: 900) == nil)
    #expect(GoldProfitBreakdown.estimate([.init(grams: -1, unitPrice: 800)], referencePrice: 900) == nil)
}

@Test func actualSaleUsesRecordedProceedsWithoutMarketAttribution() throws {
    let breakdown = try #require(GoldProfitBreakdown.sale(totalCost: 8120, proceeds: 9000))
    #expect(breakdown.components.map(\.kind) == [.sale])
    #expect(breakdown.profitCents == 88000)
    #expect(!breakdown.hasUnconfiguredRecovery)
    #expect(GoldProfitBreakdown.sale(totalCost: .infinity, proceeds: 9) == nil)
}

@Test func halfCentMatchesExistingMoneyFormatter() throws {
    for (price, expected): (Double, Int64) in [(899.875, 12), (900.125, -12)] {
        let breakdown = try #require(GoldProfitBreakdown.estimate([.init(grams: 1, unitPrice: price)], referencePrice: 900))
        #expect(breakdown.profitCents == expected)
        #expect(breakdown.components.reduce(0) { $0 + $1.cents } == expected)
    }
}

@Test func centRoundingMatchesFormattedFinalAcrossDecimalBoundaries() throws {
    for delta in [0.575, 0.125, 0.135, 1.005, -0.575, -0.125, -1.005, 12.3456] {
        let input = GoldReturnInput(grams: 1, unitPrice: 0, totalCostOverride: 900 - delta)
        let result = try #require(GoldReturnCalculator.calculate(input, referencePrice: 900)?.profit)
        let breakdown = try #require(GoldProfitBreakdown.estimate([input], referencePrice: 900))
        #expect(breakdown.profit.moneyText == result.moneyText)
        #expect(breakdown.components.reduce(0) { $0 + $1.cents } == breakdown.profitCents)
    }
    #expect(GoldProfitBreakdown.sale(totalCost: 0, proceeds: 1e30) == nil)
}

@Test func roundedZeroHasConsistentSignInSummaryAndBreakdown() {
    #expect(GoldReturnPresentation.money(-0.001, signed: true) == GoldReturnPresentation.money(0, signed: true))
}

@Test func sourceGroupsExplainTheDisplayedPortfolioWithoutChangingItsProfit() throws {
    let detailed = GoldReturnInput(grams: 10, purity: 0.99, unitPrice: 800, laborFee: 100, otherCost: 20,
        rule: .init(perGramDeduction: 10, discountRate: 0.02, fixedFee: 20))
    let manual = GoldReturnInput(grams: 10, unitPrice: 800, totalCostOverride: 9500)
    let breakdown = try #require(GoldProfitBreakdown.estimate([detailed, manual], referencePrice: 942.27))
    #expect(breakdown.groups.map(\.direction) == [.increase, .decrease])
    #expect(breakdown.groups[0].totalCents == Decimal(142270))
    #expect(breakdown.groups[1].totalCents == Decimal(-59512))
    #expect(breakdown.groups[1].components.contains { $0.kind == .unitemized })
    #expect(breakdown.groups.flatMap(\.components).count == breakdown.components.count)
    #expect(breakdown.groups.reduce(Decimal(0)) { $0 + $1.totalCents } == Decimal(breakdown.profitCents))
}

@Test func sourceGroupsKeepLossAndBreakEvenMeaningful() throws {
    let loss = try #require(GoldProfitBreakdown.estimate([.init(grams: 10, unitPrice: 800, totalCostOverride: 9500)], referencePrice: 900))
    #expect(loss.groups.map(\.direction) == [.decrease])
    #expect(loss.groups[0].totalCents == Decimal(-50000))
    let even = try #require(GoldProfitBreakdown.sale(totalCost: 800, proceeds: 800))
    #expect(even.groups.map(\.direction) == [.unchanged])
    #expect(even.groups[0].components.map(\.kind) == [.sale])
}

@Test func sourceGroupTotalsDoNotOverflowWhenLargeEffectsCancel() {
    let components: [GoldProfitBreakdown.Component] = [
        .init(kind: .price, cents: .max), .init(kind: .unitemized, cents: .max),
        .init(kind: .purity, cents: -.max), .init(kind: .deduction, cents: -.max)]
    let breakdown = GoldProfitBreakdown(components: components, profitCents: 0,
        totalCost: 0, goldValue: 0, proceeds: 0, hasUnitemizedCost: true, hasUnconfiguredRecovery: false)
    #expect(breakdown.groups[0].totalCents == Decimal(Int64.max) * 2)
    #expect(breakdown.groups.reduce(Decimal(0)) { $0 + $1.totalCents } == 0)
}

@Test func sourceCentFormattingIsConsistentForRowsGroupsAndFinalTotal() {
    #expect(GoldReturnPresentation.centsMoney(Decimal(142270)) == "¥+1422.70")
    #expect(GoldReturnPresentation.centsMoney(Decimal(-59512)) == "¥-595.12")
    #expect(GoldReturnPresentation.centsMoney(Decimal(Int64.max)) == "¥+92233720368547758.07")
    #expect(GoldReturnPresentation.centsMoney(Decimal(Int64.min)) == "¥-92233720368547758.08")
    #expect(GoldReturnPresentation.centsMoney(Decimal(82758), hidden: true) == "••••")
}
