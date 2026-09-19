# LLM Service

이 fork의 텍스트 교정 모델은 **Qwen3-8B-4bit 하나로 고정**합니다.

## 구조

- `LocalTextProvider.swift` — Swift `mlx-swift-lm` 기반 로컬 추론
- `NoneProvider.swift` — 사용자가 교정 기능을 끈 경우 원문 유지
- `CorrectionPrompts.swift` — STT 후처리 프롬프트

## 고정 모델

- Repository: `mlx-community/Qwen3-8B-4bit`
- Runtime: Swift MLX
- Revision: `LocalModelSpec.qwen3_8B.revision`의 immutable commit SHA

## 보안 규칙

- OpenAI/Groq/OpenAI-compatible provider 없음
- Codex/OAuth 접근 없음
- Python/uv worker 없음
- Vision/screenshot 입력 없음
- 등록되지 않은 모델 ID나 빈 revision으로 fallback하지 않음
