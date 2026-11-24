import Observation
import SwiftUI
import UIKit

@MainActor
enum GoldKeyboardDismissHelper {
    /// 统一收起当前第一响应者对应的系统键盘。
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// 底部操作栏与键盘收起控件的纯布局状态。
struct GoldKeyboardBarLayout: Equatable, Sendable {
    let isKeyboardVisible: Bool
    let usesInlineDismissButton: Bool

    /// 无底部常驻栏的页面保留 `.keyboard` toolbar；含 `.safeAreaInset(edge: .bottom)` 的表单页禁用它以避免 iOS 26 悬浮条夹层留白。
    var attachesKeyboardToolbar: Bool {
        !usesInlineDismissButton
    }

    /// 键盘弹出且采用底部栏内嵌收起按钮时显示右侧收起图标按钮。
    var showsInlineDismissButton: Bool {
        usesInlineDismissButton && isKeyboardVisible
    }

    /// 键盘隐藏时主按钮占满全宽。
    var primaryButtonIsFullWidth: Bool {
        !showsInlineDismissButton
    }
}

/// 轻量级键盘可见状态监听器，严格遵守 Swift 6 `@MainActor` 与无循环引用释放。
@MainActor
@Observable
final class GoldKeyboardObserver {
    private(set) var isKeyboardVisible: Bool
    @ObservationIgnored nonisolated(unsafe) private var observerTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private let notificationCenter: NotificationCenter

    init(
        initialVisible: Bool = false,
        notificationCenter: NotificationCenter = .default
    ) {
        self.isKeyboardVisible = initialVisible
        self.notificationCenter = notificationCenter

        let showToken = notificationCenter.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isKeyboardVisible = true
            }
        }

        let hideToken = notificationCenter.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isKeyboardVisible = false
            }
        }

        observerTokens = [showToken, hideToken]
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }
}

private struct GoldKeyboardDismissButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 底部实心暗金栏右侧的收起键盘图标按钮（44×44 热区）。
struct GoldKeyboardDismissButton: View {
    var action: @MainActor () -> Void = GoldKeyboardDismissHelper.dismiss

    var body: some View {
        Button(action: action) {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GoldTheme.gold)
                .frame(width: 44, height: 44)
                .background(GoldTheme.card, in: GoldTheme.circleShape)
                .overlay(
                    GoldTheme.circleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                )
                .contentShape(GoldTheme.circleShape)
        }
        .buttonStyle(GoldKeyboardDismissButtonStyle())
        .accessibilityLabel(L10n.tr("收起键盘"))
        .accessibilityIdentifier("keyboard.dismiss")
    }
}

/// 含数字键盘与底部主按钮表单页的统一 `.safeAreaInset(edge: .bottom)` 实心暗金栏。
struct GoldKeyboardActionBar<PrimaryAction: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ownedObserver: GoldKeyboardObserver?
    private let externalObserver: GoldKeyboardObserver?
    private let keyboardVisibilityOverride: Bool?
    private let dismissKeyboard: @MainActor () -> Void
    private let primaryAction: PrimaryAction

    init(
        observer: GoldKeyboardObserver? = nil,
        keyboardVisibilityOverride: Bool? = nil,
        dismissKeyboard: @escaping @MainActor () -> Void = GoldKeyboardDismissHelper.dismiss,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.externalObserver = observer
        self.keyboardVisibilityOverride = keyboardVisibilityOverride
        self.dismissKeyboard = dismissKeyboard
        self.primaryAction = primaryAction()
    }

    private var isKeyboardVisible: Bool {
        keyboardVisibilityOverride
            ?? externalObserver?.isKeyboardVisible
            ?? ownedObserver?.isKeyboardVisible
            ?? false
    }

    var layout: GoldKeyboardBarLayout {
        GoldKeyboardBarLayout(
            isKeyboardVisible: isKeyboardVisible,
            usesInlineDismissButton: true
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            primaryAction
                .frame(maxWidth: .infinity)

            if layout.showsInlineDismissButton {
                GoldKeyboardDismissButton(action: dismissKeyboard)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.9)),
                                removal: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.9))
                            )
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GoldTheme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GoldTheme.cardStroke)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0),
            value: layout.showsInlineDismissButton
        )
        .onAppear {
            if externalObserver == nil, keyboardVisibilityOverride == nil, ownedObserver == nil {
                ownedObserver = GoldKeyboardObserver()
            }
        }
    }
}

extension View {
    /// 统一为含数字键盘的表单添加交互式下滑收起；
    /// - `showToolbar == true`（默认）：兼容无底部操作栏页面，保留键盘顶部「完成」按钮；
    /// - `showToolbar == false`：适用于含 `.safeAreaInset(edge: .bottom)` 的表单页，不挂载 `ToolbarItemGroup(placement: .keyboard)`，
    ///   避免 iOS 26 Liquid Glass 透明浮层条在底部按钮与键盘之间制造留白缝隙。
    @ViewBuilder
    func goldKeyboardDismissable(showToolbar: Bool = true) -> some View {
        if showToolbar {
            self
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L10n.tr("完成")) {
                            GoldKeyboardDismissHelper.dismiss()
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(GoldTheme.gold)
                    }
                }
        } else {
            self.scrollDismissesKeyboard(.interactively)
        }
    }
}

struct GoldInputField: View {
    let title: String
    @Binding var text: String
    var placeholder = "0"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            TextField(placeholder, text: $text).keyboardType(.decimalPad)
                .font(.body).foregroundStyle(GoldTheme.text)
                .padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        }
    }
}

struct GoldRecoveryFields: View {
    @Binding var draft: HoldingDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("回收规则 · 当前参考金价为基准")).font(.subheadline.bold()).foregroundStyle(GoldTheme.gold)
            GoldInputField(title: L10n.tr("每克回收扣减（元/有效克）"), text: $draft.deductionText)
            GoldInputField(title: L10n.tr("比例折价（%）"), text: $draft.discountText)
            GoldInputField(title: L10n.tr("固定卖出费用（元/次）"), text: $draft.fixedFeeText)
            Text(L10n.tr("留空或全部为 0 时，尚未计入回收费用。请按实际回收渠道填写，这不是渠道报价。"))
                .font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }
    }
}

struct GoldResultMetric: View {
    let title: String
    let value: String
    var color = GoldTheme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Text(value).font(.system(.title3, design: .rounded).bold()).monospacedDigit()
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).goldCard()
    }
}

enum GoldReturnPresentation {
    /// Source rows and their subtotals format the same exact integer cents.
    static func centsMoney(_ cents: Decimal?, hidden: Bool = false, signed: Bool = true) -> String {
        if hidden { return "••••" }
        guard let cents else { return "—" }
        let amount = cents / 100
        let magnitude = amount < 0 ? -amount : amount
        let text = magnitude.formatted(.number.grouping(.never).precision(.fractionLength(2)))
        return "¥" + (amount < 0 ? "-" : signed ? "+" : "") + text
    }
    static func money(_ amount: Double?, hidden: Bool = false, signed: Bool = false) -> String {
        if hidden { return "••••" }
        guard let amount else { return "—" }
        let displayed = signed && abs(amount).moneyText == 0.0.moneyText ? 0.0 : amount
        return "¥" + (signed ? displayed.signedMoneyText : displayed.moneyText)
    }
    static func percent(_ value: Double?, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        return value.map { $0.signedMoneyText + "%" } ?? "—"
    }
    static func status(price: Double?, breakEven: Double?, hidden: Bool) -> String {
        guard let price = GoldReturnCalculator.validPrice(price), let breakEven else { return L10n.tr("获取参考金价后显示保本距离") }
        if hidden { return L10n.tr("保本距离 •••• 元/克") }
        let distance = price - breakEven
        return distance >= 0
            ? L10n.fmt("已超过真实保本线 ¥%@ / g", distance.moneyText)
            : L10n.fmt("距离真实保本还差 ¥%@ / g", (-distance).moneyText)
    }
    static func quoteStatus(_ quote: GoldQuote?, basis: GoldMarketBasis, failed: Bool = false, now: Date = .now) -> String {
        guard let quote else { return L10n.tr("参考金价暂不可用，仍可录入和查看保本价") }
        let stale = failed || now.timeIntervalSince(quote.asOf) > 300 || quote.asOf > now.addingTimeInterval(60)
        let time = quote.asOf.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLanguage.currentLocale))
        return stale
            ? L10n.fmt("%@参考 · 非实时 · %@", basis.title, time)
            : L10n.fmt("%@参考 · %@", basis.title, time)
    }
}

