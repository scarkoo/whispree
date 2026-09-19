import Combine
import Foundation
import KeyboardShortcuts

/// Security-hardened local-only application settings.
///
/// Cloud credentials, OAuth/Codex auth, screenshot context, browser/terminal automation,
/// and media-control settings intentionally do not exist in this fork.
@MainActor
final class AppSettings: ObservableObject, UserDefaultsStoreProviding {
    nonisolated let userDefaultsStore: UserDefaults

    @RawRepresentableUserDefault(key: "whispree.recordingMode", defaultValue: .pushToTalk)
    var recordingMode: RecordingMode

    @RawRepresentableUserDefault(key: "whispree.language", defaultValue: .korean)
    var language: SupportedLanguage

    @UserDefault(key: "whispree.isLLMEnabled", defaultValue: true)
    var isLLMEnabled: Bool

    @UserDefault(key: "whispree.hasCompletedOnboarding", defaultValue: false)
    var hasCompletedOnboarding: Bool

    @UserDefault(key: "whispree.launchAtLogin", defaultValue: false)
    var launchAtLogin: Bool

    @UserDefault(key: "whispree.showOverlay", defaultValue: true)
    var showOverlay: Bool

    @RawRepresentableUserDefault(
        key: "whispree.correctionMode",
        defaultValue: .standard,
        rawAliasMap: ["promptEngineering": "fillerRemoval"]
    )
    var correctionMode: CorrectionMode

    @UserDefault(key: "whispree.customLLMPrompt", defaultValue: nil)
    var customLLMPrompt: String?

    @UserDefault(
        key: "whispree.whisperModelId",
        defaultValue: "openai_whisper-large-v3_turbo"
    )
    var whisperModelId: String

    @UserDefault(
        key: "whispree.llmModelId",
        defaultValue: "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    )
    var llmModelId: String

    @UserDefault(
        key: "whispree.mlxAudioModelId",
        defaultValue: "mlx-community/Qwen3-ASR-1.7B-8bit"
    )
    var mlxAudioModelId: String

    @RawRepresentableUserDefault(key: "whispree.sttProviderType", defaultValue: .whisperKit)
    var sttProviderType: STTProviderType

    @RawRepresentableUserDefault(
        key: "whispree.llmProviderType",
        defaultValue: .local,
        rawAliasMap: [
            "로컬 LLM (Qwen3)": "로컬 MLX",
            "OpenAI (GPT)": "로컬 MLX",
            "OpenAI 호환 API": "로컬 MLX",
            "Groq Cloud": "로컬 MLX"
        ]
    )
    var llmProviderType: LLMProviderType

    @UserDefault(key: "whispree.audioInputChannel", defaultValue: 0)
    var audioInputChannel: Int

    @UserDefault(key: "whispree.vadEnabled", defaultValue: true)
    var vadEnabled: Bool

    @CodableUserDefault(key: "whispree.domainWordSets", defaultValue: [])
    var domainWordSets: [DomainWordSet]

    @UserDefault(key: "whispree.sharedDictionaryEnabled", defaultValue: false)
    var sharedDictionaryEnabled: Bool

    @UserDefault(key: "whispree.sharedDictionaryPath", defaultValue: nil)
    var sharedDictionaryPath: String?

    @CodableUserDefault(
        key: "whispree.toggleRecordingShortcut",
        defaultValue: WhispreeShortcut.defaultToggleRecording
    )
    var toggleRecordingShortcut: WhispreeShortcut

    @CodableUserDefault(
        key: "whispree.quickFixShortcut",
        defaultValue: WhispreeShortcut.defaultQuickFix
    )
    var quickFixShortcut: WhispreeShortcut

    init(store: UserDefaults = .standard, migrateHotkeys: Bool = true) {
        userDefaultsStore = store
        sanitizeLegacyProviderSelections()
        purgeLegacyWhispreeOAuthCredentials()
        if migrateHotkeys {
            migrateHotkeysIfNeeded()
        }
        if llmModelId.contains("Qwen2.5") {
            llmModelId = LocalModelSpec.defaultModelId
        }
    }

    private func sanitizeLegacyProviderSelections() {
        let defaults = userDefaultsStore
        if let stt = defaults.string(forKey: "whispree.sttProviderType"),
           STTProviderType(rawValue: stt) == nil {
            defaults.set(STTProviderType.whisperKit.rawValue, forKey: "whispree.sttProviderType")
        }
        if let llm = defaults.string(forKey: "whispree.llmProviderType"),
           LLMProviderType(rawValue: llm) == nil,
           llm != "없음 (원문 사용)"
        {
            defaults.set(LLMProviderType.local.rawValue, forKey: "whispree.llmProviderType")
        }

        // Purge credentials and privacy-sensitive settings left by the upstream app.
        [
            "whispree.groqApiKey",
            "whispree.openaiCompatibleBaseURL",
            "whispree.openaiCompatibleAPIKey",
            "whispree.openaiCompatibleModelId",
            "whispree.openaiCompatibleSupportsVision",
            "whispree.openaiModel",
            "whispree.groqLLMModel",
            "whispree.isScreenshotContextEnabled",
            "whispree.isScreenshotPasteEnabled",
            "whispree.pauseMediaDuringRecording",
            "whispree.restoreBrowserTab",
            "whispree.restoreTerminalContext"
        ].forEach(defaults.removeObject)
    }

    /// Remove credentials created by older Whispree OAuth implementations.
    /// Deliberately never touches ~/.codex/auth.json because that belongs to Codex.
    private func purgeLegacyWhispreeOAuthCredentials() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacyPaths = [
            home.appendingPathComponent(".whispree/oauth.json"),
            home.appendingPathComponent(".notmywhisper/oauth.json")
        ]
        for url in legacyPaths where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func migrateHotkeysIfNeeded() {
        let defaults = userDefaultsStore
        let flagKey = "whispree.hotkeyMigrationDone"
        guard !defaults.bool(forKey: flagKey) else { return }

        if defaults.data(forKey: "whispree.toggleRecordingShortcut") == nil,
           let stored = KeyboardShortcuts.getShortcut(for: .toggleRecording)
        {
            toggleRecordingShortcut = WhispreeShortcut(combo: stored)
        }
        if defaults.data(forKey: "whispree.quickFixShortcut") == nil,
           let stored = KeyboardShortcuts.getShortcut(for: .quickFix)
        {
            quickFixShortcut = WhispreeShortcut(combo: stored)
        }

        KeyboardShortcuts.setShortcut(nil, for: .toggleRecording)
        KeyboardShortcuts.setShortcut(nil, for: .quickFix)
        defaults.set(true, forKey: flagKey)
    }

    var sharedDictionaryConfig: SharedDictionaryConfig {
        SharedDictionaryConfig(customURL: sharedDictionaryPath.flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        })
    }

    func exportSharedDictionary() {
        guard sharedDictionaryEnabled, let url = sharedDictionaryConfig.resolvedFileURL else { return }
        let snapshot = domainWordSets
        Task.detached { try? SharedDictionaryStore.save(snapshot, to: url) }
    }

    @discardableResult
    func importSharedDictionary() -> Bool {
        guard sharedDictionaryEnabled,
              let url = sharedDictionaryConfig.resolvedFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let imported = try? SharedDictionaryStore.load(from: url),
              !imported.isEmpty
        else { return false }
        domainWordSets = imported
        return true
    }
}

enum STTProviderType: String, Codable, CaseIterable {
    case whisperKit = "WhisperKit"
    case mlxAudio = "MLX Audio"

    var displayName: String {
        switch self {
        case .whisperKit: "WhisperKit (로컬)"
        case .mlxAudio: "MLX Audio (로컬)"
        }
    }
}

enum LLMProviderType: String, Codable, CaseIterable {
    case none = "없음 (원문 사용)"
    case local = "로컬 MLX"

    var displayName: String { rawValue }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "없음 (원문 사용)":
            self = .none
        case "로컬 MLX", "로컬 LLM (Qwen3)", "OpenAI (GPT)", "OpenAI 호환 API", "Groq Cloud":
            self = .local
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown LLMProviderType: \(rawValue)"
            ))
        }
    }
}
