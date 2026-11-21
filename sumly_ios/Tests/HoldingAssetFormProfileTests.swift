import Foundation
import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Sumly

// MARK: - 1. 5 大形态副标题、标题、纯度胶囊与字段可见性

@Test func assetFormProfileMatchesAllFiveTypesSpecifications() {
    let accumulation = HoldingAssetFormProfile.profile(for: .accumulation)
    #expect(accumulation.drawerSubtitle == "平台渠道、赎回费率、日期、账本、备注")
    #expect(accumulation.recoverySectionTitle == "赎回费用规则")
    #expect(accumulation.channelFieldTitle == "银行 / 平台")
    #expect(accumulation.channelPlaceholder.contains("工商银行"))
    #expect(accumulation.channelPlaceholder.contains("招商银行"))
    #expect(accumulation.channelPlaceholder.contains("支付宝"))
    #expect(accumulation.discountFieldTitle == "赎回费率")
    #expect(accumulation.fixedFeeFieldTitle == "固定卖出费")
    #expect(accumulation.otherCostFieldTitle == "其他费用")
    #expect(!accumulation.showsLabor)
    #expect(!accumulation.showsBrand)
    #expect(!accumulation.showsPerGramDeduction)
    #expect(!accumulation.showsPurity)
    #expect(accumulation.showsChannel)
    #expect(accumulation.showsDiscountRate)
    #expect(accumulation.showsFixedFee)
    #expect(accumulation.showsOtherCost)
    #expect(accumulation.subPresets.map(\.title) == ["银行积存金", "支付宝黄金"])
    #expect(!accumulation.notePlaceholder.contains("定投"))

    let bean = HoldingAssetFormProfile.profile(for: .bean)
    #expect(bean.drawerSubtitle == "品牌/金店、工费、纯度、回购扣减、日期、账本、备注")
    #expect(bean.purityPresets == ["99.99", "99.9"])
    #expect(bean.laborPerGramFieldTitle == "工费")
    #expect(bean.brandPlaceholder.contains("水贝"))
    #expect(bean.brandPlaceholder.contains("菜百"))
    #expect(bean.brandPlaceholder.contains("周大福"))
    #expect(bean.recoverySectionTitle == "回购扣减规则")
    #expect(bean.showsPurity && bean.showsLabor && bean.showsBrand && bean.showsPerGramDeduction)
    #expect(bean.subPresets.map(\.title) == ["水贝低工费金豆", "品牌金豆"])

    let bar = HoldingAssetFormProfile.profile(for: .bar)
    #expect(bar.drawerSubtitle == "发行银行/品牌、加工费、纯度、回购扣减、日期、账本、备注")
    #expect(bar.purityPresets == ["99.99", "99.9"])
    #expect(bar.laborPerGramFieldTitle == "加工 / 溢价费")
    #expect(bar.brandPlaceholder.contains("工商银行"))
    #expect(bar.brandPlaceholder.contains("建设银行"))
    #expect(bar.brandPlaceholder.contains("中钞"))
    #expect(bar.recoverySectionTitle == "银行/金店回购规则")
    #expect(bar.showsPurity && bar.showsLabor && bar.showsBrand && bar.showsPerGramDeduction)
    #expect(bar.subPresets.map(\.title) == ["银行投资金条", "工艺金条"])

    let jewelry = HoldingAssetFormProfile.profile(for: .jewelry)
    #expect(jewelry.drawerSubtitle == "金饰品牌、工艺工费、纯度、回收折价、日期、账本、备注")
    #expect(jewelry.purityPresets == ["99.99", "99.9", "91.6", "75"])
    #expect(jewelry.laborPerGramFieldTitle == "工艺工费")
    #expect(jewelry.laborTotalOptionLabel == "一口价")
    #expect(jewelry.brandPlaceholder.contains("周大福"))
    #expect(jewelry.brandPlaceholder.contains("老凤祥"))
    #expect(jewelry.brandPlaceholder.contains("周生生"))
    #expect(jewelry.brandPlaceholder.contains("水贝"))
    #expect(jewelry.recoverySectionTitle == "金饰回收折价规则")
    #expect(jewelry.showsPurity && jewelry.showsLabor && jewelry.showsBrand && jewelry.showsPerGramDeduction)
    #expect(jewelry.subPresets.map(\.title) == ["品牌金饰", "水贝金饰"])

    let other = HoldingAssetFormProfile.profile(for: .other)
    #expect(other.drawerSubtitle == "纯度、品牌、渠道、工费、回收规则、日期、账本、备注")
    #expect(other.showsPurity && other.showsLabor && other.showsBrand && other.showsChannel)
    #expect(other.showsPerGramDeduction && other.showsDiscountRate && other.showsFixedFee && other.showsOtherCost)
    #expect(other.subPresets.isEmpty)
}

// MARK: - 2. 专属场景快捷微调应用（保留用户克重、单价、总价模式与备注）

@Test func assetSubPresetsApplyDefaultsAndPreserveUserEntries() throws {
    // 积存金：银行积存金 -> 支付宝黄金
    var accDraft = HoldingDraft()
    accDraft.selectAssetType(.accumulation)
    accDraft.gramsText = "10"
    accDraft.priceText = "680.00"
    accDraft.note = "每月积存"

    let accPresets = HoldingAssetFormProfile.profile(for: .accumulation).subPresets
    let bankPreset = try #require(accPresets.first { $0.id == "accumulation.bank" })
    bankPreset.apply(to: &accDraft)
    #expect(accDraft.assetType == .accumulation)
    #expect(accDraft.laborText == "0")
    #expect(accDraft.discountText == "0.5")
    #expect(accDraft.channel == "工商银行")
    #expect(accDraft.gramsText == "10")
    #expect(accDraft.priceText == "680.00")
    #expect(accDraft.note == "每月积存")
    #expect(accDraft.totalText == "6800.00")
    #expect(accDraft.defaultsSummaryText == "99.99% · 赎回0.5%")

    let alipayPreset = try #require(accPresets.first { $0.id == "accumulation.alipay" })
    alipayPreset.apply(to: &accDraft)
    #expect(accDraft.discountText == "0")
    #expect(accDraft.channel == "支付宝")
    #expect(accDraft.defaultsSummaryText == "99.99% · 0工费")

    // 金饰：品牌金饰在单价模式下同步总价，在总价模式下保留手填总价
    var jewelryDraft = HoldingDraft()
    jewelryDraft.selectAssetType(.jewelry)
    jewelryDraft.gramsText = "10"
    jewelryDraft.priceText = "680.00"
    jewelryDraft.note = "纪念日手镯"

    let jewelryPresets = HoldingAssetFormProfile.profile(for: .jewelry).subPresets
    let brandJewelry = try #require(jewelryPresets.first { $0.id == "jewelry.brand" })
    brandJewelry.apply(to: &jewelryDraft)
    #expect(jewelryDraft.purityText == "99.9")
    #expect(jewelryDraft.laborText == "60")
    #expect(jewelryDraft.deductionText == "15")
    #expect(jewelryDraft.totalText == "7400.00")
    #expect(jewelryDraft.note == "纪念日手镯")

    jewelryDraft.updateTotalPrice("7999")
    let shuibeiJewelry = try #require(jewelryPresets.first { $0.id == "jewelry.shuibei" })
    shuibeiJewelry.apply(to: &jewelryDraft)
    #expect(jewelryDraft.costMode == .total)
    #expect(jewelryDraft.totalText == "7999")
    #expect(jewelryDraft.purityText == "99.99")
    #expect(jewelryDraft.laborText == "15")
    #expect(jewelryDraft.brand == "水贝")

    // 金条 & 金豆微调
    var barDraft = HoldingDraft()
    barDraft.selectAssetType(.bar)
    barDraft.gramsText = "20"
    barDraft.priceText = "680.00"
    let craftBar = try #require(HoldingAssetFormProfile.profile(for: .bar).subPresets.first { $0.id == "bar.craft" })
    craftBar.apply(to: &barDraft)
    #expect(barDraft.laborText == "25")
    #expect(barDraft.deductionText == "10")
    #expect(barDraft.totalText == "14100.00")

    var beanDraft = HoldingDraft()
    beanDraft.selectAssetType(.bean)
    beanDraft.gramsText = "5"
    beanDraft.priceText = "680.00"
    let shuibeiBean = try #require(HoldingAssetFormProfile.profile(for: .bean).subPresets.first { $0.id == "bean.shuibei" })
    shuibeiBean.apply(to: &beanDraft)
    #expect(beanDraft.laborText == "5")
    #expect(beanDraft.deductionText == "3")
    #expect(beanDraft.brand == "水贝")
    #expect(beanDraft.totalText == "3425.00")
}

// MARK: - 3. 编辑含旧非零字段记录时的保护显示逻辑

@Test func accumulationLegacyRecordProtectionRevealsNonZeroOrNonEmptyFields() {
    // 干净的新积存金记录：隐藏工费、品牌、每克扣减与纯度
    let cleanRecord = HoldingRecord(grams: 10, unitPriceCNY: 680, timestamp: .now)
    cleanRecord.assetType = GoldAssetType.accumulation.rawValue
    cleanRecord.purity = 0.9999
    cleanRecord.laborFee = 0
    cleanRecord.brand = ""
    cleanRecord.recoveryDeduction = 0
    cleanRecord.recoveryDiscount = 0.005

    let cleanLegacy = HoldingAssetFormLegacyPresence(record: cleanRecord)
    let cleanDraft = HoldingDraft(record: cleanRecord)
    let cleanProfile = HoldingAssetFormProfile.profile(for: .accumulation, draft: cleanDraft, legacy: cleanLegacy)
    #expect(!cleanProfile.showsLabor)
    #expect(!cleanProfile.showsBrand)
    #expect(!cleanProfile.showsPerGramDeduction)
    #expect(!cleanProfile.showsPurity)

    // 含旧数据的积存金记录：laborFee > 0 / brand 非空 / recoveryDeduction > 0 / 非 99.99% 纯度全部自动展示
    let legacyRecord = HoldingRecord(grams: 10, unitPriceCNY: 680, timestamp: .now)
    legacyRecord.assetType = GoldAssetType.accumulation.rawValue
    legacyRecord.purity = 0.999
    legacyRecord.laborFee = 25
    legacyRecord.brand = "工行如意金"
    legacyRecord.recoveryDeduction = 4

    let legacyPresence = HoldingAssetFormLegacyPresence(record: legacyRecord)
    var editingDraft = HoldingDraft(record: legacyRecord)
    let editingProfile = HoldingAssetFormProfile.profile(for: .accumulation, draft: editingDraft, legacy: legacyPresence)
    #expect(editingProfile.showsLabor)
    #expect(editingProfile.showsBrand)
    #expect(editingProfile.showsPerGramDeduction)
    #expect(editingProfile.showsPurity)

    // 编辑中途即使清空输入框准备改值，字段依然保持可见不突然消失
    editingDraft.laborText = ""
    editingDraft.brand = ""
    editingDraft.deductionText = ""
    let whileClearedProfile = HoldingAssetFormProfile.profile(for: .accumulation, draft: editingDraft, legacy: legacyPresence)
    #expect(whileClearedProfile.showsLabor)
    #expect(whileClearedProfile.showsBrand)
    #expect(whileClearedProfile.showsPerGramDeduction)

    // 单独仅有一项旧字段非零时，只显示该项而不暴露其他无关项
    var onlyBrandDraft = HoldingDraft()
    onlyBrandDraft.selectAssetType(.accumulation)
    onlyBrandDraft.brand = "招商银行"
    let onlyBrandProfile = HoldingAssetFormProfile.profile(for: .accumulation, draft: onlyBrandDraft)
    #expect(onlyBrandProfile.showsBrand)
    #expect(!onlyBrandProfile.showsLabor)
    #expect(!onlyBrandProfile.showsPerGramDeduction)
}

@Test func mergedTagsPrioritizesRecentAndDeduplicates() {
    let tags = HoldingAssetFormProfile.mergedTags(
        recent: ["招商银行", " 水贝 ", "招商银行", ""],
        suggested: ["工商银行", "招商银行", "支付宝", "建设银行", "民生银行"],
        limit: 5
    )
    #expect(tags == ["招商银行", "水贝", "工商银行", "支付宝", "建设银行"])
}

// MARK: - 4. Simulator 实跑渲染验收：积存金 / 金饰 / 金条 / 金豆 展开态视觉验证

@MainActor @Test func formLinkageExpandedStatesRenderInSimulator() async throws {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
    let previousWindow = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-form-linkage-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let fixedDate = Date(timeIntervalSince1970: 1_795_200_000)

    func makeDraft(_ type: GoldAssetType, configure: (inout HoldingDraft) -> Void = { _ in }) -> HoldingDraft {
        var draft = HoldingDraft()
        draft.selectAssetType(type)
        draft.applyQuickGrams(10, fallbackUnitPrice: 685.50)
        configure(&draft)
        return draft
    }

    let cases: [(String, HoldingDraft)] = [
        (
            "01-accumulation-expanded",
            makeDraft(.accumulation) {
                $0.channel = "工商银行"
                $0.discountText = "0.5"
            }
        ),
        (
            "02-jewelry-expanded",
            makeDraft(.jewelry) {
                $0.brand = "周大福"
                $0.channel = "专柜门店"
                $0.deductionText = "15"
            }
        ),
        (
            "03-bar-expanded",
            makeDraft(.bar) {
                $0.brand = "工商银行"
                $0.channel = "手机银行"
                $0.deductionText = "3"
            }
        ),
        (
            "04-bean-expanded",
            makeDraft(.bean) {
                $0.brand = "水贝"
                $0.deductionText = "3"
            }
        )
    ]

    for (name, draftSeed) in cases {
        let content = AddHoldingSheet(
            defaultUnitPrice: 685.50,
            date: fixedDate,
            marketBasis: .domestic,
            seed: draftSeed,
            initiallyExpanded: true
        )
        .modelContainer(container)
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)

        // 完整展示顶部形态栏 + 核心输入卡 + 展开抽屉全部 5 个分区（含回收规则与备注）
        let screenWidth = scene.screen.bounds.width
        let tallFrame = CGRect(x: 0, y: 0, width: screenWidth, height: 2120)
        let window = UIWindow(windowScene: scene)
        window.frame = tallFrame
        let controller = UIHostingController(rootView: content)
        controller.view.frame = tallFrame
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: tallFrame).image { _ in
            window.drawHierarchy(in: tallFrame, afterScreenUpdates: true)
        }
        let path = directory.appendingPathComponent(name + ".png")
        let data = try #require(image.pngData())
        #expect(!data.isEmpty)
        try data.write(to: path)
        print("FORM_LINKAGE_RENDER: \(path.path)")
        window.isHidden = true
    }

    previousWindow?.makeKey()
}
