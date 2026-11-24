import SwiftUI
import SwiftData

struct AddHoldingSheet: View {
    private static let detailsParamsAnchorID = "holding.details.params"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \HoldingRecord.timestamp, order: .reverse) private var existingRecords: [HoldingRecord]
    let marketBasis: GoldMarketBasis
    @State private var draft: HoldingDraft
    @State private var purchasePrice: HoldingPurchasePriceModel
    @State private var timestamp: Date
    @State private var advanced: Bool
    @State private var selectedSubPreset: HoldingAssetSubPreset?
    @State private var selectedBook: String
    @State private var quickGramPulse = 0
    @State private var detailsFocusPulse = 0
    @State private var pendingExpandScroll = false
    @State private var highlightDetailsDrawer = false
    @State private var receipt: HoldingReceiptSnapshot?
    private let targetBook: String?
    private let editing: HoldingRecord?
    private let legacyPresence: HoldingAssetFormLegacyPresence
    private let onSaved: (() -> Void)?
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @State private var errorMessage: String?

    private var recentBrands: [String] {
        HoldingsInsights.recentTags(from: existingRecords.map(\.insightEntry), keyPath: \.brand)
    }
    private var recentChannels: [String] {
        HoldingsInsights.recentTags(from: existingRecords.map(\.insightEntry), keyPath: \.channel)
    }
    private var availableBooks: [String] {
        Array(Set(savedBooks.components(separatedBy: "\n") + existingRecords.map(\.bookName) + [selectedBook, book, "默认账本"]))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    init(defaultUnitPrice: Double?, date: Date = .now, book: String? = nil, marketBasis: GoldMarketBasis = .domestic,
         editing: HoldingRecord? = nil, seed: HoldingDraft? = nil, initiallyExpanded: Bool? = nil, onSaved: (() -> Void)? = nil) {
        targetBook = book
        self.editing = editing
        self.legacyPresence = editing.map(HoldingAssetFormLegacyPresence.init(record:)) ?? .none
        self.onSaved = onSaved
        self.marketBasis = marketBasis

        let day = editing?.timestamp ?? min(date, .now)
        _timestamp = State(initialValue: day)
        _advanced = State(initialValue: initiallyExpanded ?? (editing != nil))

        var values: HoldingDraft
        if let editing {
            values = HoldingDraft(record: editing)
        } else if let seed {
            values = seed
        } else {
            values = HoldingDraft()
            values.selectAssetType(.bean, applyDefaults: true)
        }

        let priceModel = HoldingPurchasePriceModel(
            date: day,
            basis: marketBasis,
            initialPrice: defaultUnitPrice,
            service: BackendGoldPriceService(instrumentID: marketBasis.instrumentID)
        )
        if editing != nil || seed != nil {
            priceModel.editPrice(values.priceText)
        } else if !priceModel.priceText.isEmpty {
            values.priceText = priceModel.priceText
            values.syncCalculatedTotal()
        }
        _draft = State(initialValue: values)
        _purchasePrice = State(initialValue: priceModel)

        let initialBook = editing?.bookName
            ?? book
            ?? UserDefaults.standard.string(forKey: "holdings.currentBook")
            ?? "默认账本"
        _selectedBook = State(initialValue: initialBook)
    }

    private var result: GoldReturnResult? {
        draft.input.flatMap { GoldReturnCalculator.calculate($0, referencePrice: nil) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        assetTypeSelector
                        coreInputCard {
                            focusDetailsParameters(using: scrollProxy)
                        }
                        detailsDrawer
                            .id(Self.detailsParamsAnchorID)
                            .overlay {
                                GoldTheme.holdingsCardShape
                                    .strokeBorder(
                                        GoldTheme.gold.opacity(highlightDetailsDrawer ? 0.72 : 0),
                                        lineWidth: 1.5
                                    )
                                    .allowsHitTesting(false)
                            }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(GoldTheme.up)
                        }
                    }
                    .padding(16)
                }
                .task(id: detailsFocusPulse) {
                    guard detailsFocusPulse > 0 else { return }
                    if pendingExpandScroll {
                        pendingExpandScroll = false
                        try? await Task.sleep(for: .milliseconds(reduceMotion ? 30 : 80))
                        guard !Task.isCancelled else { return }
                        scrollToDetailsParameters(using: scrollProxy)
                    }
                    setDetailsHighlight(true)
                    try? await Task.sleep(for: .milliseconds(750))
                    guard !Task.isCancelled else { return }
                    setDetailsHighlight(false)
                }
            }
            .background(GoldTheme.background)
            .goldKeyboardDismissable(showToolbar: false)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GoldKeyboardActionBar {
                    Button(editing == nil ? L10n.tr("确认入库") : L10n.tr("保存修改")) { save() }
                        .buttonStyle(GoldPrimaryButtonStyle())
                }
            }
            .navigationTitle(editing == nil ? L10n.tr("记一笔黄金") : L10n.tr("编辑持仓"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("取消")) { dismiss() }
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }
        }
        .presentationBackground(GoldTheme.background)
        .sensoryFeedback(.selection, trigger: draft.assetType)
        .sensoryFeedback(.selection, trigger: quickGramPulse)
        .sensoryFeedback(.selection, trigger: detailsFocusPulse)
        .sensoryFeedback(.selection, trigger: selectedSubPreset)
        .sensoryFeedback(.success, trigger: receipt?.id)
        .task(id: purchasePrice.selectedDay) {
            await purchasePrice.load()
            syncReferencePriceIntoDraft()
        }
        .onChange(of: advanced) { _, isExpanded in
            if !isExpanded {
                setDetailsHighlight(false)
            }
        }
        .onChange(of: purchasePrice.priceText) {
            syncReferencePriceIntoDraft()
        }
        .onChange(of: draft.laborText) {
            if draft.costMode == .unit { draft.syncCalculatedTotal() }
        }
        .onChange(of: draft.laborPerGram) {
            if draft.costMode == .unit { draft.syncCalculatedTotal() }
        }
        .onChange(of: draft.otherText) {
            if draft.costMode == .unit { draft.syncCalculatedTotal() }
        }
        .sheet(item: $receipt, onDismiss: { dismiss() }) { snapshot in
            HoldingReceiptSheet(snapshot: snapshot) {
                receipt = nil
            }
        }
    }

    // MARK: - Step 1: 顶部 4 形态大视觉图标卡片 + 标题栏右侧「其他」小胶囊

    private var assetTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("选择形态"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer()
                let isOtherSelected = draft.assetType == .other
                Button {
                    selectAssetType(.other)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10, weight: .semibold))
                        Text(GoldAssetType.other.displayName)
                            .font(.caption2.weight(isOtherSelected ? .bold : .semibold))
                    }
                    .foregroundStyle(isOtherSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isOtherSelected ? GoldTheme.gold : GoldTheme.card,
                        in: GoldTheme.capsuleShape
                    )
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(
                            isOtherSelected ? GoldTheme.gold : GoldTheme.cardStroke,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("切换其他黄金形态"))
                .accessibilityAddTraits(isOtherSelected ? .isSelected : [])
            }

            HStack(spacing: 10) {
                ForEach(GoldAssetType.primaryQuickTypes) { type in
                    let isSelected = draft.assetType == type
                    Button {
                        selectAssetType(type)
                    } label: {
                        VStack(spacing: 7) {
                            GoldAssetGlyph(type: type, size: 38, emphasized: isSelected)
                            Text(type.displayName)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? GoldTheme.goldSoft : GoldTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(type.quickTagline)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(isSelected ? GoldTheme.gold : GoldTheme.textFaint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .background(
                            ZStack {
                                GoldTheme.holdingsCardShape.fill(GoldTheme.card)
                                if isSelected {
                                    GoldTheme.holdingsCardShape.fill(
                                        RadialGradient(
                                            colors: [GoldTheme.gold.opacity(0.18), GoldTheme.gold.opacity(0.03)],
                                            center: .top,
                                            startRadius: 2,
                                            endRadius: 88
                                        )
                                    )
                                }
                            }
                        )
                        .overlay(
                            GoldTheme.holdingsCardShape.strokeBorder(
                                isSelected ? GoldTheme.gold : GoldTheme.cardStroke,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                        )
                        .shadow(color: isSelected ? GoldTheme.addButtonShadow.opacity(0.55) : .clear, radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Step 2: 核心克重 + 一键克重胶囊 + 单价/总价实时联动卡片

    private func coreInputCard(onFocusDetails: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 克重标题与当前默认参数标签
            HStack(alignment: .center) {
                Text(L10n.tr("购入克重"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer(minLength: 6)
                Button {
                    onFocusDetails()
                } label: {
                    HStack(spacing: 4) {
                        Text(draft.defaultsSummaryText)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("展开并定位到纯度与费用细节"))
            }

            // 大号克重输入框
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(
                    "",
                    text: Binding(
                        get: { draft.gramsText },
                        set: { draft.updateGrams($0) }
                    ),
                    prompt: Text("0.00").foregroundStyle(GoldTheme.textFaint)
                )
                .keyboardType(.decimalPad)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(L10n.tr("购入克重"))

                Text("g")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

            // 一键快捷克重胶囊（1g / 5g / 10g / 20g / 50g / 100g）
            HStack(spacing: 6) {
                ForEach(HoldingDraft.quickGramOptions, id: \.self) { grams in
                    let isChosen = draft.parsedGrams.map { abs($0 - grams) < 0.0001 } ?? false
                    Button {
                        quickGramPulse += 1
                        draft.applyQuickGrams(
                            grams,
                            fallbackUnitPrice: purchasePrice.validPrice ?? purchasePrice.reference?.price
                        )
                    } label: {
                        Text("\(HoldingDraft.formatGrams(grams))g")
                            .font(.system(size: 12, weight: isChosen ? .bold : .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(isChosen ? GoldTheme.onGold : GoldTheme.goldSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                isChosen ? GoldTheme.gold : GoldTheme.calendarCell,
                                in: GoldTheme.capsuleShape
                            )
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(
                                    isChosen ? GoldTheme.gold : GoldTheme.cardStroke,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(GoldTheme.cardStroke)

            // 单价 / 总价实时联动输入区
            HStack(spacing: 10) {
                linkedPriceBox(
                    title: L10n.tr("单价（元/克）"),
                    badge: draft.costMode == .unit ? (purchasePrice.isManual ? L10n.tr("手动") : L10n.tr("参考价")) : L10n.tr("参考基准"),
                    badgeHighlighted: draft.costMode == .unit,
                    placeholder: L10n.tr("元/克"),
                    text: Binding(
                        get: { purchasePrice.priceText },
                        set: {
                            purchasePrice.editPrice($0)
                            draft.updateUnitPrice($0)
                        }
                    )
                )

                linkedPriceBox(
                    title: L10n.tr("总价（元）"),
                    badge: draft.costMode == .total ? L10n.tr("实付总价") : L10n.tr("自动估算"),
                    badgeHighlighted: draft.costMode == .total,
                    placeholder: L10n.tr("自动算出"),
                    text: Binding(
                        get: { draft.totalText },
                        set: { draft.updateTotalPrice($0) }
                    )
                )
            }

            priceReferenceStatus

            // 即时保本金价摘要条
            if let result {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("预计真实保本金价"))
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text(draft.costMode == .total
                             ? L10n.fmt("综合单价 ¥%@ / g · 已含工费", result.comprehensiveUnitCost.moneyText)
                             : L10n.fmt("总投入 ¥%@ · 按当前参数估算", result.totalCost.moneyText))
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 6)
                    Text("¥\(result.breakEvenPrice.moneyText)/g")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.gold)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GoldTheme.background, in: GoldTheme.subCardShape)
                .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.24), lineWidth: 1))
            } else {
                Text(L10n.tr("选好克重并核对单价或总价，即时显示预计真实保本金价。"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
        .padding(16)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(
            GoldTheme.holdingsCardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.gold.opacity(0.28), GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }

    private func linkedPriceBox(
        title: String,
        badge: String,
        badgeHighlighted: Bool,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(badge)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(badgeHighlighted ? GoldTheme.goldSoft : GoldTheme.textFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        badgeHighlighted ? GoldTheme.gold.opacity(0.14) : GoldTheme.card,
                        in: GoldTheme.capsuleShape
                    )
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Text("¥")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                TextField(
                    "",
                    text: text,
                    prompt: Text(placeholder).foregroundStyle(GoldTheme.textFaint)
                )
                .keyboardType(.decimalPad)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                badgeHighlighted ? GoldTheme.gold.opacity(0.38) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }

    // MARK: - Step 3: 默认折叠的「补充细节」抽屉（随顶部黄金形态深度联动）

    private var detailsDrawer: some View {
        HoldingDetailsDrawerView(
            draft: $draft,
            isExpanded: $advanced,
            timestamp: $timestamp,
            selectedBook: $selectedBook,
            selectedSubPreset: $selectedSubPreset,
            isEditing: editing != nil,
            legacyPresence: legacyPresence,
            availableBooks: availableBooks,
            recentBrands: recentBrands,
            recentChannels: recentChannels
        ) { newDate in
            purchasePrice.selectDate(newDate)
        }
    }

    private func focusDetailsParameters(using proxy: ScrollViewProxy) {
        let wasCollapsed = !advanced
        if wasCollapsed {
            if reduceMotion {
                advanced = true
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    advanced = true
                }
            }
        }
        pendingExpandScroll = wasCollapsed
        detailsFocusPulse += 1

        if !wasCollapsed {
            scrollToDetailsParameters(using: proxy)
        }
    }

    private func scrollToDetailsParameters(using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.detailsParamsAnchorID, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(Self.detailsParamsAnchorID, anchor: .top)
            }
        }
    }

    private func setDetailsHighlight(_ highlighted: Bool) {
        if reduceMotion {
            highlightDetailsDrawer = highlighted
        } else {
            withAnimation(.easeOut(duration: highlighted ? 0.18 : 0.35)) {
                highlightDetailsDrawer = highlighted
            }
        }
    }

    private func selectAssetType(_ newType: GoldAssetType) {
        guard newType != draft.assetType else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            if editing == nil, let previousPreset = selectedSubPreset, previousPreset.assetType != newType {
                if draft.deductionText == previousPreset.deductionText { draft.deductionText = "" }
                if draft.discountText == previousPreset.discountText { draft.discountText = "" }
                if draft.fixedFeeText == previousPreset.fixedFeeText { draft.fixedFeeText = "" }
                if let suggestedBrand = previousPreset.suggestedBrand, draft.brand == suggestedBrand { draft.brand = "" }
                if let suggestedChannel = previousPreset.suggestedChannel, draft.channel == suggestedChannel { draft.channel = "" }
            }
            selectedSubPreset = nil
            draft.selectAssetType(newType, applyDefaults: editing == nil)
        }
    }

    private var priceReferenceStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if purchasePrice.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(L10n.tr("正在获取所选日期参考价…"))
                }
            }
            if let reference = purchasePrice.reference {
                HStack(alignment: .center, spacing: 8) {
                    Text(referenceDescription(reference))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if purchasePrice.isManual || draft.costMode == .total {
                        Button(L10n.tr("恢复参考价")) {
                            purchasePrice.useReference()
                            draft.updateUnitPrice(purchasePrice.priceText)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GoldTheme.gold)
                    }
                }
            }
            if let issue = purchasePrice.issue {
                HStack(alignment: .center, spacing: 8) {
                    Text(issueDescription(issue))
                    Spacer(minLength: 0)
                    if issue != .missingDay {
                        Button(L10n.tr("重试")) { Task { await purchasePrice.load() } }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.gold)
                            .disabled(purchasePrice.isLoading)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(GoldTheme.textSecondary)
    }

    private func syncReferencePriceIntoDraft() {
        draft.priceText = purchasePrice.priceText
        if draft.costMode == .unit {
            draft.syncCalculatedTotal()
        }
    }

    private func referenceDescription(_ reference: HoldingPurchasePriceReference) -> String {
        if !reference.isHistorical { return L10n.fmt("参考 · %@实时参考金价 %@ 元/克", marketBasis.title, reference.price.moneyText) }
        let day = HoldingsSelection.dateText(reference.date)
        if let fx = reference.exchangeRate {
            return L10n.fmt("参考 · %@国际收盘折算 %@ 元/克（汇率 %@）", day, reference.price.moneyText, fx.formatted(.number.precision(.fractionLength(2...4))))
        }
        return L10n.fmt("参考 · %@国内收盘价 %@ 元/克", day, reference.price.moneyText)
    }

    private func issueDescription(_ issue: HoldingPurchasePriceModel.Issue) -> String {
        switch issue {
        case .missingDay: L10n.tr("当天没有日线报价，请填写实际购入单价")
        case .missingExchangeRate: L10n.tr("汇率暂不可用，请填写实际购入单价")
        case .unavailable: L10n.tr("参考价暂未获取成功，可手动填写购入单价")
        }
    }

    private func save() {
        guard let input = draft.input, GoldReturnCalculator.calculate(input, referencePrice: nil) != nil else {
            errorMessage = L10n.tr("请检查克重、价格、纯度和费用，折价应小于100%。")
            return
        }
        guard timestamp <= .now else {
            errorMessage = L10n.tr("购买日期不能晚于当前时间")
            return
        }
        if let editing, editing.disposition != "holding" {
            errorMessage = L10n.tr("这笔黄金已处置，无法编辑。")
            return
        }

        let destinationBook = selectedBook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (targetBook ?? book)
            : selectedBook

        let priorBookRecords = existingRecords.filter {
            $0.bookName == destinationBook && $0.disposition == "holding"
        }
        let previousBookGrams = priorBookRecords.reduce(0.0) { $0 + max(0, $1.grams) }

        let record = editing ?? HoldingRecord(grams: input.grams, unitPriceCNY: input.unitPrice, timestamp: timestamp)
        draft.apply(to: record, input: input)
        record.timestamp = timestamp
        record.bookName = destinationBook
        if editing != nil {
            record.resetAlertBaselines()
        } else {
            modelContext.insert(record)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = L10n.tr("保存失败，请重试。")
            return
        }

        onSaved?()

        if editing == nil {
            receipt = HoldingReceiptSnapshot(
                assetType: draft.assetType,
                addedGrams: input.grams,
                unitPrice: input.unitPrice,
                totalCost: input.totalCost,
                timestamp: timestamp,
                purchaseSequence: priorBookRecords.count + 1,
                previousBookGrams: previousBookGrams,
                bookName: destinationBook
            )
        } else {
            dismiss()
        }
    }
}

// MARK: - 金额格式化

extension Double {
    /// 925.93
    var moneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)))
    }

    /// +24.98 / −12.30
    var signedMoneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)).sign(strategy: .always()))
    }
}
