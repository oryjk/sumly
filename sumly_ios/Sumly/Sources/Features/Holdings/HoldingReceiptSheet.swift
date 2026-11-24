import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 纪念卡纯数据快照（Sendable）

struct HoldingReceiptSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let assetType: GoldAssetType
    let addedGrams: Double
    let unitPrice: Double
    let totalCost: Double
    let timestamp: Date
    let purchaseSequence: Int
    let totalBookGrams: Double
    let bookName: String
    let milestone: GoldMilestoneProgress
    let newlyUnlockedMilestone: GoldMilestone?

    init(
        id: UUID = UUID(),
        assetType: GoldAssetType,
        addedGrams: Double,
        unitPrice: Double,
        totalCost: Double,
        timestamp: Date,
        purchaseSequence: Int,
        previousBookGrams: Double,
        bookName: String
    ) {
        let safeAdded = addedGrams.isFinite ? max(0, addedGrams) : 0
        let safePrevious = previousBookGrams.isFinite ? max(0, previousBookGrams) : 0
        let totalAfter = safePrevious + safeAdded
        self.id = id
        self.assetType = assetType
        self.addedGrams = safeAdded
        self.unitPrice = unitPrice.isFinite ? max(0, unitPrice) : 0
        self.totalCost = totalCost.isFinite ? max(0, totalCost) : 0
        self.timestamp = timestamp
        self.purchaseSequence = max(1, purchaseSequence)
        self.totalBookGrams = totalAfter
        self.bookName = bookName
        self.milestone = GoldMilestoneProgress.evaluate(totalGrams: totalAfter)
        self.newlyUnlockedMilestone = GoldMilestoneProgress.newlyUnlocked(previousGrams: safePrevious, currentGrams: totalAfter)
    }

    var addedGramsText: String {
        "+\(GoldVaultSummary.formatGrams(addedGrams)) g"
    }

    var totalBookGramsText: String {
        "\(GoldVaultSummary.formatGrams(totalBookGrams)) g"
    }

    var milestoneCaption: String {
        if let next = milestone.next {
            return L10n.fmt("距「%@」还差 %@ g", next.title, GoldVaultSummary.formatGrams(milestone.remainingToNext))
        }
        return L10n.tr("已点亮全部 6 档攒金里程碑")
    }
}

// MARK: - ImageRenderer 渲染与 ShareLink 传输封装

struct GoldReceiptShareImage: Transferable, Sendable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
    }
}

enum HoldingReceiptRenderer {
    @MainActor
    static func renderImage(snapshot: HoldingReceiptSnapshot, width: CGFloat = 340, scale: CGFloat = 3.0) -> UIImage? {
        let card = HoldingReceiptCardView(snapshot: snapshot)
            .frame(width: width)
            .padding(18)
            .background(GoldTheme.background)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @MainActor
    static func renderShareImage(snapshot: HoldingReceiptSnapshot, width: CGFloat = 340, scale: CGFloat = 3.0) -> GoldReceiptShareImage? {
        guard let image = renderImage(snapshot: snapshot, width: width, scale: scale),
              let data = image.pngData() else { return nil }
        return GoldReceiptShareImage(pngData: data)
    }
}

// MARK: - 暗黑金入库纪念卡主体（同时用于弹窗展示与高清图导出）

struct HoldingReceiptCardView: View {
    let snapshot: HoldingReceiptSnapshot

    var body: some View {
        VStack(spacing: 18) {
            // 顶部品牌抬头与攒金序号
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GoldTheme.gold)
                    Text(L10n.tr("记金 · 入库纪念卡"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                }
                Spacer(minLength: 8)
                Text(L10n.fmt("第 %lld 次攒金", Int64(snapshot.purchaseSequence)))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.onGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [GoldTheme.goldSoft, GoldTheme.gold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: GoldTheme.capsuleShape
                    )
            }

            // 中央核心金属图标与入库克重
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [GoldTheme.gold.opacity(0.24), GoldTheme.gold.opacity(0.05), .clear],
                                center: .center,
                                startRadius: 6,
                                endRadius: 56
                            )
                        )
                        .frame(width: 104, height: 104)

                    Circle()
                        .fill(GoldTheme.background)
                        .frame(width: 78, height: 78)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [GoldTheme.goldSoft.opacity(0.75), GoldTheme.gold.opacity(0.25)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )

                    GoldAssetGlyph(type: snapshot.assetType, size: 54, emphasized: true)
                }

                Text(snapshot.addedGramsText)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [GoldTheme.goldSoft, GoldTheme.gold],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(snapshot.assetType.displayName) · \(HoldingsSelection.dateText(snapshot.timestamp)) · \(HoldingRecord.localizedBookName(snapshot.bookName))")
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let unlocked = snapshot.newlyUnlockedMilestone {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                        Text(L10n.fmt("新解锁里程碑 · %@", unlocked.title))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(GoldTheme.gold.opacity(0.16), in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.55), lineWidth: 1))
                }
            }

            // 细金分隔线
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, GoldTheme.gold.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // 累计持有与本次投入双栏指标
            HStack(spacing: 12) {
                receiptMetric(title: L10n.tr("累计持有克重"), value: snapshot.totalBookGramsText, highlight: true)
                receiptMetric(title: L10n.tr("本次入库投入"), value: "¥\(snapshot.totalCost.moneyText)", highlight: false)
            }

            // 下一里程碑进度条
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(snapshot.milestoneCaption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text("\(Int((snapshot.milestone.progressRatio * 100).rounded()))%")
                        .font(.system(.caption, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.gold)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        GoldTheme.capsuleShape.fill(GoldTheme.background)
                        GoldTheme.capsuleShape
                            .fill(
                                LinearGradient(
                                    colors: [GoldTheme.tempWarm, GoldTheme.gold, GoldTheme.goldSoft],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * snapshot.milestone.progressRatio))
                    }
                }
                .frame(height: 7)
            }
            .padding(12)
            .background(GoldTheme.background.opacity(0.85), in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

            // 底部纪念铭文
            HStack {
                Text(L10n.tr("慢慢攒金，稳稳发光"))
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                Spacer()
                Text("Sumly")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(GoldTheme.gold.opacity(0.75))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [GoldTheme.card, GoldTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: GoldTheme.cardShape
        )
        .overlay(
            GoldTheme.cardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.goldSoft.opacity(0.65), GoldTheme.gold.opacity(0.28), GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
        )
    }

    private func receiptMetric(title: String, value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(highlight ? GoldTheme.gold : GoldTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(GoldTheme.background.opacity(0.85), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }
}

// MARK: - 入库纪念卡弹窗视图

struct HoldingReceiptSheet: View {
    let snapshot: HoldingReceiptSnapshot
    let onDone: () -> Void

    @State private var shareItem: GoldReceiptShareImage?
    @State private var previewUIImage: UIImage?
    @State private var shareTapCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(L10n.tr("入库成功"))
                            .font(.title3.bold())
                            .foregroundStyle(GoldTheme.text)
                        Text(L10n.tr("这笔黄金已稳稳存入你的攒金盒"))
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    .padding(.top, 8)

                    HoldingReceiptCardView(snapshot: snapshot)
                        .shadow(color: GoldTheme.tabBarShadow, radius: 18, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .background(GoldTheme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let shareItem, let previewUIImage {
                        ShareLink(
                            item: shareItem,
                            preview: SharePreview(
                                L10n.fmt("记金入库纪念卡 · %@", snapshot.addedGramsText),
                                image: Image(uiImage: previewUIImage)
                            )
                        ) {
                            HStack(spacing: 7) {
                                Image(systemName: "square.and.arrow.up")
                                Text(L10n.tr("分享 / 保存纪念卡"))
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(GoldTheme.gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.65), lineWidth: 1))
                        }
                        .simultaneousGesture(TapGesture().onEnded { shareTapCount += 1 })
                    }

                    Button(L10n.tr("完成"), action: onDone)
                        .buttonStyle(GoldPrimaryButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(GoldTheme.background)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    .accessibilityLabel(L10n.tr("关闭"))
                }
            }
        }
        .presentationBackground(GoldTheme.background)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .light), trigger: shareTapCount)
        .task(id: "\(snapshot.id)-\(AppLanguage.resolvedLanguageCode)") {
            let rendered = HoldingReceiptRenderer.renderImage(snapshot: snapshot)
            previewUIImage = rendered
            if let data = rendered?.pngData() {
                shareItem = GoldReceiptShareImage(pngData: data)
            }
        }
    }
}
