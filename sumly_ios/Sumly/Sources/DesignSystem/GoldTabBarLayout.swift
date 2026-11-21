import CoreGraphics

/// 底部悬浮胶囊导航栏（方案 A：左四项悬浮胶囊 + 右独立金色加号圆钮）的纯几何与留白计算模型。
/// 统一供 `SumlyApp` 底栏渲染与各 Tab 底部内容避让使用，避免硬编码常量在多处漂移。
struct GoldTabBarLayout: Equatable, Sendable {
    /// 左侧 4-Tab 悬浮胶囊高度。
    static let capsuleHeight: CGFloat = 56
    /// 右侧独立金色 `+` 圆钮直径（与胶囊等高，保持视觉基线齐平）。
    static let addButtonDiameter: CGFloat = 56
    /// 左侧胶囊与右侧 `+` 按钮之间的水平间距。
    static let itemSpacing: CGFloat = 12
    /// 紧凑/标准屏左右外边距。
    static let horizontalMargin: CGFloat = 16
    /// iPad / 大屏下外层底栏组合的最大宽度，防止胶囊被过度拉长。
    static let maxContentWidth: CGFloat = 440
    /// 胶囊内部留白（(56 - 4*2) = 48，与外胶囊保持同心圆角）。
    static let capsuleInnerPadding: CGFloat = 4
    /// 底层渐隐底衬超出底栏顶部的平滑过渡高度。
    static let scrimTopFade: CGFloat = 16
    /// 行情页等自管理底部留白的滚动内容在底栏顶部的呼吸间距。
    static let homeContentGap: CGFloat = 16
    /// 持有/日历/我的等嵌套 Tab 视图底部的额外避让间距（叠加视图自身底边距）。
    static let embeddedTabGap: CGFloat = 8
    /// 胶囊内固定 Tab 数量（行情 / 持有 / 日历 / 我的）。
    static let tabCount: Int = 4

    /// 容器可用总宽度。
    let containerWidth: CGFloat
    /// 系统传入的底部安全区高度（Home Indicator）。
    let safeAreaBottom: CGFloat
    /// 悬浮底栏距离屏幕物理底边的留白。
    let bottomPadding: CGFloat
    /// 底栏组合（左胶囊 + 间距 + 右圆钮）的实际总宽度（已按 `maxContentWidth` 限宽）。
    let contentWidth: CGFloat
    /// 左侧 4-Tab 悬浮胶囊宽度。
    let capsuleWidth: CGFloat
    /// 单个 Tab 项在胶囊内（扣除 `capsuleInnerPadding` 后）的等分宽度。
    let tabItemWidth: CGFloat
    /// 底栏主体高度（等于胶囊高度与 `+` 直径的最大值）。
    let barHeight: CGFloat
    /// 底栏从屏幕物理底边占用的总垂直高度（`barHeight + bottomPadding`）。
    let barFootprintHeight: CGFloat
    /// 底部渐隐底衬总高度（`barFootprintHeight + scrimTopFade`）。
    let scrimHeight: CGFloat
    /// 行情页（HomeView）滚动内容从屏幕物理底边算起所需的总避让高度（`barFootprintHeight + homeContentGap`）。
    let homeBottomInset: CGFloat
    /// 行情页在 `NavigationStack` 内部（系统已保留 `safeAreaBottom`）需额外叠加的底部留白。
    let homeAdditionalBottomInset: CGFloat
    /// 持有/日历/我的等 Tab 从屏幕物理底边算起所需的总安全避让高度（`barFootprintHeight + embeddedTabGap`）。
    let embeddedTabBottomInset: CGFloat
    /// 持有/日历/我的等 Tab 在 `NavigationStack` 内部（系统已保留 `safeAreaBottom`）需额外叠加的 `.safeAreaInset` 高度。
    let additionalSafeAreaBottomInset: CGFloat

    /// 根据容器宽度与系统底部安全区计算所有悬浮底栏布局度量。
    static func resolve(containerWidth: CGFloat, safeAreaBottom: CGFloat) -> GoldTabBarLayout {
        let clampedWidth = containerWidth.isFinite ? max(0, containerWidth) : 0
        let clampedSafeBottom = safeAreaBottom.isFinite ? max(0, safeAreaBottom) : 0

        let bottomPadding: CGFloat = clampedSafeBottom > 0
            ? max(clampedSafeBottom - 8, 8)
            : 12

        let availableContentWidth = max(0, clampedWidth - horizontalMargin * 2)
        let contentWidth = min(availableContentWidth, maxContentWidth)
        let capsuleWidth = max(0, contentWidth - itemSpacing - addButtonDiameter)
        let innerCapsuleWidth = max(0, capsuleWidth - capsuleInnerPadding * 2)
        let tabItemWidth = innerCapsuleWidth / CGFloat(tabCount)

        let barHeight = max(capsuleHeight, addButtonDiameter)
        let barFootprintHeight = barHeight + bottomPadding
        let scrimHeight = barFootprintHeight + scrimTopFade
        let homeBottomInset = barFootprintHeight + homeContentGap
        let homeAdditionalBottomInset = max(0, homeBottomInset - clampedSafeBottom)
        let embeddedTabBottomInset = barFootprintHeight + embeddedTabGap
        let additionalSafeAreaBottomInset = max(0, embeddedTabBottomInset - clampedSafeBottom)

        return GoldTabBarLayout(
            containerWidth: clampedWidth,
            safeAreaBottom: clampedSafeBottom,
            bottomPadding: bottomPadding,
            contentWidth: contentWidth,
            capsuleWidth: capsuleWidth,
            tabItemWidth: tabItemWidth,
            barHeight: barHeight,
            barFootprintHeight: barFootprintHeight,
            scrimHeight: scrimHeight,
            homeBottomInset: homeBottomInset,
            homeAdditionalBottomInset: homeAdditionalBottomInset,
            embeddedTabBottomInset: embeddedTabBottomInset,
            additionalSafeAreaBottomInset: additionalSafeAreaBottomInset
        )
    }
}
