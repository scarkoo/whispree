import CryptoKit
import Foundation
import HuggingFace

/// Downloads the single reviewed Qwen3 model through ordinary HTTPS instead of
/// the Hub client's Xet transport. The Swift Hugging Face snapshot progress
/// callback is currently coarse for large Xet-backed files, which makes a
/// multi-gigabyte transfer appear stuck after tokenizer/config files complete.
struct PinnedQwenDownloader: Sendable {
    private struct FileSpec: Sendable {
        let path: String
        let expectedBytes: Int64
    }

    private final class ProgressBox: @unchecked Sendable {
        let value: Progress
        init(_ value: Progress) { self.value = value }
    }

    enum DownloadError: LocalizedError {
        case invalidRepository
        case unsupportedModel
        case checksumMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .invalidRepository:
                "Qwen3 모델 repository ID가 올바르지 않습니다."
            case .unsupportedModel:
                "검토되지 않은 모델 또는 revision 다운로드가 차단되었습니다."
            case let .checksumMismatch(expected, actual):
                "Qwen3 모델 무결성 검증에 실패했습니다. expected=\(expected), actual=\(actual)"
            }
        }
    }

    static let modelID = "mlx-community/Qwen3-8B-4bit"
    static let revision = "545dc4251c05440727734bcd94334791f6ab0192"
    static let modelSHA256 = "f2d29621aab300336ad645567ff38c42aac755513006ef4e8a579cf7ef5256d8"

    /// Approximate repository payload size at the pinned revision.
    static let totalDownloadBytes: Int64 = 4_626_000_000

    static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Whispree/PinnedModels/qwen3-8b/\(revision)", isDirectory: true)
    }

    private static var verificationMarkerURL: URL {
        modelDirectory.appendingPathComponent(".verified-model-sha256")
    }

    private static let files: [FileSpec] = [
        .init(path: "model.safetensors", expectedBytes: 4_610_000_000),
        .init(path: "tokenizer.json", expectedBytes: 11_400_000),
        .init(path: "vocab.json", expectedBytes: 2_780_000),
        .init(path: "merges.txt", expectedBytes: 1_670_000),
        .init(path: "model.safetensors.index.json", expectedBytes: 64_100),
        .init(path: "tokenizer_config.json", expectedBytes: 9_710),
        .init(path: "config.json", expectedBytes: 939),
        .init(path: "added_tokens.json", expectedBytes: 707),
        .init(path: "special_tokens_map.json", expectedBytes: 613),
    ]

    static func isVerifiedModelAvailable() -> Bool {
        let fm = FileManager.default
        let model = modelDirectory.appendingPathComponent("model.safetensors")
        let config = modelDirectory.appendingPathComponent("config.json")
        let tokenizer = modelDirectory.appendingPathComponent("tokenizer.json")

        guard fm.fileExists(atPath: model.path),
              fm.fileExists(atPath: config.path),
              fm.fileExists(atPath: tokenizer.path),
              let marker = try? String(contentsOf: verificationMarkerURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              marker == modelSHA256,
              let attrs = try? fm.attributesOfItem(atPath: model.path),
              let size = attrs[.size] as? NSNumber,
              size.int64Value > 4_500_000_000
        else {
            return false
        }
        return true
    }

    func download(
        id: String = Self.modelID,
        revision requestedRevision: String = Self.revision,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard id == Self.modelID, requestedRevision == Self.revision else {
            throw DownloadError.unsupportedModel
        }

        if Self.isVerifiedModelAvailable() {
            let done = Progress(totalUnitCount: Self.totalDownloadBytes)
            done.completedUnitCount = Self.totalDownloadBytes
            progressHandler(done)
            return Self.modelDirectory
        }

        let fm = FileManager.default
        try fm.createDirectory(at: Self.modelDirectory, withIntermediateDirectories: true)
        try? fm.removeItem(at: Self.verificationMarkerURL)

        guard let repo = HuggingFace.Repo.ID(rawValue: Self.modelID) else {
            throw DownloadError.invalidRepository
        }

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 120
        sessionConfiguration.timeoutIntervalForResource = 6 * 60 * 60

        // No token discovery and no shared Hugging Face cache. This public,
        // revision-pinned model is downloaded directly into Whispree storage.
        let client = HuggingFace.HubClient(
            session: URLSession(configuration: sessionConfiguration),
            host: HuggingFace.HubClient.defaultHost,
            bearerToken: nil,
            cache: nil
        )

        var completedBeforeCurrentFile: Int64 = 0
        Self.report(completed: 0, progressHandler: progressHandler)

        for file in Self.files {
            try Task.checkCancellation()

            let destination = Self.modelDirectory.appendingPathComponent(file.path)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let fileProgressBox = ProgressBox(Progress(totalUnitCount: file.expectedBytes))
            let baseCompleted = completedBeforeCurrentFile

            // HubClient mutates Foundation.Progress from its URLSession delegate.
            // Poll it so the SwiftUI layer sees actual bytes during the 4.61 GB weight transfer.
            let progressPoller = Task {
                while !Task.isCancelled {
                    let current = max(Int64(0), fileProgressBox.value.completedUnitCount)
                    Self.report(
                        completed: min(Self.totalDownloadBytes, baseCompleted + current),
                        progressHandler: progressHandler
                    )
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }

            do {
                _ = try await client.downloadFile(
                    at: file.path,
                    from: repo,
                    to: destination,
                    revision: Self.revision,
                    progress: fileProgressBox.value,
                    transport: .lfs
                )
            } catch {
                progressPoller.cancel()
                throw error
            }
            progressPoller.cancel()

            let actualSize = ((try? fm.attributesOfItem(atPath: destination.path)[.size]) as? NSNumber)?
                .int64Value ?? file.expectedBytes
            completedBeforeCurrentFile = min(
                Self.totalDownloadBytes,
                completedBeforeCurrentFile + max(actualSize, file.expectedBytes)
            )
            Self.report(
                completed: completedBeforeCurrentFile,
                progressHandler: progressHandler
            )
        }

        let actualHash = try Self.sha256(
            of: Self.modelDirectory.appendingPathComponent("model.safetensors")
        )
        guard actualHash == Self.modelSHA256 else {
            try? fm.removeItem(
                at: Self.modelDirectory.appendingPathComponent("model.safetensors")
            )
            throw DownloadError.checksumMismatch(expected: Self.modelSHA256, actual: actualHash)
        }

        try Self.modelSHA256.write(
            to: Self.verificationMarkerURL,
            atomically: true,
            encoding: .utf8
        )
        Self.report(completed: Self.totalDownloadBytes, progressHandler: progressHandler)
        return Self.modelDirectory
    }

    private static func report(
        completed: Int64,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) {
        let progress = Progress(totalUnitCount: totalDownloadBytes)
        progress.completedUnitCount = min(max(completed, 0), totalDownloadBytes)
        progressHandler(progress)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
