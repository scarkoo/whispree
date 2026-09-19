import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissions = PermissionManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.accentPrimary)

            VStack(spacing: 8) {
                Text("Whispree Local")
                    .font(.largeTitle.bold())
                Text("음성과 교정 텍스트를 로컬 모델에서 처리하는 보안 우선 빌드입니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "마이크",
                    subtitle: "음성을 녹음해 로컬 STT로 전달",
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
                    subtitle: "전역 단축키와 결과 텍스트 삽입",
                    status: permissions.accessibility
                ) {
                    if permissions.accessibility == .denied {
                        permissions.openAccessibilitySettings()
                    } else {
                        _ = permissions.requestAccessibility()
                    }
                }
            }
            .background(DesignTokens.surfaceBackgroundView(role: .card))

            VStack(alignment: .leading, spacing: 8) {
                Label("WhisperKit Large V3 Turbo 고정 로컬 STT", systemImage: "checkmark.shield")
                Label("Qwen3 8B 고정 로컬 LLM 교정", systemImage: "checkmark.shield")
                Label("화면 캡처 · Cloud API · Codex/OAuth 없음", systemImage: "checkmark.shield")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(DesignTokens.surfaceBackgroundView(role: .inset, cornerRadius: 18))

            Spacer()

            Button("시작하기") {
                appState.settings.llmProviderType = .local
                appState.settings.isLLMEnabled = true
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(permissions.microphone != .granted || permissions.accessibility != .granted)
            .padding(.bottom, 28)
        }
        .padding(28)
        .frame(width: 500, height: 680)
        .liquidBackground()
        .task { permissions.refreshAll() }
    }
}
