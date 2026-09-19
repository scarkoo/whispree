import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissions = PermissionManager.shared
    @State private var recordingConflict: ShortcutConflict?
    @State private var quickFixConflict: ShortcutConflict?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox("권한") {
                    VStack(spacing: 0) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "마이크",
                            subtitle: "로컬 음성 인식용",
                            status: permissions.microphone
                        ) {
                            if permissions.microphone == .denied {
                                permissions.openMicrophoneSettings()
                            } else {
                                Task { _ = await permissions.requestMicrophone() }
                            }
                        }

                        Divider()

                        PermissionRow(
                            icon: "hand.raised.fill",
                            title: "손쉬운 사용",
                            subtitle: "전역 단축키와 텍스트 자동 삽입용",
                            status: permissions.accessibility
                        ) {
                            if permissions.accessibility == .denied {
                                permissions.openAccessibilitySettings()
                            } else {
                                _ = permissions.requestAccessibility()
                            }
                        }
                    }
                }

                GroupBox("녹음") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("녹음 방식", selection: recordingModeBinding) {
                            ForEach(RecordingMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        Picker("언어", selection: $appState.settings.language) {
                            ForEach(SupportedLanguage.allCases, id: \.self) { language in
                                Text(language.displayName).tag(language)
                            }
                        }

                        Toggle("녹음 오버레이 표시", isOn: $appState.settings.showOverlay)
                        Toggle("무음 구간 제거", isOn: $appState.settings.vadEnabled)
                    }
                    .padding(8)
                }

                GroupBox("단축키") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Recording")
                            Spacer()
                            ShortcutRecorderButton(kind: .toggleRecording, conflict: $recordingConflict)
                        }
                        HStack {
                            Text("Quick Fix")
                            Spacer()
                            ShortcutRecorderButton(kind: .quickFix, conflict: $quickFixConflict)
                        }
                    }
                    .padding(8)
                }

                GroupBox("보안 모드") {
                    Text("화면 캡처, AppleEvents 자동화, 미디어 원격 제어, 클라우드 STT/LLM 및 Codex/OAuth 인증 기능은 빌드에서 제거되어 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .padding(24)
        }
        .liquidBackground()
        .task { permissions.refreshAll() }
    }

    private var recordingModeBinding: Binding<RecordingMode> {
        Binding(
            get: { appState.settings.recordingMode },
            set: { hotkeyManager.updateMode($0) }
        )
    }
}
