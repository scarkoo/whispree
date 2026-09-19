import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

@MainActor
final class LocalTextProvider: LLMProvider {
    let name = "로컬 LLM"
    let requiresNetwork = false

    private var modelContainer: ModelContainer?
    private let modelId: String
    private let revision: String
    private let correctionTimeout: TimeInterval = 15.0

    init(
        modelId: String = LocalModelSpec.defaultModelId,
        revision: String? = nil
    ) {
        self.modelId = modelId
        self.revision = revision ?? LocalModelSpec.find(modelId)?.revision ?? ""
    }

    func validate() -> ProviderValidation {
        modelContainer != nil ? .valid : .invalid("로컬 LLM 모델이 로드되지 않았습니다. 모델을 다운로드해주세요.")
    }

    func setup() async throws {
        guard !revision.isEmpty else {
            throw LLMError.correctionFailed("고정된 모델 revision이 없어 로드를 거부했습니다.")
        }
        MLXMemoryControl.configureInteractiveCacheLimit()
        let config = ModelConfiguration(id: modelId, revision: revision)
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: config
        ) { _ in }
    }

    func teardown() async {
        modelContainer = nil
        MLXMemoryControl.releaseCachedBuffers()
    }

    func correct(text: String, systemPrompt: String, glossary: [String]?) async throws -> String {
        guard let modelContainer else { throw LLMError.modelNotLoaded }
        defer { MLXMemoryControl.releaseCachedBuffers() }

        var fullPrompt = systemPrompt
        if modelId.contains("Qwen3") {
            fullPrompt += "\n/no_think"
        }
        if let glossary, !glossary.isEmpty {
            fullPrompt += "\n\n용어 사전 (반드시 이 형태로 보존):\n" + glossary.joined(separator: ", ")
        }

        let messages: [[String: String]] = [
            ["role": "system", "content": fullPrompt],
            ["role": "user", "content": text]
        ]

        let result = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let output = try await modelContainer.perform { context in
                    let input = try await context.processor.prepare(input: .init(messages: messages))
                    let params = GenerateParameters(temperature: 0, topP: 1.0, repetitionPenalty: 1.2)
                    return try MLXLMCommon.generate(input: input, parameters: params, context: context) { tokens in
                        tokens.count > 2000 ? .stop : .more
                    }
                }
                var outputText = output.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if let thinkEnd = outputText.range(of: "</think>") {
                    outputText = String(outputText[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if outputText.hasPrefix("<think>") {
                    return ""
                }
                return outputText
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.correctionTimeout * 1_000_000_000))
                throw LLMError.timeout
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        if result.isEmpty { return text }
        return Self.wordEditDistance(text, result) > 0.5 ? text : result
    }

    static func wordEditDistance(_ a: String, _ b: String) -> Double {
        let wordsA = a.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let wordsB = b.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !wordsA.isEmpty else { return wordsB.isEmpty ? 0 : 1 }
        guard !wordsB.isEmpty else { return 1 }
        var dp = Array(0 ... wordsB.count)
        for i in 1 ... wordsA.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1 ... wordsB.count {
                let temp = dp[j]
                dp[j] = wordsA[i - 1] == wordsB[j - 1] ? prev : min(prev, dp[j], dp[j - 1]) + 1
                prev = temp
            }
        }
        return Double(dp[wordsB.count]) / Double(max(wordsA.count, wordsB.count))
    }
}
