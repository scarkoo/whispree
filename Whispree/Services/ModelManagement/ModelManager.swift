import Combine
import Foundation

@MainActor
final class ModelManager: ObservableObject {
    @Published var whisperModelInfo = ModelInfo.whisperLargeV3Turbo
    @Published var isWhisperKitDownloading = false

    @Published var modelCacheStates: [String: Bool] = [:] {
        didSet { persistCacheStates() }
    }
    @Published var downloadingModelIds: Set<String> = []
    @Published var queuedModelIds: Set<String> = []
    @Published var modelErrors: [String: String] = [:]
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedBytes: [String: Int64] = [:]

    var isDownloading: Bool {
        isWhisperKitDownloading || !downloadingModelIds.isEmpty
    }

    private static let cacheStatesKey = "WhispreeModelCacheStates"
    private static let whisperKitRepoId = "argmaxinc/whisperkit-coreml"

    private let appState: AppState
    private let sttService: STTService
    private var cancellables = Set<AnyCancellable>()
    private var activeDownloadTasks: [String: Task<Void, Never>] = [:]

    static var pinnedModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Whispree/PinnedModels", isDirectory: true)
    }

    var whisperKitDownloaded: Bool {
        modelCacheStates[Self.whisperKitRepoId] ?? false
    }

    var localLLMDownloaded: Bool {
        modelCacheStates[LocalModelSpec.defaultModelId] ?? false
    }

    init(appState: AppState, sttService: STTService) {
        self.appState = appState
        self.sttService = sttService

        try? FileManager.default.createDirectory(
            at: Self.pinnedModelsDirectory,
            withIntermediateDirectories: true
        )

        loadPersistedCacheStates()
        observeProviderStates()
        reconcileWithDisk()
    }

    // MARK: - Persistence

    private func loadPersistedCacheStates() {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.cacheStatesKey) as? [String: Bool] {
            modelCacheStates = saved
        }

        // Migrate only positive cache hints from older builds. The disk remains the SSOT.
        if let oldLLM = UserDefaults.standard.dictionary(forKey: "WhispreeLLMCacheStates") as? [String: Bool] {
            for (key, value) in oldLLM where value {
                modelCacheStates[key] = true
            }
            UserDefaults.standard.removeObject(forKey: "WhispreeLLMCacheStates")
        }
        if let oldSTT = UserDefaults.standard.dictionary(forKey: "WhispreeSTTCacheStates") as? [String: Bool] {
            if oldSTT["whisperKit"] == true {
                modelCacheStates[Self.whisperKitRepoId] = true
            }
            UserDefaults.standard.removeObject(forKey: "WhispreeSTTCacheStates")
        }
    }

    private func persistCacheStates() {
        UserDefaults.standard.set(modelCacheStates, forKey: Self.cacheStatesKey)
    }

    private func observeProviderStates() {
        appState.$whisperModelState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.whisperModelInfo.state = state
            }
            .store(in: &cancellables)

        appState.$whisperDownloadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fraction in
                guard let self, self.isWhisperKitDownloading else { return }
                let clamped = min(max(fraction, 0), 1)
                self.downloadProgress[Self.whisperKitRepoId] = clamped
                self.downloadedBytes[Self.whisperKitRepoId] =
                    Int64(Double(ModelInfo.whisperLargeV3Turbo.sizeBytes) * clamped)
            }
            .store(in: &cancellables)
    }

    // MARK: - Cache state

    func refreshAllCacheStates() {
        if !isWhisperKitDownloading {
            modelCacheStates[Self.whisperKitRepoId] = Self.isWhisperKitCached()
        }
        if !downloadingModelIds.contains(LocalModelSpec.defaultModelId) {
            modelCacheStates[LocalModelSpec.defaultModelId] =
                PinnedQwenDownloader.isVerifiedModelAvailable()
        }
    }

    func refreshAllCacheStatesAsync() async {
        let whisperDownloading = isWhisperKitDownloading
        let llmDownloading = downloadingModelIds.contains(LocalModelSpec.defaultModelId)

        let state = await Task.detached {
            (
                whisper: whisperDownloading ? nil : Self.isWhisperKitCached(),
                llm: llmDownloading ? nil : PinnedQwenDownloader.isVerifiedModelAvailable()
            )
        }.value

        if let whisper = state.whisper {
            modelCacheStates[Self.whisperKitRepoId] = whisper
        }
        if let llm = state.llm {
            modelCacheStates[LocalModelSpec.defaultModelId] = llm
        }
    }

    private func reconcileWithDisk() {
        modelCacheStates[Self.whisperKitRepoId] = Self.isWhisperKitCached()
        modelCacheStates[LocalModelSpec.defaultModelId] =
            PinnedQwenDownloader.isVerifiedModelAvailable()
    }

    func isLLMModelCached(_ modelId: String) -> Bool {
        guard modelId == LocalModelSpec.defaultModelId else { return false }
        return PinnedQwenDownloader.isVerifiedModelAvailable()
    }

    nonisolated static func isWhisperKitCached() -> Bool {
        let fm = FileManager.default
        let base = WhisperKitProvider.pinnedModelDownloadBase

        guard fm.fileExists(atPath: base.path),
              let enumerator = fm.enumerator(
                at: base,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return false
        }

        for case let url as URL in enumerator
        where url.lastPathComponent == WhisperKitProvider.modelVariant {
            return fm.fileExists(atPath: url.appendingPathComponent("AudioEncoder.mlmodelc").path)
                && fm.fileExists(atPath: url.appendingPathComponent("TextDecoder.mlmodelc").path)
        }
        return false
    }

    // MARK: - Startup loading

    /// Load only models that are already verified on disk.
    /// Missing models remain .notDownloaded; app startup must never implicitly download gigabytes.
    func loadModelsIfAvailable() async {
        reconcileWithDisk()

        if whisperKitDownloaded {
            await appState.switchSTTProvider(to: .whisperKit)
        } else {
            appState.whisperModelState = .notDownloaded
            appState.whisperDownloadProgress = 0
        }

        switch appState.settings.llmProviderType {
        case .none:
            await appState.switchLLMProvider(to: .none)

        case .local:
            if localLLMDownloaded {
                await appState.switchLLMProvider(to: .local)
            } else {
                appState.llmModelState = .notDownloaded
            }
        }
    }

    // MARK: - WhisperKit download

    func downloadWhisperKitModel() async {
        guard !isWhisperKitDownloading else { return }

        isWhisperKitDownloading = true
        downloadProgress[Self.whisperKitRepoId] = 0
        downloadedBytes[Self.whisperKitRepoId] = 0

        await appState.switchSTTProvider(to: .whisperKit)

        let success = appState.whisperModelState.isReady && Self.isWhisperKitCached()
        modelCacheStates[Self.whisperKitRepoId] = success

        if success {
            downloadProgress[Self.whisperKitRepoId] = 1
            downloadedBytes[Self.whisperKitRepoId] = ModelInfo.whisperLargeV3Turbo.sizeBytes
        }

        isWhisperKitDownloading = false

        if success {
            downloadProgress.removeValue(forKey: Self.whisperKitRepoId)
            downloadedBytes.removeValue(forKey: Self.whisperKitRepoId)
        }
    }

    // MARK: - Qwen download

    func downloadLLMModel(modelId: String) async {
        guard modelId == LocalModelSpec.defaultModelId else {
            modelErrors[modelId] = "허용되지 않은 LLM 모델입니다."
            return
        }
        guard activeDownloadTasks[modelId] == nil else { return }

        modelErrors.removeValue(forKey: modelId)
        queuedModelIds.insert(modelId)

        let task = Task { [weak self] in
            guard let self else { return }
            self.queuedModelIds.remove(modelId)
            await self.performLLMDownload(modelId: modelId)
        }
        activeDownloadTasks[modelId] = task
        await task.value
        activeDownloadTasks.removeValue(forKey: modelId)
    }

    func cancelLLMDownload(modelId: String) {
        activeDownloadTasks[modelId]?.cancel()
        activeDownloadTasks.removeValue(forKey: modelId)
        queuedModelIds.remove(modelId)
        downloadingModelIds.remove(modelId)
        downloadProgress.removeValue(forKey: modelId)
        downloadedBytes.removeValue(forKey: modelId)
        modelErrors.removeValue(forKey: modelId)
    }

    private func performLLMDownload(modelId: String) async {
        downloadingModelIds.insert(modelId)
        downloadProgress[modelId] = 0
        downloadedBytes[modelId] = 0
        modelCacheStates[modelId] = false

        do {
            let downloader = PinnedQwenDownloader()
            _ = try await downloader.download(
                id: modelId,
                revision: LocalModelSpec.qwen3_8B.revision,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let total = max(progress.totalUnitCount, 1)
                        let completed = min(max(progress.completedUnitCount, 0), total)
                        self.downloadedBytes[modelId] = completed
                        self.downloadProgress[modelId] =
                            min(Double(completed) / Double(total), 1)
                    }
                }
            )

            try Task.checkCancellation()
            modelCacheStates[modelId] = PinnedQwenDownloader.isVerifiedModelAvailable()

            if modelCacheStates[modelId] == true,
               appState.settings.llmProviderType == .local
            {
                await appState.switchLLMProvider(to: .local)
            }
        } catch is CancellationError {
            // User cancellation is not an error state.
        } catch {
            if !Task.isCancelled {
                modelErrors[modelId] = error.localizedDescription
            }
        }

        downloadingModelIds.remove(modelId)
        if modelCacheStates[modelId] == true {
            downloadProgress.removeValue(forKey: modelId)
            downloadedBytes.removeValue(forKey: modelId)
        }
    }

    // MARK: - Compatibility wrappers

    func downloadWhisperModel() async throws {
        await downloadWhisperKitModel()
        if case let .error(message) = appState.whisperModelState {
            throw NSError(
                domain: "ModelManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    func downloadLLMModel() async throws {
        await downloadLLMModel(modelId: LocalModelSpec.defaultModelId)
        if let error = modelErrors[LocalModelSpec.defaultModelId] {
            throw NSError(
                domain: "ModelManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
    }

    func downloadAllModels(
        whisperProgress: @escaping (Double) -> Void,
        llmProgress: @escaping (Double) -> Void
    ) async throws {
        try await downloadWhisperModel()
        whisperProgress(1)
        try await downloadLLMModel()
        llmProgress(1)
    }

    // MARK: - Delete

    func deleteWhisperModel() {
        sttService.unloadModel()
        Task { await appState.sttProvider?.teardown() }
        appState.sttProvider = nil
        appState.whisperModelState = .notDownloaded
        appState.whisperDownloadProgress = 0
        whisperModelInfo.state = .notDownloaded
        modelCacheStates[Self.whisperKitRepoId] = false

        let fm = FileManager.default
        try? fm.removeItem(at: WhisperKitProvider.pinnedModelDownloadBase)
        try? fm.removeItem(at: WhisperKitProvider.pinnedTokenizerDownloadBase)

        downloadProgress.removeValue(forKey: Self.whisperKitRepoId)
        downloadedBytes.removeValue(forKey: Self.whisperKitRepoId)
    }

    func deleteLLMModel() {
        deleteLLMModel(modelId: LocalModelSpec.defaultModelId)
    }

    func deleteLLMModel(modelId: String) {
        guard modelId == LocalModelSpec.defaultModelId else { return }

        cancelLLMDownload(modelId: modelId)
        Task { await appState.llmProvider?.teardown() }
        appState.llmProvider = nil
        appState.llmModelState = .notDownloaded

        do {
            try FileManager.default.removeItem(at: PinnedQwenDownloader.modelDirectory)
        } catch {
            if FileManager.default.fileExists(atPath: PinnedQwenDownloader.modelDirectory.path) {
                modelErrors[modelId] = "삭제 실패: \(error.localizedDescription)"
            }
        }
        modelCacheStates[modelId] = false
    }

    func cachedModelDirectory(repoId: String) -> URL? {
        guard repoId == LocalModelSpec.defaultModelId,
              PinnedQwenDownloader.isVerifiedModelAvailable()
        else {
            return nil
        }
        return PinnedQwenDownloader.modelDirectory
    }

    var totalDiskUsage: Int64 {
        Self.directorySize(Self.pinnedModelsDirectory)
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
