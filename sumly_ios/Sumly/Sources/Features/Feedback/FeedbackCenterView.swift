import PhotosUI
import SwiftUI
import UIKit

// MARK: - 1. 意见与反馈中心主页面（双段切换：提交反馈 | 我的记录）

struct FeedbackCenterView: View {
    @State private var model: FeedbackCenterViewModel
    @State private var keyboardObserver = GoldKeyboardObserver()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isDiagnosticExpanded = false
    @State private var previewAttachment: FeedbackAttachment?
    @State private var hapticSuccessCount = 0

    init(session: AuthSession, marketBasis: GoldMarketBasis) {
        _model = State(
            initialValue: FeedbackCenterViewModel(
                session: session,
                marketBasis: marketBasis
            )
        )
    }

    init(model: FeedbackCenterViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentedBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            switch model.selectedTab {
            case .submit:
                submitTabView
            case .history:
                historyTabView
            }
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .navigationTitle(FeedbackCopy.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            // 严禁使用 ToolbarItemGroup(placement: .keyboard)（会触发 iOS 26 悬浮留白）；
            // 键盘可见时在顶部导航栏右侧提供轻量收起按钮，同时支持点击空白区与下滑交互收起。
            if keyboardObserver.isKeyboardVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        GoldKeyboardDismissHelper.dismiss()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GoldTheme.gold)
                    }
                    .accessibilityLabel("收起键盘")
                    .accessibilityIdentifier("feedback.dismissKeyboard")
                }
            }
        }
        .sensoryFeedback(.success, trigger: hapticSuccessCount)
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let picked = newItems
            selectedPhotoItems = []
            Task {
                var rawDatas: [Data] = []
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        rawDatas.append(data)
                    }
                }
                await model.appendCompressedImages(rawDatas: rawDatas)
            }
        }
        .onChange(of: model.selectedTab) { _, tab in
            GoldKeyboardDismissHelper.dismiss()
            if tab == .history {
                Task { await model.loadHistoryIfNeeded() }
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            FeedbackImageLightboxSheet(
                url: attachment.resolvedURL(baseURL: model.service.baseURL)
            )
        }
    }

    // MARK: - 顶部暗黑金双段切换栏

    private var segmentedBar: some View {
        HStack(spacing: 6) {
            ForEach(FeedbackCenterTab.allCases) { tab in
                let isSelected = model.selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.title)
                            .font(.system(.subheadline, design: .rounded).weight(isSelected ? .bold : .medium))
                        if tab == .history, !model.items.isEmpty {
                            Text(verbatim: "\(model.items.count)")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? GoldTheme.gold : GoldTheme.goldSoft)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    isSelected ? GoldTheme.onGold.opacity(0.88) : GoldTheme.gold.opacity(0.15),
                                    in: GoldTheme.capsuleShape
                                )
                        }
                    }
                    .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        isSelected ? AnyShapeStyle(GoldTheme.gold) : AnyShapeStyle(Color.clear),
                        in: GoldTheme.capsuleShape
                    )
                    .contentShape(GoldTheme.capsuleShape)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feedback.tab.\(tab.rawValue)")
            }
        }
        .padding(4)
        .background(GoldTheme.card, in: GoldTheme.capsuleShape)
        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    // MARK: - Tab 1: 提交反馈

    private var submitTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = model.formError {
                    errorBanner(error)
                }

                categorySection
                contentSection
                attachmentsSection
                contactSection
                diagnosticContextSection
                submitActionButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            if keyboardObserver.isKeyboardVisible {
                GoldKeyboardDismissHelper.dismiss()
            }
        }
    }

    private var categorySection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: FeedbackCopy.categorySectionTitle)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(FeedbackCategory.allCases) { item in
                    let isSelected = model.category == item
                    Button {
                        GoldKeyboardDismissHelper.dismiss()
                        model.category = item
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbolName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.gold)
                            Text(item.title)
                                .font(.system(.subheadline, design: .rounded).weight(isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(GoldTheme.onGold)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            isSelected ? AnyShapeStyle(GoldTheme.gold) : AnyShapeStyle(GoldTheme.card),
                            in: GoldTheme.subCardShape
                        )
                        .overlay(
                            GoldTheme.subCardShape.strokeBorder(
                                isSelected ? GoldTheme.goldSoft : GoldTheme.cardStroke,
                                lineWidth: 1
                            )
                        )
                        .contentShape(GoldTheme.subCardShape)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("feedback.category.\(item.rawValue)")
                }
            }
        }
    }

    private var contentSection: some View {
        let count = model.contentCharacterCount
        let isValid = model.validationResult.isValid
        return VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: FeedbackCopy.contentSectionTitle)

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if model.content.isEmpty {
                        Text(model.category.placeholder)
                            .font(.subheadline)
                            .foregroundStyle(GoldTheme.textFaint)
                            .lineSpacing(4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(
                        text: Binding(
                            get: { model.content },
                            set: { model.updateContent($0) }
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(GoldTheme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 132, maxHeight: 200)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("feedback.contentEditor")
                }
                .background(GoldTheme.background, in: GoldTheme.subCardShape)
                .overlay(
                    GoldTheme.subCardShape.strokeBorder(
                        GoldTheme.cardStroke,
                        lineWidth: 1
                    )
                )

                HStack(spacing: 8) {
                    Text(model.contentHintText)
                        .font(.caption)
                        .foregroundStyle(isValid ? GoldTheme.textFaint : GoldTheme.goldSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    Text(verbatim: "\(count) / \(FeedbackValidation.maxContentLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count >= FeedbackValidation.maxContentLength ? GoldTheme.up : GoldTheme.textSecondary)
                }
            }
            .padding(14)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    private var attachmentsSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                AccountSectionHeader(title: FeedbackCopy.attachmentsSectionTitle)
                Spacer()
                Text(FeedbackCopy.attachmentsOptionalHint)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                    .padding(.trailing, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(model.draftAttachments) { draft in
                        draftAttachmentTile(draft)
                    }

                    if model.remainingAttachmentSlots > 0 {
                        let isProcessingPhotos = model.isProcessingPhotos
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: model.remainingAttachmentSlots,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            ZStack {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                VStack(spacing: 6) {
                                    if isProcessingPhotos {
                                        ProgressView()
                                            .tint(GoldTheme.gold)
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(GoldTheme.gold)
                                        Text("添加截图")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(GoldTheme.textSecondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .background(GoldTheme.background, in: GoldTheme.subCardShape)
                            .overlay(
                                GoldTheme.subCardShape.strokeBorder(
                                    GoldTheme.gold.opacity(0.32),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                            )
                            .contentShape(GoldTheme.subCardShape)
                        }
                        .disabled(model.isSubmitting || model.isProcessingPhotos)
                        .accessibilityIdentifier("feedback.addPhoto")
                    }
                }

                Text(FeedbackCopy.attachmentsFootnote)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }
            .padding(14)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    private func draftAttachmentTile(_ draft: FeedbackDraftAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = UIImage(data: draft.jpegData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(GoldTheme.textFaint)
                        }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .background(GoldTheme.background)
            .clipShape(GoldTheme.subCardShape)
            .overlay(
                GoldTheme.subCardShape.strokeBorder(
                    draft.uploadState.failureMessage != nil ? GoldTheme.up.opacity(0.75) : GoldTheme.cardStroke,
                    lineWidth: 1
                )
            )

            if draft.uploadState.isUploading {
                GoldTheme.subCardShape
                    .fill(GoldTheme.background.opacity(0.72))
                    .overlay {
                        VStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(GoldTheme.gold)
                            Text("上传中")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                    }
            } else if draft.uploadState.uploadedAttachment != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(GoldTheme.down)
                            .background(GoldTheme.background, in: GoldTheme.circleShape)
                            .padding(6)
                    }
                }
            } else if draft.uploadState.failureMessage != nil {
                GoldTheme.subCardShape
                    .fill(GoldTheme.background.opacity(0.65))
                    .overlay {
                        VStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(GoldTheme.up)
                            Text("待重试")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(GoldTheme.up)
                        }
                    }
            }

            if !model.isSubmitting {
                Button {
                    model.removeAttachment(id: draft.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoldTheme.text)
                        .background(GoldTheme.background, in: GoldTheme.circleShape)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除截图")
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AccountSectionHeader(title: FeedbackCopy.contactSectionTitle)
                Spacer()
                Text(FeedbackCopy.contactOptionalHint)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                    .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoldTheme.goldSoft)

                TextField(
                    "",
                    text: Binding(
                        get: { model.contact },
                        set: { model.updateContact($0) }
                    ),
                    prompt: Text(FeedbackCopy.contactPlaceholder)
                        .foregroundStyle(GoldTheme.textFaint)
                )
                .font(.subheadline)
                .foregroundStyle(GoldTheme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("feedback.contactField")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    private var diagnosticContextSection: some View {
        let context = model.diagnosticContext
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isDiagnosticExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FeedbackCopy.diagnosticTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text(context.summaryLine)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(GoldTheme.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: isDiagnosticExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isDiagnosticExpanded {
                VStack(spacing: 6) {
                    diagnosticRow(label: "应用版本", value: "v\(context.appVersion) (\(context.buildNumber))")
                    diagnosticRow(label: "系统版本", value: context.iosVersion)
                    diagnosticRow(label: "设备型号", value: context.deviceModel)
                    diagnosticRow(label: "行情口径", value: context.marketModeDisplayTitle)
                    diagnosticRow(label: "账户模式", value: context.cloudSyncDisplayTitle)
                }
                .padding(10)
                .background(GoldTheme.background, in: GoldTheme.subCardShape)
                .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.down)
                    .padding(.top, 1)
                Text(FeedbackCopy.diagnosticPrivacyNotice)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
            Spacer()
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(GoldTheme.textSecondary)
        }
    }

    private var submitActionButton: some View {
        Button {
            GoldKeyboardDismissHelper.dismiss()
            Task {
                let ok = await model.submit()
                if ok {
                    hapticSuccessCount += 1
                }
            }
        } label: {
            HStack(spacing: 8) {
                if model.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(GoldTheme.onGold)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.footnote.bold())
                }
                Text(model.submissionStatusText)
            }
        }
        .buttonStyle(GoldPrimaryButtonStyle())
        .disabled(!model.canSubmit)
        .opacity(model.canSubmit ? 1 : 0.45)
        .padding(.top, 4)
        .accessibilityIdentifier("feedback.submit")
    }

    // MARK: - Tab 2: 我的记录

    private var historyTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let banner = model.successBanner {
                    successBannerView(banner)
                }

                switch model.historyState {
                case .idle, .loading:
                    if model.items.isEmpty {
                        loadingHistoryView
                    } else {
                        historyListView
                    }
                case .failed(let message):
                    if model.items.isEmpty {
                        failedHistoryView(message)
                    } else {
                        errorBanner(message)
                        historyListView
                    }
                case .loaded:
                    if model.items.isEmpty {
                        emptyHistoryView
                    } else {
                        historyListView
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable {
            await model.refreshHistory()
        }
        .task {
            await model.loadHistoryIfNeeded()
        }
    }

    private var historyListView: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(model.items) { item in
                FeedbackRecordCard(
                    item: item,
                    baseURL: model.service.baseURL,
                    onTapAttachment: { attachment in
                        previewAttachment = attachment
                    }
                )
            }
        }
    }

    private var loadingHistoryView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(GoldTheme.gold)
            Text(FeedbackCopy.loadingHistoryText)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private func failedHistoryView(_ message: String) -> some View {
        VStack(spacing: 14) {
            AccountRowIconBadge(systemName: "wifi.exclamationmark", style: .destructive)
            VStack(spacing: 4) {
                Text("暂时无法加载记录")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(FeedbackCopy.retryActionTitle) {
                Task { await model.loadHistory() }
            }
            .buttonStyle(GoldCapsuleStyle(isSelected: true))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .padding(.top, 24)
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 14) {
            ZStack {
                GoldTheme.circleShape
                    .fill(GoldTheme.gold.opacity(0.12))
                    .frame(width: 56, height: 56)
                GoldTheme.circleShape
                    .strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1)
                    .frame(width: 56, height: 56)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(GoldTheme.gold)
            }

            VStack(spacing: 5) {
                Text(FeedbackCopy.emptyHistoryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text(FeedbackCopy.emptyHistorySubtitle)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button(FeedbackCopy.emptyHistoryAction) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.selectedTab = .submit
                }
            }
            .buttonStyle(GoldCapsuleStyle(isSelected: true))
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .padding(.top, 24)
    }

    // MARK: - 提示条

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(GoldTheme.up)
                .padding(.top, 1)
            Text(message)
                .font(.footnote)
                .foregroundStyle(GoldTheme.up)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.up.opacity(0.1), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.up.opacity(0.32), lineWidth: 1))
    }

    private func successBannerView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(GoldTheme.down)
                .padding(.top, 1)
            Text(message)
                .font(.footnote)
                .foregroundStyle(GoldTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    model.dismissSuccessBanner()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.down.opacity(0.12), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.down.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 2. 历史反馈卡片组件（含分类、状态、附图与温暖暗金开发者回复）

struct FeedbackRecordCard: View {
    let item: FeedbackItem
    let baseURL: URL
    let onTapAttachment: (FeedbackAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            Text(item.content)
                .font(.subheadline)
                .foregroundStyle(GoldTheme.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if !item.attachments.isEmpty {
                attachmentsGrid
            }

            if !item.trimmedContact.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textFaint)
                    Text("预留联系：\(item.trimmedContact)")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if item.hasDeveloperReply {
                developerReplyBlock
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: item.category.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(item.category.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(GoldTheme.goldSoft)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 0.8))

            statusBadge(for: item.status)

            Spacer(minLength: 4)

            let created = FeedbackDateFormatter.formatDisplay(item.createdAt)
            if !created.isEmpty {
                Text(created)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(GoldTheme.textFaint)
            }
        }
    }

    private func statusBadge(for status: FeedbackStatus) -> some View {
        let fg: Color = {
            switch status {
            case .new: GoldTheme.goldSoft
            case .inProgress: GoldTheme.tempFreezing
            case .resolved: GoldTheme.down
            case .archived: GoldTheme.textSecondary
            }
        }()
        let bg: Color = {
            switch status {
            case .new: GoldTheme.gold.opacity(0.12)
            case .inProgress: GoldTheme.tempFreezing.opacity(0.14)
            case .resolved: GoldTheme.down.opacity(0.14)
            case .archived: GoldTheme.calendarCell
            }
        }()
        let stroke: Color = {
            switch status {
            case .new: GoldTheme.gold.opacity(0.3)
            case .inProgress: GoldTheme.tempFreezing.opacity(0.36)
            case .resolved: GoldTheme.down.opacity(0.35)
            case .archived: GoldTheme.cardStroke
            }
        }()

        return Text(status.title)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: GoldTheme.capsuleShape)
            .overlay(GoldTheme.capsuleShape.strokeBorder(stroke, lineWidth: 0.8))
    }

    private var attachmentsGrid: some View {
        HStack(spacing: 8) {
            ForEach(item.attachments.prefix(FeedbackValidation.maxAttachmentCount)) { attachment in
                Button {
                    onTapAttachment(attachment)
                } label: {
                    AsyncImage(url: attachment.resolvedURL(baseURL: baseURL)) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                GoldTheme.background
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(GoldTheme.gold)
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            ZStack {
                                GoldTheme.background
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.textFaint)
                            }
                        @unknown default:
                            GoldTheme.background
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(GoldTheme.badgeShape)
                    .overlay(GoldTheme.badgeShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看反馈截图")
            }
            Spacer(minLength: 0)
        }
    }

    private var developerReplyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(FeedbackCopy.developerReplyTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GoldTheme.goldSoft)
                Spacer(minLength: 4)
                let replied = FeedbackDateFormatter.formatDisplay(item.repliedAt)
                if !replied.isEmpty {
                    Text(replied)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(GoldTheme.goldSoft.opacity(0.75))
                }
            }

            Text(item.adminReply)
                .font(.footnote)
                .foregroundStyle(GoldTheme.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [GoldTheme.gold.opacity(0.14), GoldTheme.gold.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: GoldTheme.subCardShape
        )
        .overlay(
            GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.36), lineWidth: 1)
        )
    }
}

// MARK: - 3. 截图大图预览弹窗（Lightbox）

private struct FeedbackImageLightboxSheet: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GoldTheme.background.ignoresSafeArea()

                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            VStack(spacing: 10) {
                                ProgressView()
                                    .tint(GoldTheme.gold)
                                Text("正在加载原图…")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(GoldTheme.textSecondary)
                                Text("截图加载失败")
                                    .font(.footnote)
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Text("无效的截图地址")
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }
            .navigationTitle("截图预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(GoldTheme.gold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
    }
}
