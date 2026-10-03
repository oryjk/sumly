import Foundation
import SwiftData
import Testing
@testable import Sumly

@Test func simpleTotalPriceComputesRealReturnWithoutDoubleCountingFees() throws {
    let input = GoldReturnInput(grams: 30, unitPrice: 780, laborFee: 2400, otherCost: 100, totalCostOverride: 25800)
    let result = try #require(GoldReturnCalculator.calculate(input, referencePrice: 900))
    #expect(result.totalCost == 25800)
    #expect(result.proceeds == 27000)
    #expect(result.profit == 1200)
    #expect(abs((result.profitPercent ?? 0) - 4.65116279) < 0.00001)
    #expect(result.breakEvenPrice == 860)
}
@Test func laborAndRecoveryDeductionProduceCorrectBreakEven() throws {
    let input = GoldReturnInput(grams: 30, unitPrice: 780, laborFee: 2400, rule: .init(perGramDeduction: 8))
    let result = try #require(GoldReturnCalculator.calculate(input, referencePrice: 900))
    #expect(result.totalCost == 25800)
    #expect(result.proceeds == 26760)
    #expect(result.profit == 960)
    #expect(result.breakEvenPrice == 868)
    #expect(GoldReturnCalculator.calculate(input, referencePrice: result.breakEvenPrice)?.profit == 0)
}
@Test func purityDiscountAndFixedFeeParticipateInSameFormula() throws {
    let input = GoldReturnInput(grams: 10, purity: 0.99, unitPrice: 800, rule: .init(perGramDeduction: 10, discountRate: 0.02, fixedFee: 20))
    let result = try #require(GoldReturnCalculator.calculate(input, referencePrice: 900))
    #expect(result.effectiveGrams == 9.9)
    #expect(result.bookValue == 8910)
    #expect(abs((result.proceeds ?? 0) - 8614.78) < 0.000001)
    #expect(abs((result.profit ?? 0) - 614.78) < 0.000001)
    let recovered = try #require(GoldReturnCalculator.calculate(input, referencePrice: result.breakEvenPrice))
    #expect(abs(recovered.profit ?? 1) < 0.000001)
}
@Test func badNumbersCannotCreateValidResultsAndNoQuoteStillHasBreakEven() throws {
    for input in [GoldReturnInput(grams: 0, unitPrice: 800), .init(grams: .nan, unitPrice: 800),
                  .init(grams: 10, purity: 0, unitPrice: 800), .init(grams: 10, unitPrice: .infinity),
                  .init(grams: 10, unitPrice: 800, rule: .init(discountRate: 1)),
                  .init(grams: 10, unitPrice: 800, totalCostOverride: -1)] {
        #expect(GoldReturnCalculator.calculate(input, referencePrice: 900) == nil)
    }
    let input = GoldReturnInput(grams: 10, unitPrice: 800, rule: .init(perGramDeduction: 8, fixedFee: 20))
    let noQuote = try #require(GoldReturnCalculator.calculate(input, referencePrice: .nan))
    #expect(noQuote.breakEvenPrice == 810)
    #expect(noQuote.proceeds == nil)
    #expect(GoldReturnCalculator.calculate(input, referencePrice: 1)?.proceeds == 0)
}
@Test func portfolioBreakEvenSolvesDifferentRules() throws {
    let inputs = [GoldReturnInput(grams: 10, unitPrice: 800), .init(grams: 10, unitPrice: 900, rule: .init(perGramDeduction: 10, discountRate: 0.1, fixedFee: 20))]
    let result = try #require(GoldReturnCalculator.aggregate(inputs, referencePrice: 900, previousPrice: 890))
    #expect(result.totalCost == 17000)
    #expect(result.proceeds == 16990)
    #expect(result.profit == -10)
    #expect(abs((result.breakEvenPrice ?? 0) - 900.526315789) < 0.000001)
    #expect(abs((result.todayChange ?? 0) - 190) < 0.000001)
}
@MainActor @Test func legacyCostAndPartialDisposalPreserveAllCosts() throws {
    let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let record = HoldingRecord(grams: 30, unitPriceCNY: 780, timestamp: .now.addingTimeInterval(-100))
    record.extraFee = 100
    #expect(record.totalPurchaseCost == 23500)
    #expect(GoldReturnCalculator.calculate(record.returnInput, referencePrice: 900)?.proceeds == 27000)
    record.laborFee = 2400; record.purchaseTotalOverride = 25800; record.purity = 0.99; record.recoveryDeduction = 8
    context.insert(record); try context.save()
    try HoldingDisposal.apply(record: record, grams: 10, proceeds: 9000, kind: "sold", date: .now, context: context)
    let fetched = try context.fetch(FetchDescriptor<HoldingRecord>())
    let sold = try #require(fetched.first { $0.disposition == "sold" })
    #expect(record.totalPurchaseCost == 17200)
    #expect(sold.totalPurchaseCost == 8600)
    #expect(sold.laborFee == 800)
    #expect(sold.purity == 0.99)
    #expect(sold.recoveryDeduction == 8)
    #expect(HoldingCalendarLogic.events(fetched, filter: .init()).filter { $0.kind == "buy" }.reduce(0) { $0 + $1.cost } == 25800)
}
@Test func draftTotalModeAndCalculatorTransferRetainInputs() throws {
    var draft = HoldingDraft()
    draft.gramsText = "30"; draft.priceText = "780"; draft.laborText = "80"; draft.purityText = "100"
    #expect(draft.input?.totalCost == 25800)
    draft.costMode = .total; draft.totalText = "25800"; draft.otherText = "100"
    #expect(draft.input?.totalCost == 25800)
    draft.discountText = "100"
    #expect(draft.input == nil)
}

@Test func derivedMetricsNeverExposeInfiniteAmountsOrPercentages() {
    let input = GoldReturnInput(grams: 1, unitPrice: 1e-310)
    #expect(GoldReturnCalculator.calculate(input, referencePrice: 900) == nil)
    #expect(GoldReturnCalculator.aggregate([input], referencePrice: 900) == nil)
}
