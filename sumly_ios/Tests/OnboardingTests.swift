import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Sumly

// MARK: - OnboardingGate 触发规则

@Test func onboardingGatePresentsOnlyForNewUsersWithZeroHoldings() {
    #expect(OnboardingGate.currentVersion == 1)
    #expect(OnboardingGate.shouldAutoPresent(completedVersion: 0, existingHoldingCount: 0))
    #expect(!OnboardingGate.shouldMarkCompletedSilently(completedVersion: 0, existingHoldingCount: 0))
    #expect(OnboardingGate.evaluateLaunch(completedVersion: 0, existingHoldingCount: 0) == .present)
}

@Test func onboardingGateSilentlySkipsExistingUsersWithHoldings() {
    for count in [1, 2, 18] {
        #expect(!OnboardingGate.shouldAutoPresent(completedVersion: 0, existingHoldingCount: count))
        #expect(OnboardingGate.shouldMarkCompletedSilently(completedVersion: 0, existingHoldingCount: count))
        #expect(OnboardingGate.evaluateLaunch(completedVersion: 0, existingHoldingCount: count) == .markCompletedSilently)
    }
}

@Test func onboardingGateDoesNotRepeatAfterCurrentOrNewerVersionCompleted() {
    let current = OnboardingGate.currentVersion
    for version in [current, current + 1, current + 5] {
        for count in [0, 1, 10] {
            #expect(!OnboardingGate.shouldAutoPresent(completedVersion: version, existingHoldingCount: count))
            #expect(!OnboardingGate.shouldMarkCompletedSilently(completedVersion: version, existingHoldingCount: count))
            #expect(OnboardingGate.evaluateLaunch(completedVersion: version, existingHoldingCount: count) == .skip)
        }
    }
}

@Test func onboardingGateHandlesNegativeHoldingCountSafely() {
    #expect(OnboardingGate.shouldAutoPresent(completedVersion: 0, existingHoldingCount: -3))
    #expect(OnboardingGate.evaluateLaunch(completedVersion: 0, existingHoldingCount: -3) == .present)
}

// MARK: - QuickStartChecklistState 进度与显隐

@Test func quickStartChecklistCalculatesProgressAndCompletionAccurately() {
    let zero = QuickStartChecklistState()
    #expect(zero.totalCount == 3)
    #expect(zero.completedCount == 0)
    #expect(zero.progressBadgeText == "0/3")
    #expect(abs(zero.progressFraction - 0.0) < 0.0001)
    #expect(!zero.isAllCompleted)
    #expect(zero.shouldShowCard(dismissed: false))
    #expect(!zero.shouldShowCard(dismissed: true))

    let stepOne = QuickStartChecklistState(hasRecordedHolding: true)
    #expect(stepOne.completedCount == 1)
    #expect(stepOne.progressBadgeText == "1/3")
    #expect(abs(stepOne.progressFraction - (1.0 / 3.0)) < 0.0001)
    #expect(stepOne.items[0].isCompleted)
    #expect(!stepOne.items[1].isCompleted)
    #expect(!stepOne.items[2].isCompleted)
    #expect(!stepOne.isAllCompleted)
    #expect(stepOne.shouldShowCard(dismissed: false))
    #expect(!stepOne.shouldShowCard(dismissed: true))

    let stepTwo = QuickStartChecklistState(hasRecordedHolding: true, hasViewedChartOverlay: true)
    #expect(stepTwo.completedCount == 2)
    #expect(stepTwo.progressBadgeText == "2/3")
    #expect(abs(stepTwo.progressFraction - (2.0 / 3.0)) < 0.0001)
    #expect(stepTwo.items[0].isCompleted)
    #expect(stepTwo.items[1].isCompleted)
    #expect(!stepTwo.items[2].isCompleted)
    #expect(!stepTwo.isAllCompleted)
    #expect(stepTwo.shouldShowCard(dismissed: false))
    #expect(!stepTwo.shouldShowCard(dismissed: true))

    let allDone = QuickStartChecklistState(
        hasRecordedHolding: true,
        hasViewedChartOverlay: true,
        hasVisitedCalendar: true
    )
    #expect(allDone.completedCount == 3)
    #expect(allDone.progressBadgeText == "3/3")
    #expect(abs(allDone.progressFraction - 1.0) < 0.0001)
    #expect(allDone.isAllCompleted)
    #expect(!allDone.shouldShowCard(dismissed: false))
    #expect(!allDone.shouldShowCard(dismissed: true))
}

@Test func quickStartChecklistMapsIndividualFlagsIndependently() {
    let onlyChart = QuickStartChecklistState(hasViewedChartOverlay: true)
    #expect(!onlyChart.items[0].isCompleted)
    #expect(onlyChart.items[1].isCompleted)
    #expect(!onlyChart.items[2].isCompleted)
    #expect(onlyChart.completedCount == 1)

    let onlyCalendar = QuickStartChecklistState(hasVisitedCalendar: true)
    #expect(!onlyCalendar.items[0].isCompleted)
    #expect(!onlyCalendar.items[1].isCompleted)
    #expect(onlyCalendar.items[2].isCompleted)
    #expect(onlyCalendar.completedCount == 1)
}

// MARK: - 引导步骤内容与客观合规静态断言

@Test func onboardingStepsMatchThreePageStructureAndCTAs() {
    let steps = OnboardingStep.allSteps
    #expect(steps.count == 3)
    #expect(steps.map(\.kind) == [.holdings, .marketChart, .calendarVault])
    #expect(Set(steps.map(\.id)).count == 3)

    #expect(steps[0].primaryButtonTitle == "下一步")
    #expect(steps[0].secondaryButtonTitle == nil)
    #expect(!steps[0].isFinalStep)

    #expect(steps[1].primaryButtonTitle == "下一步")
    #expect(steps[1].secondaryButtonTitle == nil)
    #expect(!steps[1].isFinalStep)

    #expect(steps[2].primaryButtonTitle == "立刻记下第一笔黄金")
    #expect(steps[2].secondaryButtonTitle == "先随便逛逛")
    #expect(steps[2].isFinalStep)
}

@Test func onboardingCopyContainsZeroInvestmentOrTradingAdviceTerms() {
    let allCopy = OnboardingStep.allCopyStrings + QuickStartChecklistState.allCopyStrings
    #expect(!allCopy.isEmpty)
    for text in allCopy {
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    let forbiddenTerms = [
        "投资建议", "理财建议", "买入建议", "卖出建议", "操作建议",
        "推荐买入", "推荐卖出", "抄底", "逃顶", "加仓", "减仓",
        "满仓", "空仓", "清仓", "止盈", "止损", "做多", "做空",
        "看涨", "看跌", "稳赚", "必涨", "必跌", "高收益", "高回报",
        "交易信号", "买点信号", "卖点信号", "逢低买", "逢高卖",
        "保本收益", "稳健收益", "躺赚", "翻倍", "荐股", "带单"
    ]

    let combined = allCopy.joined(separator: "\n")
    for term in forbiddenTerms {
        #expect(!combined.contains(term), "引导文案不应包含投资或交易建议词：\(term)")
    }
}

// MARK: - 视图渲染冒烟验证

@MainActor @Test func onboardingSheetAndQuickStartCardLayoutCleanly() {
    let sheetHost = UIHostingController(
        rootView: OnboardingSheetView(onCompleteAndRecord: {}, onDismiss: {})
            .frame(width: 393, height: 852)
    )
    sheetHost.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
    sheetHost.view.layoutIfNeeded()
    #expect(sheetHost.view.bounds.width == 393)

    let cardHost = UIHostingController(
        rootView: OnboardingQuickStartCard(
            state: QuickStartChecklistState(hasRecordedHolding: true),
            onSelectAction: { _ in },
            onDismiss: {}
        )
        .padding(16)
        .background(GoldTheme.background)
        .frame(width: 393)
    )
    let fitted = cardHost.sizeThatFits(in: CGSize(width: 393, height: UIView.layoutFittingCompressedSize.height))
    #expect(fitted.width == 393)
    #expect(fitted.height > 100 && fitted.height < 320)
}
