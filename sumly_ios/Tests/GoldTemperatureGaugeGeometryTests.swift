import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Sumly

@Suite("GoldTemperatureGaugeGeometry Tests")
struct GoldTemperatureGaugeGeometryTests {
    @Test func compactAndRegularRadiiMatchInsetCircleWithoutOverflow() {
        for (compact, expectedSize, expectedLineWidth, expectedTrackRadius) in [
            (true, CGFloat(104), CGFloat(9), CGFloat(47.5)),
            (false, CGFloat(184), CGFloat(14), CGFloat(85.0))
        ] {
            let g = GoldTemperatureGaugeGeometry(score: 32.3, compact: compact)
            #expect(g.size == expectedSize)
            #expect(g.lineWidth == expectedLineWidth)
            #expect(g.strokeInset == expectedLineWidth / 2)
            #expect(g.trackRadius == expectedTrackRadius)
            #expect(g.outerStrokeRadius == expectedSize / 2)
            #expect(g.center == CGPoint(x: expectedSize / 2, y: expectedSize / 2))

            // 验证 SwiftUI Circle().inset(by: strokeInset) 生成的实际路径半径严格等于 trackRadius
            let rect = CGRect(x: 0, y: 0, width: g.size, height: g.size)
            let pathRect = Circle().inset(by: g.strokeInset).path(in: rect).boundingRect
            #expect(abs(pathRect.midX - g.center.x) < 1e-6)
            #expect(abs(pathRect.midY - g.center.y) < 1e-6)
            #expect(abs(pathRect.width / 2 - g.trackRadius) < 1e-6)
            #expect(abs(pathRect.height / 2 - g.trackRadius) < 1e-6)

            // 外描边边界严格贴合 size × size，不向外溢出
            let strokedOuterRect = pathRect.insetBy(dx: -g.lineWidth / 2, dy: -g.lineWidth / 2)
            #expect(abs(strokedOuterRect.minX - 0) < 1e-6)
            #expect(abs(strokedOuterRect.minY - 0) < 1e-6)
            #expect(abs(strokedOuterRect.maxX - g.size) < 1e-6)
            #expect(abs(strokedOuterRect.maxY - g.size) < 1e-6)
        }
    }

    @Test func indicatorDistanceAndAngleStrictlyMatchArcEndAcrossScores() {
        let scores: [Double] = [0.0, 0.05, 0.5, 32.3, 50.0, 66.4, 100.0]

        for compact in [true, false] {
            for score in scores {
                let g = GoldTemperatureGaugeGeometry(score: score, compact: compact)

                // 指示圆点圆心到仪表盘圆心距离严格等于 trackRadius
                let dx = Double(g.indicatorCenter.x - g.center.x)
                let dy = Double(g.indicatorCenter.y - g.center.y)
                let distance = hypot(dx, dy)
                #expect(abs(distance - Double(g.trackRadius)) < 1e-9)

                // 彩色弧线终点角度与指示圆点角度严格一致
                #expect(abs(g.activeArcEndAngleDegrees - g.indicatorAngleDegrees) < 1e-12)

                // 彩色弧线终点坐标与指示圆点圆心完全重合
                #expect(abs(g.activeArcEndPoint.x - g.indicatorCenter.x) < 1e-12)
                #expect(abs(g.activeArcEndPoint.y - g.indicatorCenter.y) < 1e-12)

                // 有效弧线 trim 始终大于 0 且不超过总跨度
                #expect(g.activeTrimEnd >= GoldTemperatureGaugeGeometry.minimumTrim - 1e-12)
                #expect(g.activeTrimEnd <= GoldTemperatureGaugeGeometry.arcSpan + 1e-12)
            }
        }
    }

    @Test func midpointIsDeadTopAndEndpointsAreSymmetric() {
        for compact in [true, false] {
            let mid = GoldTemperatureGaugeGeometry(score: 50.0, compact: compact)
            #expect(abs(mid.indicatorAngleDegrees - 270.0) < 1e-9)
            #expect(abs(mid.indicatorCenter.x - mid.center.x) < 1e-9)
            #expect(abs(mid.indicatorCenter.y - (mid.center.y - mid.trackRadius)) < 1e-9)

            let full = GoldTemperatureGaugeGeometry(score: 100.0, compact: compact)
            #expect(abs(full.activeTrimEnd - GoldTemperatureGaugeGeometry.arcSpan) < 1e-12)
            #expect(abs(full.indicatorAngleDegrees - 399.6) < 1e-9)

            let startPoint = full.pointOnTrack(atAngleDegrees: full.startAngleDegrees)
            let endPoint = full.indicatorCenter
            #expect(abs((startPoint.x - full.center.x) + (endPoint.x - full.center.x)) < 1e-9)
            #expect(abs(startPoint.y - endPoint.y) < 1e-9)
        }
    }

    @Test func extremeAndInvalidScoresClampSafelyWithoutAngleDrift() {
        let cases: [(Double, Double)] = [
            (-20.0, 0.0),
            (0.0, 0.0),
            (150.0, 100.0),
            (.nan, 0.0),
            (.infinity, 0.0),
            (-.infinity, 0.0)
        ]

        for (raw, expectedClamped) in cases {
            let g = GoldTemperatureGaugeGeometry(score: raw, compact: true)
            #expect(g.clampedScore == expectedClamped)
            #expect(abs(g.activeArcEndAngleDegrees - g.indicatorAngleDegrees) < 1e-12)
            let distance = hypot(Double(g.indicatorCenter.x - g.center.x), Double(g.indicatorCenter.y - g.center.y))
            #expect(abs(distance - Double(g.trackRadius)) < 1e-9)
        }
    }

    @Test func geometryConformsToSendable() {
        let g: any Sendable = GoldTemperatureGaugeGeometry(score: 66.4, compact: false)
        #expect(g is GoldTemperatureGaugeGeometry)
    }

    @MainActor @Test func renderGoldTemperatureGaugesForVisualReview() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-gauge-ui-review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let reportJSON = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "as_of": "2026-11-21",
            "model_version": "v1",
            "degraded": false,
            "missing_factors": [],
            "score": 28.0,
            "level": "cool",
            "level_label": "偏冷蓄势",
            "change_1d": -1.4,
            "change_5d": -4.2,
            "volatility_alert": false,
            "volatility_note": "",
            "macro_regime": {
              "score": 72.0,
              "regime": "tailwind",
              "label": "长期宏观顺风",
              "summary": "美债高企叠加央行购金，中长期支撑稳固。"
            },
            "action_guide": {
              "signal": "cool_tailwind",
              "title": "偏冷区间 · 宏观偏暖",
              "summary": "五维市场热度处于近3年偏低分位，交易拥挤度较低。",
              "dca_multiplier": 1.2,
              "dca_label": "拥挤度较低",
              "ma200_deviation_pct": -3.12,
              "ma200_note": "低于200日均线3.12%，处于年线下方。",
              "domestic_premium_pct": 0.25,
              "domestic_premium_note": "国内金价较国际溢价 +0.25%。",
              "disclaimer": "数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。"
            },
            "dimensions": [
              {
                "key": "trend_momentum",
                "name": "趋势与动量",
                "weight": 0.30,
                "score": 28.0,
                "available": true,
                "status": "cool",
                "summary": "价格回踩均线",
                "metrics": {"ma200_dev": -3.12}
              }
            ]
          }
        }
        """
        let report = try BackendMacroService.decodeEnvelope(MacroTemperatureReport.self, from: Data(reportJSON.utf8))
        let treasury = MacroTreasurySummary(
            totalDebtTrillionUSD: 36.2,
            debtChangeYoYTrillion: 1.9,
            debtToGDPPct: 123.4,
            interestToRevenuePct: 18.2,
            fiscalStressScore: 76.0,
            yield10yNominalPct: 4.35,
            yield2yNominalPct: 4.18,
            spread10y2yPct: 0.17,
            yield10yRealPct: 2.02,
            breakeven10yPct: 2.33,
            tltPrice: 91.5,
            goldImpactNote: "财政压力处于高位，中长期利好黄金。"
        )

        let compactCardView = ScrollView {
            VStack(spacing: 18) {
                GoldTemperatureCard(
                    temperature: report,
                    treasury: treasury,
                    isLoading: false,
                    errorMessage: nil,
                    onRetry: {},
                    onOpenDashboard: {}
                )
                HStack(spacing: 14) {
                    ForEach([0.0, 32.3, 50.0], id: \.self) { value in
                        let lvl = MacroTemperatureLevel.from(score: value)
                        GoldTemperatureGauge(score: value, level: lvl, levelLabel: lvl.defaultLabel, compact: true)
                    }
                }
                HStack(spacing: 14) {
                    ForEach([66.4, 100.0], id: \.self) { value in
                        let lvl = MacroTemperatureLevel.from(score: value)
                        GoldTemperatureGauge(score: value, level: lvl, levelLabel: lvl.defaultLabel, compact: true)
                    }
                }
            }
            .padding(16)
        }
        .background(GoldTheme.background)

        let detailHeroView = ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    GoldTemperatureGauge(score: 28.0, level: .cool, levelLabel: "偏冷蓄势", compact: false)
                    Text("常规大图 28.0°（当前实盘温度）")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .goldCard(padding: 16)

                HStack(spacing: 12) {
                    GoldTemperatureGauge(score: 0.0, level: .freezing, levelLabel: "极冷低迷", compact: false)
                        .scaleEffect(0.85)
                        .frame(width: 160, height: 160)
                    GoldTemperatureGauge(score: 66.4, level: .warm, levelLabel: "偏热活跃", compact: false)
                        .scaleEffect(0.85)
                        .frame(width: 160, height: 160)
                }

                HStack(spacing: 12) {
                    GoldTemperatureGauge(score: 50.0, level: .neutral, levelLabel: "温和中性", compact: false)
                        .scaleEffect(0.85)
                        .frame(width: 160, height: 160)
                    GoldTemperatureGauge(score: 100.0, level: .hot, levelLabel: "极度火热", compact: false)
                        .scaleEffect(0.85)
                        .frame(width: 160, height: 160)
                }
            }
            .padding(16)
        }
        .background(GoldTheme.background)

        let fixtures: [(String, AnyView)] = [
            ("gauge-home-compact", AnyView(compactCardView)),
            ("gauge-detail-regular", AnyView(detailHeroView))
        ]

        for (name, rootView) in fixtures {
            let window = UIWindow(windowScene: scene)
            let controller = UIHostingController(
                rootView: rootView
                    .preferredColorScheme(.dark)
                    .tint(GoldTheme.gold)
            )
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = directory.appendingPathComponent(name + ".png")
            try #require(image.pngData()).write(to: path)
            print("GAUGE_RENDER_ARTIFACT: \(path.path)")
            window.isHidden = true
        }
        previous?.makeKey()
    }
}
