import SwiftUI

struct STTSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox("로컬 STT") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Provider")
                            Spacer()
                            Text("WhisperKit Large V3 Turbo")
                                .foregroundStyle(.secondary)
                        }

                        Text("STT는 revision이 고정된 WhisperKit 모델만 사용합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Picker("언어", selection: languageBinding) {
                            ForEach(SupportedLanguage.allCases, id: \.self) { language in
                                Text(language.displayName).tag(language)
                            }
                        }

                        Toggle("무음 구간 제거 (VAD)", isOn: vadEnabledBinding)
                    }
                    .padding(8)
                }

                GroupBox("상태") {
                    HStack {
                        Text("WhisperKit (로컬 고정)")
                        Spacer()
                        stateLabel(appState.whisperModelState)
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
        .liquidBackground()
    }

    private var languageBinding: Binding<SupportedLanguage> {
        Binding(
            get: { appState.settings.language },
            set: { appState.settings.language = $0 }
        )
    }

    private var vadEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.vadEnabled },
            set: { appState.settings.vadEnabled = $0 }
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
