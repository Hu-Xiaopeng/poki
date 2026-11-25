import Foundation
import PiSwiftAI
import XCTest
@testable import Poki

/// GPT-6.2 can be picked (issue #754), and model lists stay current without a release.
final class ModelListsTests: XCTestCase {
    private var isolated: IsolatedTestStorage!
    private var storage: PokiStorage { isolated.storage }

    override func setUpWithError() throws {
        isolated = try IsolatedTestStorage(prefix: "poki-model-lists")
    }

    override func tearDownWithError() throws {
        try isolated?.tearDown()
        isolated = nil
    }

    func testGPT62IsBundledForOpenAIChatGPTAndOpenRouter() {
        for provider in [ModelProvider.openai, .chatgpt] {
            let ids = ModelCatalog.all(provider, storage: storage).map(\.id)
            XCTAssertTrue(ids.contains("gpt-6.2-sol"), "\(provider)")
            XCTAssertTrue(ids.contains("gpt-6.2-astra"), "\(provider)")
            XCTAssertTrue(ModelCatalog.available(provider, storage: storage).map(\.id).contains("gpt-6.2-sol"), "\(provider)")
        }
        XCTAssertTrue(ModelCatalog.all(.openrouter, storage: storage).map(\.id).contains("openai/gpt-6.2-sol"))
    }

    func testGPT62RunsWithItsOwnSetup() throws {
        let sol = try XCTUnwrap(ModelProvider.openai.piModel("gpt-6.2-sol", storage: storage))
        XCTAssertEqual(sol.id, "gpt-6.2-sol")
        XCTAssertEqual(sol.name, "GPT-6.2 Sol")
        XCTAssertEqual(sol.api, .openAIResponses)
        XCTAssertTrue(sol.reasoning)
        XCTAssertEqual(sol.input, [.text, .image])

        let astra = try XCTUnwrap(ModelProvider.openai.piModel("gpt-6.2-astra", storage: storage))
        XCTAssertEqual(astra.name, "GPT-6.2 Astra")
        XCTAssertEqual(astra.cost.input, 8)
        XCTAssertEqual(astra.cost.output, 40)
        XCTAssertEqual(astra.cost.tiers?.first?.input, 16)
        // GPT-6.2 rejects reasoning effort none: no level maps to it.
        XCTAssertFalse((astra.thinkingLevelMap ?? [:]).values.contains { $0 == "none" })
        XCTAssertFalse((sol.thinkingLevelMap ?? [:]).values.contains { $0 == "none" })
    }

    func testGPT62ThroughACodexSignInKeepsCodexsAPI() throws {
        let codex = try XCTUnwrap(ModelProvider.knownModel(provider: "openai-codex", id: "gpt-6.2-astra"))
        XCTAssertEqual(codex.api, .openAICodexResponses)
        XCTAssertEqual(codex.contextWindow, 272_000)
        XCTAssertEqual(codex.cost.input, 8)
    }

    func testCustomProviderServingGPT62GetsItsSetup() throws {
        let model = ModelProvider.customModel("openai/gpt-6.2-astra", baseUrl: "https://gateway.example/v1", api: .openAIResponses, reasoning: nil)
        XCTAssertTrue(model.reasoning)
        XCTAssertEqual(model.maxTokens, 128_000)
    }

    func testNewDefaultIsSwitchedOnOnceForAnOwnerWhoChoseModels() {
        // Saved by Poki 0.5.0: Terra off, Sol on.
        storage.defaults.set(["gpt-6.1-sol"], forKey: "models.enabled.openai")
        XCTAssertEqual(ModelCatalog.enabled(.openai, storage: storage), ["gpt-6.1-sol", "gpt-6.2-sol"])

        // Terra stays off, and GPT-6.2 Sol stays off once switched off.
        ModelCatalog.set("gpt-6.2-sol", on: false, for: .openai, notify: false, storage: storage)
        XCTAssertEqual(ModelCatalog.enabled(.openai, storage: storage), ["gpt-6.1-sol"])
    }

    func testCodexListIsReadBySlugAndSkipsHiddenModels() {
        let items: [[String: Any]] = [
            ["slug": "gpt-6.2-sol", "visibility": "list"],
            ["slug": "gpt-6.3-nova", "visibility": "list"],
            ["slug": "gpt-6.2-astra-internal", "visibility": "hide"],
            ["slug": "gpt-realtime-2.1", "visibility": "list"],
        ]
        XCTAssertEqual(ModelCatalog.listedIDs(items, .chatgpt), ["gpt-6.2-sol", "gpt-6.3-nova"])
    }

    func testOpenAIListAddsANewModelAndKeepsRealtimeOut() {
        let items: [[String: Any]] = [["id": "gpt-6.3-nova"], ["id": "gpt-realtime-2.1"], ["id": "text-embedding-4"]]
        XCTAssertEqual(ModelCatalog.listedIDs(items, .openai), ["gpt-6.3-nova"])
    }

    func testCodexModelsRequestNamesTheWorkspace() throws {
        let token = Self.jwt(["https://api.openai.com/auth": ["chatgpt_account_id": "workspace-1"], "exp": 4_102_444_800])
        let request = try XCTUnwrap(ModelCatalog.codexModelsRequest(accessToken: token))
        XCTAssertEqual(request.url?.host, "chatgpt.com")
        XCTAssertEqual(request.url?.path, "/backend-api/codex/models")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "client_version")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "workspace-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertNil(ModelCatalog.codexModelsRequest(accessToken: Self.jwt(["exp": 4_102_444_800])))
    }

    func testListIsStaleWhenMissingOrADayOld() {
        let now = Date()
        XCTAssertTrue(ModelCatalog.isStale(.openai, now: now, storage: storage))
        storage.defaults.set(now.timeIntervalSince1970 - 60, forKey: "models.listedAt.openai")
        XCTAssertFalse(ModelCatalog.isStale(.openai, now: now, storage: storage))
        storage.defaults.set(now.timeIntervalSince1970 - ModelCatalog.listLifetime - 1, forKey: "models.listedAt.openai")
        XCTAssertTrue(ModelCatalog.isStale(.openai, now: now, storage: storage))
    }

    private static func jwt(_ claims: [String: Any]) -> String {
        func part(_ object: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return "\(part(["alg": "none"])).\(part(claims)).c2ln"
    }
}
