import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Sumly

@Suite("GoldKeyboardDismiss")
struct GoldKeyboardDismissTests {
    @Test("含底部操作栏的表单禁用键盘 toolbar，并按键盘显隐切换内嵌收起按钮与主按钮宽度")
    func inlineDismissBarLayoutTransitions() {
        let hidden = GoldKeyboardBarLayout(isKeyboardVisible: false, usesInlineDismissButton: true)
        #expect(hidden.attachesKeyboardToolbar == false)
        #expect(hidden.showsInlineDismissButton == false)
        #expect(hidden.primaryButtonIsFullWidth == true)

        let visible = GoldKeyboardBarLayout(isKeyboardVisible: true, usesInlineDismissButton: true)
        #expect(visible.attachesKeyboardToolbar == false)
        #expect(visible.showsInlineDismissButton == true)
        #expect(visible.primaryButtonIsFullWidth == false)
    }

    @Test("无底部操作栏的表单保持兼容：保留键盘 toolbar 且主按钮全宽")
    func toolbarOnlyFormLayoutRemainsCompatible() {
        let hidden = GoldKeyboardBarLayout(isKeyboardVisible: false, usesInlineDismissButton: false)
        #expect(hidden.attachesKeyboardToolbar == true)
        #expect(hidden.showsInlineDismissButton == false)
        #expect(hidden.primaryButtonIsFullWidth == true)

        let visible = GoldKeyboardBarLayout(isKeyboardVisible: true, usesInlineDismissButton: false)
        #expect(visible.attachesKeyboardToolbar == true)
        #expect(visible.showsInlineDismissButton == false)
        #expect(visible.primaryButtonIsFullWidth == true)
    }

    @MainActor
    @Test("GoldKeyboardObserver 响应键盘弹出与收起通知且无循环引用")
    func observerTracksKeyboardNotificationsAndDeallocatesCleanly() {
        let center = NotificationCenter()
        weak var weakObserver: GoldKeyboardObserver?

        do {
            let observer = GoldKeyboardObserver(notificationCenter: center)
            weakObserver = observer
            #expect(observer.isKeyboardVisible == false)

            center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
            #expect(observer.isKeyboardVisible == true)

            center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
            #expect(observer.isKeyboardVisible == true)

            center.post(name: UIResponder.keyboardWillHideNotification, object: nil)
            #expect(observer.isKeyboardVisible == false)

            center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
            #expect(observer.isKeyboardVisible == true)
        }

        #expect(weakObserver == nil)
        // 释放后再次派发通知不应崩溃或保留悬空观察者
        center.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    @MainActor
    @Test("GoldKeyboardActionBar 布局跟随外部 observer 与 override 状态同步")
    func actionBarLayoutFollowsObserverAndOverride() {
        let center = NotificationCenter()
        let observer = GoldKeyboardObserver(notificationCenter: center)

        let barFromObserver = GoldKeyboardActionBar(observer: observer) {
            Button("确认入库") {}
        }
        #expect(barFromObserver.layout.attachesKeyboardToolbar == false)
        #expect(barFromObserver.layout.showsInlineDismissButton == false)
        #expect(barFromObserver.layout.primaryButtonIsFullWidth == true)

        center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        #expect(barFromObserver.layout.showsInlineDismissButton == true)
        #expect(barFromObserver.layout.primaryButtonIsFullWidth == false)

        center.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        #expect(barFromObserver.layout.showsInlineDismissButton == false)
        #expect(barFromObserver.layout.primaryButtonIsFullWidth == true)

        let overriddenVisible = GoldKeyboardActionBar(observer: observer, keyboardVisibilityOverride: true) {
            Button("保存为持仓") {}
        }
        #expect(overriddenVisible.layout.showsInlineDismissButton == true)
        #expect(overriddenVisible.layout.primaryButtonIsFullWidth == false)
    }

    @MainActor
    @Test("GoldKeyboardDismissHelper.dismiss() 可收起当前第一响应者输入框")
    func dismissHelperResignsFirstResponder() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        let textField = UITextField(frame: CGRect(x: 20, y: 80, width: 200, height: 44))
        textField.keyboardType = .decimalPad
        controller.view.addSubview(textField)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            textField.resignFirstResponder()
            window.isHidden = true
            previous?.makeKey()
        }

        let becameFirst = textField.becomeFirstResponder()
        #expect(becameFirst == true)
        #expect(textField.isFirstResponder == true)

        GoldKeyboardDismissHelper.dismiss()
        try await Task.sleep(for: .milliseconds(100))
        #expect(textField.isFirstResponder == false)
    }

    @MainActor
    @Test("AddHoldingSheet 表单输入框聚焦弹出键盘且底部栏紧贴无多余键盘 toolbar")
    func addHoldingSheetKeyboardFocusAndDismissIntegration() async throws {
        let schema = Schema([HoldingRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)

        var seed = HoldingDraft()
        seed.selectAssetType(.bean, applyDefaults: true)
        seed.gramsText = "10"
        seed.priceText = "768.50"
        seed.syncCalculatedTotal()

        let sheet = AddHoldingSheet(defaultUnitPrice: 768.50, marketBasis: .domestic, seed: seed)
            .modelContainer(container)
            .preferredColorScheme(.dark)
            .tint(GoldTheme.gold)

        let controller = UIHostingController(rootView: sheet)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            GoldKeyboardDismissHelper.dismiss()
            window.isHidden = true
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()

        let textFields = Self.findTextFields(in: controller.view)
        let gramsField = try #require(textFields.first)
        // SwiftUI 会挂一个 0 高度占位 RootUIView，只要未挂载 .keyboard toolbar，就不会出现非零高度键盘工具栏
        #expect((gramsField.inputAccessoryView?.bounds.height ?? 0) == 0)
        #expect(Self.containsToolbar(in: gramsField.inputAccessoryView) == false)

        gramsField.becomeFirstResponder()
        try await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        #expect(gramsField.isFirstResponder == true)
        #expect((gramsField.inputAccessoryView?.bounds.height ?? 0) == 0)
        #expect(Self.containsToolbar(in: gramsField.inputAccessoryView) == false)

        GoldKeyboardDismissHelper.dismiss()
        try await Task.sleep(for: .milliseconds(250))
        #expect(gramsField.isFirstResponder == false)
    }

    @MainActor
    @Test("GoldCalculatorSheet 与 HoldingAlertSheet 同样不挂载多余键盘 toolbar")
    func calculatorAndAlertSheetsAvoidKeyboardToolbarConflict() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }

        let calcWindow = UIWindow(windowScene: scene)
        let calcController = UIHostingController(
            rootView: GoldCalculatorSheet(model: HoldingsViewModel(), marketBasis: .domestic)
                .preferredColorScheme(.dark)
                .tint(GoldTheme.gold)
        )
        calcWindow.rootViewController = calcController
        calcWindow.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        calcController.view.layoutIfNeeded()

        let calcField = try #require(Self.findTextFields(in: calcController.view).first)
        #expect((calcField.inputAccessoryView?.bounds.height ?? 0) == 0)
        #expect(Self.containsToolbar(in: calcField.inputAccessoryView) == false)
        calcWindow.isHidden = true

        let schema = Schema([HoldingRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let record = HoldingRecord(grams: 10, unitPriceCNY: 750, timestamp: .now)
        try record.setAlerts([HoldingAlert(kind: .price, threshold: 900, enabled: true, basis: .domestic)])
        container.mainContext.insert(record)

        let alertWindow = UIWindow(windowScene: scene)
        let alertController = UIHostingController(
            rootView: HoldingAlertSheet(record: record, basis: .domestic)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .tint(GoldTheme.gold)
        )
        alertWindow.rootViewController = alertController
        alertWindow.makeKeyAndVisible()
        defer {
            GoldKeyboardDismissHelper.dismiss()
            alertWindow.isHidden = true
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(350))
        alertController.view.layoutIfNeeded()

        let alertField = try #require(Self.findTextFields(in: alertController.view).first)
        #expect((alertField.inputAccessoryView?.bounds.height ?? 0) == 0)
        #expect(Self.containsToolbar(in: alertField.inputAccessoryView) == false)
    }

    @MainActor
    private static func findTextFields(in root: UIView) -> [UITextField] {
        var found: [UITextField] = []
        if let field = root as? UITextField {
            found.append(field)
        }
        for subview in root.subviews {
            found.append(contentsOf: findTextFields(in: subview))
        }
        return found
    }

    @MainActor
    private static func containsToolbar(in root: UIView?) -> Bool {
        guard let root else { return false }
        if root is UIToolbar { return true }
        return root.subviews.contains { containsToolbar(in: $0) }
    }
}
