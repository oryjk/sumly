import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Sumly

/// Review artifacts cover states that cannot safely be created in a user's book.
@MainActor @Test func renderProfitBreakdownStatesForVisualReview() async throws {
    let detailed = GoldReturnInput(grams: 10, purity: 0.99, unitPrice: 800, laborFee: 100, otherCost: 20,
        rule: .init(perGramDeduction: 10, discountRate: 0.02, fixedFee: 20))
    let manual = GoldReturnInput(grams: 10, unitPrice: 800, totalCostOverride: 9500)
    let fixtures: [(String, GoldProfitBreakdown?, Bool, Bool, DynamicTypeSize)] = [
        ("itemized", GoldProfitBreakdown.estimate([detailed], referencePrice: 900), false, false, .large),
        ("manual-loss", GoldProfitBreakdown.estimate([manual], referencePrice: 900), false, false, .large),
        ("hidden", GoldProfitBreakdown.estimate([detailed], referencePrice: 900), true, false, .large),
        ("no-quote", nil, false, false, .large),
        ("sold", GoldProfitBreakdown.sale(totalCost: 8120, proceeds: 9000), false, true, .large),
        ("large-text", GoldProfitBreakdown.estimate([detailed], referencePrice: 900), false, false, .accessibility2)
    ]
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-profit-ui-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, breakdown, hidden, actual, size) in fixtures {
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: NavigationStack {
            ScrollView { GoldProfitBreakdownCard(breakdown: breakdown, hidden: hidden, actual: actual, unconfiguredRecovery: breakdown == nil).padding(16) }
                .background(GoldTheme.background).navigationTitle("盈亏来源").navigationBarTitleDisplayMode(.inline)
        }.environment(\.dynamicTypeSize, size).preferredColorScheme(.dark).tint(GoldTheme.gold))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let path = directory.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: path)
        print("PROFIT_RENDER_ARTIFACT: \(path.path)")
        window.isHidden = true
    }
    previous?.makeKey()
}

@MainActor @Test func renderProfitRecordDetailsForVisualReview() async throws {
    let first = HoldingRecord(grams: 1, unitPriceCNY: 800, timestamp: Date(timeIntervalSince1970: 1_790_000_000))
    let second = HoldingRecord(grams: 1, unitPriceCNY: 1000, timestamp: first.timestamp)
    let manual = HoldingRecord(grams: 1, unitPriceCNY: 100, timestamp: first.timestamp)
    manual.purchaseTotalOverride = 950
    let records = [first, second, manual]
    let breakdown = try #require(GoldProfitBreakdown.estimate(records.map(\.returnInput), referencePrice: 900))
    let price = try #require(breakdown.components.first { $0.kind == .price })
    let total = try #require(breakdown.components.first { $0.kind == .unitemized })
    let sale = try #require(GoldProfitBreakdown.sale(totalCost: 800, proceeds: 850)).components[0]
    let fixtures: [(String, GoldProfitBreakdown.Component, Bool, DynamicTypeSize)] = [
        ("record-offsets", price, false, .large),
        ("record-manual", total, false, .large),
        ("record-hidden", price, true, .large),
        ("record-large-text", price, false, .accessibility2),
        ("record-sold", sale, false, .large)
    ]
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-profit-ui-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, component, hidden, size) in fixtures {
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(component.kind.title).font(.headline).foregroundStyle(GoldTheme.text)
                    GoldProfitSourceDetails(component: component, records: records, hidden: hidden)
                }.padding(16)
            }.background(GoldTheme.background).navigationTitle("逐笔明细").navigationBarTitleDisplayMode(.inline)
        }.environment(\.dynamicTypeSize, size).preferredColorScheme(.dark).tint(GoldTheme.gold))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let path = directory.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: path)
        print("PROFIT_RENDER_ARTIFACT: \(path.path)")
        window.isHidden = true
    }
    previous?.makeKey()
}
