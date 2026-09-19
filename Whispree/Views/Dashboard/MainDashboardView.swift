import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var permissions = PermissionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(24)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    recordingCard
                    transcriptionCard
                    providerCard

                    if permissions.accessibility != .granted {
                        accessibilityWarning
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidBackground()
        .task { permissions.refreshAll() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title)
                .foregroundStyle(DesignTokens.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Whispree Local")
                    .font(.title2.bold())
                Text("온디바이스 STT + LLM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(appState.isReady ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
        }
    }

    private var recordingCard: some View {
        VStack(spacing: 10) {
            if appState.isRecording {
                ScrollingWaveformView()
                    .frame(height: 56)
                Text("Listening... ESC to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if appState.transcriptionState == .transcribing || appState.transcriptionState == .correcting {
                ProgressView()
                Text(appState.transcriptionState.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "mic.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("단축키를 눌러 로컬 받아쓰기를 시작하세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .padding(16)
        .background(DesignTokens.surfaceBackgroundView(role: .card))
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last Transcription").font(.headline)
                Spacer()
                if !appState.finalText.isEmpty {
                    Button {
                        let value = appState.correctedText.isEmpty ? appState.finalText : appState.correctedText
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }

            if appState.finalText.isEmpty {
                Text("아직 전사 기록이 없습니다.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Text(appState.finalText)
                    .textSelection(.enabled)
                if !appState.correctedText.isEmpty {
                    Divider()
                    Text(appState.correctedText)
                        .textSelection(.enabled)
                        .foregroundStyle(DesignTokens.accentPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignTokens.surfaceBackgroundView(role: .card))
    }

    private var providerCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("STT", systemImage: "mic.fill")
                Spacer()
                Text("WhisperKit Large V3 Turbo")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Label("LLM", systemImage: "text.badge.checkmark")
                Spacer()
                Picker("", selection: llmBinding) {
                    Text("사용 안 함").tag(LLMProviderType.none)
                    Text("Qwen3 8B (로컬)").tag(LLMProviderType.local)
                }
                .frame(width: 190)
            }

            if appState.settings.llmProviderType == .local {
                Text("LLM: \(LocalModelSpec.qwen3_8B.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(DesignTokens.surfaceBackgroundView(role: .card))
    }

    private var accessibilityWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("텍스트 자동 삽입을 위해 손쉬운 사용 권한이 필요합니다.")
                .font(.caption)
            Spacer()
            Button("설정") { permissions.openAccessibilitySettings() }
                .controlSize(.small)
        }
        .padding(12)
        .background(DesignTokens.surfaceBackgroundView(role: .inset, cornerRadius: 18))
    }

    private var llmBinding: Binding<LLMProviderType> {
        Binding(
            get: { appState.settings.llmProviderType },
            set: { type in
                appState.settings.llmProviderType = type
                appState.settings.isLLMEnabled = type != .none
                Task { await appState.switchLLMProvider(to: type) }
            }
        )
    }
}
