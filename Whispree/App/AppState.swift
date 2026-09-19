import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    typealias STTProviderFactory = (STTProviderType, AppSettings) -> any STTProvider

    @Published var transcriptionState: TranscriptionState = .idle
    @Published var partialText = ""
    @Published var finalText = ""
    @Published var correctedText = ""
    @Published var currentError: AppError?
    @Published var dictationQueueSnapshot: DictationQueueSnapshot = .empty

    @Published var currentAudioLevel: Float = 0
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 64)
    @Published var isRecording = false
    @Published var isThinkingPause = false

    @Published var whisperModelState: ModelState = .notDownloaded
    @Published var llmModelState: ModelState = .notDownloaded
    @Published var whisperDownloadProgress: Double = 0
    @Published var llmDownloadProgress: Double = 0

    @Published var sttProvider: (any STTProvider)?
    @Published var llmProvider: (any LLMProvider)?

    let settings: AppSettings

    private let sttProviderFactory: STTProviderFactory
    private var activeSTTProviderConfigurationKey: String?
    private var sttProviderLoadGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    @Published var transcriptionHistory: [TranscriptionRecord] = [] {
        didSet { saveHistory() }
    }
    private static let historyKey = "WhispreeHistory"

    var isReady: Bool { sttProvider?.isReady ?? false }

    init(
        settings: AppSettings? = nil,
        sttProviderFactory: STTProviderFactory? = nil
    ) {
        let resolvedSettings = settings ?? AppSettings()
        self.settings = resolvedSettings
        self.sttProviderFactory = sttProviderFactory ?? { _, _ in
            WhisperKitProvider()
        }

        resolvedSettings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        loadHistory()
    }

    func switchSTTProvider(to type: STTProviderType) async {
        let configurationKey = sttProviderConfigurationKey(for: type)
        if activeSTTProviderConfigurationKey == configurationKey {
            if whisperModelState == .loading { return }
            if whisperModelState == .ready, sttProvider != nil { return }
        }

        sttProviderLoadGeneration += 1
        let generation = sttProviderLoadGeneration
        activeSTTProviderConfigurationKey = configurationKey
        whisperModelState = .loading

        let provider = sttProviderFactory(type, settings)
        let previous = sttProvider
        sttProvider = nil
        await previous?.teardown()

        guard generation == sttProviderLoadGeneration else {
            await provider.teardown()
            return
        }

        do {
            try await provider.setup()
            guard generation == sttProviderLoadGeneration else {
                await provider.teardown()
                return
            }
            let validation = provider.validate()
            sttProvider = provider
            if validation.isValid {
                whisperModelState = .ready
            } else {
                activeSTTProviderConfigurationKey = nil
                whisperModelState = .error(validation.message)
            }
        } catch {
            await provider.teardown()
            guard generation == sttProviderLoadGeneration else { return }
            activeSTTProviderConfigurationKey = nil
            whisperModelState = .error(error.localizedDescription)
        }
    }

    func sttProviderConfigurationKey(for type: STTProviderType) -> String {
        "whisperKit:\(WhisperKitProvider.modelRevision)"
    }

    func switchLLMProvider(to type: LLMProviderType) async {
        await llmProvider?.teardown()
        llmModelState = .loading

        switch type {
        case .none:
            llmProvider = NoneProvider()
            llmModelState = .ready

        case .local:
            let spec = LocalModelSpec.qwen3_8B
            let provider: any LLMProvider = LocalTextProvider(
                modelId: spec.id,
                revision: spec.revision
            )
            llmProvider = provider
            do {
                try await provider.setup()
                let validation = provider.validate()
                llmModelState = validation.isValid ? .ready : .error(validation.message)
            } catch {
                llmModelState = .error(error.localizedDescription)
            }
        }
    }

    func addToHistory(original: String, corrected: String?) {
        transcriptionHistory.insert(
            TranscriptionRecord(
                id: UUID(),
                timestamp: Date(),
                originalText: original,
                correctedText: corrected,
                language: nil
            ),
            at: 0
        )
        if transcriptionHistory.count > 100 {
            transcriptionHistory = Array(transcriptionHistory.prefix(100))
        }
    }

    func clearError() { currentError = nil }


    private func saveHistory() {
        if let data = try? JSONEncoder().encode(transcriptionHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let history = try? JSONDecoder().decode([TranscriptionRecord].self, from: data)
        {
            transcriptionHistory = history
        }
    }
}
