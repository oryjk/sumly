import SwiftUI

/// 底部主导航 Tab 项定义（左胶囊内固定 4 项）。
enum GoldPrimaryTab: Int, CaseIterable, Identifiable, Sendable {
    case market = 0
    case holdings = 1
    case calendar = 2
    case account = 3

    var id: String {
        switch self {
        case .market: "market"
        case .holdings: "holdings"
        case .calendar: "calendar"
        case .account: "account"
        }
    }

    var title: String {
        switch self {
        case .market: "行情"
        case .holdings: "持有"
        case .calendar: "日历"
        case .account: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .market: "chart.xyaxis.line"
        case .holdings: "bag.fill"
        case .calendar: "calendar"
        case .account: "person.fill"
        }
    }

    var usesMoneyBagIcon: Bool {
        self == .holdings
    }
}

/// 方案 A · 悬浮双体底栏：左侧 4-Tab 深色悬浮胶囊 + 右侧独立金色 `+` 按钮。
struct GoldFloatingTabBar: View {
    @Binding var selectedTab: Int
    let layout: GoldTabBarLayout
    let onAdd: () -> Void

    @Namespace private var tabHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            bottomScrim
            HStack(spacing: GoldTabBarLayout.itemSpacing) {
                tabCapsule
                addButton
            }
            .frame(width: layout.contentWidth, height: layout.barHeight)
            .frame(maxWidth: .infinity)
            .padding(.bottom, layout.bottomPadding)
        }
        .frame(maxWidth: .infinity)
    }

    /// 底部渐隐底衬：由背景色平滑渐隐至透明，避免滚动文字从悬浮胶囊下方生硬穿出。
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: GoldTheme.background.opacity(0), location: 0.0),
                .init(color: GoldTheme.background.opacity(0.72), location: 0.16),
                .init(color: GoldTheme.background.opacity(0.94), location: 0.37),
                .init(color: GoldTheme.background.opacity(0.99), location: 0.61),
                .init(color: GoldTheme.background, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: layout.scrimHeight)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private var tabCapsule: some View {
        HStack(spacing: 0) {
            ForEach(GoldPrimaryTab.allCases) { tab in
                tabItem(tab)
            }
        }
        .padding(GoldTabBarLayout.capsuleInnerPadding)
        .frame(maxWidth: .infinity)
        .frame(height: GoldTabBarLayout.capsuleHeight)
        .background {
            ZStack {
                GoldTheme.capsuleShape
                    .fill(.ultraThinMaterial)
                    .opacity(0.35)
                GoldTheme.capsuleShape
                    .fill(GoldTheme.tabBarSurface)
            }
        }
        .overlay {
            GoldTheme.capsuleShape
                .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
        }
        .shadow(color: GoldTheme.tabBarShadow, radius: 14, x: 0, y: 6)
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8),
            value: selectedTab
        )
    }

    private func tabItem(_ tab: GoldPrimaryTab) -> some View {
        let isSelected = selectedTab == tab.rawValue
        return Button {
            selectedTab = tab.rawValue
        } label: {
            VStack(spacing: 3) {
                if tab.usesMoneyBagIcon {
                    GoldMoneyBagShape()
                        .fill(isSelected ? GoldTheme.gold : GoldTheme.textSecondary)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(height: 20)
                }
                Text(tab.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? GoldTheme.gold : GoldTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    selectedHighlightPill
                }
            }
            .contentShape(GoldTheme.capsuleShape)
        }
        .buttonStyle(GoldScalePressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tabbar.\(tab.id)")
    }

    @ViewBuilder
    private var selectedHighlightPill: some View {
        if reduceMotion {
            GoldTheme.capsuleShape
                .fill(GoldTheme.tabBarHighlight)
        } else {
            GoldTheme.capsuleShape
                .fill(GoldTheme.tabBarHighlight)
                .matchedGeometryEffect(id: "tabSelectionHighlight", in: tabHighlight)
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(GoldTheme.onGold)
                .frame(
                    width: GoldTabBarLayout.addButtonDiameter,
                    height: GoldTabBarLayout.addButtonDiameter
                )
                .background(GoldTheme.gold, in: GoldTheme.circleShape)
                .shadow(color: GoldTheme.addButtonShadow, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(GoldScalePressStyle())
        .accessibilityLabel("添加黄金")
        .accessibilityIdentifier("tabbar.add")
    }
}

/// 轻弹缩放按压反馈，供悬浮底栏 Tab 项与独立金色 `+` 按钮共用。
struct GoldScalePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct GoldTabBarAdditionalBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// 供嵌套在 `NavigationStack` 内部的 Tab 根视图与子页面读取的额外底部安全区避让高度。
    var goldTabBarAdditionalBottomInset: CGFloat {
        get { self[GoldTabBarAdditionalBottomInsetKey.self] }
        set { self[GoldTabBarAdditionalBottomInsetKey.self] = newValue }
    }
}

extension View {
    /// 在 `NavigationStack` 内部视图上叠加悬浮底栏的额外底部安全区避让，
    /// 使 `List` / `ScrollView` 既可平滑滚过底栏渐隐底衬，又能在滚到底部时完整避开悬浮胶囊与 `+` 按钮。
    func goldTabBarContentSafeArea() -> some View {
        modifier(GoldTabBarContentSafeAreaModifier())
    }
}

private struct GoldTabBarContentSafeAreaModifier: ViewModifier {
    @Environment(\.goldTabBarAdditionalBottomInset) private var additionalInset

    func body(content: Content) -> some View {
        if additionalInset > 0 {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: additionalInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}
