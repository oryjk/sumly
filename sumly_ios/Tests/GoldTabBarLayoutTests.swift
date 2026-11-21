import CoreGraphics
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Sumly

@Suite("GoldTabBarLayout Tests")
struct GoldTabBarLayoutTests {
    @Test func compactScreenWithoutHomeIndicator() {
        let layout = GoldTabBarLayout.resolve(containerWidth: 375, safeAreaBottom: 0)

        #expect(layout.bottomPadding == 12)
        #expect(layout.barHeight == 56)
        #expect(layout.barFootprintHeight == 68)
        #expect(layout.scrimHeight == 84)
        #expect(layout.contentWidth == 343)
        #expect(layout.capsuleWidth == 275)
        #expect(abs(layout.tabItemWidth - 66.75) < 1e-6)
        #expect(layout.homeBottomInset == 84)
        #expect(layout.homeAdditionalBottomInset == 84)
        #expect(layout.embeddedTabBottomInset == 76)
        #expect(layout.additionalSafeAreaBottomInset == 76)
        #expect(layout.homeBottomInset < 112)
    }

    @Test func standardScreenWithHomeIndicator() {
        let layout = GoldTabBarLayout.resolve(containerWidth: 402, safeAreaBottom: 34)

        #expect(layout.bottomPadding == 26)
        #expect(layout.barHeight == 56)
        #expect(layout.barFootprintHeight == 82)
        #expect(layout.scrimHeight == 98)
        #expect(layout.contentWidth == 370)
        #expect(layout.capsuleWidth == 302)
        #expect(abs(layout.tabItemWidth - 73.5) < 1e-6)
        #expect(layout.homeBottomInset == 98)
        #expect(layout.homeAdditionalBottomInset == 64)
        #expect(layout.embeddedTabBottomInset == 90)
        #expect(layout.additionalSafeAreaBottomInset == 56)
        // 相比旧版凸起大黄球（112 + safeBottom 或 112）释放更多图表可视高度。
        #expect(layout.homeBottomInset < 112)
    }

    @Test func iPadClampsContentWidthAndCentersGracefully() {
        let layoutWithIndicator = GoldTabBarLayout.resolve(containerWidth: 834, safeAreaBottom: 20)

        #expect(layoutWithIndicator.contentWidth == GoldTabBarLayout.maxContentWidth)
        #expect(layoutWithIndicator.contentWidth == 440)
        #expect(layoutWithIndicator.capsuleWidth == 372)
        #expect(abs(layoutWithIndicator.tabItemWidth - 91) < 1e-6)
        #expect(layoutWithIndicator.bottomPadding == 12)
        #expect(layoutWithIndicator.barFootprintHeight == 68)
        #expect(layoutWithIndicator.homeBottomInset == 84)
        #expect(layoutWithIndicator.homeAdditionalBottomInset == 64)
        #expect(layoutWithIndicator.embeddedTabBottomInset == 76)
        #expect(layoutWithIndicator.additionalSafeAreaBottomInset == 56)

        let layoutWithoutIndicator = GoldTabBarLayout.resolve(containerWidth: 834, safeAreaBottom: 0)
        #expect(layoutWithoutIndicator.contentWidth == 440)
        #expect(layoutWithoutIndicator.bottomPadding == 12)
        #expect(layoutWithoutIndicator.homeBottomInset == 84)
        #expect(layoutWithoutIndicator.additionalSafeAreaBottomInset == 76)
    }

    @Test func smallNonZeroSafeBottomRespectsMinimumBottomPadding() {
        let layoutSmall = GoldTabBarLayout.resolve(containerWidth: 390, safeAreaBottom: 10)
        #expect(layoutSmall.bottomPadding == 8)
        #expect(layoutSmall.barFootprintHeight == 64)
        #expect(layoutSmall.homeBottomInset == 80)

        let layoutTiny = GoldTabBarLayout.resolve(containerWidth: 390, safeAreaBottom: 4)
        #expect(layoutTiny.bottomPadding == 8)
        #expect(layoutTiny.barFootprintHeight == 64)
    }

    @Test func geometryInvariantsHoldAcrossScreenWidths() {
        let cases: [(CGFloat, CGFloat)] = [
            (375, 0),
            (375, 34),
            (402, 34),
            (430, 34),
            (834, 20),
            (1024, 20)
        ]

        for (width, safeBottom) in cases {
            let layout = GoldTabBarLayout.resolve(containerWidth: width, safeAreaBottom: safeBottom)
            #expect(layout.contentWidth <= GoldTabBarLayout.maxContentWidth)
            #expect(abs(layout.capsuleWidth + GoldTabBarLayout.itemSpacing + GoldTabBarLayout.addButtonDiameter - layout.contentWidth) < 1e-6)
            #expect(abs(layout.tabItemWidth * CGFloat(GoldTabBarLayout.tabCount) + GoldTabBarLayout.capsuleInnerPadding * 2 - layout.capsuleWidth) < 1e-6)
            #expect(layout.homeBottomInset > layout.barFootprintHeight)
            #expect(layout.embeddedTabBottomInset > layout.barFootprintHeight)
            #expect(layout.safeAreaBottom + layout.homeAdditionalBottomInset == layout.homeBottomInset)
            #expect(layout.safeAreaBottom + layout.additionalSafeAreaBottomInset == layout.embeddedTabBottomInset)
            #expect(layout.scrimHeight == layout.barFootprintHeight + GoldTabBarLayout.scrimTopFade)
        }
    }

    @Test func invalidInputsClampSafelyWithoutNaN() {
        let invalidCases: [(CGFloat, CGFloat)] = [
            (-100, -20),
            (.nan, .nan),
            (.infinity, .infinity),
            (0, 0)
        ]

        for (width, safeBottom) in invalidCases {
            let layout = GoldTabBarLayout.resolve(containerWidth: width, safeAreaBottom: safeBottom)
            #expect(layout.contentWidth.isFinite && layout.contentWidth >= 0)
            #expect(layout.capsuleWidth.isFinite && layout.capsuleWidth >= 0)
            #expect(layout.tabItemWidth.isFinite && layout.tabItemWidth >= 0)
            #expect(layout.bottomPadding.isFinite && layout.bottomPadding >= 8)
            #expect(layout.homeBottomInset.isFinite && layout.homeBottomInset >= layout.barFootprintHeight)
        }
    }

    @Test func primaryTabDefinitionsPreserveFourTabsAndMoneyBagIcon() {
        let tabs = GoldPrimaryTab.allCases
        #expect(tabs.count == GoldTabBarLayout.tabCount)
        #expect(tabs.map(\.title) == ["行情", "持有", "日历", "我的"])
        #expect(tabs.map(\.rawValue) == [0, 1, 2, 3])
        #expect(tabs.filter(\.usesMoneyBagIcon) == [.holdings])
        #expect(GoldPrimaryTab.market.symbol == "chart.xyaxis.line")
        #expect(GoldPrimaryTab.calendar.symbol == "calendar")
        #expect(GoldPrimaryTab.account.symbol == "person.fill")
    }

    @MainActor @Test func renderFloatingTabBarTabsForVisualReview() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-tabbar-plan-a", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let container = try ModelContainer(
            for: HoldingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let r1 = HoldingRecord(
            grams: 10,
            unitPriceCNY: 712,
            timestamp: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
        )
        r1.brand = "周大福"
        let r2 = HoldingRecord(
            grams: 20,
            unitPriceCNY: 695,
            timestamp: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
        )
        r2.brand = "银行投资金条"
        container.mainContext.insert(r1)
        container.mainContext.insert(r2)
        try container.mainContext.save()

        let quoteStore = LiveGoldQuoteStore()
        quoteStore.ingest(
            GoldQuote(
                symbol: "AU9999",
                price: 755.01,
                open: 762.40,
                high: 765.80,
                low: 751.20,
                prevClose: 764.55,
                usdCNY: 7.24,
                cnyPerGram: 755.01,
                asOf: .now
            ),
            for: .domestic
        )

        let homeScrolledShell = TabBarVisualShell(selectedTab: 0) { layout in
            ScrollView {
                VStack(spacing: 14) {
                    GoldTemperatureCard(
                        temperature: Self.sampleTemperatureReport(),
                        treasury: MacroTreasurySummary(
                            totalDebtTrillionUSD: 36.22,
                            debtChangeYoYTrillion: 2.12,
                            debtToGDPPct: 122.9,
                            interestToRevenuePct: 18.4,
                            fiscalStressScore: 76.0,
                            yield10yNominalPct: 4.32,
                            yield2yNominalPct: 4.18,
                            spread10y2yPct: 0.14,
                            yield10yRealPct: 1.92,
                            breakeven10yPct: 2.40,
                            tltPrice: 91.25,
                            goldImpactNote: "美债总规模与财政付息压力处于近 3 年偏高位。"
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        onRetry: {},
                        onOpenDashboard: {}
                    )
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("今日盘口参考").font(.subheadline.bold()).foregroundStyle(GoldTheme.text)
                            Spacer()
                            Text("国内 · 元/克").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }
                        HStack {
                            Text("今开 ¥762.40").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                            Spacer()
                            Text("昨收 ¥764.55").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                            Spacer()
                            Text("最高 ¥765.80").font(.caption).foregroundStyle(GoldTheme.up)
                            Spacer()
                            Text("最低 ¥751.20").font(.caption).foregroundStyle(GoldTheme.down)
                        }
                    }
                    .goldCard(padding: 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 240)
                .padding(.bottom, layout.homeBottomInset)
            }
            .background(GoldTheme.background)
        }

        let holdingsShell = TabBarVisualShell(selectedTab: 1) { _ in
            HoldingsView(marketBasis: .domestic, quoteStore: quoteStore)
                .modelContainer(container)
        }

        let calendarShell = TabBarVisualShell(selectedTab: 2) { _ in
            HoldingsCalendarSheet(
                initialBook: "默认账本",
                hideAmounts: false,
                marketBasis: .domestic,
                quoteStore: quoteStore,
                isEmbeddedTab: true
            )
            .modelContainer(container)
        }

        let fixtures: [(String, CGSize?, Bool, AnyView)] = [
            ("tabbar-home-bottom", nil, true, AnyView(homeScrolledShell)),
            ("tabbar-holdings-bottom", nil, true, AnyView(holdingsShell)),
            ("tabbar-calendar", nil, false, AnyView(calendarShell)),
            ("tabbar-calendar-bottom", nil, true, AnyView(calendarShell)),
            ("tabbar-ipad-834", CGSize(width: 834, height: 180), false, AnyView(
                ZStack(alignment: .bottom) {
                    GoldTheme.background.ignoresSafeArea()
                    GoldFloatingTabBar(
                        selectedTab: .constant(0),
                        layout: GoldTabBarLayout.resolve(containerWidth: 834, safeAreaBottom: 20),
                        onAdd: {}
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            ))
        ]

        for (name, customSize, scrollToBottom, rootView) in fixtures {
            let window = UIWindow(windowScene: scene)
            if let customSize {
                window.frame = CGRect(origin: .zero, size: customSize)
            }
            let controller = UIHostingController(
                rootView: rootView
                    .preferredColorScheme(.dark)
                    .tint(GoldTheme.gold)
            )
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .dark
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            var maxObservedBottomInset: CGFloat = 0
            if scrollToBottom {
                for _ in 0..<3 {
                    maxObservedBottomInset = max(
                        maxObservedBottomInset,
                        Self.scrollAllScrollViewsToBottom(in: controller.view)
                    )
                    try await Task.sleep(for: .milliseconds(180))
                    controller.view.layoutIfNeeded()
                }
            }
            if name == "tabbar-holdings-bottom" || name == "tabbar-calendar-bottom" {
                let expectedLayout = GoldTabBarLayout.resolve(
                    containerWidth: window.bounds.width,
                    safeAreaBottom: window.safeAreaInsets.bottom
                )
                #expect(maxObservedBottomInset >= expectedLayout.embeddedTabBottomInset - 1)
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let data = try #require(image.pngData())
            #expect(data.count > 5_000)
            let path = directory.appendingPathComponent(name + ".png")
            try data.write(to: path, options: .atomic)
            print("TABBAR_RENDER_ARTIFACT: \(path.path)")
            window.isHidden = true
        }
        previous?.makeKey()
    }

    @MainActor
    @discardableResult
    private static func scrollAllScrollViewsToBottom(in view: UIView) -> CGFloat {
        var maxBottomInset: CGFloat = 0
        if let scrollView = view as? UIScrollView {
            let maxY = max(
                -scrollView.adjustedContentInset.top,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: maxY), animated: false)
            maxBottomInset = max(maxBottomInset, scrollView.adjustedContentInset.bottom)
        }
        for subview in view.subviews {
            maxBottomInset = max(maxBottomInset, scrollAllScrollViewsToBottom(in: subview))
        }
        return maxBottomInset
    }

    private static func sampleTemperatureReport() -> MacroTemperatureReport {
        MacroTemperatureReport(
            asOf: "2026-11-21",
            modelVersion: "v1",
            degraded: false,
            missingFactors: [],
            score: 27.4,
            level: .cool,
            levelLabel: "偏冷蓄势",
            change1d: -0.9,
            change5d: -2.4,
            volatilityAlert: false,
            volatilityNote: "",
            macroRegime: MacroRegime(score: 68.0, regime: .tailwind, label: "长期顺风", summary: ""),
            actionGuide: MacroActionGuide(
                signal: "cool_tailwind",
                title: "短冷长强",
                summary: "",
                dcaMultiplier: 1.0,
                dcaLabel: "拥挤度偏低",
                ma200DeviationPct: -3.1,
                ma200Note: "低于 200 日均线 3.1%",
                domesticPremiumPct: -0.4,
                domesticPremiumNote: "国内较国际折价 0.4%",
                disclaimer: MacroPresentation.defaultDisclaimer
            ),
            dimensions: [],
            guideHelp: nil
        )
    }
}

private struct TabBarVisualShell<Content: View>: View {
    @State private var selectedTab: Int
    private let content: (GoldTabBarLayout) -> Content

    init(selectedTab: Int, @ViewBuilder content: @escaping (GoldTabBarLayout) -> Content) {
        _selectedTab = State(initialValue: selectedTab)
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = GoldTabBarLayout.resolve(
                containerWidth: geometry.size.width,
                safeAreaBottom: geometry.safeAreaInsets.bottom
            )
            ZStack(alignment: .bottom) {
                GoldTheme.background.ignoresSafeArea()
                content(layout)
                    .environment(\.goldTabBarAdditionalBottomInset, layout.additionalSafeAreaBottomInset)
                GoldFloatingTabBar(
                    selectedTab: $selectedTab,
                    layout: layout,
                    onAdd: {}
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
