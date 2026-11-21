import Foundation
import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Sumly

struct GoldCalendarEngineTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return cal
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func bar(_ year: Int, _ month: Int, _ day: Int, close: Double, open: Double? = nil) -> (CalendarDayKey, CalendarDailyMarketBar) {
        let key = CalendarDayKey(year: year, month: month, day: day)
        return (key, CalendarDailyMarketBar(dayKey: key, closeCNYPerGram: close, openCNYPerGram: open ?? close))
    }

    // MARK: - 1. 防失真金融公式 Δ1 ~ Δ4 + 赠送恒记 0 + 月战报一致性

    @Test func carriedOverAndNewBuyWithHighLaborFeeAvoidsDistortion() {
        // 11/02 昨收 600，11/03 收盘 610 (+10/g)，11/04 收盘 605 (-5/g)
        let bars = Dictionary(uniqueKeysWithValues: [
            bar(2026, 11, 2, close: 600),
            bar(2026, 11, 3, close: 610),
            bar(2026, 11, 4, close: 605)
        ])

        // 11/02 买入 10g（纯度 99%，单价 600）
        let carried = CalendarHoldingItem(
            grams: 10,
            purity: 0.99,
            unitPriceCNY: 600,
            timestamp: day(2026, 11, 2),
            brand: "投资金条",
            assetType: "金条"
        )
        // 11/03 新买入 5g 品牌金饰：裸金单价 608，但工费高达 300（60元/g）
        let jewelryWithHighFee = CalendarHoldingItem(
            grams: 5,
            purity: 1.0,
            unitPriceCNY: 608,
            totalPurchaseCost: 5 * 608 + 300,
            laborFee: 300,
            timestamp: day(2026, 11, 3),
            brand: "周大福",
            assetType: "金饰"
        )

        let snap = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: [carried, jewelryWithHighFee],
            dailyBars: bars,
            liveQuote: nil,
            temperatures: [:],
            milestoneFirstReached: [:],
            now: day(2026, 11, 4),
            calendar: calendar
        )

        // 11/03:
        // Δ1 = (10 * 0.99) * (610 - 600) = 99.0
        // Δ2 = 5 * (610 - 608) = 10.0 （工费 300 不污染当日盈亏，且新增本金不被算作盈利！）
        // 合计 = 109.0
        // B_D = 9.9 * 600 + 5 * 608 = 5940 + 3040 = 8980
        let d3 = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 3)]!
        #expect(d3.status == .trading)
        #expect(abs((d3.dailyPnL ?? 0) - 109.0) < 1e-6)
        #expect(abs(d3.dailyPnLBasis - 8980.0) < 1e-6)
        #expect(abs((d3.dailyPnLRatePercent ?? 0) - (109.0 / 8980.0 * 100)) < 1e-6)
        #expect(d3.pnlHeatLevel == .medium) // 1.2138% -> [0.5%, 1.5%)

        // 11/04: 全部 14.9g 纯金结转，跌 5 元/g -> -74.5
        let d4 = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 4)]!
        #expect(abs((d4.dailyPnL ?? 0) - (-74.5)) < 1e-6)

        // 校验逐日盈亏之和 == 月战报总额（11/02: 0 + 11/03: 109 + 11/04: -74.5 = 34.5）
        let month = snap.monthSummary(11)!
        let sumOfDays = snap.daysByKey.values
            .filter { $0.dayKey.month == 11 && $0.status == .trading }
            .compactMap(\.dailyPnL)
            .reduce(0, +)
        #expect(abs((month.totalPnL ?? 0) - sumOfDays) < 1e-6)
        #expect(abs((month.totalPnL ?? 0) - 34.5) < 1e-6)
        #expect(month.pnlRedDays == 1)
        #expect(month.pnlGreenDays == 1)
    }

    @Test func partialSaleSameDayTradeAndGiftZeroPnL() {
        let bars = Dictionary(uniqueKeysWithValues: [
            bar(2026, 11, 2, close: 600),
            bar(2026, 11, 3, close: 620),
            bar(2026, 11, 4, close: 615)
        ])

        // 昨日结转、今日部分卖出：2g，昨收 600，实收 1250 -> Δ3 = 1250 - 2*600 = +50
        let soldCarried = CalendarHoldingItem(
            grams: 2,
            purity: 1.0,
            unitPriceCNY: 550,
            timestamp: day(2026, 11, 2),
            disposition: "sold",
            disposedAt: day(2026, 11, 3),
            disposalAmount: 1250
        )
        // 同日买入同日卖出：3g，买价 610，实收 1860 -> Δ4 = 1860 - 3*610 = +30
        let sameDayTrade = CalendarHoldingItem(
            grams: 3,
            purity: 1.0,
            unitPriceCNY: 610,
            timestamp: day(2026, 11, 3),
            disposition: "sold",
            disposedAt: day(2026, 11, 3),
            disposalAmount: 1860
        )
        // 昨日结转、11/04 赠出：4g -> 11/04 当日无其他持仓，赠送恒记 0，绝不误算亏损！
        let gifted = CalendarHoldingItem(
            grams: 4,
            purity: 1.0,
            unitPriceCNY: 580,
            timestamp: day(2026, 11, 2),
            disposition: "gift",
            disposedAt: day(2026, 11, 4),
            disposalAmount: 0
        )

        let snap = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: [soldCarried, sameDayTrade, gifted],
            dailyBars: bars,
            liveQuote: nil,
            temperatures: [:],
            milestoneFirstReached: [:],
            now: day(2026, 11, 4),
            calendar: calendar
        )

        // 11/03: gifted 结转仍持有 4*(620-600)=+80; soldCarried Δ3=+50; sameDayTrade Δ4=+30 -> 合计 +160
        let d3 = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 3)]!
        #expect(abs((d3.dailyPnL ?? 0) - 160.0) < 1e-6)
        #expect(d3.soldGrams == 5)
        #expect(d3.endOfDayHoldingGrams == 4)

        // 11/04: 仅有 gifted 被赠出 -> 恒记 0，不计入绿天，收盘在库归零
        let d4 = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 4)]!
        #expect(d4.dailyPnL == 0)
        #expect(d4.pnlDirection == .flat)
        #expect(d4.giftGrams == 4)
        #expect(d4.endOfDayHoldingGrams == 0)

        let month = snap.monthSummary(11)!
        #expect(month.pnlGreenDays == 0)
    }

    // MARK: - 2. 休市 / 周末防重复算周五 / 早于历史起点 / 未来日边界

    @Test func weekendQuoteDoesNotDuplicateFridayPnLAndBoundsAreRespected() {
        // 2026-11-20 周五有收盘价 620；2026-11-21 周六无日线，liveQuote 仍停留在周五
        let bars = Dictionary(uniqueKeysWithValues: [
            bar(2026, 11, 19, close: 610),
            bar(2026, 11, 20, close: 620)
        ])
        let holding = CalendarHoldingItem(grams: 10, unitPriceCNY: 600, timestamp: day(2026, 11, 10))
        let fridayQuote = CalendarLiveQuoteInput(cnyPerGram: 620, prevCloseCNYPerGram: 610, asOf: day(2026, 11, 20))

        let snap = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: [holding],
            dailyBars: bars,
            liveQuote: fridayQuote,
            temperatures: [:],
            milestoneFirstReached: [:],
            now: day(2026, 11, 21), // 周六
            calendar: calendar
        )

        // 早于历史日线起点 (11/10 < 11/19) -> .noMarketData，保留事件微标与克重，盈亏为 nil
        let earlyDay = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 10)]!
        #expect(earlyDay.status == .noMarketData)
        #expect(earlyDay.dailyPnL == nil)
        #expect(earlyDay.hasBuy == true)
        #expect(earlyDay.buyGrams == 10)

        // 周五 11/20 -> 交易日，+100
        let friday = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 20)]!
        #expect(friday.status == .trading)
        #expect(abs((friday.dailyPnL ?? 0) - 100.0) < 1e-6)

        // 周六 11/21（今天）-> 休市，不重复计算周五盈亏，但保留在库克重与前收参考估值
        let saturday = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 21)]!
        #expect(saturday.isToday == true)
        #expect(saturday.status == .closed)
        #expect(saturday.dailyPnL == nil)
        #expect(saturday.endOfDayHoldingGrams == 10)
        #expect(abs((saturday.endOfDayValuationCNY ?? 0) - 6200.0) < 1e-6)

        // 周日 11/22（未来）-> .future
        let futureDay = snap.daysByKey[CalendarDayKey(year: 2026, month: 11, day: 22)]!
        #expect(futureDay.status == .future)
        #expect(futureDay.dailyPnL == nil)

        // 月战报只统计周五 1 个红天，不把周六算进去
        let month = snap.monthSummary(11)!
        #expect(month.pnlRedDays == 1)
        #expect(abs((month.totalPnL ?? 0) - 100.0) < 1e-6)
    }

    // MARK: - 3. 国际口径汇率折算与缺失汇率降级

    @Test func internationalBasisConversionUsesCurrentFXAndDegradesWithoutFX() {
        let usdPrices = [
            GoldDailyPrice(date: day(2026, 11, 18), open: 2600, high: 2620, low: 2590, close: 2610),
            GoldDailyPrice(date: day(2026, 11, 19), open: 2610, high: 2650, low: 2605, close: 2640)
        ]

        let converted = GoldCalendarEngine.convertDailyBars(usdPrices, basis: .international, usdCNY: 7.2, calendar: calendar)
        #expect(converted.count == 2)
        let expected18 = 2610 * 7.2 / 31.1034768
        #expect(abs((converted[CalendarDayKey(year: 2026, month: 11, day: 18)]?.closeCNYPerGram ?? 0) - expected18) < 1e-6)

        // 缺少汇率时不得编造价格，优雅返回空表
        let missingFX = GoldCalendarEngine.convertDailyBars(usdPrices, basis: .international, usdCNY: nil, calendar: calendar)
        #expect(missingFX.isEmpty)
    }

    // MARK: - 4. 里程碑首次达成日、陪伴天数与客观连续记录月数

    @Test func milestoneFirstAchievementDoesNotRepeatAfterSaleAndRebuy() {
        let items = [
            CalendarHoldingItem(grams: 12, unitPriceCNY: 580, timestamp: day(2026, 9, 5)),
            CalendarHoldingItem(grams: 5, unitPriceCNY: 580, timestamp: day(2026, 9, 5), disposition: "sold", disposedAt: day(2026, 9, 20), disposalAmount: 3000),
            CalendarHoldingItem(grams: 6, unitPriceCNY: 600, timestamp: day(2026, 10, 12))
        ]
        // 11 月 1 日尚未记账：连续记录月数应客观回溯 10 月 + 9 月 = 2 个月，不制造断签焦虑
        let stats = GoldCalendarEngine.computeCompanionStats(items: items, now: day(2026, 11, 1), calendar: calendar)
        #expect(stats.hasAnyRecords == true)
        #expect(stats.companionDays == 58) // 9/5 -> 11/1 共 58 天
        #expect(stats.consecutiveActiveMonths == 2)

        // 1g 与 10g 均在 9/5 首次点亮；10/12 虽然再次跨回 13g，但不重复点亮 10g
        let sep5 = stats.milestoneFirstReached[CalendarDayKey(year: 2026, month: 9, day: 5)] ?? []
        let oct12 = stats.milestoneFirstReached[CalendarDayKey(year: 2026, month: 10, day: 12)] ?? []
        #expect(sep5.map(\.id) == ["1g", "10g"])
        #expect(oct12.isEmpty)
    }

    // MARK: - 5. 5 秒实时报价 O(1) 增量更新与全量重算完全一致

    @Test func patchTodayMatchesFullRecomputeExactly() {
        let bars = Dictionary(uniqueKeysWithValues: [
            bar(2026, 11, 18, close: 600),
            bar(2026, 11, 19, close: 610)
        ])
        let items = [
            CalendarHoldingItem(grams: 20, unitPriceCNY: 590, timestamp: day(2026, 11, 18))
        ]
        let now = day(2026, 11, 20)
        let quote1 = CalendarLiveQuoteInput(cnyPerGram: 615, prevCloseCNYPerGram: 610, asOf: now)
        let quote2 = CalendarLiveQuoteInput(cnyPerGram: 604, prevCloseCNYPerGram: 610, asOf: now)

        let base = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: items,
            dailyBars: bars,
            liveQuote: quote1,
            temperatures: [:],
            milestoneFirstReached: [:],
            now: now,
            calendar: calendar
        )
        let patched = GoldCalendarEngine.patchToday(
            in: base,
            items: items,
            dailyBars: bars,
            liveQuote: quote2,
            temperature: nil,
            unlockedMilestones: [],
            now: now,
            calendar: calendar
        )
        let full = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: items,
            dailyBars: bars,
            liveQuote: quote2,
            temperatures: [:],
            milestoneFirstReached: [:],
            now: now,
            calendar: calendar
        )

        let todayKey = CalendarDayKey(year: 2026, month: 11, day: 20)
        #expect(patched.daysByKey[todayKey] == full.daysByKey[todayKey])
        #expect(patched.monthSummary(11) == full.monthSummary(11))
        #expect(patched.totalPnL == full.totalPnL)
        #expect(patched.pnlRedDays == full.pnlRedDays)
        #expect(patched.pnlGreenDays == full.pnlGreenDays)
        #expect(patched.marketRedDays == full.marketRedDays)
        #expect(patched.marketGreenDays == full.marketGreenDays)
        #expect(patched.weeks == full.weeks)
    }

    @MainActor
    @Test func viewModelIsolatesLiveQuoteTicksToO1IncrementalPatchAndDegradesEmptyPortfolio() {
        let now = day(2026, 11, 20)
        let vm = HoldingsCalendarViewModel(initialDate: now, calendar: calendar)
        let dailyPrices = [
            GoldDailyPrice(date: day(2026, 11, 18), open: 600, high: 605, low: 598, close: 600),
            GoldDailyPrice(date: day(2026, 11, 19), open: 600, high: 612, low: 599, close: 610)
        ]

        // 1) 空持仓态：自动降级为大盘图层，隐藏盈亏；无温度数据时隐藏温度
        vm.applyDirectFixtures(
            dailyPrices: dailyPrices,
            temperaturePoints: [],
            basis: .domestic,
            items: [],
            liveQuote: GoldQuote(symbol: "AU9999", price: 615, open: 610, high: 616, low: 609, prevClose: 610, usdCNY: 0, cnyPerGram: 615, asOf: now),
            now: now
        )
        #expect(vm.hasAnyRecordsInScope == false)
        #expect(vm.availableLayers == [.market])
        #expect(vm.effectiveLayer == .market)

        // 未来日点击严格拦截
        vm.selectDate(day(2026, 11, 25), now: now)
        #expect(vm.selectedDayKey == CalendarDayKey(year: 2026, month: 11, day: 20))

        // 2) 有持仓后：自动切回盈亏图层；连续 5 次 5s 实时报价只走 O(1) 补丁不触发全年重算
        let items = [CalendarHoldingItem(grams: 10, unitPriceCNY: 595, timestamp: day(2026, 11, 18))]
        let quote0 = GoldQuote(symbol: "AU9999", price: 615, open: 610, high: 616, low: 609, prevClose: 610, usdCNY: 0, cnyPerGram: 615, asOf: now)
        vm.syncInputs(items: items, filter: .init(), basis: .domestic, liveQuote: quote0, now: now)
        let fullAfterHoldings = vm.fullComputeCount
        let patchBefore = vm.incrementalPatchCount
        #expect(vm.effectiveLayer == .pnl)

        for tick in 1...5 {
            let price = 615.0 + Double(tick)
            let q = GoldQuote(symbol: "AU9999", price: price, open: 610, high: price, low: 609, prevClose: 610, usdCNY: 0, cnyPerGram: price, asOf: now)
            vm.syncInputs(items: items, filter: .init(), basis: .domestic, liveQuote: q, now: now)
        }
        #expect(vm.fullComputeCount == fullAfterHoldings)
        #expect(vm.incrementalPatchCount == patchBefore + 5)
        // 最终实时价 620 vs 昨收 610 -> +100
        #expect(abs((vm.selectedDaySnapshot?.dailyPnL ?? 0) - 100.0) < 1e-6)
    }

    // MARK: - 6. 温度缓存 TTL、磁盘持久化与 3y -> all 扩展

    @Test func macroTemperatureCacheRespectsTTLDiskPersistenceAndAllReuse() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-temp-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        actor CountingMacroService: MacroServicing {
            var calls: [MacroHistoryRange] = []
            func fetchTemperature() async throws -> MacroTemperatureReport { fatalError("unused") }
            func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
                calls.append(range)
                let pts = [
                    MacroTemperatureHistoryPoint(
                        dateString: "2026-11-19",
                        date: GoldDailyPrice.parseDay("2026-11-19")!,
                        score: 64,
                        level: .warm,
                        goldPriceUSD: 2650
                    )
                ]
                return MacroTemperatureHistory(range: range.rawValue, modelVersion: "v1", points: pts)
            }
            func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport { fatalError("unused") }
            func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog { fatalError("unused") }
            func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail { fatalError("unused") }
            func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport { fatalError("unused") }
        }

        let service = CountingMacroService()
        let cache = MacroTemperatureHistoryCache(directory: dir, ttl: 1800)
        let t0 = day(2026, 11, 20)

        let first = try await cache.fetch(scope: "test", range: .threeYears, service: service, now: t0)
        #expect(first.count == 1)
        // TTL 内命中内存缓存，不发第二次请求
        let second = try await cache.fetch(scope: "test", range: .threeYears, service: service, now: t0.addingTimeInterval(600))
        #expect(second == first)
        #expect(await service.calls == [.threeYears])

        // 切更早年份触发 .all 扩展
        #expect(MacroTemperatureHistoryCache.preferredRange(for: 2022, now: t0, calendar: calendar) == .all)
        #expect(MacroTemperatureHistoryCache.preferredRange(for: 2025, now: t0, calendar: calendar) == .threeYears)
        _ = try await cache.fetch(scope: "test", range: .all, service: service, now: t0.addingTimeInterval(601))
        #expect(await service.calls == [.threeYears, .all])

        // 已有新鲜 .all 后，新缓存实例可从磁盘读取并直接满足 .threeYears
        let coldCache = MacroTemperatureHistoryCache(directory: dir, ttl: 1800)
        let fromDisk = try await coldCache.fetch(scope: "test", range: .threeYears, service: service, now: t0.addingTimeInterval(700))
        #expect(fromDisk.count == 1)
        #expect(await service.calls == [.threeYears, .all])
    }

    // MARK: - 7. 隐私脱敏规则与 52 周热力矩阵

    @Test func privacyMaskingRulesAndYearHeatmapMatrix() {
        // 隐私模式下月历格不铺满 `••`，仅留极轻 `+`/`-`
        #expect(GoldCalendarFormat.compactCellPnL(128.5, hideAmounts: true) == "+")
        #expect(GoldCalendarFormat.compactCellPnL(-46.2, hideAmounts: true) == "-")
        #expect(GoldCalendarFormat.compactCellPnL(0, hideAmounts: true) == "")
        #expect(!GoldCalendarFormat.compactCellPnL(128.5, hideAmounts: true).contains("•"))

        // 正常模式紧凑数值
        #expect(GoldCalendarFormat.compactCellPnL(3.24, hideAmounts: false) == "+3.2")
        #expect(GoldCalendarFormat.compactCellPnL(128.4, hideAmounts: false) == "+128")
        #expect(GoldCalendarFormat.compactCellPnL(-1250, hideAmounts: false) == "-1.2k" || GoldCalendarFormat.compactCellPnL(-1250, hideAmounts: false) == "-1.3k")

        // 52~53 周热力矩阵覆盖全年 365 天，且 12 个月完整
        let snap = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: [],
            dailyBars: [:],
            liveQuote: nil,
            temperatures: [:],
            milestoneFirstReached: [:],
            now: day(2026, 11, 21),
            calendar: calendar
        )
        #expect(snap.monthSummaries.count == 12)
        #expect(snap.weeks.count >= 52 && snap.weeks.count <= 54)
        #expect(snap.weeks.allSatisfy { $0.count == 7 })
        let inYearCells = snap.weeks.flatMap { $0 }.filter(\.inTargetYear)
        #expect(inYearCells.count == 365)
    }

    @MainActor
    @Test func posterPrivacyMaskingHidesBuyGramsEvenWhenYearlyPnLIsNil() throws {
        // 模拟无日线数据（如早于日线起点/缺汇率/弱网）导致 totalPnL == nil，但当年有买金记录
        let items = [
            CalendarHoldingItem(grams: 10, unitPriceCNY: 580, timestamp: day(2026, 3, 8)),
            CalendarHoldingItem(grams: 5, unitPriceCNY: 600, timestamp: day(2026, 11, 5))
        ]
        let companion = GoldCalendarEngine.computeCompanionStats(items: items, now: day(2026, 11, 20), calendar: calendar)
        let yearSnap = GoldCalendarEngine.buildYearSnapshot(
            year: 2026,
            items: items,
            dailyBars: [:],
            liveQuote: nil,
            temperatures: [:],
            milestoneFirstReached: companion.milestoneFirstReached,
            now: day(2026, 11, 20),
            calendar: calendar
        )
        #expect(yearSnap.totalPnL == nil)
        #expect(yearSnap.totalBuyGrams == 15)
        let monthSnap = try #require(yearSnap.monthSummary(11))

        let masked = GoldCalendarPosterSnapshot(
            year: 2026,
            month: 11,
            monthSummary: monthSnap,
            yearSnapshot: yearSnap,
            companion: companion,
            basis: .domestic,
            layer: .pnl,
            maskSensitiveAmounts: true
        )
        #expect(masked.yearlyBuySubtitle == nil)
        #expect(masked.monthlyBuySubtitle == nil)
        let renderedYearly = try #require(GoldCalendarPosterRenderer.renderImage(snapshot: masked, mode: .yearly))
        #expect(renderedYearly.size.width > 300)

        let unmasked = GoldCalendarPosterSnapshot(
            year: 2026,
            month: 11,
            monthSummary: monthSnap,
            yearSnapshot: yearSnap,
            companion: companion,
            basis: .domestic,
            layer: .pnl,
            maskSensitiveAmounts: false
        )
        #expect(unmasked.yearlyBuySubtitle == "新攒 +15g · 2笔")
        #expect(unmasked.monthlyBuySubtitle == "本月新攒 +5g")
    }

    // MARK: - 8. 合规零违规词断言

    @Test func allCalendarCopyIsStrictlyObjectiveAndCompliant() {
        let forbidden = [
            "建议", "加仓", "减仓", "定投", "抄底", "追高", "止盈", "建仓", "分批",
            "仓位", "买点", "卖点", "入场", "离场", "逢低", "划算", "便宜", "断签", "别断"
        ]
        let mockMonth = GoldCalendarMonthSummary(
            year: 2026, month: 11, totalPnL: 380, pnlRedDays: 10, pnlGreenDays: 5, pnlFlatDays: 0,
            marketMonthChangePercent: 2.3, latestReferencePriceCNY: 620, marketRedDays: 10, marketGreenDays: 5,
            newBuyGrams: 5, newBuyCount: 2, endOfMonthHoldingGrams: 15,
            unlockedMilestones: [GoldMilestone.ladder[1]]
        )
        let companion = GoldCalendarCompanionStats(
            companionDays: 45, consecutiveActiveMonths: 3, currentHoldingGrams: 15,
            milestoneProgress: .evaluate(totalGrams: 15), milestoneFirstReached: [:], hasAnyRecords: true
        )
        let sampleDay = GoldCalendarDaySnapshot(
            dayKey: CalendarDayKey(year: 2026, month: 11, day: 21),
            date: day(2026, 11, 21), status: .closed, isToday: true,
            endOfDayHoldingGrams: 15, endOfDayEffectiveGrams: 15,
            referencePriceCNY: nil, lastKnownPriceCNY: 620, prevCloseCNY: 615,
            marketChangeCNY: nil, marketChangePercent: nil,
            dailyPnL: nil, dailyPnLRatePercent: nil, dailyPnLBasis: 0, endOfDayValuationCNY: 9300,
            buyGrams: 0, buyCount: 0, soldGrams: 0, giftGrams: 0, events: [], unlockedMilestones: [],
            temperatureScore: 64, temperatureLevel: .warm
        )
        let emptyDay = GoldCalendarDaySnapshot(
            dayKey: CalendarDayKey(year: 2026, month: 11, day: 21),
            date: day(2026, 11, 21), status: .closed, isToday: true,
            endOfDayHoldingGrams: 0, endOfDayEffectiveGrams: 0,
            referencePriceCNY: nil, lastKnownPriceCNY: 620, prevCloseCNY: 615,
            marketChangeCNY: nil, marketChangePercent: nil,
            dailyPnL: nil, dailyPnLRatePercent: nil, dailyPnLBasis: 0, endOfDayValuationCNY: nil,
            buyGrams: 0, buyCount: 0, soldGrams: 0, giftGrams: 0, events: [], unlockedMilestones: [],
            temperatureScore: nil, temperatureLevel: nil
        )

        let strings: [String] = [
            GoldCalendarFormat.headerCompanionBadge(companionDays: 45, hasRecords: true),
            GoldCalendarFormat.headerCompanionBadge(companionDays: 0, hasRecords: false),
            GoldCalendarFormat.monthCompanionBanner(monthSummary: mockMonth, companion: companion, hideAmounts: false) ?? "",
            GoldCalendarFormat.monthCompanionBanner(monthSummary: mockMonth, companion: companion, hideAmounts: true) ?? "",
            GoldCalendarFormat.emptyDayJournalNote(snapshot: sampleDay, hideAmounts: false),
            GoldCalendarFormat.emptyDayJournalNote(snapshot: sampleDay, hideAmounts: true),
            GoldCalendarFormat.emptyDayJournalNote(snapshot: emptyDay, hideAmounts: false),
            GoldCalendarFormat.basisFootnote(basis: .domestic),
            GoldCalendarFormat.basisFootnote(basis: .international)
        ] + MacroTemperatureLevel.allCases.map(\.defaultLabel)

        for text in strings {
            for word in forbidden {
                #expect(!text.contains(word), "发现违规词「\(word)」出现在文案：\(text)")
            }
        }
    }

    // MARK: - 9. iPhone Simulator 多态可视化渲染与验收拼图生成

    @MainActor
    @Test func renderCalendarRedesignStatesForVisualVerification() async throws {
        let now = day(2026, 11, 20) // 周五交易日，展示最完整的实时红绿战报与当日手账
        let (dailyPrices, tempPoints) = makeSyntheticMarketYear(upTo: now)
        let prevClosePrice = dailyPrices.last?.close ?? 621.50
        let livePrice = (prevClosePrice * 1.0112 * 100).rounded() / 100
        let liveQuote = GoldQuote(
            symbol: "AU9999",
            price: livePrice,
            open: prevClosePrice,
            high: livePrice + 1.4,
            low: prevClosePrice - 0.8,
            prevClose: prevClosePrice,
            usdCNY: 7.24,
            cnyPerGram: livePrice,
            asOf: now
        )

        // 构建有持仓 SwiftData 容器（含 1g/10g 里程碑、金条/金豆）
        let filledContainer = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let r1 = HoldingRecord(grams: 6, unitPriceCNY: 572.0, timestamp: day(2026, 8, 12))
        r1.brand = "中金投资金条"; r1.assetType = GoldAssetType.bar.rawValue
        let r2 = HoldingRecord(grams: 5, unitPriceCNY: 598.5, timestamp: day(2026, 11, 5))
        r2.brand = "攒金小豆"; r2.assetType = GoldAssetType.bean.rawValue
        let r3 = HoldingRecord(grams: 2.5, unitPriceCNY: livePrice - 2.4, timestamp: day(2026, 11, 20))
        r3.brand = "周大福金豆"; r3.assetType = GoldAssetType.bean.rawValue
        filledContainer.mainContext.insert(r1)
        filledContainer.mainContext.insert(r2)
        filledContainer.mainContext.insert(r3)
        try filledContainer.mainContext.save()
        let filledItems = [r1, r2, r3].map(\.calendarItem)

        let emptyContainer = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))

        let quoteStore = LiveGoldQuoteStore()
        quoteStore.ingest(liveQuote, for: .domestic)

        func makeVM(items: [CalendarHoldingItem], tab: GoldCalendarViewTab = .month) -> HoldingsCalendarViewModel {
            let vm = HoldingsCalendarViewModel(initialDate: now, calendar: calendar)
            vm.activeTab = tab
            vm.applyDirectFixtures(
                dailyPrices: dailyPrices,
                temperaturePoints: tempPoints,
                basis: .domestic,
                items: items,
                filter: HoldingCalendarFilter(book: "默认账本"),
                liveQuote: liveQuote,
                now: now
            )
            return vm
        }

        let vmMonthPnL = makeVM(items: filledItems, tab: .month)
        let vmEmptyMarket = makeVM(items: [], tab: .month)
        let vmYearHeatmap = makeVM(items: filledItems, tab: .year)
        let vmPrivacy = makeVM(items: filledItems, tab: .month)
        vmPrivacy.selectDate(day(2026, 11, 5), now: now) // 选中非今日，顺便验证 375pt 窄屏含「今」按钮时零截断！

        let posterSnapshot = GoldCalendarPosterSnapshot(
            year: 2026,
            month: 11,
            monthSummary: try #require(vmMonthPnL.focusedMonthSummary),
            yearSnapshot: try #require(vmMonthPnL.yearSnapshot),
            companion: vmMonthPnL.companionStats,
            basis: .domestic,
            layer: .pnl,
            maskSensitiveAmounts: true
        )

        // 验证高清海报渲染器正常产出 PNG
        let renderedPoster = try #require(GoldCalendarPosterRenderer.renderImage(snapshot: posterSnapshot, mode: .monthly))
        #expect(renderedPoster.size.width > 300)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }

        // 使用 375×812 窄屏验证零截断！
        let phoneSize = CGSize(width: 375, height: 812)
        let fixtures: [(String, Bool, AnyView)] = [
            ("1. 月历·持仓盈亏", false, AnyView(
                HoldingsCalendarSheet(
                    initialBook: "默认账本",
                    hideAmounts: false,
                    marketBasis: .domestic,
                    quoteStore: quoteStore,
                    isEmbeddedTab: true,
                    preloadedViewModel: vmMonthPnL
                )
                .modelContainer(filledContainer)
            )),
            ("2. 当日黄金手账卡", true, AnyView(
                HoldingsCalendarSheet(
                    initialBook: "默认账本",
                    hideAmounts: false,
                    marketBasis: .domestic,
                    quoteStore: quoteStore,
                    isEmbeddedTab: true,
                    preloadedViewModel: vmMonthPnL
                )
                .modelContainer(filledContainer)
            )),
            ("3. 无持仓·大盘态", false, AnyView(
                HoldingsCalendarSheet(
                    initialBook: "默认账本",
                    hideAmounts: false,
                    marketBasis: .domestic,
                    quoteStore: quoteStore,
                    isEmbeddedTab: true,
                    preloadedViewModel: vmEmptyMarket
                )
                .modelContainer(emptyContainer)
            )),
            ("4. 年览·52周热力", false, AnyView(
                HoldingsCalendarSheet(
                    initialBook: "默认账本",
                    hideAmounts: false,
                    marketBasis: .domestic,
                    quoteStore: quoteStore,
                    isEmbeddedTab: true,
                    preloadedViewModel: vmYearHeatmap
                )
                .modelContainer(filledContainer)
            )),
            ("5. 隐私脱敏态", false, AnyView(
                HoldingsCalendarSheet(
                    initialBook: "默认账本",
                    hideAmounts: true,
                    marketBasis: .domestic,
                    quoteStore: quoteStore,
                    isEmbeddedTab: true,
                    preloadedViewModel: vmPrivacy
                )
                .modelContainer(filledContainer)
            )),
            ("6. 月度海报预览", false, AnyView(
                GoldCalendarPosterSheet(snapshot: posterSnapshot, initialMode: .monthly)
            ))
        ]

        var captured: [(String, UIImage)] = []
        for (label, scrollToBottom, view) in fixtures {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: phoneSize)
            let controller = UIHostingController(
                rootView: view
                    .preferredColorScheme(.dark)
                    .tint(GoldTheme.gold)
            )
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .dark
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            if scrollToBottom {
                Self.scrollVerticalToBottom(in: controller.view)
                try await Task.sleep(for: .milliseconds(120))
                controller.view.layoutIfNeeded()
            }

            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let png = try #require(image.pngData())
            #expect(png.count > 10_000)
            captured.append((label, image))
            window.isHidden = true
        }
        previousKey?.makeKey()

        // 拼接 5 联多态可视化验收图并保存（仅当设置了验收输出路径或默认写入 scratch 目录）
        let composite = Self.composeReviewBoard(captured, tileSize: phoneSize)
        let pngData = try #require(composite.pngData())
        #expect(pngData.count > 50_000)

        let scratchDir = URL(fileURLWithPath: "/Users/carlwang/.gemini/antigravity/brain/77e4602c-38ee-4d0a-9163-02d8952f541c/scratch", isDirectory: true)
        if FileManager.default.fileExists(atPath: scratchDir.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
            let outURL = scratchDir.appendingPathComponent("sim_calendar_redesign.png")
            try? pngData.write(to: outURL, options: .atomic)
            print("CALENDAR_REDESIGN_ARTIFACT: \(outURL.path)")
        } else {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("sim_calendar_redesign.png")
            try? pngData.write(to: fallback, options: .atomic)
            print("CALENDAR_REDESIGN_ARTIFACT: \(fallback.path)")
        }
    }

    private func makeSyntheticMarketYear(upTo endDate: Date) -> ([GoldDailyPrice], [MacroTemperatureHistoryPoint]) {
        var prices: [GoldDailyPrice] = []
        var temps: [MacroTemperatureHistoryPoint] = []
        var cursor = CalendarDayKey(year: 2026, month: 1, day: 1)
        let endKey = CalendarDayKey(date: endDate, calendar: calendar)
        var currentPrice = 560.0
        var step = 0

        while cursor < endKey {
            let d = cursor.noonDate(calendar: calendar)
            let weekday = calendar.component(.weekday, from: d)
            if weekday != 1 && weekday != 7 {
                // 确定性波浪波动，产生覆盖 3 档红绿热力的自然样本
                let wave = sin(Double(step) * 0.43) * 0.014 + cos(Double(step) * 0.17) * 0.008 + 0.0005
                let open = currentPrice
                let close = max(510, currentPrice * (1 + wave))
                prices.append(GoldDailyPrice(date: d, open: open, high: max(open, close) * 1.004, low: min(open, close) * 0.996, close: close))
                let score = min(92, max(18, 52 + sin(Double(step) * 0.11) * 28))
                temps.append(MacroTemperatureHistoryPoint(
                    dateString: cursor.isoString,
                    date: d,
                    score: score,
                    level: MacroTemperatureLevel.from(score: score),
                    goldPriceUSD: close * 4.3
                ))
                currentPrice = close
                step += 1
            }
            cursor = cursor.addingDays(1, calendar: calendar)
        }
        // 为今日补齐黄金温度样本，便于三联指标格视觉核验
        temps.append(MacroTemperatureHistoryPoint(
            dateString: endKey.isoString,
            date: endKey.noonDate(calendar: calendar),
            score: 64,
            level: .warm,
            goldPriceUSD: currentPrice * 4.3
        ))
        return (prices, temps)
    }

    @MainActor
    private static func scrollVerticalToBottom(in root: UIView) {
        if let scroll = root as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 10 {
            let maxY = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: maxY), animated: false)
        }
        for child in root.subviews {
            scrollVerticalToBottom(in: child)
        }
    }

    @MainActor
    private static func composeReviewBoard(_ panels: [(String, UIImage)], tileSize: CGSize) -> UIImage {
        let padding: CGFloat = 24
        let headerHeight: CGFloat = 38
        let cols = panels.count
        let totalWidth = CGFloat(cols) * tileSize.width + CGFloat(cols + 1) * padding
        let totalHeight = tileSize.height + headerHeight + padding * 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight), format: format)
        return renderer.image { ctx in
            UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 0.95, green: 0.80, blue: 0.25, alpha: 1)
            ]

            for (idx, (title, image)) in panels.enumerated() {
                let x = padding + CGFloat(idx) * (tileSize.width + padding)
                let titleRect = CGRect(x: x, y: padding, width: tileSize.width, height: headerHeight)
                (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

                let imgRect = CGRect(x: x, y: padding + headerHeight, width: tileSize.width, height: tileSize.height)
                let clipPath = UIBezierPath(roundedRect: imgRect, cornerRadius: 24)
                ctx.cgContext.saveGState()
                clipPath.addClip()
                image.draw(in: imgRect)
                ctx.cgContext.restoreGState()

                UIColor(white: 1, alpha: 0.14).setStroke()
                clipPath.lineWidth = 1.5
                clipPath.stroke()
            }
        }
    }
}
