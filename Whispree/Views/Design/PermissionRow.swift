import SwiftUI

struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: PermissionManager.Status
    var actionLabel: String? = nil
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignTokens.accentPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.semanticColors(for: .success).foreground)
            case .unavailable:
                Text("사용 불가").font(.caption).foregroundStyle(.secondary)
            case .denied, .notDetermined:
                Button(action: onAction) {
                    Text(actionLabel ?? (status == .denied ? "설정 열기" : "허용하기"))
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
    }
}
