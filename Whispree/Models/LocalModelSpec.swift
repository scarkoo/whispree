import Foundation

/// 이 보안 강화 fork에서 허용하는 유일한 로컬 LLM 사양.
struct LocalModelSpec: Identifiable, Codable, Hashable {
    let id: String
    let revision: String
    let displayName: String
    let description: String
    let sizeBytes: Int64
    let minMemoryGB: Int
    let qualityScore: Int

    var sizeDescription: String {
        let gb = Double(sizeBytes) / 1_000_000_000
        return String(format: "~%.1f GB", gb)
    }

    func compatibility(otherModelSizeBytes: Int64 = 0) -> ModelCompatibilityResult {
        ModelCompatibility.evaluate(
            modelSizeBytes: sizeBytes,
            otherModelSizeBytes: otherModelSizeBytes
        )
    }

    static let qwen3_8B = LocalModelSpec(
        id: "mlx-community/Qwen3-8B-4bit",
        revision: "545dc4251c05440727734bcd94334791f6ab0192",
        displayName: "Qwen3 8B (4-bit)",
        description: "고정된 로컬 텍스트 교정 모델",
        sizeBytes: 4_626_000_000,
        minMemoryGB: 16,
        qualityScore: 20
    )

    static let supported: [LocalModelSpec] = [qwen3_8B]
    static let defaultModelId = qwen3_8B.id

    static func find(_ modelId: String) -> LocalModelSpec? {
        modelId == qwen3_8B.id ? qwen3_8B : nil
    }
}
