import Foundation

/// Local-only LLM provider contract.
@MainActor
protocol LLMProvider {
    var name: String { get }
    var requiresNetwork: Bool { get }

    func validate() -> ProviderValidation
    func setup() async throws
    func teardown() async

    func correct(
        text: String,
        systemPrompt: String,
        glossary: [String]?
    ) async throws -> String
}

@MainActor
extension LLMProvider {
    var isReady: Bool { validate().isValid }
}

enum LLMError: LocalizedError {
    case modelNotLoaded
    case correctionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "LLM model is not loaded"
        case let .correctionFailed(msg): "Text correction failed: \(msg)"
        case .timeout: "Text correction timed out"
        }
    }
}
