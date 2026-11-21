import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Sumly

private struct StubWidgetFetcher: GoldWidgetFetching {
    let result: Result<GoldWidgetSnapshot, Error>

    func fetchSnapshot(for basis: GoldWidgetBasis, now: Date) async throws -> GoldWidgetSnapshot {
        try result.get()
    }
}

private enum StubWidgetError: Error {
    case offline
}

struct GoldWidgetSnapshotTests {

    // MARK: - 1. 实时报价 JSON 解码

    @Test func decodeDomesticAu9999Quote() throws {
        let json = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "symbol": "AU9999",
            "price": 755.01,
            "open": 770.50,
            "high": 773.50,
            "low": 755.01,
            "prev_close": 764.55,
            "usd_cny": 6.67185,
            "cny_per_gram": 755.01,
            "as_of": "2026-11-21T02:30:00+08:00"
          }
        }
        """
        let quote = try GoldWidgetAPIClient.decodeQuote(from: Data(json.utf8), basis: .domestic)
        #expect(quote.basis == .domestic)
        #expect(abs(quote.cnyPerGram - 755.01) < 1e-6)
        #expect(quote.usdPerOz == nil)
        #expect(quote.conversionRatio == 1)
        let changeCNY = try #require(quote.changeCNY)
        let changePct = try #require(quote.changePercent)
        #expect(abs(changeCNY - (-9.54)) < 1e-4)
        #expect(abs(changePct - (-1.24779)) < 1e-3)
    }

    @Test func decodeInternationalXauusdQuoteConvertsToCNYPerGram() throws {
        let json = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "symbol": "XAUUSD",
            "price": 3534.64,
            "open": 3628.88,
            "high": 3636.63,
            "low": 3502.73,
            "prev_close": 3625.01,
            "usd_cny": 6.67185,
            "cny_per_gram": 758.1978,
            "as_of": "2026-11-21T05:55:00+08:00"
          }
        }
        """
        let quote = try GoldWidgetAPIClient.decodeQuote(from: Data(json.utf8), basis: .international)
        #expect(quote.basis == .international)
        #expect(abs(quote.cnyPerGram - 758.1978) < 1e-4)
        #expect(abs((quote.usdPerOz ?? 0) - 3534.64) < 1e-4)
        let changePct = try #require(quote.changePercent)
        #expect(abs(changePct - (-2.49295)) < 1e-3)
        let changeCNY = try #require(quote.changeCNY)
        #expect(changeCNY < 0)
    }

    @Test func decodeQuoteRejectsEnvelopeErrorAndInvalidPrice() {
        let errorJSON = #"{"code": 50001, "message": "upstream timeout", "data": null}"#
        #expect(throws: GoldWidgetAPIClient.ClientError.envelope(50001, "upstream timeout")) {
            _ = try GoldWidgetAPIClient.decodeQuote(from: Data(errorJSON.utf8), basis: .domestic)
        }

        let badPriceJSON = """
        {"code": 0, "data": {"price": 0, "cny_per_gram": 0, "as_of": "2026-11-21T02:30:00+08:00"}}
        """
        #expect(throws: GoldWidgetAPIClient.ClientError.malformedPayload) {
            _ = try GoldWidgetAPIClient.decodeQuote(from: Data(badPriceJSON.utf8), basis: .domestic)
        }
    }

    // MARK: - 2. 近一月日线解码与单位折算

    @Test func decodeDailySeriesSortsTrimsAndConvertsUSD() throws {
        var bars: [String] = []
        for day in 1...40 {
            let month = day <= 30 ? 10 : 11
            let d = day <= 30 ? day : day - 30
            let close = 3500.0 + Double(day) * 2.5
            bars.append(#"{"date": "\#(String(format: "2026-%02d-%02d", month, d))", "close": \#(close)}"#)
        }
        let reversed = bars.reversed().joined(separator: ",")
        let json = """
        {"code": 0, "data": {"unit": "USD/troy_oz", "bars": [\(reversed)]}}
        """

        let ratio = 0.2145
        let series = try GoldWidgetAPIClient.decodeDailySeries(
            from: Data(json.utf8),
            basis: .international,
            conversionRatio: ratio,
            limit: 30
        )

        #expect(series.count == 30)
        #expect(series.first?.date == "2026-10-11")
        #expect(series.last?.date == "2026-11-10")
        #expect(abs((series.last?.priceCNY ?? 0) - 3600.0 * ratio) < 1e-4)
    }

    @Test func decodeDailySeriesRejectsEmptyBars() {
        let json = #"{"code": 0, "data": {"unit": "CNY/g", "bars": []}}"#
        #expect(throws: GoldWidgetAPIClient.ClientError.emptyData) {
            _ = try GoldWidgetAPIClient.decodeDailySeries(
                from: Data(json.utf8),
                basis: .domestic,
                conversionRatio: 1
            )
        }
    }

    // MARK: - 3. 黄金温度计解码与纯客观文案校验

    @Test func decodeTemperatureUsesPureObjectiveClientCopy() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "as_of": "2026-11-20",
            "score": 27.3,
            "level": "cool",
            "level_label": "建议逢低定投加仓",
            "macro_regime": {
              "score": 66.9,
              "regime": "tailwind",
              "label": "长期宏观偏暖"
            }
          }
        }
        """
        let temp = try GoldWidgetAPIClient.decodeTemperature(from: Data(json.utf8))
        #expect(temp.roundedDegree == 27)
        #expect(temp.level == .cool)
        #expect(temp.regime == .tailwind)
        #expect(temp.shortBadgeText == "27° 偏冷")
        #expect(temp.dualHorizonText == "27° 偏冷 · 支撑偏强")

        // 穷举所有档位与宏观状态组合，确保绝不出现任何投顾或历史遗留“偏暖”措辞
        let forbidden = ["定投", "建议", "加仓", "买入", "卖出", "逢低", "抄底", "止盈", "止损", "偏暖"]
        for level in GoldWidgetTemperatureLevel.allCases {
            for regime in GoldWidgetMacroRegime.allCases {
                let sample = GoldWidgetTemperatureSnapshot(score: 50, level: level, regime: regime, asOf: "2026-11-20")
                for word in forbidden {
                    #expect(!sample.shortBadgeText.contains(word))
                    #expect(!sample.dualHorizonText.contains(word))
                }
            }
        }
    }

    // MARK: - 4. 涨跌方向与格式化

    @Test func trendDirectionAndFormattingFollowDomesticConvention() {
        #expect(GoldWidgetTrendDirection.resolve(changeCNY: 5.2, changePercent: 0.7) == .up)
        #expect(GoldWidgetTrendDirection.resolve(changeCNY: -3.1, changePercent: -0.4) == .down)
        #expect(GoldWidgetTrendDirection.resolve(changeCNY: 0, changePercent: 0) == .flat)
        #expect(GoldWidgetTrendDirection.resolve(changeCNY: nil, changePercent: nil) == .flat)

        #expect(GoldWidgetFormatting.formatPriceCNY(755.01) == "755.01")
        #expect(GoldWidgetFormatting.formatPriceCNY(0) == "--")
        #expect(GoldWidgetFormatting.formatSignedChangeCNY(8.4) == "+8.40")
        #expect(GoldWidgetFormatting.formatSignedChangeCNY(-9.54) == "-9.54")
        #expect(GoldWidgetFormatting.formatSignedChangeCNY(0.001) == "0.00")
        #expect(GoldWidgetFormatting.formatSignedPercent(1.256) == "+1.26%")
        #expect(GoldWidgetFormatting.formatSignedPercent(-1.247) == "-1.25%")
        #expect(GoldWidgetFormatting.formatUSDPerOz(3534.64) == "$3535/oz")

        let tz = TimeZone(secondsFromGMT: 8 * 3600)!
        let d1 = GoldWidgetAPIClient.parseRFC3339("2026-11-21T09:45:00+08:00")!
        let sameDayNow = GoldWidgetAPIClient.parseRFC3339("2026-11-21T14:00:00+08:00")!
        let nextDayNow = GoldWidgetAPIClient.parseRFC3339("2026-11-22T08:00:00+08:00")!
        #expect(GoldWidgetFormatting.formatUpdatedTime(d1, now: sameDayNow, timeZone: tz) == "09:45")
        #expect(GoldWidgetFormatting.formatUpdatedTime(d1, now: nextDayNow, timeZone: tz) == "11/21 09:45")
        #expect(GoldWidgetFormatting.formatUpdatedTime(d1, now: nextDayNow, timeZone: tz, compact: true) == "11/21")
    }

    // MARK: - 5. Sparkline 采样与归一化

    @Test func sparklineNormalizationHandlesEdgeCasesAndDownsampling() {
        #expect(GoldWidgetSparkline.sampleAndNormalize([]).isEmpty)
        #expect(GoldWidgetSparkline.sampleAndNormalize([-1, 0, .nan, .infinity]).isEmpty)

        let single = GoldWidgetSparkline.sampleAndNormalize([750])
        #expect(single.count == 2)
        #expect(single[0] == .init(x: 0, y: 0.5))
        #expect(single[1] == .init(x: 1, y: 0.5))

        let flat = GoldWidgetSparkline.sampleAndNormalize([750, 750, 750, 750])
        #expect(flat.allSatisfy { abs($0.y - 0.5) < 1e-9 })

        let raw = (0..<60).map { 700.0 + Double($0) * 2.0 }
        let normalized = GoldWidgetSparkline.sampleAndNormalize(raw, maxPoints: 30)
        #expect(normalized.count == 30)
        #expect(abs(normalized.first!.x - 0) < 1e-9)
        #expect(abs(normalized.last!.x - 1) < 1e-9)
        #expect(abs(normalized.first!.y - 0) < 1e-9)
        #expect(abs(normalized.last!.y - 1) < 1e-9)
    }

    // MARK: - 6. 缓存降级与 Timeline 刷新间隔

    @Test func serviceCachesLiveSnapshotAndFallsBackOnNetworkFailure() async throws {
        let suiteName = "test.sumly.widget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = GoldWidgetCacheStore(defaults: defaults, keyPrefix: "unit")

        let now = Date(timeIntervalSince1970: 1_795_200_000)

        // 冷启动断网：无缓存时应返回 nil（绝不捏造假数据），并缩短重试间隔至 5 分钟
        let coldOffline = GoldWidgetSnapshotService(
            fetcher: StubWidgetFetcher(result: .failure(StubWidgetError.offline)),
            cache: cache
        )
        let coldResult = await coldOffline.loadSnapshot(for: .domestic, now: now)
        #expect(coldResult == nil)
        #expect(coldOffline.nextRefreshDate(from: now, snapshot: coldResult).timeIntervalSince(now) == 300)

        // 在线拉取成功：写缓存，返回新鲜快照，下次刷新 15 分钟
        let liveSnapshot = GoldWidgetSnapshot.previewPlaceholder(basis: .domestic)
        let online = GoldWidgetSnapshotService(
            fetcher: StubWidgetFetcher(result: .success(liveSnapshot)),
            cache: cache
        )
        let liveResult = try #require(await online.loadSnapshot(for: .domestic, now: now))
        #expect(liveResult.isCachedFallback == false)
        #expect(liveResult.cnyPerGram == liveSnapshot.cnyPerGram)
        #expect(online.nextRefreshDate(from: now, snapshot: liveResult).timeIntervalSince(now) == 900)

        // 随后断网：自动回退至最近有效缓存，保留真实价格与时间戳，并标记 isCachedFallback = true
        let offlineAfterCache = GoldWidgetSnapshotService(
            fetcher: StubWidgetFetcher(result: .failure(StubWidgetError.offline)),
            cache: cache
        )
        let fallback = try #require(await offlineAfterCache.loadSnapshot(for: .domestic, now: now.addingTimeInterval(1200)))
        #expect(fallback.isCachedFallback == true)
        #expect(fallback.cnyPerGram == liveSnapshot.cnyPerGram)
        #expect(fallback.asOf == liveSnapshot.asOf)
    }

    // MARK: - 7. 主 App 桥接器 WidgetSnapshotBridge

    @Test func bridgePublishesMainAppQuoteAndPreservesCachedContext() throws {
        let suiteName = "test.sumly.bridge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GoldWidgetCacheStore(defaults: defaults, keyPrefix: "bridge")

        let asOf = Date(timeIntervalSince1970: 1_795_200_000)
        let quote1 = GoldQuote(
            symbol: "AU9999",
            price: 755.01,
            open: 760,
            high: 765,
            low: 752,
            prevClose: 764.55,
            usdCNY: 6.67,
            cnyPerGram: 755.01,
            asOf: asOf
        )
        let daily = [
            GoldDailyPrice(date: Date(timeIntervalSince1970: 1_794_900_000), open: 780, high: 785, low: 775, close: 782),
            GoldDailyPrice(date: Date(timeIntervalSince1970: 1_795_000_000), open: 782, high: 784, low: 760, close: 764.55)
        ]
        let report = MacroTemperatureReport(
            asOf: "2026-11-20",
            modelVersion: "v2",
            degraded: false,
            missingFactors: [],
            score: 27.3,
            level: .cool,
            levelLabel: "偏冷区间",
            change1d: -0.5,
            change5d: -2.1,
            volatilityAlert: false,
            volatilityNote: "",
            macroRegime: MacroRegime(score: 66.9, regime: .tailwind, label: "支撑偏强", summary: ""),
            actionGuide: MacroActionGuide(
                signal: "cool",
                title: "",
                summary: "",
                dcaMultiplier: 1,
                dcaLabel: "",
                ma200DeviationPct: nil,
                ma200Note: "",
                domesticPremiumPct: nil,
                domesticPremiumNote: "",
                disclaimer: ""
            ),
            dimensions: [],
            guideHelp: nil
        )

        let published = try #require(
            WidgetSnapshotBridge.publishQuote(
                quote1,
                basis: .domestic,
                dailyPrices: daily,
                temperature: report,
                store: store,
                reloadTimeline: false,
                now: asOf
            )
        )
        #expect(published.recentSeries.count == 2)
        #expect(published.temperature?.dualHorizonText == "27° 偏冷 · 支撑偏强")

        // 仅推送新实时报价时，应自动保留已有缓存中的日线与温度数据
        let quote2 = GoldQuote(
            symbol: "AU9999",
            price: 768.20,
            open: 760,
            high: 770,
            low: 755,
            prevClose: 764.55,
            usdCNY: 6.67,
            cnyPerGram: 768.20,
            asOf: asOf.addingTimeInterval(60)
        )
        let merged = try #require(
            WidgetSnapshotBridge.publishQuote(
                quote2,
                basis: .domestic,
                store: store,
                reloadTimeline: false,
                now: asOf.addingTimeInterval(60)
            )
        )
        #expect(merged.cnyPerGram == 768.20)
        #expect(merged.trendDirection == .up)
        #expect(merged.recentSeries.count == 2)
        #expect(merged.temperature?.roundedDegree == 27)

        WidgetSnapshotBridge.publishHoldingsSummary(totalGrams: 128.5, store: store, now: asOf)
        #expect(store.loadHoldingsSummary()?.totalGrams == 128.5)
    }

    // MARK: - 8. Simulator 视觉渲染验证（小号 / 中号 / 锁屏圆形与矩形）

    @MainActor @Test func renderGoldWidgetShowcaseForVisualReview() async throws {
        let now = GoldWidgetAPIClient.parseRFC3339("2026-11-21T10:30:00+08:00")!

        let domesticUpSeries: [Double] = [
            738.2, 742.6, 740.1, 746.5, 751.8, 749.2, 755.0, 761.4,
            758.9, 764.8, 770.2, 766.5, 773.0, 779.6, 785.4, 781.2,
            774.8, 769.5, 763.2, 758.0, 754.6, 759.8, 764.55
        ].enumerated().map { _, v in v }

        let domesticPoints = domesticUpSeries.enumerated().map { idx, price in
            GoldWidgetPricePoint(date: String(format: "2026-11-%02d", min(idx + 1, 28)), priceCNY: price)
        }

        let domesticSnapshot = GoldWidgetSnapshot(
            basis: .domestic,
            cnyPerGram: 772.95,
            changeCNY: 8.40,
            changePercent: 1.10,
            usdPerOz: nil,
            asOf: now,
            fetchedAt: now,
            recentSeries: domesticPoints,
            temperature: GoldWidgetTemperatureSnapshot(
                score: 27.3,
                level: .cool,
                regime: .tailwind,
                asOf: "2026-11-20"
            ),
            isCachedFallback: false
        )

        let intlSnapshot = GoldWidgetSnapshot(
            basis: .international,
            cnyPerGram: 758.20,
            changeCNY: -19.37,
            changePercent: -2.49,
            usdPerOz: 3534.64,
            asOf: now,
            fetchedAt: now,
            recentSeries: domesticPoints,
            temperature: GoldWidgetTemperatureSnapshot(
                score: 27.3,
                level: .cool,
                regime: .tailwind,
                asOf: "2026-11-20"
            ),
            isCachedFallback: false
        )

        let showcase = VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("记金 · WidgetKit 桌面与锁屏小组件")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(GoldTheme.goldSoft)
                Text("国内红涨绿跌 · 暗黑金色系 · 纯客观黄金温度")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
            }

            // 1. 桌面小号（红涨国内 + 绿跌国际）
            VStack(alignment: .leading, spacing: 8) {
                Text("桌面小号（systemSmall）")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
                HStack(spacing: 16) {
                    GoldSmallWidgetView(basis: .domestic, snapshot: domesticSnapshot, now: now)
                        .frame(width: 158, height: 158)
                        .background(GoldWidgetBackground())
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                        )

                    GoldSmallWidgetView(basis: .international, snapshot: intlSnapshot, now: now)
                        .frame(width: 158, height: 158)
                        .background(GoldWidgetBackground())
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                        )
                }
            }

            // 2. 桌面中号（带近一月金色折线图）
            VStack(alignment: .leading, spacing: 8) {
                Text("桌面中号（systemMedium · 近一月走势）")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
                GoldMediumWidgetView(basis: .domestic, snapshot: domesticSnapshot, now: now)
                    .frame(width: 332, height: 158)
                    .background(GoldWidgetBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                    )
            }

            // 3. 锁屏小组件（圆形 + 矩形）
            VStack(alignment: .leading, spacing: 8) {
                Text("锁屏小组件（accessoryCircular & accessoryRectangular）")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
                HStack(spacing: 18) {
                    GoldAccessoryCircularView(basis: .domestic, snapshot: domesticSnapshot)
                        .frame(width: 76, height: 76)
                        .foregroundStyle(GoldTheme.text)
                        .padding(10)
                        .background(GoldTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                        )

                    GoldAccessoryRectangularView(basis: .domestic, snapshot: domesticSnapshot)
                        .frame(width: 196, height: 76)
                        .foregroundStyle(GoldTheme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(GoldTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                        )
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GoldTheme.background)
        .preferredColorScheme(.dark)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: showcase)
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(450))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let pngData = try #require(image.pngData())
        #expect(pngData.count > 10_000)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sumly-widget-ui-review", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("sim_gold_widget.png")
        try pngData.write(to: outputURL, options: .atomic)
        print("WIDGET_RENDER_ARTIFACT: \(outputURL.path)")
    }
}
