import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Sumly

@Suite(.serialized)
struct HoldingHolderTests {
    @Test func holderEnumCoversAllSevenFamilyMembersAndParsing() {
        #expect(HoldingHolder.allCases == [.mother, .father, .husband, .wife, .child, .grandfather, .grandmother])
        #expect(HoldingHolder.parse(nil) == nil)
        #expect(HoldingHolder.parse("") == nil)
        #expect(HoldingHolder.parse("   ") == nil)
        #expect(HoldingHolder.parse("stranger") == nil)
        #expect(HoldingHolder.parse("mother") == .mother)
        #expect(HoldingHolder.parse(" grandmother ") == .grandmother)

        #expect(HoldingHolder.isValidCloudValue(nil))
        #expect(HoldingHolder.isValidCloudValue("father"))
        #expect(!HoldingHolder.isValidCloudValue(""))
        #expect(!HoldingHolder.isValidCloudValue("uncle"))
    }

    @Test func holderDisplayNamesTranslateAcrossAllSixLanguages() {
        for language in AppLanguage.allCases where language != .system {
            AppLanguage.$taskOverrideForTesting.withValue(language) {
                for holder in HoldingHolder.allCases {
                    #expect(!holder.displayName.isEmpty)
                    #expect(!holder.ownershipLabel.isEmpty)
                    if language != .zhHans {
                        #expect(holder.displayName != holder.rawValue)
                    }
                }
            }
        }
    }

    @MainActor
    @Test func draftAndSwiftDataRoundTripHolder() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: HoldingRecord.self, configurations: config)
        let context = container.mainContext

        var draft = HoldingDraft()
        draft.assetType = .jewelry
        draft.gramsText = "12.5"
        draft.priceText = "780"
        draft.brand = "周大福"
        draft.holder = .mother

        let input = try #require(draft.input)
        let record = HoldingRecord(grams: input.grams, unitPriceCNY: input.unitPrice, timestamp: .now)
        draft.apply(to: record, input: input)
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<HoldingRecord>())
        #expect(fetched.count == 1)
        #expect(fetched[0].holder == "mother")
        #expect(fetched[0].holdingHolder == .mother)

        let editingDraft = HoldingDraft(record: fetched[0])
        #expect(editingDraft.holder == .mother)

        // 切回自己（nil）后清空存储值
        var clearedDraft = editingDraft
        clearedDraft.holder = nil
        clearedDraft.apply(to: fetched[0], input: try #require(clearedDraft.input))
        #expect(fetched[0].holder.isEmpty)
        #expect(fetched[0].holdingHolder == nil)
    }

    @MainActor
    @Test func partialDisposalPreservesHolderAndSearchMatchesHolderName() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: HoldingRecord.self, configurations: config)
        let context = container.mainContext

        let purchasedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let motherRecord = HoldingRecord(grams: 10, unitPriceCNY: 780, timestamp: purchasedAt)
        motherRecord.brand = "周生生"
        motherRecord.holder = HoldingHolder.mother.rawValue

        let fatherRecord = HoldingRecord(grams: 20, unitPriceCNY: 770, timestamp: purchasedAt)
        fatherRecord.brand = "招行积存金"
        fatherRecord.holder = HoldingHolder.father.rawValue

        context.insert(motherRecord)
        context.insert(fatherRecord)
        try context.save()

        let filtered = HoldingsSelection.records(
            [motherRecord, fatherRecord],
            book: "默认账本",
            search: "母亲",
            filter: .all,
            sort: .newest,
            quote: 800
        )
        #expect(filtered.map(\.id) == [motherRecord.id])

        try HoldingDisposal.apply(
            record: motherRecord,
            grams: 4,
            proceeds: 3400,
            kind: "sold",
            date: purchasedAt.addingTimeInterval(86400),
            context: context
        )
        let all = try context.fetch(FetchDescriptor<HoldingRecord>())
        #expect(all.count == 2 + 1)
        let sold = try #require(all.first { $0.disposition == "sold" })
        #expect(sold.holdingHolder == .mother)
    }

    @MainActor
    @Test func cloudDocumentPreservesHolderAndOmitsUnsetHolderForLegacyCompatibility() throws {
        // 未设置持有人时，JSON 编码必须省略 holder 字段以保持与旧端/旧服务兼容
        let plain = HoldingRecord(grams: 5, unitPriceCNY: 780, timestamp: .now)
        let plainWire = HoldingCloudRecord(plain)
        #expect(plainWire.holder == nil)
        let plainJSON = String(decoding: try HoldingCloudCoding.encode(plainWire), as: UTF8.self)
        #expect(!plainJSON.contains("\"holder\""))

        // 设置持有人时，往返编解码与 apply 完整保留
        let assigned = HoldingRecord(grams: 8, unitPriceCNY: 790, timestamp: .now)
        assigned.holder = HoldingHolder.grandmother.rawValue
        let assignedWire = HoldingCloudRecord(assigned)
        #expect(assignedWire.holder == "grandmother")
        let encoded = try HoldingCloudCoding.encode(assignedWire)
        let decoded = try HoldingCloudCoding.decode(HoldingCloudRecord.self, from: encoded)
        #expect(decoded == assignedWire)
        #expect(decoded.makeRecord().holdingHolder == .grandmother)

        // 文档校验拒绝非法 holder 值
        var invalidRecord = assignedWire
        invalidRecord.holder = "invalid_role"
        let invalidDoc = HoldingDocument(books: ["默认账本"], records: [invalidRecord])
        #expect(!invalidDoc.isValid)

        // 三方合并能识别并保留独立的 holder 修改
        let base = HoldingDocument(books: ["默认账本"], records: [plainWire])
        var local = base
        local.records[0].holder = HoldingHolder.wife.rawValue
        let merged = HoldingCloudMerge.merge(base: base, local: local, remote: base)
        #expect(merged.conflicts.isEmpty)
        #expect(merged.document.records.first?.holder == "wife")
    }

    @MainActor
    @Test func avatarsAndSelectorRenderWithoutCrash() throws {
        for holder in HoldingHolder.allCases {
            let renderer = ImageRenderer(content: HoldingHolderAvatar(holder: holder, size: 36, emphasized: true))
            renderer.scale = 2
            #expect(renderer.uiImage != nil)
        }

        // 导出暗黑金视觉验收拼图（7 位家人近景头像 + 表单选择器 + 持仓列表卡片 + 详情徽章）
        let sampleDay = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        let sampleRows: [(String, GoldAssetType, Double, Double, HoldingHolder?)] = [
            ("周大福手镯", .jewelry, 25, 792, .mother),
            ("招行积存金", .accumulation, 50, 760, .father),
            ("投资金条", .bar, 30, 775, .husband),
            ("六福吊坠", .jewelry, 12.5, 815, .wife),
            ("小金豆", .bean, 3, 780, .child),
            ("贺岁金条", .bar, 20, 745, .grandfather),
            ("古法金镯", .jewelry, 32, 768, .grandmother),
            ("海外购买", .bar, 10, 770, nil)
        ]
        let records: [HoldingRecord] = sampleRows.map { item in
            let r = HoldingRecord(grams: item.2, unitPriceCNY: item.3, timestamp: sampleDay)
            r.brand = item.0
            r.assetType = item.1.rawValue
            r.holder = item.4?.rawValue ?? ""
            return r
        }

        let showcase = VStack(alignment: .leading, spacing: 14) {
            Text("7 位家人暗黑金头像近景")
                .font(.caption.bold())
                .foregroundStyle(GoldTheme.textSecondary)
            HStack(spacing: 10) {
                ForEach(HoldingHolder.allCases) { holder in
                    VStack(spacing: 4) {
                        HoldingHolderAvatar(holder: holder, size: 42, emphasized: true)
                        Text(holder.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GoldTheme.text)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)

            HoldingHolderSelectorCard(selected: .constant(.mother))

            VStack(spacing: 10) {
                ForEach(records) { record in
                    HoldingRowView(
                        record: record,
                        result: GoldReturnCalculator.calculate(record.returnInput, referencePrice: 805.0),
                        hideAmounts: false
                    )
                }
            }
        }
        .padding(16)
        .frame(width: 393)
        .background(GoldTheme.background)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: showcase)
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-holder-review", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("holder-showcase.png")
        try #require(image.pngData()).write(to: url)
        print("HOLDER_REVIEW_ARTIFACT: \(url.path)")
    }
}
