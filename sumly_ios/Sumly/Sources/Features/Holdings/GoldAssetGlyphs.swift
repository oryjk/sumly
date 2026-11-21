import SwiftUI

/// 现代暗金质感矢量图标：严格基于 `GoldTheme` 令牌与光影渐变绘制，零硬编码任意颜色。
struct GoldAssetGlyph: View {
    let type: GoldAssetType
    var size: CGFloat = 36
    var emphasized: Bool = true

    var body: some View {
        Group {
            switch type {
            case .bean:
                GoldBeanGlyph(emphasized: emphasized)
            case .bar:
                GoldBarGlyph(emphasized: emphasized)
            case .jewelry:
                GoldJewelryGlyph(emphasized: emphasized)
            case .accumulation:
                GoldAccumulationGlyph(emphasized: emphasized)
            case .other:
                GoldOtherGlyph(emphasized: emphasized)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 通用金属色板（纯 GoldTheme 派生）

private enum GoldMetalPalette {
    static let specular = GoldTheme.text.opacity(0.92)
    static let bright = GoldTheme.goldSoft
    static let mid = GoldTheme.gold
    static let deep = GoldTheme.tempWarm
    static let shadow = GoldTheme.onGold
    static let obsidian = GoldTheme.card

    static func sheenGradient(emphasized: Bool) -> LinearGradient {
        LinearGradient(
            colors: emphasized
                ? [bright, mid, deep]
                : [bright.opacity(0.82), mid.opacity(0.82), deep.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 1. 金豆（饱满立体圆润金豆 + 弧形镜面高光 + 底部投影）

private struct GoldBeanGlyph: View {
    let emphasized: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 底部接触投影
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [GoldMetalPalette.shadow.opacity(0.62), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: s * 0.42
                        )
                    )
                    .frame(width: s * 0.72, height: s * 0.20)
                    .offset(y: s * 0.34)

                // 金豆主体：立体球面金属渐变
                GoldBeanBodyShape()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: emphasized ? GoldMetalPalette.specular : GoldMetalPalette.bright, location: 0.02),
                                .init(color: GoldMetalPalette.bright, location: 0.24),
                                .init(color: GoldMetalPalette.mid, location: 0.56),
                                .init(color: GoldMetalPalette.deep, location: 0.84),
                                .init(color: GoldMetalPalette.shadow.opacity(0.68), location: 1.0)
                            ]),
                            center: UnitPoint(x: 0.34, y: 0.30),
                            startRadius: s * 0.02,
                            endRadius: s * 0.58
                        )
                    )

                // 右下暖金环境反光带
                GoldBeanRimBounceShape()
                    .stroke(
                        LinearGradient(
                            colors: [.clear, GoldMetalPalette.bright.opacity(emphasized ? 0.58 : 0.38), .clear],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        ),
                        style: StrokeStyle(lineWidth: max(1.2, s * 0.055), lineCap: .round)
                    )

                // 顶部左侧弧形镜面高光
                GoldBeanHighlightShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.specular.opacity(emphasized ? 0.94 : 0.72),
                                GoldMetalPalette.bright.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 次级高光点
                Circle()
                    .fill(GoldMetalPalette.specular.opacity(emphasized ? 0.92 : 0.65))
                    .frame(width: max(2.2, s * 0.095), height: max(2.2, s * 0.095))
                    .offset(x: -s * 0.03, y: -s * 0.22)

                // 细腻高光描边
                GoldBeanBodyShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.bright.opacity(emphasized ? 0.85 : 0.55),
                                GoldMetalPalette.mid.opacity(0.45),
                                GoldMetalPalette.shadow.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(0.8, s * 0.026)
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct GoldBeanBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 柔和有机饱满金豆轮廓：顶部略收、底部圆润厚实
        p.move(to: CGPoint(x: 0.46, y: 0.16))
        p.addCurve(
            to: CGPoint(x: 0.85, y: 0.48),
            control1: CGPoint(x: 0.69, y: 0.15),
            control2: CGPoint(x: 0.86, y: 0.29)
        )
        p.addCurve(
            to: CGPoint(x: 0.54, y: 0.86),
            control1: CGPoint(x: 0.84, y: 0.72),
            control2: CGPoint(x: 0.73, y: 0.86)
        )
        p.addCurve(
            to: CGPoint(x: 0.14, y: 0.58),
            control1: CGPoint(x: 0.30, y: 0.86),
            control2: CGPoint(x: 0.14, y: 0.76)
        )
        p.addCurve(
            to: CGPoint(x: 0.46, y: 0.16),
            control1: CGPoint(x: 0.14, y: 0.35),
            control2: CGPoint(x: 0.26, y: 0.17)
        )
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBeanHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.26, y: 0.45))
        p.addCurve(
            to: CGPoint(x: 0.44, y: 0.24),
            control1: CGPoint(x: 0.24, y: 0.34),
            control2: CGPoint(x: 0.33, y: 0.26)
        )
        p.addCurve(
            to: CGPoint(x: 0.47, y: 0.31),
            control1: CGPoint(x: 0.48, y: 0.24),
            control2: CGPoint(x: 0.50, y: 0.28)
        )
        p.addCurve(
            to: CGPoint(x: 0.33, y: 0.47),
            control1: CGPoint(x: 0.39, y: 0.34),
            control2: CGPoint(x: 0.34, y: 0.40)
        )
        p.addCurve(
            to: CGPoint(x: 0.26, y: 0.45),
            control1: CGPoint(x: 0.31, y: 0.50),
            control2: CGPoint(x: 0.27, y: 0.49)
        )
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBeanRimBounceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.77, y: 0.56))
        p.addCurve(
            to: CGPoint(x: 0.50, y: 0.80),
            control1: CGPoint(x: 0.75, y: 0.72),
            control2: CGPoint(x: 0.64, y: 0.80)
        )
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 2. 金条（斜切立体梯形金砖 + 顶部高光斜面 + 9999 压纹线条）

private struct GoldBarGlyph: View {
    let emphasized: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 底部斜向投影
                GoldBarShadowShape()
                    .fill(GoldMetalPalette.shadow.opacity(0.55))
                    .blur(radius: max(1.0, s * 0.04))

                // 左侧前斜面（厚重暗金）
                GoldBarFrontFaceShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.deep,
                                GoldMetalPalette.shadow.opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 右侧斜面（温润中金）
                GoldBarSideFaceShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.mid,
                                GoldMetalPalette.deep,
                                GoldMetalPalette.shadow.opacity(0.52)
                            ],
                            startPoint: .top,
                            endPoint: .bottomTrailing
                        )
                    )

                // 顶面平整斜面（亮金拉丝渐变）
                GoldBarTopFaceShape()
                    .fill(
                        LinearGradient(
                            colors: emphasized
                                ? [GoldMetalPalette.bright, GoldMetalPalette.mid, GoldMetalPalette.deep]
                                : [GoldMetalPalette.bright.opacity(0.84), GoldMetalPalette.mid.opacity(0.82), GoldMetalPalette.deep.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 顶面镜面扫光带
                GoldBarSheenShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.specular.opacity(emphasized ? 0.62 : 0.42),
                                GoldMetalPalette.bright.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(GoldBarTopFaceShape())

                // 顶面细刻 9999 压纹（阴刻 + 亮边浮雕）
                GoldBarEngravingShape()
                    .stroke(
                        GoldMetalPalette.shadow.opacity(0.46),
                        style: StrokeStyle(lineWidth: max(0.85, s * 0.03), lineCap: .round, lineJoin: .round)
                    )
                GoldBarEngravingShape()
                    .stroke(
                        GoldMetalPalette.bright.opacity(0.52),
                        style: StrokeStyle(lineWidth: max(0.55, s * 0.018), lineCap: .round, lineJoin: .round)
                    )
                    .offset(x: max(0.4, s * 0.014), y: max(0.4, s * 0.014))

                // 顶面棱线镜面高光
                GoldBarTopFaceShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.specular.opacity(0.82),
                                GoldMetalPalette.bright.opacity(0.45),
                                GoldMetalPalette.shadow.opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(0.75, s * 0.025)
                    )

                // 整体外轮廓收边
                GoldBarOuterSilhouetteShape()
                    .stroke(GoldMetalPalette.shadow.opacity(0.32), lineWidth: max(0.6, s * 0.018))
            }
            .scaleEffect(1.08)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct GoldBarShadowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.14, y: 0.68))
        p.addLine(to: CGPoint(x: 0.43, y: 0.87))
        p.addLine(to: CGPoint(x: 0.90, y: 0.56))
        p.addLine(to: CGPoint(x: 0.64, y: 0.42))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBarTopFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.18, y: 0.50))
        p.addLine(to: CGPoint(x: 0.59, y: 0.21))
        p.addLine(to: CGPoint(x: 0.81, y: 0.34))
        p.addLine(to: CGPoint(x: 0.41, y: 0.66))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBarFrontFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.18, y: 0.50))
        p.addLine(to: CGPoint(x: 0.41, y: 0.66))
        p.addLine(to: CGPoint(x: 0.43, y: 0.82))
        p.addLine(to: CGPoint(x: 0.11, y: 0.62))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBarSideFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.41, y: 0.66))
        p.addLine(to: CGPoint(x: 0.81, y: 0.34))
        p.addLine(to: CGPoint(x: 0.89, y: 0.49))
        p.addLine(to: CGPoint(x: 0.43, y: 0.82))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBarOuterSilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.18, y: 0.50))
        p.addLine(to: CGPoint(x: 0.59, y: 0.21))
        p.addLine(to: CGPoint(x: 0.81, y: 0.34))
        p.addLine(to: CGPoint(x: 0.89, y: 0.49))
        p.addLine(to: CGPoint(x: 0.43, y: 0.82))
        p.addLine(to: CGPoint(x: 0.11, y: 0.62))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBarSheenShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.25, y: 0.34))
        p.addLine(to: CGPoint(x: 0.55, y: 0.18))
        p.addLine(to: CGPoint(x: 0.65, y: 0.36))
        p.addLine(to: CGPoint(x: 0.35, y: 0.58))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldBarEngravingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 内框印记（沿顶面透视方向）
        p.move(to: CGPoint(x: 0.28, y: 0.49))
        p.addLine(to: CGPoint(x: 0.58, y: 0.28))
        p.addLine(to: CGPoint(x: 0.72, y: 0.36))
        p.addLine(to: CGPoint(x: 0.42, y: 0.58))
        p.closeSubpath()
        // 内部 9999 压纹细刻线条
        p.move(to: CGPoint(x: 0.39, y: 0.48))
        p.addLine(to: CGPoint(x: 0.55, y: 0.37))
        p.move(to: CGPoint(x: 0.44, y: 0.51))
        p.addLine(to: CGPoint(x: 0.60, y: 0.40))
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 3. 金饰（精致细链环 + 雕刻扣头 + 多切面水滴/菱钻黄金吊坠 + 折射高光）

private struct GoldJewelryGlyph: View {
    let emphasized: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 柔和金光氛围光晕（仅在强调态微微透出）
                if emphasized {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [GoldMetalPalette.mid.opacity(0.24), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: s * 0.46
                            )
                        )
                        .frame(width: s * 0.76, height: s * 0.76)
                        .offset(y: s * 0.16)
                }

                // 精致项链主链条
                GoldNecklaceChainShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.deep.opacity(0.85),
                                GoldMetalPalette.bright,
                                GoldMetalPalette.mid,
                                GoldMetalPalette.bright,
                                GoldMetalPalette.deep.opacity(0.85)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: max(1.15, s * 0.042), lineCap: .round, lineJoin: .round)
                    )

                // 链条高光链节珠点，营造真实 24K 细金链闪耀质感
                GoldNecklaceBeadsShape()
                    .fill(GoldMetalPalette.specular.opacity(emphasized ? 0.85 : 0.58))

                // 吊坠 V 形雕刻扣头（Bail）
                GoldPendantBailShape()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.specular.opacity(0.85), GoldMetalPalette.mid, GoldMetalPalette.deep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                GoldPendantBailShape()
                    .stroke(GoldMetalPalette.bright.opacity(0.8), lineWidth: max(0.65, s * 0.02))

                // 吊坠外层雕塑感黄金包边（Teardrop Bezel）
                GoldPendantBezelShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.bright,
                                GoldMetalPalette.mid,
                                GoldMetalPalette.deep,
                                GoldMetalPalette.shadow.opacity(0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 内凹暗金托槽，增强立体镶嵌景深
                GoldPendantInnerWellShape()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.shadow.opacity(0.68), GoldMetalPalette.obsidian],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 多切面黄金菱钻主石（四向光影切面 + 中央台面）
                GoldPendantFacetTopLeft()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.specular, GoldMetalPalette.bright],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                GoldPendantFacetTopRight()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.bright, GoldMetalPalette.mid],
                            startPoint: .top,
                            endPoint: .bottomTrailing
                        )
                    )
                GoldPendantFacetBottomLeft()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.mid, GoldMetalPalette.deep],
                            startPoint: .topLeading,
                            endPoint: .bottom
                        )
                    )
                GoldPendantFacetBottomRight()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.deep, GoldMetalPalette.shadow.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottomTrailing
                        )
                    )

                // 中央镜面菱形台面
                GoldPendantCenterTable()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.specular.opacity(0.95),
                                GoldMetalPalette.bright,
                                GoldMetalPalette.mid
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 切面折光棱线
                GoldPendantFacetLines()
                    .stroke(GoldMetalPalette.specular.opacity(0.58), lineWidth: max(0.5, s * 0.016))

                // 外圈金边镜面高光描边
                GoldPendantBezelShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                GoldMetalPalette.specular.opacity(0.88),
                                GoldMetalPalette.bright.opacity(0.55),
                                GoldMetalPalette.deep.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(0.85, s * 0.025)
                    )

                // 左上冠部四角星耀折光点
                GoldStarGlintShape()
                    .fill(GoldMetalPalette.specular.opacity(emphasized ? 0.96 : 0.72))
                    .frame(width: s * 0.24, height: s * 0.24)
                    .position(x: geo.size.width * 0.37, y: geo.size.height * 0.60)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct GoldNecklaceChainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.14, y: 0.09))
        p.addCurve(
            to: CGPoint(x: 0.50, y: 0.37),
            control1: CGPoint(x: 0.20, y: 0.26),
            control2: CGPoint(x: 0.34, y: 0.37)
        )
        p.addCurve(
            to: CGPoint(x: 0.86, y: 0.09),
            control1: CGPoint(x: 0.66, y: 0.37),
            control2: CGPoint(x: 0.80, y: 0.26)
        )
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldNecklaceBeadsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let centers: [CGPoint] = [
            CGPoint(x: 0.20, y: 0.18),
            CGPoint(x: 0.29, y: 0.28),
            CGPoint(x: 0.39, y: 0.34),
            CGPoint(x: 0.61, y: 0.34),
            CGPoint(x: 0.71, y: 0.28),
            CGPoint(x: 0.80, y: 0.18)
        ]
        let radius: CGFloat = 0.022
        for c in centers {
            p.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantBailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.31))
        p.addQuadCurve(to: CGPoint(x: 0.56, y: 0.40), control: CGPoint(x: 0.57, y: 0.34))
        p.addLine(to: CGPoint(x: 0.525, y: 0.47))
        p.addLine(to: CGPoint(x: 0.475, y: 0.47))
        p.addLine(to: CGPoint(x: 0.44, y: 0.40))
        p.addQuadCurve(to: CGPoint(x: 0.50, y: 0.31), control: CGPoint(x: 0.43, y: 0.34))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantBezelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.43))
        p.addCurve(
            to: CGPoint(x: 0.74, y: 0.72),
            control1: CGPoint(x: 0.61, y: 0.50),
            control2: CGPoint(x: 0.75, y: 0.60)
        )
        p.addCurve(
            to: CGPoint(x: 0.50, y: 0.94),
            control1: CGPoint(x: 0.73, y: 0.85),
            control2: CGPoint(x: 0.63, y: 0.94)
        )
        p.addCurve(
            to: CGPoint(x: 0.26, y: 0.72),
            control1: CGPoint(x: 0.37, y: 0.94),
            control2: CGPoint(x: 0.27, y: 0.85)
        )
        p.addCurve(
            to: CGPoint(x: 0.50, y: 0.43),
            control1: CGPoint(x: 0.25, y: 0.60),
            control2: CGPoint(x: 0.39, y: 0.50)
        )
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantInnerWellShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.48))
        p.addCurve(
            to: CGPoint(x: 0.69, y: 0.72),
            control1: CGPoint(x: 0.59, y: 0.54),
            control2: CGPoint(x: 0.70, y: 0.62)
        )
        p.addCurve(
            to: CGPoint(x: 0.50, y: 0.89),
            control1: CGPoint(x: 0.68, y: 0.82),
            control2: CGPoint(x: 0.60, y: 0.89)
        )
        p.addCurve(
            to: CGPoint(x: 0.31, y: 0.72),
            control1: CGPoint(x: 0.40, y: 0.89),
            control2: CGPoint(x: 0.32, y: 0.82)
        )
        p.addCurve(
            to: CGPoint(x: 0.50, y: 0.48),
            control1: CGPoint(x: 0.30, y: 0.62),
            control2: CGPoint(x: 0.41, y: 0.54)
        )
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantFacetTopLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.50))
        p.addLine(to: CGPoint(x: 0.50, y: 0.70))
        p.addLine(to: CGPoint(x: 0.33, y: 0.71))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantFacetTopRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.50))
        p.addLine(to: CGPoint(x: 0.67, y: 0.71))
        p.addLine(to: CGPoint(x: 0.50, y: 0.70))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantFacetBottomLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.33, y: 0.71))
        p.addLine(to: CGPoint(x: 0.50, y: 0.70))
        p.addLine(to: CGPoint(x: 0.50, y: 0.87))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantFacetBottomRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.70))
        p.addLine(to: CGPoint(x: 0.67, y: 0.71))
        p.addLine(to: CGPoint(x: 0.50, y: 0.87))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantCenterTable: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.58))
        p.addLine(to: CGPoint(x: 0.58, y: 0.70))
        p.addLine(to: CGPoint(x: 0.50, y: 0.80))
        p.addLine(to: CGPoint(x: 0.42, y: 0.70))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldPendantFacetLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.50))
        p.addLine(to: CGPoint(x: 0.50, y: 0.58))
        p.move(to: CGPoint(x: 0.33, y: 0.71))
        p.addLine(to: CGPoint(x: 0.42, y: 0.70))
        p.move(to: CGPoint(x: 0.67, y: 0.71))
        p.addLine(to: CGPoint(x: 0.58, y: 0.70))
        p.move(to: CGPoint(x: 0.50, y: 0.80))
        p.addLine(to: CGPoint(x: 0.50, y: 0.87))
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldStarGlintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50, y: 0.02))
        p.addQuadCurve(to: CGPoint(x: 0.98, y: 0.50), control: CGPoint(x: 0.56, y: 0.44))
        p.addQuadCurve(to: CGPoint(x: 0.50, y: 0.98), control: CGPoint(x: 0.56, y: 0.56))
        p.addQuadCurve(to: CGPoint(x: 0.02, y: 0.50), control: CGPoint(x: 0.44, y: 0.56))
        p.addQuadCurve(to: CGPoint(x: 0.50, y: 0.02), control: CGPoint(x: 0.44, y: 0.44))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 4. 积存金（层叠暗金储金卡 + 精刻芯片 + 光泽纹理）

private struct GoldAccumulationGlyph: View {
    let emphasized: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let cardRadius = max(4, s * 0.13)
            ZStack {
                // 后层叠加储金卡，表现定投积少成多
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.deep.opacity(0.45), GoldMetalPalette.obsidian],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                            .strokeBorder(GoldMetalPalette.mid.opacity(0.45), lineWidth: max(0.75, s * 0.024))
                    )
                    .frame(width: s * 0.74, height: s * 0.52)
                    .offset(x: s * 0.07, y: -s * 0.11)

                // 前层主金属储金卡
                let frontShape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                ZStack {
                    frontShape
                        .fill(
                            LinearGradient(
                                colors: emphasized
                                    ? [GoldMetalPalette.bright, GoldMetalPalette.mid, GoldMetalPalette.deep]
                                    : [GoldMetalPalette.bright.opacity(0.84), GoldMetalPalette.mid.opacity(0.82), GoldMetalPalette.deep.opacity(0.76)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 对角斜切镜面流光
                    GoldCardSheenShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    GoldMetalPalette.specular.opacity(emphasized ? 0.52 : 0.34),
                                    GoldMetalPalette.bright.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(frontShape)

                    // 精刻金库芯片
                    GoldVaultChipView(scale: s)
                        .position(x: s * 0.22, y: s * 0.25)

                    // 右上数字金库波纹
                    GoldDigitalWaveShape()
                        .stroke(
                            GoldMetalPalette.shadow.opacity(0.55),
                            style: StrokeStyle(lineWidth: max(0.9, s * 0.032), lineCap: .round)
                        )
                        .frame(width: s * 0.18, height: s * 0.18)
                        .position(x: s * 0.62, y: s * 0.17)

                    // 底部卡号压纹条
                    HStack(spacing: s * 0.045) {
                        Capsule()
                            .fill(GoldMetalPalette.shadow.opacity(0.46))
                            .frame(width: s * 0.20, height: max(1.6, s * 0.048))
                        Capsule()
                            .fill(GoldMetalPalette.shadow.opacity(0.32))
                            .frame(width: s * 0.11, height: max(1.6, s * 0.048))
                        Spacer(minLength: 0)
                        Circle()
                            .fill(GoldMetalPalette.specular.opacity(0.75))
                            .frame(width: max(2.4, s * 0.075), height: max(2.4, s * 0.075))
                    }
                    .padding(.horizontal, s * 0.10)
                    .offset(y: s * 0.17)

                    frontShape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    GoldMetalPalette.specular.opacity(0.78),
                                    GoldMetalPalette.bright.opacity(0.45),
                                    GoldMetalPalette.shadow.opacity(0.38)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(0.85, s * 0.026)
                        )
                }
                .frame(width: s * 0.78, height: s * 0.55)
                .offset(x: -s * 0.04, y: s * 0.08)
                .shadow(color: GoldMetalPalette.shadow.opacity(0.42), radius: s * 0.08, y: s * 0.05)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct GoldVaultChipView: View {
    let scale: CGFloat

    var body: some View {
        let w = scale * 0.22
        let h = scale * 0.17
        let chipShape = RoundedRectangle(cornerRadius: max(2, scale * 0.045), style: .continuous)
        ZStack {
            chipShape
                .fill(
                    LinearGradient(
                        colors: [GoldMetalPalette.specular.opacity(0.75), GoldMetalPalette.bright, GoldMetalPalette.deep.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            GoldVaultChipGridShape()
                .stroke(GoldMetalPalette.shadow.opacity(0.48), lineWidth: max(0.65, scale * 0.02))
            chipShape
                .strokeBorder(GoldMetalPalette.shadow.opacity(0.45), lineWidth: max(0.65, scale * 0.02))
        }
        .frame(width: w, height: h)
    }
}

private struct GoldVaultChipGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.34, y: 0.04))
        p.addLine(to: CGPoint(x: 0.34, y: 0.96))
        p.move(to: CGPoint(x: 0.66, y: 0.04))
        p.addLine(to: CGPoint(x: 0.66, y: 0.96))
        p.move(to: CGPoint(x: 0.04, y: 0.50))
        p.addLine(to: CGPoint(x: 0.34, y: 0.50))
        p.move(to: CGPoint(x: 0.66, y: 0.50))
        p.addLine(to: CGPoint(x: 0.96, y: 0.50))
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldCardSheenShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.28, y: 0.0))
        p.addLine(to: CGPoint(x: 0.56, y: 0.0))
        p.addLine(to: CGPoint(x: 0.30, y: 1.0))
        p.addLine(to: CGPoint(x: 0.06, y: 1.0))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

private struct GoldDigitalWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: 0.18, y: 0.82), radius: 0.28, startAngle: .degrees(-78), endAngle: .degrees(-12), clockwise: false)
        p.move(to: CGPoint(x: 0.18 + 0.56 * cos(-78 * .pi / 180), y: 0.82 + 0.56 * sin(-78 * .pi / 180)))
        p.addArc(center: CGPoint(x: 0.18, y: 0.82), radius: 0.56, startAngle: .degrees(-78), endAngle: .degrees(-12), clockwise: false)
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

// MARK: - 5. 其他（精致暗金八芒星克重徽章）

private struct GoldOtherGlyph: View {
    let emphasized: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 外圈拉丝黄金徽章环
                Circle()
                    .fill(GoldMetalPalette.sheenGradient(emphasized: emphasized))
                    .frame(width: s * 0.82, height: s * 0.82)
                    .shadow(color: GoldMetalPalette.shadow.opacity(0.45), radius: s * 0.08, y: s * 0.04)

                // 内凹暗金盘面
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [GoldMetalPalette.obsidian, GoldMetalPalette.shadow],
                            center: .center,
                            startRadius: 0,
                            endRadius: s * 0.38
                        )
                    )
                    .frame(width: s * 0.68, height: s * 0.68)

                // 内圆细金线
                Circle()
                    .strokeBorder(GoldMetalPalette.bright.opacity(0.42), lineWidth: max(0.6, s * 0.02))
                    .frame(width: s * 0.62, height: s * 0.62)

                // 次级斜向四角星（暖金底）
                GoldStarGlintShape()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.mid, GoldMetalPalette.deep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: s * 0.44, height: s * 0.44)
                    .rotationEffect(.degrees(45))

                // 主正向四角星（亮金高光）
                GoldStarGlintShape()
                    .fill(
                        LinearGradient(
                            colors: [GoldMetalPalette.specular, GoldMetalPalette.bright, GoldMetalPalette.mid],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: s * 0.56, height: s * 0.56)

                // 中心镜面星核
                Circle()
                    .fill(GoldMetalPalette.specular)
                    .frame(width: max(2.2, s * 0.09), height: max(2.2, s * 0.09))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
