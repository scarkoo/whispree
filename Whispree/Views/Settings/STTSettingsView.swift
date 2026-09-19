import SwiftUI

struct STTSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox("로컬 STT") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Provider", selection: providerBinding) {
                            ForEach(STTProviderType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }

                        Text("음성은 선택한 온디바이스 모델에서 처리됩니다. 모델 다운로드 외에는 STT 오디오가 네트워크로 전송되지 않습니다.")
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
                        Text(appState.settings.sttProviderType.displayName)
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

    private var providerBinding: Binding<STTProviderType> {
        Binding(
            get: { appState.settings.sttProviderType },
            set: { type in
                appState.settings.sttProviderType = type
                Task { await appState.switchSTTProvider(to: type) }
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
