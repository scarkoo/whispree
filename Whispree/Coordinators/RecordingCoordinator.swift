import AppKit
import Combine
import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    private let appState: AppState
    private let audioService: AudioService
    private let textInsertionService: TextInsertionService

    private let queue = DictationQueueState()
    private var processingTasks: [DictationJobID: Task<Void, Never>] = [:]
    private var deliveryTask: Task<Void, Never>?
    private var levelCancellable: AnyCancellable?
    private var bandsCancellable: AnyCancellable?
    private var thinkingPauseCancellable: AnyCancellable?
    private var workspaceObserver: AnyCancellable?
    private var activeRecordingContext: ExternalContext?
    private var lastExternalApp: NSRunningApplication?

    init(
        appState: AppState,
        audioService: AudioService,
        textInsertionService: TextInsertionService
    ) {
        self.appState = appState
        self.audioService = audioService
        self.textInsertionService = textInsertionService

        levelCancellable = audioService.$currentLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] level in appState?.currentAudioLevel = level }

        bandsCancellable = audioService.$frequencyBands
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] bands in appState?.frequencyBands = bands }

        thinkingPauseCancellable = audioService.$isThinkingPause
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] paused in
                guard let appState else { return }
                appState.isThinkingPause = appState.settings.vadEnabled ? paused : false
            }

        workspaceObserver = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier
                else { return }
                Task { @MainActor [weak self] in self?.lastExternalApp = app }
            }
    }

    func startRecording() {
        guard !audioService.isRecording else { return }
        guard appState.transcriptionState != .inserting else { return }
        guard let sttProvider = appState.sttProvider else {
            appState.currentError = .sttError("STT 프로바이더가 설정되지 않았습니다.")
            return
        }

        let validation = sttProvider.validate()
        guard validation.isValid else {
            appState.currentError = .sttError(validation.message)
            return
        }

        queue.setRecordingActive(true)
        let previousApp = currentExternalTargetApp()
        activeRecordingContext = previousApp.map(ExternalContext.app)

        do {
            try audioService.startRecording(channelSelection: appState.settings.audioInputChannel)
            appState.transcriptionState = .recording
            appState.isRecording = true
            appState.partialText = ""
            appState.finalText = ""
            appState.correctedText = ""
            refreshProjectedState()
        } catch {
            queue.setRecordingActive(false)
            activeRecordingContext = nil
            appState.isRecording = false
            appState.currentError = .sttError("Failed to start recording: \(error.localizedDescription)")
            scheduleProcessingAndDelivery()
            refreshProjectedState()
        }
    }

    func stopRecording() {
        guard audioService.isRecording else { return }

        let audioBuffer = audioService.stopRecording()
        appState.isRecording = false
        queue.setRecordingActive(false)

        defer {
            activeRecordingContext = nil
            scheduleProcessingAndDelivery()
            refreshProjectedState()
        }

        guard !audioBuffer.isEmpty else { return }
        let maxAmplitude = audioBuffer.map { abs($0) }.max() ?? 0
        guard maxAmplitude > 0.01 else { return }

        let enqueued = queue.enqueue(
            snapshot: makeJobSnapshot(),
            audio: .memory(audioBuffer),
            targetContext: activeRecordingContext
        )
        if enqueued == nil {
            appState.currentError = .sttError("녹음된 오디오가 비어 있습니다.")
        }
    }

    func cancel() {
        if audioService.isRecording {
            cancelActiveRecordingOnly()
            return
        }
        if let jobID = queue.activeDeliveryJobID ?? queue.foregroundJobID {
            cancel(jobID: jobID)
        } else {
            refreshProjectedState()
        }
    }

    private func scheduleProcessingAndDelivery() {
        scheduleSTTJobs()
        scheduleLLMJobs()
        scheduleDelivery()
    }

    private func scheduleSTTJobs() {
        while let jobID = queue.startNextSTT() {
            processingTasks[jobID] = Task { [weak self] in
                await self?.processSTT(jobID: jobID)
            }
        }
    }

    private func scheduleLLMJobs() {
        while let jobID = queue.startNextLLM() {
            processingTasks[jobID] = Task { [weak self] in
                await self?.processLLM(jobID: jobID)
            }
        }
    }

    private func scheduleDelivery() {
        guard deliveryTask == nil, let jobID = queue.startDeliveryIfPossible() else { return }
        deliveryTask = Task { [weak self] in await self?.deliver(jobID: jobID) }
    }

    private func processSTT(jobID: DictationJobID) async {
        defer {
            if queue.job(id: jobID)?.status == .transcribing {
                queue.failSTT(jobID: jobID, message: "STT transcription was interrupted")
            }
            processingTasks[jobID] = nil
            scheduleProcessingAndDelivery()
            refreshProjectedState()
        }

        guard let job = queue.job(id: jobID),
              let audioBuffer = job.audio.samples
        else {
            queue.failSTT(jobID: jobID, message: "Unsupported queued audio payload")
            return
        }

        guard currentSTTProviderConfigKey() == job.snapshot.sttProviderConfigKey else {
            queue.failSTT(jobID: jobID, message: "STT provider changed before queued job started")
            return
        }
        guard let provider = appState.sttProvider else {
            queue.failSTT(jobID: jobID, message: "No STT provider configured")
            return
        }

        let trimmedBuffer = job.snapshot.vadEnabled
            ? AudioService.trimSilence(audioBuffer)
            : audioBuffer

        do {
            if let whisper = provider as? WhisperKitProvider {
                whisper.domainWordSets = job.snapshot.domainWordSets
            }
            let result = try await provider.transcribe(
                audioBuffer: trimmedBuffer,
                language: job.snapshot.language == .auto ? nil : job.snapshot.language,
                promptTokens: nil
            )
            guard !Task.isCancelled else { return }
            queue.completeSTT(
                jobID: jobID,
                text: result.text,
                requiresLLM: shouldRunLLM(for: job)
            )
            appState.finalText = result.text
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            queue.failSTT(jobID: jobID, message: error.localizedDescription)
            appState.currentError = .sttError(error.localizedDescription)
        }
    }

    private func processLLM(jobID: DictationJobID) async {
        defer {
            if queue.job(id: jobID)?.status == .correcting {
                queue.failLLMFallbackToRaw(jobID: jobID)
            }
            processingTasks[jobID] = nil
            scheduleProcessingAndDelivery()
            refreshProjectedState()
        }

        guard let job = queue.job(id: jobID) else { return }
        guard currentLLMProviderConfigKey() == job.snapshot.llmProviderConfigKey else {
            queue.failLLMFallbackToRaw(jobID: jobID)
            return
        }
        guard let provider = appState.llmProvider,
              provider.isReady,
              !(provider is NoneProvider)
        else {
            queue.failLLMFallbackToRaw(jobID: jobID)
            return
        }

        do {
            let corrected = try await provider.correct(
                text: job.transcribedText,
                systemPrompt: systemPrompt(for: job),
                glossary: job.snapshot.glossary.isEmpty ? nil : job.snapshot.glossary
            )
            guard !Task.isCancelled else { return }
            queue.completeLLM(jobID: jobID, correctedText: corrected)
            appState.correctedText = corrected
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            queue.failLLMFallbackToRaw(jobID: jobID)
            appState.correctedText = ""
        }
    }

    private func deliver(jobID: DictationJobID) async {
        defer {
            deliveryTask = nil
            scheduleDelivery()
            refreshProjectedState()
        }

        guard let job = queue.job(id: jobID), !job.status.isTerminal else { return }
        guard job.snapshot.hasCompletedOnboarding else {
            queue.completeDelivery(jobID: jobID, copiedFallback: true)
            return
        }
        guard !queue.snapshot.isRecordingActive else {
            queue.pauseActiveDeliveryForRecording(jobID: jobID)
            return
        }

        appState.transcriptionState = .inserting
        let text = job.correctedText.isEmpty ? job.transcribedText : job.correctedText
        let targetApp = job.targetContext?.app
        let success = await textInsertionService.insertText(text, targetApp: targetApp)

        if !success {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        appState.addToHistory(
            original: job.transcribedText,
            corrected: job.correctedText.isEmpty ? nil : job.correctedText
        )
        queue.completeDelivery(jobID: jobID, copiedFallback: !success)
    }

    private func cancel(jobID: DictationJobID) {
        processingTasks[jobID]?.cancel()
        processingTasks[jobID] = nil
        if queue.activeDeliveryJobID == jobID {
            deliveryTask?.cancel()
            deliveryTask = nil
        }
        queue.cancelJob(jobID: jobID)
        scheduleProcessingAndDelivery()
        refreshProjectedState()
    }

    private func cancelActiveRecordingOnly() {
        activeRecordingContext = nil
        _ = audioService.stopRecording()
        queue.setRecordingActive(false)
        appState.isRecording = false
        appState.isThinkingPause = false
        scheduleProcessingAndDelivery()
        refreshProjectedState()
    }

    private func makeJobSnapshot() -> DictationJobSnapshot {
        let enabledSets = appState.settings.domainWordSets.filter(\.isEnabled)
        return DictationJobSnapshot(
            sttProviderType: appState.settings.sttProviderType,
            llmProviderType: appState.settings.llmProviderType,
            llmEnabled: appState.settings.isLLMEnabled,
            sttProviderConfigKey: currentSTTProviderConfigKey(),
            llmProviderConfigKey: currentLLMProviderConfigKey(),
            correctionMode: appState.settings.correctionMode,
            customPrompt: appState.settings.customLLMPrompt,
            language: appState.settings.language,
            glossary: enabledSets.flatMap(\.words),
            domainWordSets: appState.settings.domainWordSets,
            correctionMappings: enabledSets.flatMap(\.corrections),
            hasCompletedOnboarding: appState.settings.hasCompletedOnboarding,
            vadEnabled: appState.settings.vadEnabled
        )
    }

    private func shouldRunLLM(for job: DictationJob) -> Bool {
        guard job.snapshot.llmEnabled, job.snapshot.llmProviderType != .none else { return false }
        guard currentLLMProviderConfigKey() == job.snapshot.llmProviderConfigKey else { return false }
        guard let provider = appState.llmProvider,
              provider.isReady,
              !(provider is NoneProvider)
        else { return false }
        return true
    }

    private func currentSTTProviderConfigKey() -> String {
        appState.sttProviderConfigurationKey(for: appState.settings.sttProviderType)
    }

    private func currentLLMProviderConfigKey() -> String {
        switch appState.settings.llmProviderType {
        case .none: "none"
        case .local: "local:\(appState.settings.llmModelId)"
        }
    }

    private func systemPrompt(for job: DictationJob) -> String {
        var prompt: String = switch job.snapshot.correctionMode {
        case .custom:
            job.snapshot.customPrompt ?? CorrectionPrompts.codeSwitchPrompt
        case .standard, .fillerRemoval, .structured:
            CorrectionPrompts.prompt(for: job.snapshot.correctionMode, language: job.snapshot.language)
        }

        if !job.snapshot.correctionMappings.isEmpty {
            let mapping = job.snapshot.correctionMappings
                .map { "\($0.from) → \($0.to)" }
                .joined(separator: "\n")
            prompt += "\n\n교정 매핑 (왼쪽 표현이 텍스트에 있으면 오른쪽으로 교정):\n" + mapping
        }
        return prompt
    }

    private func currentExternalTargetApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? lastExternalApp
            : frontmost
    }

    private func refreshProjectedState() {
        appState.dictationQueueSnapshot = queue.snapshot
        if appState.isRecording {
            appState.transcriptionState = .recording
        } else if queue.activeDeliveryJobID != nil {
            appState.transcriptionState = .inserting
        } else if !queue.correctingJobIDs().isEmpty {
            appState.transcriptionState = .correcting
        } else if !queue.transcribingJobIDs().isEmpty {
            appState.transcriptionState = .transcribing
        } else {
            appState.transcriptionState = .idle
            appState.isThinkingPause = false
        }
    }
}
