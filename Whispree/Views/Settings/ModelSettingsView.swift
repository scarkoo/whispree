import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var modelManager: ModelManager

    private let device = DeviceCapability.current
    private let llmSpec = LocalModelSpec.qwen3_8B

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 10) {
                    modelInfoPill(device.chipName, systemImage: "cpu")
                    modelInfoPill("\(device.totalRAMGB) GB", systemImage: "memorychip")
                    modelInfoPill("~\(device.memoryBandwidthGBs) GB/s", systemImage: "arrow.left.arrow.right")
                    modelInfoPill("\(device.gpuCores) cores", systemImage: "gpu")
                }

                LiquidSection("STT 모델") {
                    let whisperInfo = ModelInfo.whisperLargeV3Turbo
                    let whisperCompat = ModelCompatibility.evaluate(modelSizeBytes: whisperInfo.sizeBytes)
                    DownloadableModelRow(
                        name: "WhisperKit Large V3 Turbo",
                        description: "고정 revision · 로컬 CoreML + ANE",
                        metrics: .local(
                            size: whisperInfo.sizeDescription,
                            ramPercent: whisperCompat.ramUsagePercent,
                            tokPerSec: nil,
                            qualityScore: 75,
                            grade: whisperCompat.grade
                        ),
                        state: modelManager.whisperKitDownloaded ? .ready : activeWhisperKitState,
                        downloadedBytes: whisperDownloadedBytes,
                        totalBytes: whisperInfo.sizeBytes,
                        onDownload: { Task { await modelManager.downloadWhisperKitModel() } },
                        onDelete: { modelManager.deleteWhisperModel() }
                    )
                }

                LiquidSection("LLM 모델") {
                    let compat = llmSpec.compatibility(otherModelSizeBytes: 1_500_000_000)
                    let state: ModelState = {
                        if modelManager.localLLMDownloaded { return .ready }
                        if modelManager.queuedModelIds.contains(llmSpec.id) { return .queued }
                        if modelManager.downloadingModelIds.contains(llmSpec.id) {
                            if let progress = modelManager.downloadProgress[llmSpec.id] {
                                return .downloading(progress: progress)
                            }
                            return .loading
                        }
                        if let error = modelManager.modelErrors[llmSpec.id] {
                            return .error(error)
                        }
                        return .notDownloaded
                    }()

                    DownloadableModelRow(
                        name: llmSpec.displayName,
                        description: "고정 revision · Swift MLX 전용",
                        metrics: .local(
                            size: llmSpec.sizeDescription,
                            ramPercent: compat.ramUsagePercent,
                            tokPerSec: compat.estimatedTokPerSec,
                            qualityScore: llmSpec.qualityScore,
                            grade: compat.grade
                        ),
                        state: state,
                        isSelected: appState.settings.llmProviderType == .local,
                        downloadedBytes: modelManager.downloadedBytes[llmSpec.id],
                        totalBytes: llmSpec.sizeBytes,
                        onDownload: { Task { await modelManager.downloadLLMModel(modelId: llmSpec.id) } },
                        onCancel: { modelManager.cancelLLMDownload(modelId: llmSpec.id) },
                        onDelete: { modelManager.deleteLLMModel(modelId: llmSpec.id) }
                    )
                }

                LiquidSection("저장 공간") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("고정 모델 위치:")
                            Spacer()
                            Text("~/Library/Application Support/Whispree/PinnedModels/")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Finder에서 열기") {
                            let directory = ModelManager.pinnedModelsDirectory
                            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(directory)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(24)
        }
        .liquidBackground()
        .task {
            await modelManager.refreshAllCacheStatesAsync()
        }
    }

    private var whisperDownloadedBytes: Int64? {
        guard let progress = modelManager.downloadProgress["argmaxinc/whisperkit-coreml"] else {
            return nil
        }
        return Int64(Double(ModelInfo.whisperLargeV3Turbo.sizeBytes) * progress)
    }

    private var activeWhisperKitState: ModelState {
        let whisperKey = "argmaxinc/whisperkit-coreml"
        if let progress = modelManager.downloadProgress[whisperKey] {
            return .downloading(progress: progress)
        }
        if case .downloading = appState.whisperModelState { return appState.whisperModelState }
        if case .loading = appState.whisperModelState { return appState.whisperModelState }
        if modelManager.isWhisperKitDownloading { return .loading }
        return .notDownloaded
    }

    private func modelInfoPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

enum ModelMetrics {
    case local(size: String, ramPercent: Int, tokPerSec: Int?, qualityScore: Int, grade: CompatibilityGrade)
}

struct DownloadableModelRow: View {
    let name: String
    let description: String
    let metrics: ModelMetrics
    let state: ModelState
    var isSelected: Bool = false
    var downloadedBytes: Int64? = nil
    var totalBytes: Int64? = nil
    let onDownload: () -> Void
    var onCancel: (() -> Void)? = nil
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                        if isSelected {
                            Text("사용 중")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                metricsView
            }

            stateControls
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var stateControls: some View {
        switch state {
        case .notDownloaded:
            Button("다운로드") { onDownload() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .queued:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("다운로드 대기 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let onCancel {
                    Button("취소", role: .cancel) { onCancel() }
                        .font(.caption)
                        .controlSize(.small)
                }
            }
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                HStack {
                    Text(progressLabel(progress: progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let onCancel {
                        Button("취소", role: .cancel) { onCancel() }
                            .font(.caption)
                            .controlSize(.small)
                    }
                }
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("로딩 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            HStack {
                Label("준비됨", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("삭제", role: .destructive) { onDelete() }
                    .font(.caption)
                    .controlSize(.small)
            }
        case let .error(message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.semanticColors(for: .danger).foreground)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button("재시도") { onDownload() }
                    .font(.caption)
                    .controlSize(.small)
            }
        }
    }

    private func progressLabel(progress: Double) -> String {
        let pct = progress < 0.01
            ? String(format: "%.1f%%", progress * 100)
            : String(format: "%d%%", Int(progress * 100))
        if let downloaded = downloadedBytes, let total = totalBytes, total > 0 {
            return "\(formatBytes(downloaded)) / \(formatBytes(total)) (\(pct)) 다운로드 중..."
        }
        return "\(pct) 다운로드 중..."
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @ViewBuilder
    private var metricsView: some View {
        switch metrics {
        case let .local(size, ramPercent, tokPerSec, qualityScore, grade):
            ModelMetricsView(
                sizeText: size,
                ramPercent: ramPercent,
                tokPerSec: tokPerSec,
                latencyMs: nil,
                qualityScore: qualityScore,
                grade: grade
            )
        }
    }
}
