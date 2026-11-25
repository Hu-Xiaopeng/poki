import PiSwiftAI
import PokiCore
import SwiftUI
import UIKit
import XCTest
@testable import Poki

@MainActor
final class ModelShortNameTests: XCTestCase {
    private var window: UIWindow?
    private var hostLocalization: HostLocalizationSnapshot!
    private var storage: IsolatedTestStorage!

    override func setUp() async throws {
        hostLocalization = HostLocalizationSnapshot.capture()
        storage = try IsolatedTestStorage(prefix: "model-short-name")
        AppLocalization.shared.preference = "en"
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        hostLocalization.restore()
        hostLocalization.assertUnchanged()
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
    }

    func testComposerModelButtonShowsShortNameWithoutProviderPrefix() throws {
        let store = storage.storage
        try configureAllBuiltInProviders(in: store)
        ModelCatalog.set("openai/gpt-6.2-sol", on: true, for: .openrouter, notify: false, storage: store)
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)

        let cases: [(ModelProvider, String, String)] = [
            (.chatgpt, "gpt-6.1-terra", "6.1 Terra"),
            (.openai, "gpt-6.2-sol", "6.2 Sol"),
            (.anthropic, "claude-sonnet-5-5", "Sonnet 5.5"),
            (.deepseek, "deepseek-flash", "V4.1 Flash"),
            (.gemini, "gemini-3.8-flash", "3.8 Flash"),
            (.openrouter, "openai/gpt-6.2-sol", "6.2 Sol"),
        ]

        let window = try show(
            ComposerInputView(
                input: .constant("Draft"),
                focused: .constant(true),
                adding: .constant(false),
                settingsPresented: .constant(false),
                running: false,
                send: { _, _ in },
                stop: {},
                openVoice: {}
            )
            .frame(width: 393, height: 180)
            .environment(app)
        )

        for (provider, id, expectedShortName) in cases {
            ModelKeys.choose(provider, model: id, in: store)
            settle {
                self.accessibilityValue(identifier: "composer.settings.model", in: window) == expectedShortName
            }
            let shown = accessibilityValue(identifier: "composer.settings.model", in: window)
            XCTAssertEqual(shown, expectedShortName, "Provider \(provider.rawValue) model \(id) should show short name")
        }
    }

    func testPokiMenuGroupsShowShortModelNamesForEveryProviderAndKeepStorageIDs() throws {
        let store = storage.storage
        try configureAllBuiltInProviders(in: store)
        // Enable every built-in model so every provider's full set is verified in the menu.
        for provider in [ModelProvider.chatgpt, .openai, .anthropic, .deepseek, .gemini, .openrouter] {
            for choice in provider.models(in: store) {
                ModelCatalog.set(choice.id, on: true, for: provider, notify: false, storage: store)
            }
        }
        // Add a dynamically listed OpenAI model and two custom endpoints sharing a model name.
        store.defaults.set(["gpt-6.3-mini"], forKey: "models.listed.openai")
        ModelCatalog.set("gpt-6.3-mini", on: true, for: .openai, notify: false, storage: store)
        let firstCustom = CustomProviders.upsert(
            CustomProvider(name: "Office", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8765/v1")], model: "shared-model"),
            storage: store
        )
        let secondCustom = CustomProviders.upsert(
            CustomProvider(name: "Home", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8766/v1")], model: "shared-model"),
            storage: store
        )

        ModelKeys.choose(.chatgpt, model: "gpt-6.1-terra", in: store)
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)
        let bearPlace = CGRect(x: 161, y: 260, width: 80, height: 80)
        let window = try show(
            PokiFlight(
                status: PokiStatus(.ready),
                home: true,
                places: [.home: bearPlace],
                pokes: 0,
                tap: {},
                openModel: {},
                openCustomization: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(app)
        )

        settle { self.menuButton(in: window, identifier: "home.poki")?.menu != nil }
        let button = try XCTUnwrap(menuButton(in: window, identifier: "home.poki"))
        let modelMenu = try XCTUnwrap(
            flattenMenuElements(try XCTUnwrap(button.menu))
                .first(where: { $0.accessibilityIdentifier == "status.model" }) as? UIMenu
        )

        XCTAssertEqual(modelMenu.subtitle, "6.1 Terra")

        let groups = Dictionary(
            uniqueKeysWithValues: modelMenu.children.compactMap { $0 as? UIMenu }.map { menu in
                (menu.title, menu.children.compactMap { $0 as? UIAction })
            }
        )

        XCTAssertEqual(groups["ChatGPT"]?.map(\.title), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol"])
        XCTAssertEqual(groups["OpenAI"]?.map(\.title), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol", "6.3-mini"])
        XCTAssertEqual(groups["Anthropic"]?.map(\.title), ["Haiku 5.5", "Sonnet 5.5", "Opus 5.5"])
        XCTAssertEqual(groups["DeepSeek"]?.map(\.title), ["V4.1 Flash", "V4 Pro (no screenshots)"])
        XCTAssertEqual(groups["Gemini"]?.map(\.title), ["3.8 Flash", "4 Argon"])
        XCTAssertEqual(groups["OpenRouter"]?.map(\.title), ["3.8 Flash", "Sonnet 5.5", "Opus 5.5", "6.2 Sol", "6.1 Sol"])
        XCTAssertEqual(groups["Office"]?.map(\.title), ["shared-model"])
        XCTAssertEqual(groups["Home"]?.map(\.title), ["shared-model"])

        // Picking identically named short labels under separate groups keeps distinct provider + ID storage.
        let openAITerra = try XCTUnwrap(groups["OpenAI"]?.first(where: { $0.title == "6.1 Terra" }))
        openAITerra.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .openai)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.1-terra")

        let chatGPTSol = try XCTUnwrap(groups["ChatGPT"]?.first(where: { $0.title == "6.2 Sol" }))
        chatGPTSol.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .chatgpt)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.2-sol")

        let homeShared = try XCTUnwrap(groups["Home"]?.first(where: { $0.title == "shared-model" }))
        homeShared.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .custom)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), CustomProviders.choiceID(secondCustom.id, "shared-model"))
        XCTAssertNotEqual(ModelKeys.selectedModel(in: store), CustomProviders.choiceID(firstCustom.id, "shared-model"))

        // Localized DeepSeek V4 Pro keeps its localized parenthetical note without the DeepSeek prefix.
        AppLocalization.shared.preference = "zh-Hans"
        ModelKeys.saved += 1
        settle {
            self.groupActionTitles(in: window, group: "DeepSeek") == ["V4.1 Flash", "V4 Pro（不支持截图）"]
        }
        XCTAssertEqual(groupActionTitles(in: window, group: "DeepSeek"), ["V4.1 Flash", "V4 Pro（不支持截图）"])

        AppLocalization.shared.preference = "zh-Hant"
        ModelKeys.saved += 1
        settle {
            self.groupActionTitles(in: window, group: "DeepSeek") == ["V4.1 Flash", "V4 Pro（不支援截圖）"]
        }
        XCTAssertEqual(groupActionTitles(in: window, group: "DeepSeek"), ["V4.1 Flash", "V4 Pro（不支援截圖）"])
    }

    func testLegacySavedSelectionKeepsOriginalProviderModelIDAndAPIRequest() throws {
        let store = storage.storage
        try configureAllBuiltInProviders(in: store)

        // Write legacy UserDefaults keys directly as previous releases saved them.
        store.defaults.set("chatgpt", forKey: "chat.provider")
        store.defaults.set("gpt-6.1-terra", forKey: "chat.model.chatgpt")
        store.defaults.set(["gpt-6.1-terra", "gpt-6.2-sol"], forKey: "models.enabled.chatgpt")

        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .chatgpt)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.1-terra")
        let chatGPTRequestModel = try XCTUnwrap(ModelProvider.chatgpt.piModel(ModelKeys.selectedModel(in: store), storage: store))
        XCTAssertEqual(chatGPTRequestModel.id, "gpt-6.1-terra")

        // Verify OpenRouter legacy ID and API model ID stay intact.
        store.defaults.set("openrouter", forKey: "chat.provider")
        store.defaults.set("anthropic/claude-sonnet-5.5", forKey: "chat.model.openrouter")
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .openrouter)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "anthropic/claude-sonnet-5.5")
        let openRouterRequestModel = try XCTUnwrap(ModelProvider.openrouter.piModel(ModelKeys.selectedModel(in: store), storage: store))
        XCTAssertEqual(openRouterRequestModel.id, "anthropic/claude-sonnet-5.5")

        // Switch back to legacy ChatGPT selection and confirm the UI renders the short label while keeping IDs.
        store.defaults.set("chatgpt", forKey: "chat.provider")
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)
        let window = try show(
            ComposerInputView(
                input: .constant("Hi"),
                focused: .constant(true),
                adding: .constant(false),
                settingsPresented: .constant(false),
                running: false,
                send: { _, _ in },
                stop: {},
                openVoice: {}
            )
            .frame(width: 393, height: 180)
            .environment(app)
        )
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: window) == "6.1 Terra" }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: window), "6.1 Terra")
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.1-terra")
    }

    func testComposerSheetAndModelSettingsRowsUseShortDisplayNames() throws {
        let store = storage.storage
        try configureAllBuiltInProviders(in: store)
        for choice in ModelProvider.deepseek.models(in: store) {
            ModelCatalog.set(choice.id, on: true, for: .deepseek, notify: false, storage: store)
        }
        ModelKeys.choose(.chatgpt, model: "gpt-6.1-terra", in: store)
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)

        let sheetWindow = try show(
            ComposerTaskSettings(
                kind: .model,
                approvalIconSize: 22,
                previewSelection: .constant(nil),
                openModelSetup: {}
            )
            .environment(app)
        )

        settle {
            self.accessibilityLabel(identifier: "composer.model.chatgpt.gpt-6.1-terra", in: sheetWindow) != nil
        }
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.chatgpt.gpt-6.1-terra", in: sheetWindow), "6.1 Terra")
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.deepseek.deepseek-flash", in: sheetWindow), "V4.1 Flash")
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.deepseek.deepseek-v4-pro", in: sheetWindow), "V4 Pro (no screenshots)")

        // TextChatFeature lists models inside one provider's account page, so rows must not repeat the provider prefix.
        let settingsWindow = try show(
            NavigationStack {
                TextChatFeature(provider: .chatgpt)
            }
            .environment(app)
        )
        settle { self.visibleTexts(in: settingsWindow).contains("6.2 Sol") }
        let texts = visibleTexts(in: settingsWindow)
        XCTAssertTrue(texts.contains { $0.contains("6.1 Terra") }, "Expected short model name in TextChatFeature, got: \(texts)")
        XCTAssertTrue(texts.contains("6.2 Sol"), "Expected short model name in TextChatFeature, got: \(texts)")
        XCTAssertFalse(texts.contains { $0.contains("ChatGPT GPT-") }, "Provider prefix must not appear in TextChatFeature, got: \(texts)")
    }

    // MARK: Helpers

    private func configureAllBuiltInProviders(in store: PokiStorage) throws {
        try ChatGPTAccount.save(
            OAuthCredentials(
                refresh: "test-refresh",
                access: "test-access",
                expires: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                clientId: "test-client"
            ),
            service: store.keychainService
        )
        for provider in [ModelProvider.openai, .anthropic, .deepseek, .gemini, .openrouter] {
            try ModelKeys.save("sk-test-\(provider.rawValue)", for: provider, storage: store)
        }
    }

    private func groupActionTitles(in window: UIWindow, group: String) -> [String]? {
        guard let button = menuButton(in: window, identifier: "home.poki"),
              let menu = button.menu,
              let modelMenu = flattenMenuElements(menu).first(where: { $0.accessibilityIdentifier == "status.model" }) as? UIMenu,
              let section = modelMenu.children.compactMap({ $0 as? UIMenu }).first(where: { $0.title == group }) else {
            return nil
        }
        return section.children.compactMap { ($0 as? UIAction)?.title }
    }

    private func show(_ view: some View) throws -> UIWindow {
        window?.isHidden = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let next = UIWindow(windowScene: scene)
        next.frame = scene.screen.bounds
        next.rootViewController = UIHostingController(rootView: view)
        next.makeKeyAndVisible()
        self.window = next
        return next
    }

    private func settle(for seconds: TimeInterval = 2, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func menuButton(in root: UIView, identifier: String) -> UIButton? {
        if let button = root as? UIButton,
           button.showsMenuAsPrimaryAction,
           button.accessibilityIdentifier == identifier {
            return button
        }
        for subview in root.subviews {
            if let found = menuButton(in: subview, identifier: identifier) { return found }
        }
        return nil
    }

    private func flattenMenuElements(_ menu: UIMenu) -> [UIMenuElement] {
        var result: [UIMenuElement] = []
        for child in menu.children {
            result.append(child)
            if let submenu = child as? UIMenu {
                result.append(contentsOf: flattenMenuElements(submenu))
            }
        }
        return result
    }

    private func accessibilityElement(identifier: String, in root: NSObject) -> NSObject? {
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        let selector = NSSelectorFromString("accessibilityIdentifier")
        while let item = pending.popLast() {
            guard visited.insert(ObjectIdentifier(item)).inserted else { continue }
            let id = item.responds(to: selector) ? item.perform(selector)?.takeUnretainedValue() as? String : nil
            if id == identifier { return item }
            if let view = item as? UIView { pending.append(contentsOf: view.subviews) }
            if let children = item.accessibilityElements {
                pending.append(contentsOf: children.compactMap { $0 as? NSObject })
            }
            let count = item.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count {
                    if let child = item.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return nil
    }

    private func accessibilityValue(identifier: String, in root: NSObject) -> String? {
        accessibilityElement(identifier: identifier, in: root)?.accessibilityValue
    }

    private func accessibilityLabel(identifier: String, in root: NSObject) -> String? {
        accessibilityElement(identifier: identifier, in: root)?.accessibilityLabel
    }

    private func visibleTexts(in root: NSObject) -> [String] {
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        var result: [String] = []
        while let item = pending.popLast() {
            guard visited.insert(ObjectIdentifier(item)).inserted else { continue }
            if let label = item.accessibilityLabel, !label.isEmpty { result.append(label) }
            if let uiLabel = item as? UILabel, let text = uiLabel.text, !text.isEmpty { result.append(text) }
            if let view = item as? UIView { pending.append(contentsOf: view.subviews) }
            if let children = item.accessibilityElements {
                pending.append(contentsOf: children.compactMap { $0 as? NSObject })
            }
            let count = item.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count {
                    if let child = item.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return result
    }
}
