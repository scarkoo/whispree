import SwiftUI

struct LLMSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox("로컬 텍스트 교정") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("교정", selection: providerBinding) {
                            Text("사용 안 함").tag(LLMProviderType.none)
                            Text("Qwen3 8B (로컬)").tag(LLMProviderType.local)
                        }

                        HStack {
                            Text("고정 모델")
                            Spacer()
                            Text("Qwen3-8B-4bit")
                                .foregroundStyle(.secondary)
                        }

                        Text("교정 텍스트는 revision이 고정된 Qwen3 8B 모델에서만 로컬 처리됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appState.settings.llmProviderType == .local {
                            HStack {
                                Text("상태")
                                Spacer()
                                stateLabel(appState.llmModelState)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("교정 방식") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: correctionModeBinding) {
                            ForEach(CorrectionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        Text(appState.settings.correctionMode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appState.settings.correctionMode == .custom {
                            TextEditor(text: Binding(
                                get: { appState.settings.customLLMPrompt ?? "" },
                                set: { appState.settings.customLLMPrompt = $0 }
                            ))
                            .font(.body)
                            .frame(minHeight: 140)
                            .padding(6)
                            .background(.quaternary.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
        .liquidBackground()
    }

    private var correctionModeBinding: Binding<CorrectionMode> {
        Binding(
            get: { appState.settings.correctionMode },
            set: { appState.settings.correctionMode = $0 }
        )
    }

    private var providerBinding: Binding<LLMProviderType> {
        Binding(
            get: { appState.settings.llmProviderType },
            set: { type in
                appState.settings.llmProviderType = type
                appState.settings.isLLMEnabled = type != .none
                Task { await appState.switchLLMProvider(to: type) }
            }
        )
    }

    @ViewBuilder
    private func stateLabel(_ state: ModelState) -> some View {
        switch state {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .loading, .queued, .downloading:
            ProgressView().controlSize(.small)
        case .notDownloaded:
            Text("모델 필요").foregroundStyle(.secondary)
        case let .error(message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }
}
