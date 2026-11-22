import SwiftUI
import StoreKit
import UIKit

/// 高保真暗黑金「记金会员」订阅与管理弹窗（严格遵循 Apple App Store Review 3.1.1 / 3.1.2 / 5.1.1）。
struct MembershipPaywallSheet: View {
    @Bindable var membership: MembershipStore
    /// 当由「禅观」门禁拉起时设为 true：订阅或恢复解锁后平滑关闭弹窗并自动衔接打开禅观。
    var autoDismissOnUnlock: Bool = false
    /// 已订阅态点击「立即打开禅观」或解锁后衔接回调。
    var onOpenChanlun: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedPlan: MembershipPlan = MembershipPlan.defaultSelection
    @State private var isOpeningManageSubscriptions = false

    var body: some View {
        MembershipPaywallContent(
            membership: membership,
            selectedPlan: $selectedPlan,
            isOpeningManageSubscriptions: isOpeningManageSubscriptions,
            showsChanlunAction: onOpenChanlun != nil,
            onClose: { dismiss() },
            onPurchase: { plan in
                Task {
                    let unlocked = await membership.purchase(plan: plan)
                    if unlocked && autoDismissOnUnlock {
                        dismiss()
                    }
                }
            },
            onRestore: {
                Task {
                    let unlocked = await membership.restorePurchases()
                    if unlocked && autoDismissOnUnlock {
                        dismiss()
                    }
                }
            },
            onRetryLoadProducts: {
                Task { await membership.loadProducts() }
            },
            onOpenChanlun: {
                if let onOpenChanlun {
                    onOpenChanlun()
                } else {
                    dismiss()
                }
            },
            onManageSubscriptions: {
                Task { await openManageSubscriptions() }
            }
        )
        .presentationBackground(GoldTheme.background)
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .task {
            membership.clearFeedback()
            if membership.products.isEmpty {
                await membership.loadProducts()
            }
            await membership.refreshEntitlements()
        }
    }

    private func openManageSubscriptions() async {
        guard !isOpeningManageSubscriptions else { return }
        isOpeningManageSubscriptions = true
        defer { isOpeningManageSubscriptions = false }

        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                await membership.refreshEntitlements()
                return
            } catch {
                // 在模拟器或无订阅管理上下文时平滑回退至系统订阅管理页面
            }
        }
        openURL(MembershipCopy.manageSubscriptionsFallbackURL)
    }
}

/// 可独立渲染的暗黑金会员弹窗内容视图（供正式弹窗与多态视觉核验共用）。
struct MembershipPaywallContent: View {
    @Bindable var membership: MembershipStore
    @Binding var selectedPlan: MembershipPlan
    var isOpeningManageSubscriptions: Bool = false
    var showsChanlunAction: Bool = true
    var onClose: () -> Void = {}
    var onPurchase: (MembershipPlan) -> Void = { _ in }
    var onRestore: () -> Void = {}
    var onRetryLoadProducts: () -> Void = {}
    var onOpenChanlun: () -> Void = {}
    var onManageSubscriptions: () -> Void = {}

    private var savingsPercent: Int {
        membership.yearlySavingsPercent()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 顶部暗金氛围微光
            LinearGradient(
                colors: [
                    GoldTheme.gold.opacity(0.14),
                    GoldTheme.background,
                    GoldTheme.background
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.36)
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 13) {
                        if membership.isActive {
                            activeMemberHero
                            activeEntitlementCard
                            benefitsCard(isUnlocked: true)
                            feedbackBanner
                            activeActionsSection
                        } else {
                            paywallHero
                            benefitsCard(isUnlocked: false)
                            planSelectionSection
                            feedbackBanner
                            purchaseButtonSection
                        }
                        complianceFooter
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .sensoryFeedback(.selection, trigger: selectedPlan)
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(MembershipCopy.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.goldSoft)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
            .overlay(
                GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 0.8)
            )

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(GoldTheme.card, in: GoldTheme.circleShape)
                    .overlay(
                        GoldTheme.circleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                    )
                    .contentShape(GoldTheme.circleShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            .accessibilityIdentifier("membership.close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - 未订阅顶部 Hero

    private var paywallHero: some View {
        VStack(spacing: 8) {
            crownEmblem(isActive: false)

            VStack(spacing: 4) {
                Text(MembershipCopy.title)
                    .font(.title3.bold())
                    .foregroundStyle(GoldTheme.text)

                Text(MembershipCopy.subtitle)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 已订阅顶部 Hero

    private var activeMemberHero: some View {
        VStack(spacing: 8) {
            crownEmblem(isActive: true)

            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Text(MembershipCopy.title)
                        .font(.title3.bold())
                        .foregroundStyle(GoldTheme.text)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(MembershipCopy.activeBadgeTitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(GoldTheme.down)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(GoldTheme.down.opacity(0.14), in: GoldTheme.capsuleShape)
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(GoldTheme.down.opacity(0.38), lineWidth: 0.9)
                    )
                }

                Text(MembershipCopy.activeMemberSubtitle)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func crownEmblem(isActive: Bool) -> some View {
        ZStack {
            GoldTheme.circleShape
                .fill(
                    RadialGradient(
                        colors: [
                            GoldTheme.gold.opacity(isActive ? 0.30 : 0.24),
                            GoldTheme.gold.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 36
                    )
                )
                .frame(width: 72, height: 72)

            GoldTheme.circleShape
                .fill(
                    LinearGradient(
                        colors: [GoldTheme.card, GoldTheme.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    GoldTheme.circleShape.strokeBorder(
                        LinearGradient(
                            colors: [GoldTheme.goldSoft.opacity(0.85), GoldTheme.gold.opacity(0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.4
                    )
                )

            Image(systemName: "crown.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [GoldTheme.goldSoft, GoldTheme.gold, GoldTheme.tempWarm],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .accessibilityHidden(true)
    }

    // MARK: - 已订阅状态卡

    private var activeEntitlementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("当前生效方案")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)

                Spacer()

                if membership.entitlement.isSandbox {
                    Text("沙盒环境")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
                        .overlay(
                            GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 0.8)
                        )
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(membership.entitlement.planTitle ?? MembershipCopy.title)
                    .font(.title3.bold())
                    .foregroundStyle(GoldTheme.goldSoft)

                Spacer()

                if let plan = membership.entitlement.activePlan {
                    Text("\(membership.displayPrice(for: plan))/\(plan.billingUnit)")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                }
            }

            GoldTheme.cardStroke.frame(height: 1)

            VStack(spacing: 8) {
                infoRow(
                    label: "有效期至",
                    value: membership.entitlement.formattedExpirationDate() ?? "持续有效",
                    valueColor: GoldTheme.text
                )
                infoRow(
                    label: "续费方式",
                    value: membership.entitlement.willAutoRenew ? "到期自动续费" : "已关闭自动续费",
                    valueColor: membership.entitlement.willAutoRenew ? GoldTheme.down : GoldTheme.goldSoft
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(
                    colors: [GoldTheme.card, GoldTheme.background.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [GoldTheme.gold.opacity(0.13), .clear],
                    center: .topTrailing,
                    startRadius: 6,
                    endRadius: 180
                )
            }
            .clipShape(GoldTheme.cardShape)
        )
        .overlay(
            GoldTheme.cardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.gold.opacity(0.45), GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.1
            )
        )
    }

    private func infoRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - 客观权益清单

    private func benefitsCard(isUnlocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(isUnlocked ? "已解锁会员权益" : "会员核心权益")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                Spacer()
            }

            VStack(spacing: 9) {
                ForEach(MembershipCopy.benefits) { benefit in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: benefit.iconSystemName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GoldTheme.gold)
                            .frame(width: 30, height: 30)
                            .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.badgeShape)
                            .overlay(
                                GoldTheme.badgeShape.strokeBorder(GoldTheme.gold.opacity(0.26), lineWidth: 0.8)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(benefit.detail)
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        if isUnlocked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GoldTheme.down)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(
            GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - 双方案可选卡片（年度默认选中）

    private var planSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("选择订阅方案")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .padding(.leading, 2)
                Spacer()
                if membership.isLoadingProducts {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(GoldTheme.gold)
                        Text("正在获取价格…")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(MembershipPlan.allCases) { plan in
                    planCard(for: plan)
                }
            }

            if membership.productsLoadFailed && membership.products.isEmpty && !membership.isLoadingProducts {
                Button(action: onRetryLoadProducts) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                        Text(MembershipCopy.retryLoadProductsTitle)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(GoldTheme.goldSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(GoldTheme.gold.opacity(0.08), in: GoldTheme.subCardShape)
                    .overlay(
                        GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.24), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("membership.retryProducts")
            }
        }
    }

    private func planCard(for plan: MembershipPlan) -> some View {
        let isSelected = selectedPlan == plan
        let isYearly = plan == .yearly
        let priceText = membership.displayPrice(for: plan)
        let periodText = membership.periodLabel(for: plan)
        let monthlyEquivalent = membership.monthlyEquivalentText(for: plan)

        return Button {
            selectedPlan = plan
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // 单选圆形指示器
                ZStack {
                    GoldTheme.circleShape
                        .fill(isSelected ? GoldTheme.gold : .clear)
                        .frame(width: 22, height: 22)
                    GoldTheme.circleShape
                        .strokeBorder(
                            isSelected ? GoldTheme.gold : GoldTheme.textFaint,
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GoldTheme.onGold)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(isSelected ? GoldTheme.text : GoldTheme.text.opacity(0.92))

                        if isYearly {
                            Text(MembershipPricing.yearlyBadgeText(savingsPercent: savingsPercent))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(GoldTheme.onGold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [GoldTheme.goldSoft, GoldTheme.gold],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: GoldTheme.capsuleShape
                                )
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("订阅周期：\(periodText)")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)

                        if let monthlyEquivalent {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textFaint)
                            Text(monthlyEquivalent)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? GoldTheme.gold : GoldTheme.text)
                    Text("/ \(plan.billingUnit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    GoldTheme.card
                    if isSelected {
                        LinearGradient(
                            colors: [GoldTheme.gold.opacity(0.14), GoldTheme.gold.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .clipShape(GoldTheme.holdingsCardShape)
            )
            .overlay(
                GoldTheme.holdingsCardShape.strokeBorder(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [GoldTheme.goldSoft.opacity(0.9), GoldTheme.gold.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(GoldTheme.cardStroke),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .contentShape(GoldTheme.holdingsCardShape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("membership.plan.\(plan.shortTitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 反馈提示条

    @ViewBuilder
    private var feedbackBanner: some View {
        if let status = membership.statusMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.gold)
                    .padding(.top, 1)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.goldSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.gold.opacity(0.1), in: GoldTheme.subCardShape)
            .overlay(
                GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1)
            )
        }

        if let error = membership.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.up)
                    .padding(.top, 1)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.up)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.up.opacity(0.1), in: GoldTheme.subCardShape)
            .overlay(
                GoldTheme.subCardShape.strokeBorder(GoldTheme.up.opacity(0.32), lineWidth: 1)
            )
        }
    }

    // MARK: - 主操作按钮

    private var purchaseButtonSection: some View {
        VStack(spacing: 8) {
            Button {
                onPurchase(selectedPlan)
            } label: {
                HStack(spacing: 8) {
                    if membership.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(GoldTheme.onGold)
                        Text(MembershipCopy.purchasingStatusTitle)
                    } else {
                        Text(membership.ctaTitle(for: selectedPlan))
                    }
                }
            }
            .buttonStyle(GoldPrimaryButtonStyle())
            .disabled(membership.isPurchasing || membership.isRestoring)
            .opacity(membership.isRestoring ? 0.65 : 1)
            .accessibilityIdentifier("membership.subscribe")
        }
    }

    private var activeActionsSection: some View {
        VStack(spacing: 10) {
            if showsChanlunAction {
                Button(action: onOpenChanlun) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.subheadline.weight(.bold))
                        Text(MembershipCopy.openChanlunTitle)
                    }
                }
                .buttonStyle(GoldPrimaryButtonStyle())
                .accessibilityIdentifier("membership.openChanlun")
            }

            Button(action: onManageSubscriptions) {
                HStack(spacing: 6) {
                    if isOpeningManageSubscriptions {
                        ProgressView()
                            .controlSize(.small)
                            .tint(GoldTheme.goldSoft)
                    } else {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(MembershipCopy.manageSubscriptionsTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(GoldTheme.goldSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                .overlay(
                    GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.38), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isOpeningManageSubscriptions)
            .accessibilityIdentifier("membership.manageSubscriptions")
        }
    }

    // MARK: - Apple 3.1.2 必填合规页脚

    private var complianceFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onRestore) {
                    HStack(spacing: 4) {
                        if membership.isRestoring {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(GoldTheme.goldSoft)
                            Text(MembershipCopy.restoringStatusTitle)
                        } else {
                            Text(MembershipCopy.restoreButtonTitle)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                }
                .buttonStyle(.plain)
                .disabled(membership.isPurchasing || membership.isRestoring)
                .accessibilityIdentifier("membership.restore")

                Text("·")
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textFaint)

                Link(MembershipCopy.privacyPolicyTitle, destination: MembershipCopy.privacyPolicyURL)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .accessibilityIdentifier("membership.privacyPolicy")

                Text("·")
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textFaint)

                Link(MembershipCopy.termsOfUseTitle, destination: MembershipCopy.termsOfUseURL)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .accessibilityIdentifier("membership.termsOfUse")
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 5) {
                Text(MembershipCopy.autoRenewalDisclosure)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(MembershipCopy.complianceDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 4)
    }
}
