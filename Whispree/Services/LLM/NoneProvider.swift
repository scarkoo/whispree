import Foundation

@MainActor
final class NoneProvider: LLMProvider {
    let name = "없음 (원문 사용)"
    let requiresNetwork = false

    func validate() -> ProviderValidation { .valid }
    func setup() async throws {}
    func teardown() async {}

    func correct(text: String, systemPrompt: String, glossary: [String]?) async throws -> String {
        text
    }
}
