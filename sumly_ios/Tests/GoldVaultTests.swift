import Foundation
import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Sumly

// MARK: - 1. GoldAssetType.bean 排序与编码 / 云同步兼容

@Test func goldAssetTypeOrderAndEncodingCompatibility() throws {
    #expect(GoldAssetType.allCases == [.bean, .bar, .jewelry, .accumulation, .other])
    #expect(GoldAssetType.bean.rawValue == "金豆")
    #expect(GoldAssetType.primaryQuickTypes == [.bean, .bar, .jewelry, .accumulation])

    // Codable / JSON 编解码往返兼容
    let encoded = try JSONEncoder().encode(GoldAssetType.allCases)
    let decoded = try JSONDecoder().decode([GoldAssetType].self, from: encoded)
    #expect(decoded == GoldAssetType.allCases)

    // 旧记录与未知字符串安全回退到 .other
    #expect(GoldAssetType(rawValue: "金豆") == .bean)
    #expect(GoldAssetType(rawValue: "金条") == .bar)
    #expect(GoldAssetType(rawValue: "金饰") == .jewelry)
    #expect(GoldAssetType(rawValue: "积存金") == .accumulation)
    #expect(GoldAssetType(rawValue: "其他") == .other)
    #expect(GoldAssetType(rawValue: "未知旧分类") == nil)
}

@MainActor @Test func beanAssetTypeRoundTripsThroughHoldingRecordAndCloudJSON() throws {
    let record = HoldingRecord(grams: 3, unitPriceCNY: 685.5, timestamp: Date(timeIntervalSince1970: 1_790_000_000))
    var draft = HoldingDraft()
    draft.selectAssetType(.bean)
    draft.applyQuickGrams(3, fallbackUnitPrice: 685.5)
    let input = try #require(draft.input)
    draft.apply(to: record, input: input)

    #expect(record.assetType == "金豆")
    #expect(record.displayName == "金豆")

    // 验证云同步 JSONB 编码往返
    let cloudRecord = HoldingCloudRecord(record)
    let json = try JSONEncoder().encode(cloudRecord)
    let restoredCloud = try JSONDecoder().decode(HoldingCloudRecord.self, from: json)
    #expect(restoredCloud.assetType == "金豆")

    let restoredRecord = restoredCloud.makeRecord()
    let restoredDraft = HoldingDraft(record: restoredRecord)
    #expect(restoredDraft.assetType == .bean)
    #expect(restoredDraft.parsedGrams == 3)
}

// MARK: - 2. 快捷克重应用、形态切换默认值与单价/总价实时联动

@Test func assetTypeSwitchAppliesDefaultsWithoutOverwritingUserGramsOrPrice() {
    var draft = HoldingDraft()
    draft.gramsText = "12.5"
    draft.priceText = "680.00"
    draft.note = "发薪攒金"

    draft.selectAssetType(.jewelry)
    #expect(draft.assetType == .jewelry)
    #expect(draft.purityText == "99.9")
    #expect(draft.laborText == "50")
    #expect(draft.laborPerGram == true)
    // 不覆盖已手填克重、单价与备注
    #expect(draft.gramsText == "12.5")
    #expect(draft.priceText == "680.00")
    #expect(draft.note == "发薪攒金")
    // 12.5 * 680 + 12.5 * 50 = 9125.00
    #expect(draft.totalText == "9125.00")

    draft.selectAssetType(.accumulation)
    #expect(draft.purityText == "99.99")
    #expect(draft.laborText == "0")
    #expect(draft.gramsText == "12.5")
    #expect(draft.priceText == "680.00")
    // 12.5 * 680 = 8500.00
    #expect(draft.totalText == "8500.00")
}

@Test func quickGramsAndLinkedUnitTotalPriceCalculation() throws {
    var draft = HoldingDraft()
    draft.selectAssetType(.accumulation) // 0 工费
    draft.applyQuickGrams(10, fallbackUnitPrice: 682.40)

    #expect(draft.gramsText == "10")
    #expect(draft.priceText == "682.40")
    #expect(draft.costMode == .unit)
    #expect(draft.totalText == "6824.00")
    #expect(try #require(draft.input).totalCost == 6824.0)

    // 修改单价实时联动总价
    draft.updateUnitPrice("700")
    #expect(draft.costMode == .unit)
    #expect(draft.totalText == "7000.00")

    // 直接修改总价切换为总价优先模式
    draft.updateTotalPrice("7150")
    #expect(draft.costMode == .total)
    #expect(try #require(draft.input).totalCost == 7150.0)

    // 再次修改单价切回单价联动模式
    draft.updateUnitPrice("690")
    #expect(draft.costMode == .unit)
    #expect(draft.totalText == "6900.00")
}

// MARK: - 3. GoldVaultSummary 陈列计算与全部 6 档里程碑边界

@Test func vaultSummaryAggregatesActiveEntriesAndFoldsOverflow() {
    let entries: [GoldVaultEntry] = [
        GoldVaultEntry(assetType: "金条", grams: 20),
        GoldVaultEntry(assetType: "金条", grams: 10),
        GoldVaultEntry(assetType: "金豆", grams: 5),
        GoldVaultEntry(assetType: "金饰", grams: 8.5),
        GoldVaultEntry(assetType: "积存金", grams: 15),
        GoldVaultEntry(assetType: "其他", grams: 2),
        // 已处置记录不得计入攒金盒
        GoldVaultEntry(assetType: "金条", grams: 50, disposition: "sold"),
        GoldVaultEntry(assetType: "金豆", grams: 10, disposition: "gift")
    ]

    let summary = GoldVaultSummary(entries: entries)
    #expect(!summary.isEmpty)
    #expect(summary.recordCount == 6)
    #expect(abs(summary.totalGrams - 60.5) < 0.0001)
    #expect(summary.barCount == 2)
    #expect(summary.beanCount == 5)
    #expect(summary.jewelryCount == 1)
    #expect(summary.accumulationCount == 1)
    #expect(summary.otherCount == 1)
    #expect(summary.totalDisplayPieces == 10) // 2 bar + 5 bean + 1 jewelry + 1 acc + 1 other

    // 限制 7 个槽位时，保留全部 5 类至少各 1 枚，并折叠显示 +3
    let folded = summary.visibleTrayTokens(limit: 7)
    #expect(folded.tokens.count == 7)
    #expect(folded.overflowCount == 3)
    let representedTypes = Set(folded.tokens.map(\.type))
    #expect(representedTypes == Set(GoldAssetType.allCases))

    // 上限充足时不折叠
    let full = summary.visibleTrayTokens(limit: 12)
    #expect(full.tokens.count == 10)
    #expect(full.overflowCount == 0)
}

@Test func allSixMilestoneUnlockBoundaries() {
    #expect(GoldMilestone.ladder.map(\.targetGrams) == [1, 10, 50, 100, 500, 1000])

    let zero = GoldMilestoneProgress.evaluate(totalGrams: 0)
    #expect(zero.unlocked.isEmpty)
    #expect(zero.current == nil)
    #expect(zero.next?.targetGrams == 1)
    #expect(zero.remainingToNext == 1)
    #expect(zero.progressRatio == 0)

    let subFirst = GoldMilestoneProgress.evaluate(totalGrams: 0.5)
    #expect(subFirst.unlocked.isEmpty)
    #expect(subFirst.next?.targetGrams == 1)
    #expect(abs(subFirst.progressRatio - 0.5) < 0.0001)

    let boundaries: [(Double, Int, Double?)] = [
        (1, 1, 10),
        (9.99, 1, 10),
        (10, 2, 50),
        (49.99, 2, 50),
        (50, 3, 100),
        (99.99, 3, 100),
        (100, 4, 500),
        (499.99, 4, 500),
        (500, 5, 1000),
        (999.99, 5, 1000),
        (1000, 6, nil),
        (1250, 6, nil)
    ]

    for (grams, expectedUnlockedCount, expectedNextTarget) in boundaries {
        let progress = GoldMilestoneProgress.evaluate(totalGrams: grams)
        #expect(progress.unlocked.count == expectedUnlockedCount)
        #expect(progress.next?.targetGrams == expectedNextTarget)
        if let expectedNextTarget {
            #expect(abs(progress.remainingToNext - (expectedNextTarget - grams)) < 0.001)
        } else {
            #expect(progress.remainingToNext == 0)
            #expect(progress.progressRatio == 1.0)
        }
    }

    // 跨档解锁检测
    #expect(GoldMilestoneProgress.newlyUnlocked(previousGrams: 0, currentGrams: 1)?.targetGrams == 1)
    #expect(GoldMilestoneProgress.newlyUnlocked(previousGrams: 8, currentGrams: 12)?.targetGrams == 10)
    #expect(GoldMilestoneProgress.newlyUnlocked(previousGrams: 5, currentGrams: 120)?.targetGrams == 100)
    #expect(GoldMilestoneProgress.newlyUnlocked(previousGrams: 15, currentGrams: 25) == nil)
}

// MARK: - 4. hideAmounts 隐私脱敏

@Test func vaultSummaryRespectsHideAmountsMasking() {
    let summary = GoldVaultSummary(entries: [
        GoldVaultEntry(assetType: "金条", grams: 30),
        GoldVaultEntry(assetType: "金豆", grams: 3),
        GoldVaultEntry(assetType: "积存金", grams: 12.5)
    ])

    #expect(summary.formattedTotalGrams(hideAmounts: false) == "45.5 g")
    #expect(summary.formattedTotalGrams(hideAmounts: true) == "•••• g")
    #expect(summary.progressPercentText(hideAmounts: true) == "••%")
    #expect(summary.milestoneHeadline(hideAmounts: true) == "里程碑进度已隐藏")
    #expect(!summary.milestoneHeadline(hideAmounts: true).contains("4.5"))
    #expect(!summary.milestoneHeadline(hideAmounts: true).contains("50g"))

    let hiddenBadges = summary.categoryBadges(hideAmounts: true)
    #expect(hiddenBadges.count == 3)
    for badge in hiddenBadges {
        #expect(badge.text.contains("••••"))
        #expect(!badge.text.contains("30"))
        #expect(!badge.text.contains("12.5"))
    }
}

// MARK: - 5. 矢量图标、纪念卡渲染与模拟器目视验收图生成

@MainActor @Test func assetGlyphsReceiptAndVaultRenderCleanly() async throws {
    // 1) 验证 5 枚矢量图标通过 ImageRenderer 渲染非空位图
    for type in GoldAssetType.allCases {
        let renderer = ImageRenderer(
            content: GoldAssetGlyph(type: type, size: 64, emphasized: true)
                .padding(8)
                .background(GoldTheme.background)
        )
        renderer.scale = 2.0
        let image = try #require(renderer.uiImage)
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    // 2) 验证入库纪念卡 ImageRenderer 渲染与 PNG 导出
    let receiptSnapshot = HoldingReceiptSnapshot(
        assetType: .jewelry,
        addedGrams: 10,
        unitPrice: 685.5,
        totalCost: 7355,
        timestamp: Date(timeIntervalSince1970: 1_795_200_000),
        purchaseSequence: 6,
        previousBookGrams: 92.5,
        bookName: "默认账本"
    )
    #expect(receiptSnapshot.newlyUnlockedMilestone?.targetGrams == 100)
    let renderedCard = try #require(HoldingReceiptRenderer.renderImage(snapshot: receiptSnapshot))
    #expect(renderedCard.size.width > 0 && renderedCard.size.height > 0)
    let shareImage = try #require(HoldingReceiptRenderer.renderShareImage(snapshot: receiptSnapshot))
    #expect(!shareImage.pngData.isEmpty)

    // 3) 若在 Simulator 宿主窗口环境下运行，输出 3 屏合成目视验收素材到临时目录
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-gold-vault-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    var demoDraft = HoldingDraft()
    demoDraft.selectAssetType(.jewelry)
    demoDraft.applyQuickGrams(10, fallbackUnitPrice: 685.50)

    let vaultSummary = GoldVaultSummary(entries: [
        GoldVaultEntry(assetType: "金条", grams: 50),
        GoldVaultEntry(assetType: "金条", grams: 10),
        GoldVaultEntry(assetType: "金豆", grams: 5),
        GoldVaultEntry(assetType: "金饰", grams: 12.5),
        GoldVaultEntry(assetType: "积存金", grams: 15)
    ])

    let panels: [(String, AnyView)] = [
        (
            "01-quick-add",
            AnyView(
                AddHoldingSheet(
                    defaultUnitPrice: 685.50,
                    date: Date(timeIntervalSince1970: 1_795_200_000),
                    marketBasis: .domestic,
                    seed: demoDraft
                )
                .modelContainer(container)
            )
        ),
        (
            "02-receipt-card",
            AnyView(
                HoldingReceiptSheet(snapshot: receiptSnapshot, onDone: {})
            )
        ),
        (
            "03-vault-and-glyphs",
            AnyView(
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            GoldVaultCard(summary: vaultSummary, hideAmounts: false, onAddTap: {})
                            VStack(alignment: .leading, spacing: 12) {
                                Text("现代暗金矢量图标细节（放大检视）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(GoldTheme.goldSoft)
                                HStack(spacing: 10) {
                                    ForEach(GoldAssetType.allCases) { type in
                                        VStack(spacing: 6) {
                                            GoldAssetGlyph(type: type, size: 52, emphasized: true)
                                            Text(type.rawValue)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(GoldTheme.text)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(GoldTheme.background, in: GoldTheme.subCardShape)
                                        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1))
                                    }
                                }
                            }
                            .padding(16)
                            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
                            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

                            GoldVaultCard(summary: vaultSummary, hideAmounts: true, onAddTap: {})
                        }
                        .padding(16)
                    }
                    .background(GoldTheme.background)
                    .navigationTitle("我的攒金盒")
                    .navigationBarTitleDisplayMode(.inline)
                }
            )
        )
    ]

    for (name, view) in panels {
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: view.preferredColorScheme(.dark).tint(GoldTheme.gold))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let path = directory.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: path)
        print("GOLD_VAULT_RENDER: \(path.path)")
        window.isHidden = true
    }
    previousWindow?.makeKey()
}
