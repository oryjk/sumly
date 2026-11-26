import SwiftUI

/// 7 位家庭成员暗黑金专属矢量头像：
/// 严格基于 `GoldTheme` 令牌绘制，零硬编码颜色；
/// 通过强辨识度发型、眼镜、胡须、皇冠/珍珠配饰与专属光环色，在 22pt 列表尺寸与 38pt 选择器尺寸下均一眼可辨。
struct HoldingHolderAvatar: View {
    let holder: HoldingHolder
    var size: CGFloat = 24
    var emphasized: Bool = true

    var body: some View {
        let accent = holder.accentColor
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 徽章深底 + 专属主题微光
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(emphasized ? 0.34 : 0.20),
                                GoldTheme.calendarCell,
                                GoldTheme.background
                            ],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: s * 0.04,
                            endRadius: s * 0.65
                        )
                    )

                // 角色专属矢量肖像
                Group {
                    switch holder {
                    case .mother:
                        MotherPortrait(accent: accent)
                    case .father:
                        FatherPortrait(accent: accent)
                    case .husband:
                        HusbandPortrait(accent: accent)
                    case .wife:
                        WifePortrait(accent: accent)
                    case .child:
                        ChildPortrait(accent: accent)
                    case .grandfather:
                        GrandfatherPortrait(accent: accent)
                    case .grandmother:
                        GrandmotherPortrait(accent: accent)
                    }
                }
                .clipShape(Circle())

                // 外圈高光描边
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accent.opacity(emphasized ? 0.92 : 0.55),
                                GoldTheme.goldSoft.opacity(emphasized ? 0.55 : 0.25),
                                accent.opacity(0.32)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1.0, s * 0.055)
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(holder.ownershipLabel)
    }
}

/// 表单/选择器用的「自己（未设置）」默认图标，与家人头像视觉尺寸一致。
struct HoldingSelfHolderGlyph: View {
    var size: CGFloat = 36
    var selected: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? GoldTheme.gold.opacity(0.22) : GoldTheme.calendarCell)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(selected ? GoldTheme.gold : GoldTheme.textSecondary)
            Circle()
                .strokeBorder(
                    selected ? GoldTheme.gold : GoldTheme.cardStroke,
                    lineWidth: max(1, size * 0.045)
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 详情页使用的持有人胶囊徽章（头像 + 「XX持有」）。
struct HoldingHolderBadge: View {
    let holder: HoldingHolder

    var body: some View {
        HStack(spacing: 6) {
            HoldingHolderAvatar(holder: holder, size: 20, emphasized: true)
            Text(holder.ownershipLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.text)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(GoldTheme.card, in: GoldTheme.capsuleShape)
        .overlay(
            GoldTheme.capsuleShape.strokeBorder(
                holder.accentColor.opacity(0.45),
                lineWidth: 1
            )
        )
    }
}

/// 记一笔 / 编辑持仓页面顶部可见的「在谁手上」横向快捷选择卡片。
struct HoldingHolderSelectorCard: View {
    @Binding var selected: HoldingHolder?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                Text(L10n.tr("在谁手上"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer(minLength: 6)
                Text(selected?.ownershipLabel ?? L10n.tr("自己持有"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected == nil ? GoldTheme.textFaint : GoldTheme.goldSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        selected == nil ? GoldTheme.background : GoldTheme.gold.opacity(0.14),
                        in: GoldTheme.capsuleShape
                    )
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(
                            selected == nil ? GoldTheme.cardStroke : GoldTheme.gold.opacity(0.35),
                            lineWidth: 1
                        )
                    )
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
            LazyVGrid(columns: columns, spacing: 8) {
                selfOptionChip
                ForEach(HoldingHolder.allCases) { holder in
                    holderOptionChip(holder)
                }
            }
        }
        .padding(14)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(
            GoldTheme.holdingsCardShape.strokeBorder(
                selected == nil ? GoldTheme.cardStroke : GoldTheme.gold.opacity(0.32),
                lineWidth: 1
            )
        )
    }

    private var selfOptionChip: some View {
        let isSelected = selected == nil
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selected = nil
            }
        } label: {
            VStack(spacing: 5) {
                HoldingSelfHolderGlyph(size: 34, selected: isSelected)
                Text(L10n.tr("自己"))
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? GoldTheme.goldSoft : GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? GoldTheme.gold.opacity(0.12) : GoldTheme.background,
                in: GoldTheme.subCardShape
            )
            .overlay(
                GoldTheme.subCardShape.strokeBorder(
                    isSelected ? GoldTheme.gold : GoldTheme.cardStroke,
                    lineWidth: isSelected ? 1.4 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("自己持有"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func holderOptionChip(_ holder: HoldingHolder) -> some View {
        let isSelected = selected == holder
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selected = (selected == holder) ? nil : holder
            }
        } label: {
            VStack(spacing: 5) {
                HoldingHolderAvatar(holder: holder, size: 34, emphasized: isSelected)
                Text(holder.displayName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? GoldTheme.goldSoft : GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? holder.accentColor.opacity(0.16) : GoldTheme.background,
                in: GoldTheme.subCardShape
            )
            .overlay(
                GoldTheme.subCardShape.strokeBorder(
                    isSelected ? holder.accentColor : GoldTheme.cardStroke,
                    lineWidth: isSelected ? 1.4 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(holder.ownershipLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 角色专属主题色（纯 GoldTheme 令牌）

extension HoldingHolder {
    var accentColor: Color {
        switch self {
        case .mother: GoldTheme.up
        case .father: GoldTheme.chartSecondary
        case .husband: GoldTheme.tempCool
        case .wife: GoldTheme.gold
        case .child: GoldTheme.tempWarm
        case .grandfather: GoldTheme.textSecondary
        case .grandmother: GoldTheme.goldSoft
        }
    }
}

// MARK: - 公共肖像调色板（纯 GoldTheme 派生）

private enum PortraitPalette {
    static let skinLight = GoldTheme.goldSoft
    static let skinMid = GoldTheme.gold.opacity(0.85)
    static let skinShade = GoldTheme.tempWarm.opacity(0.72)

    static let hairDark = GoldTheme.onGold
    static let hairDarkSheen = GoldTheme.calendarCell
    static let hairSilver = GoldTheme.text
    static let hairSilverShade = GoldTheme.serviceText

    static let eye = GoldTheme.onGold
    static let glasses = GoldTheme.onGold
    static let highlight = GoldTheme.text.opacity(0.95)
    static let blush = GoldTheme.up.opacity(0.45)

    static var skinGradient: LinearGradient {
        LinearGradient(
            colors: [skinLight, skinMid, skinShade],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var darkHairGradient: LinearGradient {
        LinearGradient(
            colors: [hairDarkSheen, hairDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var silverHairGradient: LinearGradient {
        LinearGradient(
            colors: [hairSilver, hairSilverShade],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 1. 母亲（优雅低盘发波浪轮廓 + 珍珠耳饰 + 柔和圆领）

private struct MotherPortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 后层蓬松齐肩波浪发
                MotherHairBackShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 柔美肩膀与衣领
                RoundedShouldersShape(widthRatio: 0.72, topY: 0.74)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 脖颈
                Capsule()
                    .fill(PortraitPalette.skinShade)
                    .frame(width: s * 0.16, height: s * 0.18)
                    .position(x: s * 0.50, y: s * 0.70)

                // 脸蛋
                Ellipse()
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.42, height: s * 0.45)
                    .position(x: s * 0.50, y: s * 0.47)

                // 温婉中分波浪前刘海
                MotherBangsShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 两侧珍珠耳饰（高辨识度点缀）
                Circle()
                    .fill(PortraitPalette.highlight)
                    .frame(width: max(2.2, s * 0.085), height: max(2.2, s * 0.085))
                    .position(x: s * 0.28, y: s * 0.55)
                Circle()
                    .fill(PortraitPalette.highlight)
                    .frame(width: max(2.2, s * 0.085), height: max(2.2, s * 0.085))
                    .position(x: s * 0.72, y: s * 0.55)

                // 柔和眉眼与微笑
                GentleFaceFeatures(eyeY: 0.48, mouthY: 0.58, scale: s)

                // 领口金色小吊坠
                Circle()
                    .fill(GoldTheme.goldSoft)
                    .frame(width: max(2.0, s * 0.075), height: max(2.0, s * 0.075))
                    .position(x: s * 0.50, y: s * 0.80)
            }
        }
    }
}

private struct MotherHairBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.14))
        p.addCurve(to: CGPoint(x: 0.80, y: 0.48), control1: CGPoint(x: 0.72, y: 0.14), control2: CGPoint(x: 0.82, y: 0.30))
        p.addCurve(to: CGPoint(x: 0.74, y: 0.74), control1: CGPoint(x: 0.82, y: 0.62), control2: CGPoint(x: 0.79, y: 0.70))
        p.addLine(to: CGPoint(x: 0.26, y: 0.74))
        p.addCurve(to: CGPoint(x: 0.20, y: 0.48), control1: CGPoint(x: 0.21, y: 0.70), control2: CGPoint(x: 0.18, y: 0.62))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.14), control1: CGPoint(x: 0.18, y: 0.30), control2: CGPoint(x: 0.28, y: 0.14))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct MotherBangsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.27, y: 0.44))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.31), control1: CGPoint(x: 0.31, y: 0.34), control2: CGPoint(x: 0.42, y: 0.30))
        p.addCurve(to: CGPoint(x: 0.73, y: 0.44), control1: CGPoint(x: 0.58, y: 0.30), control2: CGPoint(x: 0.69, y: 0.34))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.18), control1: CGPoint(x: 0.74, y: 0.26), control2: CGPoint(x: 0.64, y: 0.18))
        p.addCurve(to: CGPoint(x: 0.27, y: 0.44), control1: CGPoint(x: 0.36, y: 0.18), control2: CGPoint(x: 0.26, y: 0.26))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 2. 父亲（利落偏分短发 + 标志性方框眼镜 + 商务衬衫领带）

private struct FatherPortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 宽厚肩膀与西装
                RoundedShouldersShape(widthRatio: 0.80, topY: 0.73)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 白色衬衫 V 领 + 领带结
                FatherCollarShape()
                    .fill(PortraitPalette.highlight.opacity(0.9))
                FatherTieShape()
                    .fill(GoldTheme.onGold.opacity(0.85))

                // 脖颈
                Capsule()
                    .fill(PortraitPalette.skinShade)
                    .frame(width: s * 0.19, height: s * 0.16)
                    .position(x: s * 0.50, y: s * 0.70)

                // 稳重脸庞
                RoundedRectangle(cornerRadius: s * 0.20, style: .continuous)
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.42, height: s * 0.45)
                    .position(x: s * 0.50, y: s * 0.47)

                // 干练偏分短发
                FatherHairShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 标志性方框眼镜
                SquareGlassesOverlay(yRatio: 0.48, size: s)

                // 沉稳微笑
                SmileArcShape()
                    .stroke(PortraitPalette.eye.opacity(0.8), style: StrokeStyle(lineWidth: max(1.0, s * 0.036), lineCap: .round))
                    .frame(width: s * 0.14, height: s * 0.06)
                    .position(x: s * 0.50, y: s * 0.59)
            }
        }
    }
}

private struct FatherHairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.28, y: 0.43))
        p.addCurve(to: CGPoint(x: 0.30, y: 0.24), control1: CGPoint(x: 0.26, y: 0.33), control2: CGPoint(x: 0.27, y: 0.27))
        p.addCurve(to: CGPoint(x: 0.70, y: 0.24), control1: CGPoint(x: 0.38, y: 0.16), control2: CGPoint(x: 0.64, y: 0.16))
        p.addCurve(to: CGPoint(x: 0.72, y: 0.43), control1: CGPoint(x: 0.74, y: 0.29), control2: CGPoint(x: 0.74, y: 0.36))
        p.addLine(to: CGPoint(x: 0.69, y: 0.36))
        p.addCurve(to: CGPoint(x: 0.37, y: 0.33), control1: CGPoint(x: 0.62, y: 0.31), control2: CGPoint(x: 0.46, y: 0.30))
        p.addLine(to: CGPoint(x: 0.31, y: 0.37))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct FatherCollarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.39, y: 0.73))
        p.addLine(to: CGPoint(x: 0.50, y: 0.90))
        p.addLine(to: CGPoint(x: 0.61, y: 0.73))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct FatherTieShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.47, y: 0.77))
        p.addLine(to: CGPoint(x: 0.53, y: 0.77))
        p.addLine(to: CGPoint(x: 0.55, y: 0.96))
        p.addLine(to: CGPoint(x: 0.45, y: 0.96))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 3. 老公（年轻阳光微翘碎短发 + 无眼镜 + 简约圆领）

private struct HusbandPortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 简约活力圆领肩部
                RoundedShouldersShape(widthRatio: 0.78, topY: 0.74)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 圆领高光内边
                Circle()
                    .fill(GoldTheme.background.opacity(0.38))
                    .frame(width: s * 0.24, height: s * 0.14)
                    .position(x: s * 0.50, y: s * 0.77)

                // 脖颈
                Capsule()
                    .fill(PortraitPalette.skinShade)
                    .frame(width: s * 0.18, height: s * 0.16)
                    .position(x: s * 0.50, y: s * 0.70)

                // 俊朗脸型
                RoundedRectangle(cornerRadius: s * 0.20, style: .continuous)
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.42, height: s * 0.45)
                    .position(x: s * 0.50, y: s * 0.48)

                // 年轻蓬松微翘短发（带斜刘海尖角）
                HusbandHairShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 清晰双眼与阳光笑脸（无眼镜，与父亲明显区分）
                GentleFaceFeatures(eyeY: 0.49, mouthY: 0.60, scale: s, strongBrows: true)
            }
        }
    }
}

private struct HusbandHairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.28, y: 0.44))
        p.addCurve(to: CGPoint(x: 0.30, y: 0.21), control1: CGPoint(x: 0.24, y: 0.32), control2: CGPoint(x: 0.25, y: 0.24))
        p.addQuadCurve(to: CGPoint(x: 0.52, y: 0.15), control: CGPoint(x: 0.39, y: 0.14))
        // 前额微翘层次尖角
        p.addQuadCurve(to: CGPoint(x: 0.74, y: 0.26), control: CGPoint(x: 0.68, y: 0.16))
        p.addCurve(to: CGPoint(x: 0.72, y: 0.44), control1: CGPoint(x: 0.76, y: 0.32), control2: CGPoint(x: 0.75, y: 0.39))
        p.addLine(to: CGPoint(x: 0.68, y: 0.36))
        p.addLine(to: CGPoint(x: 0.58, y: 0.39))
        p.addLine(to: CGPoint(x: 0.52, y: 0.33))
        p.addLine(to: CGPoint(x: 0.40, y: 0.38))
        p.addLine(to: CGPoint(x: 0.31, y: 0.35))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 4. 老婆（飘逸长披肩发 + 闪耀迷你小皇冠发饰）

private struct WifePortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 飘逸长披肩发
                WifeLongHairShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 柔美衣领
                RoundedShouldersShape(widthRatio: 0.70, topY: 0.75)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), GoldTheme.tempWarm.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 脖颈
                Capsule()
                    .fill(PortraitPalette.skinShade)
                    .frame(width: s * 0.15, height: s * 0.16)
                    .position(x: s * 0.50, y: s * 0.71)

                // 甜美脸庞
                Ellipse()
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.40, height: s * 0.43)
                    .position(x: s * 0.50, y: s * 0.50)

                // 轻盈斜刘海
                WifeBangsShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 标志性迷你金色小皇冠（与母亲一眼区分！）
                MiniCrownShape()
                    .fill(
                        LinearGradient(
                            colors: [PortraitPalette.highlight, GoldTheme.goldSoft, GoldTheme.gold],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 柔和甜美五官 + 淡淡腮红
                GentleFaceFeatures(eyeY: 0.51, mouthY: 0.61, scale: s, showBlush: true)
            }
        }
    }
}

private struct WifeLongHairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.21))
        p.addCurve(to: CGPoint(x: 0.79, y: 0.56), control1: CGPoint(x: 0.73, y: 0.21), control2: CGPoint(x: 0.80, y: 0.36))
        p.addCurve(to: CGPoint(x: 0.82, y: 0.88), control1: CGPoint(x: 0.79, y: 0.72), control2: CGPoint(x: 0.84, y: 0.80))
        p.addLine(to: CGPoint(x: 0.18, y: 0.88))
        p.addCurve(to: CGPoint(x: 0.21, y: 0.56), control1: CGPoint(x: 0.16, y: 0.80), control2: CGPoint(x: 0.21, y: 0.72))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.21), control1: CGPoint(x: 0.20, y: 0.36), control2: CGPoint(x: 0.27, y: 0.21))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct WifeBangsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.28, y: 0.47))
        p.addCurve(to: CGPoint(x: 0.62, y: 0.36), control1: CGPoint(x: 0.36, y: 0.37), control2: CGPoint(x: 0.50, y: 0.36))
        p.addCurve(to: CGPoint(x: 0.72, y: 0.47), control1: CGPoint(x: 0.68, y: 0.37), control2: CGPoint(x: 0.71, y: 0.41))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.23), control1: CGPoint(x: 0.72, y: 0.30), control2: CGPoint(x: 0.63, y: 0.23))
        p.addCurve(to: CGPoint(x: 0.28, y: 0.47), control1: CGPoint(x: 0.37, y: 0.23), control2: CGPoint(x: 0.28, y: 0.30))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct MiniCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.36, y: 0.25))
        p.addLine(to: CGPoint(x: 0.33, y: 0.13))
        p.addLine(to: CGPoint(x: 0.44, y: 0.19))
        p.addLine(to: CGPoint(x: 0.50, y: 0.09))
        p.addLine(to: CGPoint(x: 0.56, y: 0.19))
        p.addLine(to: CGPoint(x: 0.67, y: 0.13))
        p.addLine(to: CGPoint(x: 0.64, y: 0.25))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 5. 孩子（圆润幼态比例 + 俏皮呆毛 + 圆脸腮红）

private struct ChildPortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 小巧肩膀
                RoundedShouldersShape(widthRatio: 0.62, topY: 0.78)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 圆润可爱的娃娃脸（大头圆脸比例）
                Circle()
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.48, height: s * 0.46)
                    .position(x: s * 0.50, y: s * 0.54)

                // 可爱圆刘海 + 头顶俏皮小呆毛
                ChildHairShape()
                    .fill(PortraitPalette.darkHairGradient)

                // 圆溜溜大眼睛 + 暖红腮红 + 开心笑脸
                GentleFaceFeatures(eyeY: 0.55, mouthY: 0.65, scale: s, showBlush: true, bigEyes: true)
            }
        }
    }
}

private struct ChildHairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 顶部圆润发冠
        p.move(to: CGPoint(x: 0.25, y: 0.52))
        p.addCurve(to: CGPoint(x: 0.48, y: 0.28), control1: CGPoint(x: 0.24, y: 0.36), control2: CGPoint(x: 0.34, y: 0.28))
        // 头顶俏皮卷翘呆毛
        p.addCurve(to: CGPoint(x: 0.56, y: 0.16), control1: CGPoint(x: 0.46, y: 0.20), control2: CGPoint(x: 0.52, y: 0.15))
        p.addCurve(to: CGPoint(x: 0.55, y: 0.28), control1: CGPoint(x: 0.58, y: 0.20), control2: CGPoint(x: 0.57, y: 0.24))
        p.addCurve(to: CGPoint(x: 0.75, y: 0.52), control1: CGPoint(x: 0.68, y: 0.29), control2: CGPoint(x: 0.76, y: 0.38))
        p.addQuadCurve(to: CGPoint(x: 0.50, y: 0.43), control: CGPoint(x: 0.64, y: 0.43))
        p.addQuadCurve(to: CGPoint(x: 0.25, y: 0.52), control: CGPoint(x: 0.36, y: 0.43))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 6. 爷爷（银白两鬓 + 经典圆眼镜 + 标志性白胡子）

private struct GrandfatherPortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 温和立领毛衣肩部
                RoundedShouldersShape(widthRatio: 0.78, topY: 0.74)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.90), GoldTheme.calendarCell],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 脖颈
                Capsule()
                    .fill(PortraitPalette.skinShade)
                    .frame(width: s * 0.18, height: s * 0.15)
                    .position(x: s * 0.50, y: s * 0.71)

                // 银白色两鬓白发（突出在脸两侧，经典老爷爷特征）
                Circle()
                    .fill(PortraitPalette.silverHairGradient)
                    .frame(width: s * 0.18, height: s * 0.20)
                    .position(x: s * 0.27, y: s * 0.42)
                Circle()
                    .fill(PortraitPalette.silverHairGradient)
                    .frame(width: s * 0.18, height: s * 0.20)
                    .position(x: s * 0.73, y: s * 0.42)

                // 慈祥圆润脸庞（顶部露额头）
                Ellipse()
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.44, height: s * 0.47)
                    .position(x: s * 0.50, y: s * 0.47)

                // 顶部稀疏银发边
                GrandfatherTopHairShape()
                    .fill(PortraitPalette.silverHairGradient)

                // 经典圆眼镜
                RoundGlassesOverlay(yRatio: 0.47, size: s)

                // 标志性银白八字胡子（极高辨识度）
                GrandfatherMustacheShape()
                    .fill(PortraitPalette.silverHairGradient)
            }
        }
    }
}

private struct GrandfatherTopHairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.27, y: 0.42))
        p.addCurve(to: CGPoint(x: 0.35, y: 0.27), control1: CGPoint(x: 0.27, y: 0.34), control2: CGPoint(x: 0.30, y: 0.29))
        p.addQuadCurve(to: CGPoint(x: 0.31, y: 0.42), control: CGPoint(x: 0.32, y: 0.35))
        p.closeSubpath()

        p.move(to: CGPoint(x: 0.73, y: 0.42))
        p.addCurve(to: CGPoint(x: 0.65, y: 0.27), control1: CGPoint(x: 0.73, y: 0.34), control2: CGPoint(x: 0.70, y: 0.29))
        p.addQuadCurve(to: CGPoint(x: 0.69, y: 0.42), control: CGPoint(x: 0.68, y: 0.35))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GrandfatherMustacheShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.56))
        p.addCurve(to: CGPoint(x: 0.34, y: 0.62), control1: CGPoint(x: 0.44, y: 0.54), control2: CGPoint(x: 0.36, y: 0.57))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.62), control1: CGPoint(x: 0.38, y: 0.65), control2: CGPoint(x: 0.46, y: 0.64))
        p.addCurve(to: CGPoint(x: 0.66, y: 0.62), control1: CGPoint(x: 0.54, y: 0.64), control2: CGPoint(x: 0.62, y: 0.65))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.56), control1: CGPoint(x: 0.64, y: 0.57), control2: CGPoint(x: 0.56, y: 0.54))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 7. 奶奶（银白头顶高盘丸子发髻 + 圆眼镜 + 珍珠项链）

private struct GrandmotherPortrait: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 标志性头顶银白高盘发髻（Top Bun，极高辨识度）
                Circle()
                    .fill(PortraitPalette.silverHairGradient)
                    .frame(width: s * 0.28, height: s * 0.24)
                    .position(x: s * 0.50, y: s * 0.18)

                // 后层柔和银白盘发轮廓
                Ellipse()
                    .fill(PortraitPalette.silverHairGradient)
                    .frame(width: s * 0.56, height: s * 0.48)
                    .position(x: s * 0.50, y: s * 0.45)

                // 温润衣领肩部
                RoundedShouldersShape(widthRatio: 0.72, topY: 0.75)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.82), GoldTheme.tempWarm.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 脖颈
                Capsule()
                    .fill(PortraitPalette.skinShade)
                    .frame(width: s * 0.16, height: s * 0.15)
                    .position(x: s * 0.50, y: s * 0.71)

                // 慈祥脸庞
                Ellipse()
                    .fill(PortraitPalette.skinGradient)
                    .frame(width: s * 0.41, height: s * 0.43)
                    .position(x: s * 0.50, y: s * 0.50)

                // 柔和中分银白前发
                GrandmotherBangsShape()
                    .fill(PortraitPalette.silverHairGradient)

                // 慈祥圆眼镜
                RoundGlassesOverlay(yRatio: 0.50, size: s)

                // 慈祥微笑
                SmileArcShape()
                    .stroke(PortraitPalette.eye.opacity(0.8), style: StrokeStyle(lineWidth: max(1.0, s * 0.036), lineCap: .round))
                    .frame(width: s * 0.13, height: s * 0.055)
                    .position(x: s * 0.50, y: s * 0.62)

                // 颈间三颗精致珍珠
                HStack(spacing: s * 0.025) {
                    Circle().fill(PortraitPalette.highlight).frame(width: max(2.0, s * 0.065), height: max(2.0, s * 0.065))
                    Circle().fill(PortraitPalette.highlight).frame(width: max(2.2, s * 0.075), height: max(2.2, s * 0.075))
                    Circle().fill(PortraitPalette.highlight).frame(width: max(2.0, s * 0.065), height: max(2.0, s * 0.065))
                }
                .position(x: s * 0.50, y: s * 0.79)
            }
        }
    }
}

private struct GrandmotherBangsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.28, y: 0.46))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.35), control1: CGPoint(x: 0.33, y: 0.37), control2: CGPoint(x: 0.43, y: 0.34))
        p.addCurve(to: CGPoint(x: 0.72, y: 0.46), control1: CGPoint(x: 0.57, y: 0.34), control2: CGPoint(x: 0.67, y: 0.37))
        p.addCurve(to: CGPoint(x: 0.50, y: 0.25), control1: CGPoint(x: 0.72, y: 0.30), control2: CGPoint(x: 0.63, y: 0.25))
        p.addCurve(to: CGPoint(x: 0.28, y: 0.46), control1: CGPoint(x: 0.37, y: 0.25), control2: CGPoint(x: 0.28, y: 0.30))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 公共五官与几何辅助图形

private struct RoundedShouldersShape: Shape {
    let widthRatio: CGFloat
    let topY: CGFloat

    func path(in rect: CGRect) -> Path {
        let half = widthRatio / 2
        var p = Path()
        p.move(to: CGPoint(x: 0.50 - half, y: 1.04))
        p.addCurve(
            to: CGPoint(x: 0.50, y: topY),
            control1: CGPoint(x: 0.50 - half, y: topY + 0.04),
            control2: CGPoint(x: 0.50 - half * 0.45, y: topY)
        )
        p.addCurve(
            to: CGPoint(x: 0.50 + half, y: 1.04),
            control1: CGPoint(x: 0.50 + half * 0.45, y: topY),
            control2: CGPoint(x: 0.50 + half, y: topY + 0.04)
        )
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GentleFaceFeatures: View {
    let eyeY: CGFloat
    let mouthY: CGFloat
    let scale: CGFloat
    var showBlush: Bool = false
    var bigEyes: Bool = false
    var strongBrows: Bool = false

    var body: some View {
        let eyeSize = max(1.8, scale * (bigEyes ? 0.075 : 0.058))
        ZStack {
            if strongBrows {
                Capsule()
                    .fill(PortraitPalette.eye.opacity(0.85))
                    .frame(width: scale * 0.10, height: max(1.0, scale * 0.028))
                    .position(x: scale * 0.41, y: scale * (eyeY - 0.065))
                Capsule()
                    .fill(PortraitPalette.eye.opacity(0.85))
                    .frame(width: scale * 0.10, height: max(1.0, scale * 0.028))
                    .position(x: scale * 0.59, y: scale * (eyeY - 0.065))
            }

            Circle()
                .fill(PortraitPalette.eye)
                .frame(width: eyeSize, height: eyeSize)
                .position(x: scale * 0.41, y: scale * eyeY)
            Circle()
                .fill(PortraitPalette.eye)
                .frame(width: eyeSize, height: eyeSize)
                .position(x: scale * 0.59, y: scale * eyeY)

            if showBlush {
                Ellipse()
                    .fill(PortraitPalette.blush)
                    .frame(width: scale * 0.10, height: scale * 0.055)
                    .position(x: scale * 0.35, y: scale * (eyeY + 0.07))
                Ellipse()
                    .fill(PortraitPalette.blush)
                    .frame(width: scale * 0.10, height: scale * 0.055)
                    .position(x: scale * 0.65, y: scale * (eyeY + 0.07))
            }

            SmileArcShape()
                .stroke(PortraitPalette.eye.opacity(0.82), style: StrokeStyle(lineWidth: max(1.0, scale * 0.036), lineCap: .round))
                .frame(width: scale * 0.14, height: scale * 0.06)
                .position(x: scale * 0.50, y: scale * mouthY)
        }
    }
}

private struct SmileArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return p
    }
}

private struct SquareGlassesOverlay: View {
    let yRatio: CGFloat
    let size: CGFloat

    var body: some View {
        let lensW = size * 0.165
        let lensH = size * 0.115
        let stroke = max(1.1, size * 0.042)
        ZStack {
            // 镜片微反光底
            RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                .fill(GoldTheme.background.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                        .strokeBorder(PortraitPalette.glasses, lineWidth: stroke)
                )
                .frame(width: lensW, height: lensH)
                .position(x: size * 0.405, y: size * yRatio)

            RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                .fill(GoldTheme.background.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                        .strokeBorder(PortraitPalette.glasses, lineWidth: stroke)
                )
                .frame(width: lensW, height: lensH)
                .position(x: size * 0.595, y: size * yRatio)

            // 鼻梁连接横杠
            Rectangle()
                .fill(PortraitPalette.glasses)
                .frame(width: size * 0.04, height: stroke)
                .position(x: size * 0.50, y: size * yRatio)

            // 镜片内眼点
            Circle()
                .fill(PortraitPalette.eye)
                .frame(width: max(1.5, size * 0.045), height: max(1.5, size * 0.045))
                .position(x: size * 0.405, y: size * yRatio)
            Circle()
                .fill(PortraitPalette.eye)
                .frame(width: max(1.5, size * 0.045), height: max(1.5, size * 0.045))
                .position(x: size * 0.595, y: size * yRatio)
        }
    }
}

private struct RoundGlassesOverlay: View {
    let yRatio: CGFloat
    let size: CGFloat

    var body: some View {
        let diameter = size * 0.155
        let stroke = max(1.0, size * 0.038)
        ZStack {
            Circle()
                .fill(GoldTheme.background.opacity(0.16))
                .overlay(Circle().strokeBorder(PortraitPalette.glasses, lineWidth: stroke))
                .frame(width: diameter, height: diameter)
                .position(x: size * 0.405, y: size * yRatio)

            Circle()
                .fill(GoldTheme.background.opacity(0.16))
                .overlay(Circle().strokeBorder(PortraitPalette.glasses, lineWidth: stroke))
                .frame(width: diameter, height: diameter)
                .position(x: size * 0.595, y: size * yRatio)

            Rectangle()
                .fill(PortraitPalette.glasses)
                .frame(width: size * 0.04, height: stroke)
                .position(x: size * 0.50, y: size * yRatio)

            Circle()
                .fill(PortraitPalette.eye)
                .frame(width: max(1.4, size * 0.042), height: max(1.4, size * 0.042))
                .position(x: size * 0.405, y: size * yRatio)
            Circle()
                .fill(PortraitPalette.eye)
                .frame(width: max(1.4, size * 0.042), height: max(1.4, size * 0.042))
                .position(x: size * 0.595, y: size * yRatio)
        }
    }
}
